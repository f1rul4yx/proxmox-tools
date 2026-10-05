# AGENTS.md

Cola de scripts bash independientes para gestionar un Proxmox VE remoto vía API REST + SSH. Sin build, sin tests, sin CI, sin linters (`shellcheck`/`shfmt` no están instalados).

## Verificación

El único chequeo disponible es sintaxis. **Nunca ejecutes un `proxmox-*.sh` para probar un cambio**: actúan contra un Proxmox real (crean contenedores, lanzan `apt upgrade`, sobrescriben `~/.bashrc` en todas las máquinas, ejecutan comandos arbitrarios).

```bash
bash -n proxmox-*.sh
git diff --check
```

## Estructura

- `proxmox-<acción>.sh` — una herramienta por fichero, autónomo y copiable a otro host. **No existe librería compartida**: `check_deps`, `api_get`, `calculate_ip`, `get_lxc_list`, `get_vm_list` están duplicados literalmente en cada script. Al añadir una función compartida, cópiala a todos los scripts, no extraigas un `lib/`.
- `.env` — credenciales, gitignored. Todos los scripts hacen `source "${SCRIPT_DIR}/.env"` y salen con error 1 si no existe. Se carga como bash (no se parsea), así que los valores van entre comillas. Se crea con `cp .env.example .env`. Nunca lo commitees.
- `configs/.bashrc` — payload de `proxmox-bashrc.sh`. Editarlo cambia el `~/.bashrc` de root de todas las máquinas en el siguiente deploy (hace backup a `~/.bashrc.bak`).
- `logs/` — cada script hace `tee -a` de toda su salida en `logs/<nombre>_<timestamp>.log`. Ya está en `.gitignore`; el README pide añadirlo y está desactualizado.

## Convenciones

- Cabecera obligatoria: bloque `# ===` con descripción, `Autor: Diego Vargas`, `Fecha`, `Versión`. Sube `Versión` al tocar un script.
- Banner de sección `# -----------------------------------------` + `NOMBRE EN MAYÚSCULAS`. Cada función va precedida de `# Función: <qué hace>`.
- Comentarios, mensajes y salida en español. Colores como variables `ROJO`/`VERDE`/`AZUL`/`AMARILLO`/`MAGENTA` + `RESET`; `proxmox-lxc.sh` es el excepción (sin color).
- Variables de configuración al principio del fichero (plantillas, disco, memoria, bridge, gateway, DNS, CIDR, `SSH_KEY`). Cambiar comportamiento, no hardcodear en el cuerpo.
- SSH siempre no interactivo: `-n -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes`. Requiere la clave privada cargada en el agente (`ssh-agent bash && ssh-add ~/.ssh/id_rsa`); sin ella los scripts fallan al conectar.
- Auth de API: cabecera `Authorization: PVEAPIToken=${PROXMOX_TOKEN_ID}=${PROXMOX_TOKEN_SECRET}` con `curl -s -k` sobre `${PROXMOX_HOST}/api2/json`. Los tokens deben tener Privilege Separation desactivado.
- `api_get` no valida errores HTTP. Si necesitas codes, copia el patrón de `api_post` (`proxmox-lxc.sh`), que extrae el status con `-w '\n%{http_code}'` y hace `exit 1`.
- Tareas async: `create_lxc` saca el `upid` y `wait_task` lo sondea (`/tasks/<upid>/status`, `exitstatus != OK` → error).

## Convención de argumentos

`proxmox-bashrc.sh` y `proxmox-timezone.sh` siguen `<vmid> | all` con `case "$1"`. `proxmox-exec.sh` usa `[<vmid>|all] <comando>` y trata un único argumento no numérico como comando para todas las máquinas. `all` = contenedores LXC **y** VMs QEMU en ejecución. Un `vmid` concreto se resuelve por API contra LXC y luego QEMU, con fallback `vmid-<n>`.

## Convención de IPs (crítico)

`calculate_ip` (idéntico en los 5 scripts) deriva la IP del VMID con `printf "%04d"`: primer dígito → tercer octeto, los otros tres → cuarto. `2001 → 192.168.2.1`, `3234 → 192.168.3.234`. Solo aplica a VMIDs de 4 dígitos. Cualquier cambio debe replicarse en los 5 scripts.

Convención relacionada: `2010 → /22` en el CIDR pero gateway `192.168.0.1`, así que la máscara cubre `192.168.0.0–192.168.3.255`. Es intencional, no lo "arregles". Startup order = los 3 últimos dígitos del VMID.

## Plantillas LXC

`proxmox-lxc.sh` mantiene un `TEMPLATE_DEBIAN13`/`TEMPLATE_DEBIAN12` por versión y `TEMPLATE_STORAGE="local"` separado de `DISK_STORAGE="local-lvm"`. Una plantilla nueva necesita variable nueva + rama en el `case` de `ask_user`; actualiza también la tabla de ejemplo del README.

## README

El README está en español y documenta el uso de cada herramienta con salida de ejemplo real. Al añadir o cambiar una herramienta, actualiza su sección: es la doc de facto, no hay otra fuente.