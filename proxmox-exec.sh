#!/bin/bash
# =========================================
# Ejecución remota de comandos en Proxmox
# Autor: Diego Vargas
# Fecha: 2026-05-12
# Versión: 1.0
# =========================================



RESET="\e[0m"
ROJO="\e[31m"
VERDE="\e[32m"
AZUL="\e[34m"
AMARILLO="\e[33m"
MAGENTA="\e[35m"



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
LOG_FILE="${LOG_DIR}/exec_$(date +%Y-%m-%d_%H-%M-%S).log"
mkdir -p "$LOG_DIR"

# -----------------------------------------
# FUNCIONES DEFINIDAS
# -----------------------------------------

check_deps() {
  for cmd in curl jq ssh; do
    if ! command -v "$cmd" &>/dev/null; then
      echo -e "${ROJO}[-] '$cmd' no encontrado. Instálalo antes de continuar.${RESET}"
      exit 1
    fi
  done
}

api_get() {
  local endpoint="$1"
  local response

  response=$(curl -s -k \
    -H "Authorization: PVEAPIToken=${PROXMOX_TOKEN_ID}=${PROXMOX_TOKEN_SECRET}" \
    "${PROXMOX_HOST}/api2/json${endpoint}")

  echo "$response"
}

calculate_ip() {
  local vmid="$1"
  local padded
  padded=$(printf "%04d" "$vmid")

  local octet3 octet4
  octet3=$((10#${padded:0:1}))
  octet4=$((10#${padded:1}))

  echo "192.168.${octet3}.${octet4}"
}

get_lxc_list() {
  api_get "/nodes/${PROXMOX_NODE}/lxc" | \
    jq -r '.data[] | select(.status == "running") | [.vmid, .name] | @tsv'
}

get_vm_list() {
  api_get "/nodes/${PROXMOX_NODE}/qemu" | \
    jq -r '.data[] | select(.status == "running") | [.vmid, .name] | @tsv'
}

exec_machine() {
  local vmid="$1"
  local name="$2"
  local command="$3"
  local ip
  ip=$(calculate_ip "$vmid")

  echo -e "\n${MAGENTA}========================================${RESET}"
  echo -e "${MAGENTA}  ${name} (ID: ${vmid}, IP: ${ip})${RESET}"
  echo -e "${MAGENTA}========================================${RESET}"

  local ret
  ssh -n \
      -o StrictHostKeyChecking=no \
      -o ConnectTimeout=10 \
      -o BatchMode=yes \
      -o ServerAliveInterval=30 \
      -o ServerAliveCountMax=3 \
      "root@${ip}" \
      "$command" 2>&1
  ret=$?

  echo -e "${AMARILLO}---${RESET}"
  if [[ $ret -eq 255 ]]; then
    echo -e "${ROJO}[-] '${name}' — conexión SSH fallida${RESET}"
  elif [[ $ret -ne 0 ]]; then
    echo -e "${ROJO}[-] '${name}' — código de salida: ${ret}${RESET}"
  fi
}

# -----------------------------------------
# PROGRAMA
# -----------------------------------------

check_deps

exec > >(tee -a "$LOG_FILE") 2>&1

echo ""
echo "========================================="
echo "   Ejecución remota en Proxmox           "
echo "   $(date '+%Y-%m-%d %H:%M:%S')          "
echo "========================================="

if [[ $# -eq 0 ]]; then
  echo -e "\n${ROJO}[-] Uso: $0 [<vmid> | all] <comando>${RESET}"
  echo -e "${AZUL}[i]   $0 \"cat /etc/crontab\"          -> todas las máquinas${RESET}"
  echo -e "${AZUL}[i]   $0 all \"cat /etc/crontab\"      -> todas las máquinas${RESET}"
  echo -e "${AZUL}[i]   $0 2010 \"cat /etc/crontab\"     -> solo máquina 2010${RESET}"
  exit 1
fi

if [[ $# -eq 1 ]]; then
  target="all"
  command="$1"
else
  if [[ "$1" == "all" || "$1" =~ ^[0-9]+$ ]]; then
    target="$1"
    shift
    command="$*"
  else
    target="all"
    command="$*"
  fi
fi

echo -e "\n${AZUL}[i] Comando: ${command}${RESET}"
echo -e "${AZUL}[i] Target:  ${target}${RESET}"

run_on_all() {
  local cmd="$1"

  echo ""
  echo "[*] Obteniendo contenedores LXC en ejecución..."
  local lxc_list
  lxc_list=$(get_lxc_list)

  if [[ -z "$lxc_list" ]]; then
    echo -e "${AMARILLO}[!] No hay contenedores LXC en ejecución.${RESET}"
  else
    while IFS=$'\t' read -r vmid name; do
      exec_machine "$vmid" "$name" "$cmd"
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
      exec_machine "$vmid" "$name" "$cmd"
    done <<< "$vm_list"
  fi
}

run_on_one() {
  local target_vmid="$1"
  local cmd="$2"
  local name ip

  ip=$(calculate_ip "$target_vmid")
  name=$(api_get "/nodes/${PROXMOX_NODE}/lxc" | jq -r --arg id "$target_vmid" '.data[] | select(.vmid == ($id | tonumber)) | .name')

  if [[ -z "$name" ]]; then
    name=$(api_get "/nodes/${PROXMOX_NODE}/qemu" | jq -r --arg id "$target_vmid" '.data[] | select(.vmid == ($id | tonumber)) | .name')
  fi

  if [[ -z "$name" ]]; then
    name="vmid-${target_vmid}"
  fi

  exec_machine "$target_vmid" "$name" "$cmd"
}

if [[ "$target" == "all" ]]; then
  run_on_all "$command"
else
  run_on_one "$target" "$command"
fi

echo ""
echo -e "${VERDE}[+] Proceso completado. Log guardado en: ${LOG_FILE}${RESET}"
