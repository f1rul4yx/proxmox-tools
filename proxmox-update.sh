#!/bin/bash
# =========================================
# Actualización de máquinas en Proxmox
# Autor: Diego Vargas
# Fecha: 2026-03-18
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

LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/update_$(date +%Y-%m-%d_%H-%M-%S).log"
mkdir -p "$LOG_DIR"

# -----------------------------------------
# FUNCIONES DEFINIDAS
# -----------------------------------------

# Función: Comprobación de dependencias
check_deps() {
  for cmd in curl jq ssh; do
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

# Función: Actualizar una máquina por SSH
update_machine() {
  local vmid="$1"
  local name="$2"
  local ip
  ip=$(calculate_ip "$vmid")

  echo -e "${AZUL}[i] Actualizando '${name}' (ID: ${vmid}, IP: ${ip})...${RESET}"

  ssh -n \
      -o StrictHostKeyChecking=no \
      -o ConnectTimeout=10 \
      -o BatchMode=yes \
      -o ServerAliveInterval=30 \
      -o ServerAliveCountMax=3 \
      "root@${ip}" \
      "DEBIAN_FRONTEND=noninteractive apt update && DEBIAN_FRONTEND=noninteractive apt upgrade -y"

  if [[ $? -eq 0 ]]; then
    echo -e "${VERDE}[+] '${name}' actualizado correctamente.${RESET}"
  else
    echo -e "${ROJO}[-] Error al actualizar '${name}'. Continuando con el siguiente...${RESET}"
  fi
}

# Función: Mostrar lista de máquinas con sus IPs
show_machine_list() {
  local list="$1"
  while IFS=$'\t' read -r vmid name; do
    local ip
    ip=$(calculate_ip "$vmid")
    echo -e "${AZUL}[i]   - ${name} (ID: ${vmid}, IP: ${ip})${RESET}"
  done <<< "$list"
}

# -----------------------------------------
# PROGRAMA
# -----------------------------------------

check_deps

exec > >(tee -a "$LOG_FILE") 2>&1

echo ""
echo "========================================="
echo "   Actualización de máquinas Proxmox     "
echo "   $(date '+%Y-%m-%d %H:%M:%S')          "
echo "========================================="

# Contenedores LXC
echo ""
echo "[*] Obteniendo contenedores LXC en ejecución..."
lxc_list=$(get_lxc_list)

if [[ -z "$lxc_list" ]]; then
  echo -e "${AMARILLO}[!] No hay contenedores LXC en ejecución.${RESET}"
else
  show_machine_list "$lxc_list"
  while IFS=$'\t' read -r vmid name; do
    echo ""
    update_machine "$vmid" "$name"
  done <<< "$lxc_list"
fi

# Máquinas virtuales QEMU
echo ""
echo "[*] Obteniendo VMs en ejecución..."
vm_list=$(get_vm_list)

if [[ -z "$vm_list" ]]; then
  echo -e "${AMARILLO}[!] No hay VMs en ejecución.${RESET}"
else
  show_machine_list "$vm_list"
  while IFS=$'\t' read -r vmid name; do
    echo ""
    update_machine "$vmid" "$name"
  done <<< "$vm_list"
fi

echo ""
echo -e "${VERDE}[+] Proceso completado. Log guardado en: ${LOG_FILE}${RESET}"
