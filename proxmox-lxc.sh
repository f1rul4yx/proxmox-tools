#!/bin/bash
# =========================================
# Creación de contenedores LXC en Proxmox
# Autor: Diego Vargas
# Fecha: 2026-03-16
# Versión: 1.0
# =========================================



# -----------------------------------------
# CARGA DE CONFIGURACIÓN
# -----------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "[-] Archivo .env no encontrado en: $ENV_FILE"
  exit 1
fi

source "$ENV_FILE"

# -----------------------------------------
# CONFIGURACIÓN LXC
# -----------------------------------------

TEMPLATE="debian-13-standard_13.1-2_amd64.tar.zst"
TEMPLATE_STORAGE="local"
DISK_STORAGE="local-lvm"
DISK_SIZE="8"
MEMORY="512"
SWAP="512"
CORES="1"
BRIDGE="vmbr0"
GATEWAY="192.168.0.1"
NAMESERVER="192.168.2.12"
CIDR="22"
SSH_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDuY/xX5VpFHKf9e4A0cz4eryNYhNnL5CksiOPLyQB7RFS/nfN2hIk7YcZXPtYEBIS1vdNPHScwEjBBOhxr50QTCw+5Pl75l+b889V7pZbCZxX4TkVBEv4b/LY8i5vfd70IByYQoad75u0W48VpZLwg/fGwtPh68vkTbMMPC8CKov0NrFw3qHQLKcI6L2XAgYZYxw5Mbs88z40mAlZO6vL+F/Ue7ID647fmth10oAKMBsxvIFBHJ/zoKE9iDBx3xXAqrKWDfsDOFxUt+9Nx9MRQgS3aSqilwdK6UzRXalo9oCs0ToLML8ylVJK2j8sTE2mfltSbby/0IRD5PG6NE2LW6mq5WmPRLyG529pL3sXFcVHUH7EsK1tN6ARGVWqO3I7mNjNhLhFvmadv79qwiVBK4jxeEVML+ya4h56HOh9FlAjHBIM0HrFYQya0/vKT/a8Z26ACir99Ib/lkoYUHIzsU6Rduh9s96lbvqin5Xcse3BQnNx1AFosOiWkx+KeHgE= diego@debian"

# -----------------------------------------
# FUNCIONES DEFINIDAS
# -----------------------------------------

# Función: Comprobación de dependencias
check_deps() {
  for cmd in curl jq; do
    if ! command -v "$cmd" &>/dev/null; then
      echo "[-] '$cmd' no encontrado. Instálalo antes de continuar."
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

# Función: Petición POST a la API de Proxmox
api_post() {
  local endpoint="$1"
  shift

  local response http_code
  response=$(curl -s -k -w '\n%{http_code}' \
    -H "Authorization: PVEAPIToken=${PROXMOX_TOKEN_ID}=${PROXMOX_TOKEN_SECRET}" \
    -X POST \
    "$@" \
    "${PROXMOX_HOST}/api2/json${endpoint}")

  http_code=$(echo "$response" | tail -1)
  response=$(echo "$response" | sed '$d')

  if [[ "$http_code" -ge 400 ]] 2>/dev/null; then
    echo "[-] Error HTTP ${http_code} en POST ${endpoint}" >&2
    echo "$response" | jq . >&2 2>/dev/null || echo "$response" >&2
    exit 1
  fi

  echo "$response"
}

# Función: Esperar a que termine una tarea de Proxmox
wait_task() {
  local upid="$1"
  local encoded_upid
  encoded_upid=$(echo -n "$upid" | jq -sRr @uri)

  echo "[*] Esperando a que termine la tarea..."
  while true; do
    local task_data status
    task_data=$(api_get "/nodes/${PROXMOX_NODE}/tasks/${encoded_upid}/status")
    status=$(echo "$task_data" | jq -r '.data.status')

    case "$status" in
      stopped)
        local exitstatus
        exitstatus=$(echo "$task_data" | jq -r '.data.exitstatus')
        if [[ "$exitstatus" != "OK" ]]; then
          echo "[-] La tarea terminó con error: ${exitstatus}"
          exit 1
        fi
        return 0
        ;;
      running)
        sleep 1
        ;;
      *)
        echo "[-] Estado inesperado: ${status}"
        exit 1
        ;;
    esac
  done
}

# Función: Obtener el siguiente VMID libre
next_id() {
  api_get "/cluster/nextid" | jq -r '.data'
}

# Función: Calcular la IP a partir del CT ID
#   2001  -> 192.168.2.1
#   2011  -> 192.168.2.11
#   3007  -> 192.168.3.7
#   0013  -> 192.168.0.13
calculate_ip() {
  local ctid="$1"
  local padded
  padded=$(printf "%04d" "$ctid")

  local octet3 octet4
  octet3=$((10#${padded:0:1}))
  octet4=$((10#${padded:1}))

  echo "192.168.${octet3}.${octet4}"
}

# Función: Calcular el startup order a partir del CT ID
#   2001  -> order=0
#   2003  -> order=2
#   2017  -> order=16
calculate_startup_order() {
  local ctid="$1"
  local padded
  padded=$(printf "%04d" "$ctid")

  local octet4
  octet4=$((10#${padded:1}))
  local order=$((octet4 - 1))

  echo "order=${order},up=10,down=30"
}

# Función: Pedir datos al usuario
ask_user() {
  local default_id
  default_id=$(next_id)

  read -rp "CT ID [$default_id]: " CTID
  CTID="${CTID:-$default_id}"

  if ! [[ "$CTID" =~ ^[0-9]+$ ]] || [[ "$CTID" -lt 100 ]]; then
    echo "[-] CT ID no válido: $CTID"
    exit 1
  fi

  read -rp "Hostname: " HOSTNAME
  if [[ -z "$HOSTNAME" ]]; then
    echo "[-] El hostname no puede estar vacío."
    exit 1
  fi

  if [[ "$HOSTNAME" =~ [^a-zA-Z0-9._-] ]]; then
    echo "[-] Hostname no válido. Usa solo letras, números, '.', '-' y '_'."
    exit 1
  fi

  IP=$(calculate_ip "$CTID")
  STARTUP=$(calculate_startup_order "$CTID")
}

# Función: Mostrar resumen antes de crear
show_summary() {
  echo ""
  echo "--- Resumen ---"
  echo "  CT ID:     $CTID"
  echo "  Hostname:  $HOSTNAME"
  echo "  Template:  $TEMPLATE"
  echo "  Disco:     ${DISK_SIZE} GB ($DISK_STORAGE)"
  echo "  Memoria:   ${MEMORY} MB (swap: ${SWAP} MB)"
  echo "  Cores:     $CORES"
  echo "  IP:        ${IP}/${CIDR}"
  echo "  Gateway:   $GATEWAY"
  echo "  DNS:       $NAMESERVER"
  echo "  SSH key:   sí (sin password)"
  echo "  Nesting:   sí"
  echo "  Onboot:    sí"
  echo "  Startup:   $STARTUP"
  echo ""
}

# Función: Crear el contenedor LXC
create_lxc() {
  local net0="name=eth0,bridge=${BRIDGE},firewall=1,gw=${GATEWAY},ip=${IP}/${CIDR},type=veth"

  local response upid
  response=$(api_post "/nodes/${PROXMOX_NODE}/lxc" \
    -d "vmid=${CTID}" \
    -d "hostname=${HOSTNAME}" \
    -d "ostemplate=${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}" \
    -d "ostype=debian" \
    -d "arch=amd64" \
    -d "memory=${MEMORY}" \
    -d "swap=${SWAP}" \
    -d "cores=${CORES}" \
    --data-urlencode "rootfs=${DISK_STORAGE}:${DISK_SIZE}" \
    --data-urlencode "net0=${net0}" \
    -d "unprivileged=1" \
    -d "nameserver=${NAMESERVER}" \
    -d "onboot=1" \
    --data-urlencode "startup=${STARTUP}" \
    --data-urlencode "features=nesting=1" \
    --data-urlencode "ssh-public-keys=${SSH_KEY}")

  upid=$(echo "$response" | jq -r '.data // empty')
  if [[ -z "$upid" ]]; then
    echo "[-] La API no devolvió tarea."
    echo "$response" | jq . 2>/dev/null || echo "$response"
    exit 1
  fi

  wait_task "$upid"
}

# Función: Verificar que el contenedor existe tras la creación
verify_lxc() {
  local check
  check=$(api_get "/nodes/${PROXMOX_NODE}/lxc/${CTID}/status/current" | jq -r '.data.vmid // empty')

  if [[ "$check" != "$CTID" ]]; then
    echo "[-] El contenedor $CTID no se encontró después de la creación."
    exit 1
  fi

  echo "[+] Contenedor '${HOSTNAME}' (ID: ${CTID}) creado correctamente."
}

# Función: Arrancar el contenedor
start_lxc() {
  echo "[*] Arrancando contenedor ${CTID}..."
  api_post "/nodes/${PROXMOX_NODE}/lxc/${CTID}/status/start" > /dev/null
  echo "[+] Contenedor arrancado."
  echo "[+] Acceso: ssh root@${IP}"
}

# -----------------------------------------
# PROGRAMA
# -----------------------------------------

check_deps
ask_user
show_summary
echo "[*] Creando contenedor '${HOSTNAME}' (ID: ${CTID})..."
create_lxc
verify_lxc
start_lxc
