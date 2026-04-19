#!/bin/bash
# =========================================
# Despliegue de .bashrc en máquinas Proxmox
# Autor: Diego Vargas
# Fecha: 2026-04-19
# Versión: 1.0
# =========================================



RESET="\e[0m"
ROJO="\e[31m"
VERDE="\e[32m"
AZUL="\e[34m"
AMARILLO="\e[33m"



# -----------------------------------------
# CARGA DE CONFIGURACIÓN
# -----------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo -e "${ROJO}[-] Archivo .env no encontrado en: $ENV_FILE${RESET}"
  exit 1
fi

source "$ENV_FILE"

BASHRC_FILE="${SCRIPT_DIR}/configs/.bashrc"

if [[ ! -f "$BASHRC_FILE" ]]; then
  echo -e "${ROJO}[-] Archivo configs/.bashrc no encontrado en: $BASHRC_FILE${RESET}"
  exit 1
fi

LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/bashrc_$(date +%Y-%m-%d_%H-%M-%S).log"
mkdir -p "$LOG_DIR"

# -----------------------------------------
# FUNCIONES DEFINIDAS
# -----------------------------------------

# Función: Comprobación de dependencias
check_deps() {
  for cmd in curl jq ssh scp; do
    if ! command -v "$cmd" &>/dev/null; then
      echo -e "${ROJO}[-] '$cmd' no encontrado. Instálalo antes de continuar.${RESET}"
      exit 1
    fi
  done
}

# Función: Petición GET a la API de Proxmox
api_get() {
  local endpoint="$1"
  local response

  response=$(curl -s -k \
    -H "Authorization: PVEAPIToken=${PROXMOX_TOKEN_ID}=${PROXMOX_TOKEN_SECRET}" \
    "${PROXMOX_HOST}/api2/json${endpoint}")

  echo "$response"
}

# Función: Calcular la IP a partir del VMID
#   2001  -> 192.168.2.1
#   2011  -> 192.168.2.11
#   3007  -> 192.168.3.7
#   0013  -> 192.168.0.13
calculate_ip() {
  local vmid="$1"
  local padded
  padded=$(printf "%04d" "$vmid")

  local octet3 octet4
  octet3=$((10#${padded:0:1}))
  octet4=$((10#${padded:1}))

  echo "192.168.${octet3}.${octet4}"
}

# Función: Obtener lista de contenedores LXC en ejecución
get_lxc_list() {
  api_get "/nodes/${PROXMOX_NODE}/lxc" | \
    jq -r '.data[] | select(.status == "running") | [.vmid, .name] | @tsv'
}

# Función: Obtener lista de VMs QEMU en ejecución
get_vm_list() {
  api_get "/nodes/${PROXMOX_NODE}/qemu" | \
    jq -r '.data[] | select(.status == "running") | [.vmid, .name] | @tsv'
}

# Función: Desplegar .bashrc en una máquina
deploy_bashrc() {
  local vmid="$1"
  local name="$2"
  local ip
  ip=$(calculate_ip "$vmid")

  echo -e "${AZUL}[i] Desplegando en '${name}' (ID: ${vmid}, IP: ${ip})...${RESET}"

  scp -q \
      -o StrictHostKeyChecking=no \
      -o ConnectTimeout=10 \
      -o BatchMode=yes \
      "$BASHRC_FILE" "root@${ip}:~/.bashrc.new"

  if [[ $? -ne 0 ]]; then
    echo -e "${ROJO}[-] Error al copiar a '${name}'. Continuando...${RESET}"
    return
  fi

  ssh -n \
      -o StrictHostKeyChecking=no \
      -o ConnectTimeout=10 \
      -o BatchMode=yes \
      "root@${ip}" \
      "cp ~/.bashrc ~/.bashrc.bak && mv ~/.bashrc.new ~/.bashrc"

  if [[ $? -eq 0 ]]; then
    echo -e "${VERDE}[+] '${name}' actualizado correctamente.${RESET}"
  else
    echo -e "${ROJO}[-] Error al aplicar en '${name}'. Continuando...${RESET}"
  fi
}

# Función: Desplegar en todas las máquinas en ejecución
deploy_all() {
  echo ""
  echo "[*] Obteniendo contenedores LXC en ejecución..."
  local lxc_list
  lxc_list=$(get_lxc_list)

  if [[ -z "$lxc_list" ]]; then
    echo -e "${AMARILLO}[!] No hay contenedores LXC en ejecución.${RESET}"
  else
    while IFS=$'\t' read -r vmid name; do
      echo ""
      deploy_bashrc "$vmid" "$name"
    done <<< "$lxc_list"
  fi

  echo ""
  echo "[*] Obteniendo VMs en ejecución..."
  local vm_list
  vm_list=$(get_vm_list)

  if [[ -z "$vm_list" ]]; then
    echo -e "${AMARILLO}[!] No hay VMs en ejecución.${RESET}"
  else
    while IFS=$'\t' read -r vmid name; do
      echo ""
      deploy_bashrc "$vmid" "$name"
    done <<< "$vm_list"
  fi
}

# Función: Desplegar en una máquina concreta por VMID
deploy_one() {
  local target_vmid="$1"
  local name ip
  ip=$(calculate_ip "$target_vmid")

  name=$(api_get "/nodes/${PROXMOX_NODE}/lxc" | jq -r --arg id "$target_vmid" '.data[] | select(.vmid == ($id | tonumber)) | .name')
  if [[ -z "$name" ]]; then
    name=$(api_get "/nodes/${PROXMOX_NODE}/qemu" | jq -r --arg id "$target_vmid" '.data[] | select(.vmid == ($id | tonumber)) | .name')
  fi
  if [[ -z "$name" ]]; then
    name="vmid-${target_vmid}"
  fi

  echo ""
  deploy_bashrc "$target_vmid" "$name"
}

# -----------------------------------------
# PROGRAMA
# -----------------------------------------

check_deps

exec > >(tee -a "$LOG_FILE") 2>&1

echo ""
echo "========================================="
echo "   Despliegue de .bashrc en Proxmox      "
echo "   $(date '+%Y-%m-%d %H:%M:%S')          "
echo "========================================="

if [[ $# -eq 0 ]]; then
  echo -e "${ROJO}[-] Uso: $0 <vmid> | all${RESET}"
  echo -e "${AZUL}[i]   $0 2010       -> despliega en máquina con ID 2010${RESET}"
  echo -e "${AZUL}[i]   $0 all        -> despliega en todas las máquinas${RESET}"
  exit 1
fi

case "$1" in
  all)
    deploy_all
    ;;
  *)
    if ! [[ "$1" =~ ^[0-9]+$ ]]; then
      echo -e "${ROJO}[-] VMID no válido: $1${RESET}"
      exit 1
    fi
    deploy_one "$1"
    ;;
esac

echo ""
echo -e "${VERDE}[+] Proceso completado. Log guardado en: ${LOG_FILE}${RESET}"
