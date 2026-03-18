# proxmox-tools

Herramientas para gestionar Proxmox VE de forma remota usando la API REST.

## Requisitos

- `curl`
- `jq`
- `ssh`
- API Token de Proxmox con Privilege Separation desactivado

## Instalación

```bash
git clone https://github.com/f1rul4yx/proxmox-tools.git
cd proxmox-tools
cp .env.example .env
```

Editar `.env` con los datos de tu Proxmox:

```
PROXMOX_HOST="https://192.168.2.1:8006"
PROXMOX_NODE="pve1"
PROXMOX_TOKEN_ID="root@pam!token"
PROXMOX_TOKEN_SECRET="tu-secret-aquí"
```

## Crear el API Token en Proxmox

1. Ir a **Datacenter > Permissions > API Tokens > Add**
2. User: `root@pam`
3. Token ID: `token`
4. **Desmarcar** Privilege Separation
5. Copiar el secret que muestra (solo se ve una vez)

## Herramientas

### proxmox-lxc.sh

Crea contenedores LXC con la configuración base: Debian 13, 512 MB RAM, 1 core, 8 GB disco, nesting, acceso por SSH key sin contraseña. La IP y el startup order se calculan a partir del CT ID.

```bash
chmod +x proxmox-lxc.sh
./proxmox-lxc.sh
```

```
CT ID [2018]: 2020
Hostname: mi-servicio

--- Resumen ---
  CT ID:     2020
  Hostname:  mi-servicio
  Template:  debian-13-standard_13.1-2_amd64.tar.zst
  Disco:     8 GB (local-lvm)
  Memoria:   512 MB (swap: 512 MB)
  Cores:     1
  IP:        192.168.2.20/22
  Gateway:   192.168.0.1
  DNS:       192.168.2.3
  SSH key:   sí (sin password)
  Nesting:   sí
  Onboot:    sí
  Startup:   order=19,up=10,down=30

[*] Creando contenedor 'mi-servicio' (ID: 2020)...
[*] Esperando a que termine la tarea...
[+] Contenedor 'mi-servicio' (ID: 2020) creado correctamente.
[+] Acceso: ssh root@192.168.2.20
```

#### Cálculo automático de IP y startup order

| CT ID | IP | Startup order |
|-------|-----|---------------|
| 2003 | 192.168.2.3/22 | order=2 |
| 2017 | 192.168.2.17/22 | order=16 |
| 2056 | 192.168.2.56/22 | order=55 |

#### Configuración del contenedor

Idéntica a la creación manual desde la GUI:

```
arch: amd64
cores: 1
features: nesting=1
memory: 512
nameserver: 192.168.2.3
net0: name=eth0,bridge=vmbr0,firewall=1,gw=192.168.0.1,ip=192.168.2.X/22,type=veth
onboot: 1
ostype: debian
rootfs: local-lvm:vm-XXXX-disk-0,size=8G
startup: order=X,up=10,down=30
swap: 512
unprivileged: 1
```

Para cambiar los valores por defecto, editar la sección "CONFIGURACIÓN LXC" del script.

---

### proxmox-update.sh

Actualiza todos los contenedores LXC y VMs en ejecución ejecutando `apt update && apt upgrade -y` en cada uno vía SSH. Si una máquina falla, continúa con la siguiente.

```bash
chmod +x proxmox-update.sh
./proxmox-update.sh
```

```
=========================================
   Actualización de máquinas Proxmox
=========================================

[*] Obteniendo contenedores LXC en ejecución...
[i]   - mi-servicio (ID: 2020, IP: 192.168.2.20)
[i]   - otro-ct (ID: 2021, IP: 192.168.2.21)

[i] Actualizando 'mi-servicio' (ID: 2020, IP: 192.168.2.20)...
[+] 'mi-servicio' actualizado correctamente.

[i] Actualizando 'otro-ct' (ID: 2021, IP: 192.168.2.21)...
[+] 'otro-ct' actualizado correctamente.

[*] Obteniendo VMs en ejecución...
[!] No hay VMs en ejecución.

[+] Proceso completado.
```

> La IP se calcula a partir del VMID con la misma convención que `proxmox-lxc.sh`. Las máquinas deben tener configurada la SSH key para acceso como `root`.

Antes de ejecutar el script, cargar la clave privada en el agente SSH:

```bash
ssh-agent bash
ssh-add ~/.ssh/id_rsa
```

Los logs se guardan en `logs/`. Para excluirlos del repositorio:

```bash
echo "logs/" >> .gitignore
```
