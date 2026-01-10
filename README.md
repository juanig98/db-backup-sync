# 🔄 DB Backup Sync

Sistema automatizado y modular para sincronizar backups de bases de datos desde múltiples servidores remotos mediante SSH/SFTP con elevación de privilegios (sudo).

## 📋 Descripción

Este proyecto permite descargar automáticamente backups de bases de datos desde servidores remotos a un servidor local cuando el backup está generado por root pero el acceso SSH es mediante un usuario sin privilegios.

**Características principales:**
- ✅ **Multiservidor**: Soporta múltiples configuraciones para diferentes bases de datos y servidores
- ✅ **Acceso seguro**: SSH con clave pública + sudo sin contraseña
- ✅ **Validación robusta**: Verifica existencia, integridad (gzip) y tamaño de archivos
- ✅ **Descarga atómica**: Usa archivo temporal con renombrado final para evitar corrupción
- ✅ **Política de retención**: Limpieza automática de backups antiguos configurable
- ✅ **Logs detallados**: Registro separado por configuración con timestamps ISO 8601
- ✅ **Reutilizable**: Un solo script con múltiples archivos de configuración

---

## 🏗️ Arquitectura

```
┌──────────────────────┐                              ┌──────────────────────────┐
│  Servidor A (Prod)   │                              │                          │
│  /var/backups/db/    │──┐                           │  Servidor B (Destino)   │
│  Usuario:  appuser    │  │                           │  /var/backups/remote-db/ │
│  Backup owner:  root  │  │                           │  ├── produccion/         │
└──────────────────────┘  │   SSH + sudo cat          │  ├── staging/            │
                          ├────────────────────────►  │  └── analytics/          │
┌──────────────────────┐  │                           │                          │
│  Servidor C (Stage)  │  │                           │  Usuario: root (cron)    │
│  /backups/mysql/     │──┘                           │  Script: sync-db-backup  │
└──────────────────────┘                              └──────────────────────────┘
```

---

## 📦 Instalación

### 1️⃣ En Servidor B (Destino)

#### a) Crear estructura de directorios

```bash
sudo mkdir -p /opt/db-backup-sync/bin
sudo mkdir -p /opt/db-backup-sync/etc
sudo mkdir -p /var/backups/remote-db/{produccion,staging,analytics}
sudo mkdir -p /var/log
```

#### b) Descargar e instalar el script principal

```bash
sudo nano /opt/db-backup-sync/bin/sync-db-backup.sh
```

Copiar el contenido del script y guardar. 

**Establecer permisos:**

```bash
sudo chmod 750 /opt/db-backup-sync/bin/sync-db-backup.sh
sudo chown root:root /opt/db-backup-sync/bin/sync-db-backup.sh
```

#### c) Crear symlink para facilitar ejecución

```bash
sudo ln -sf /opt/db-backup-sync/bin/sync-db-backup.sh /usr/local/bin/sync-db-backup
```

#### d) Crear archivos de configuración

**Ejemplo 1: Producción - Servidor A**

```bash
sudo nano /opt/db-backup-sync/etc/db-prod-serverA.conf
```

```bash
# ============================================================
# Configuración:  Base de datos PRODUCCIÓN (Servidor A)
# ============================================================

# === Identificación ===
CONFIG_NAME="Producción - Servidor A"

# === Servidor remoto ===
REMOTE_USER="appuser"
REMOTE_HOST="192.168.1.100"
SSH_PORT="22"
SSH_KEY="/root/.ssh/id_backup_sync"
REMOTE_DIR="/var/backups/db"

# === Configuración del backup ===
# Formato del archivo: {YYYYMMDD}{HHmm}. {DB_NAME}.sql.gz
# Ejemplo: 202601100300.produccion.sql.gz
DB_NAME="produccion"
BACKUP_TIME="0300"

# === Almacenamiento local ===
LOCAL_DIR="/var/backups/remote-db/produccion"
LOG_FILE="/var/log/db-backup-sync-prod.log"

# === Retención (días) ===
RETENTION_DAYS="14"
```

**Ejemplo 2: Staging - Servidor B**

```bash
sudo nano /opt/db-backup-sync/etc/db-staging-serverB.conf
```

```bash
# ============================================================
# Configuración: Base de datos STAGING (Servidor B)
# ============================================================

CONFIG_NAME="Staging - Servidor B"

REMOTE_USER="deploy"
REMOTE_HOST="staging.example.com"
SSH_PORT="2222"
SSH_KEY="/root/.ssh/id_backup_staging"
REMOTE_DIR="/backups/mysql"

DB_NAME="staging_db"
BACKUP_TIME="0200"

LOCAL_DIR="/var/backups/remote-db/staging"
LOG_FILE="/var/log/db-backup-sync-staging.log"

RETENTION_DAYS="7"
```

**Establecer permisos en archivos de configuración:**

```bash
sudo chmod 600 /opt/db-backup-sync/etc/*. conf
sudo chown root:root /opt/db-backup-sync/etc/*. conf
```

#### e) Generar claves SSH para cada servidor

**Para Producción (Servidor A):**

```bash
sudo ssh-keygen -t ed25519 -f /root/. ssh/id_backup_sync -C "backup-sync-prod" -N ""
sudo ssh-copy-id -i /root/.ssh/id_backup_sync. pub appuser@192.168.1.100
```

**Para Staging (Servidor B):**

```bash
sudo ssh-keygen -t ed25519 -f /root/.ssh/id_backup_staging -C "backup-sync-staging" -N ""
sudo ssh-copy-id -i /root/.ssh/id_backup_staging.pub deploy@staging.example. com
```

**Probar conexiones:**

```bash
sudo ssh -i /root/.ssh/id_backup_sync appuser@192.168.1.100 "echo 'Conexión OK'"
sudo ssh -i /root/.ssh/id_backup_staging deploy@staging.example.com "echo 'Conexión OK'"
```

---

### 2️⃣ En Servidores Remotos (Origen)

Repetir estos pasos en **cada servidor remoto** (A, B, C, etc.).

#### a) Configurar permisos sudo

En **cada servidor remoto**, editar configuración de sudoers:

```bash
sudo visudo
```

**Agregar al final (ajustar usuario y rutas según tu configuración):**

```sudoers
# Permitir a appuser leer backups de DB sin contraseña
appuser ALL=(root) NOPASSWD: /usr/bin/test -f /var/backups/db/*. sql.gz
appuser ALL=(root) NOPASSWD: /usr/bin/cat /var/backups/db/*. sql.gz
appuser ALL=(root) NOPASSWD: /usr/bin/du -h /var/backups/db/*.sql.gz
```

> ⚠️ **Importante:** 
> - Reemplazar `appuser` con el usuario SSH correspondiente
> - Reemplazar `/var/backups/db/` con la ruta real de los backups
> - Usar rutas absolutas a los comandos (`/usr/bin/cat`, etc.)

**Validar sintaxis:**

```bash
sudo visudo -c
```

#### b) Verificar permisos desde Servidor B

Desde el **Servidor B**, probar los comandos con sudo:

```bash
# Probar test
sudo ssh -i /root/.ssh/id_backup_sync appuser@192.168.1.100 \
  "sudo test -f /var/backups/db/test.sql.gz && echo 'OK' || echo 'No existe'"

# Probar cat (con un backup real)
sudo ssh -i /root/.ssh/id_backup_sync appuser@192.168.1.100 \
  "sudo cat /var/backups/db/202601100300.produccion.sql.gz" | head -c 100

# Probar du
sudo ssh -i /root/.ssh/id_backup_sync appuser@192.168.1.100 \
  "sudo du -h /var/backups/db/202601100300.produccion.sql.gz"
```

---

## ⚙️ Configuración

### Variables del archivo `.conf`

| Variable | Descripción | Ejemplo | Requerida |
|----------|-------------|---------|-----------|
| `CONFIG_NAME` | Identificación descriptiva | `"Producción - Servidor A"` | No |
| `REMOTE_USER` | Usuario SSH en servidor origen | `appuser` | ✅ |
| `REMOTE_HOST` | IP o hostname del servidor origen | `192.168.1.100` | ✅ |
| `SSH_PORT` | Puerto SSH | `22` (por defecto) | No |
| `SSH_KEY` | Ruta a la clave privada SSH | `/root/.ssh/id_backup_sync` | ✅ |
| `REMOTE_DIR` | Directorio de backups en origen | `/var/backups/db` | ✅ |
| `DB_NAME` | Nombre de la base de datos | `produccion` | ✅ |
| `BACKUP_TIME` | Hora de generación (HHmm) | `0300` | ✅ |
| `LOCAL_DIR` | Directorio local para backups | `/var/backups/remote-db/produccion` | ✅ |
| `LOG_FILE` | Ruta del archivo de log | `/var/log/db-backup-sync-prod.log` | ✅ |
| `RETENTION_DAYS` | Días de retención (vacío = no borrar) | `7`, `14`, `30` | No |

### Formato del nombre del archivo de backup

El script busca archivos con el siguiente formato:

```
{YYYYMMDD}{HHmm}.{DB_NAME}.sql.gz
```

**Componentes:**
- `YYYYMMDD`: Fecha (año, mes, día)
- `HHmm`: Hora de generación (24h)
- `DB_NAME`: Nombre de la base de datos
- `.sql.gz`: Extensión fija

**Ejemplos:**
- `202601100300.produccion.sql.gz`
- `202601152200.staging_db.sql.gz`
- `202612310100.analytics.sql.gz`

---

## ⏰ Configuración de Cron

### En Servidor B (Destino) - Sincronización

Editar crontab de root:

```bash
sudo crontab -e
```

**Agregar las siguientes líneas:**

```cron
# ============================================================
# Sincronización de backups de múltiples bases de datos
# ============================================================

# Producción - Servidor A (ejecutar diariamente a las 22:05)
5 22 * * * /usr/local/bin/sync-db-backup -env /opt/db-backup-sync/etc/db-prod-serverA.conf

# Staging - Servidor B (ejecutar diariamente a las 22:10)
10 22 * * * /usr/local/bin/sync-db-backup -env /opt/db-backup-sync/etc/db-staging-serverB.conf

# Analytics - Servidor C (ejecutar diariamente a las 22:15)
15 22 * * * /usr/local/bin/sync-db-backup -env /opt/db-backup-sync/etc/db-analytics-serverC.conf
```

**Verificar crontab:**

```bash
sudo crontab -l
```

### En Servidores Remotos (Origen) - Generación de backups

**IMPORTANTE:** Este README asume que los backups **ya se generan** en los servidores remotos.  Si necesitas configurar la generación automática, aquí un ejemplo:

```bash
sudo crontab -e
```

**Ejemplo para mysqldump:**

```cron
# Generar backup de base de datos a las 22:05 todos los días
5 22 * * * /usr/local/bin/backup-mysql. sh
```

**Script de ejemplo (`/usr/local/bin/backup-mysql.sh`):**

```bash
#!/bin/bash
set -euo pipefail

DB_NAME="produccion"
BACKUP_DIR="/var/backups/db"
TIMESTAMP=$(date +%Y%m%d%H%M)
BACKUP_FILE="${TIMESTAMP}.${DB_NAME}.sql. gz"

mkdir -p "$BACKUP_DIR"

mysqldump -u root -p"${MYSQL_ROOT_PASSWORD}" \
  --single-transaction \
  --routines \
  --triggers \
  "$DB_NAME" | gzip > "${BACKUP_DIR}/${BACKUP_FILE}"

chmod 600 "${BACKUP_DIR}/${BACKUP_FILE}"

echo "[$(date -Iseconds)] Backup creado: ${BACKUP_FILE}"
```

---

## 🧪 Pruebas y Uso

### Ejecución manual

```bash
# Sincronizar producción
sudo sync-db-backup -env /opt/db-backup-sync/etc/db-prod-serverA. conf

# Sincronizar staging
sudo sync-db-backup -env /opt/db-backup-sync/etc/db-staging-serverB.conf

# Ver ayuda
sync-db-backup -h
```

### Monitorear logs en tiempo real

```bash
# Log de producción
sudo tail -f /var/log/db-backup-sync-prod.log

# Log de staging
sudo tail -f /var/log/db-backup-sync-staging.log

# Todos los logs simultáneamente
sudo tail -f /var/log/db-backup-sync-*.log
```

### Verificar backups descargados

```bash
# Listar backups de producción
ls -lh /var/backups/remote-db/produccion/

# Listar todos los backups
find /var/backups/remote-db/ -name "*.sql.gz" -type f -printf "%T+ %p\n" | sort -r
```

### Verificar integridad de un backup

```bash
# Validar compresión gzip
gzip -t /var/backups/remote-db/produccion/202601100300.produccion.sql.gz

# Ver primeras líneas del SQL
zcat /var/backups/remote-db/produccion/202601100300.produccion.sql. gz | head -20
```

---

## 📊 Estructura de archivos

```
/opt/db-backup-sync/
├── bin/
│   └── sync-db-backup.sh              # Script principal
└── etc/
    ├── db-prod-serverA.conf           # Config:  Producción Servidor A
    ├── db-staging-serverB.conf        # Config: Staging Servidor B
    └── db-analytics-serverC.conf      # Config: Analytics Servidor C

/var/backups/remote-db/
├── produccion/
│   ├── 202601100300.produccion. sql.gz
│   ├── 202601110300.produccion.sql.gz
│   └── . tmp/                          # Archivos temporales durante descarga
├── staging/
│   └── ... 
└── analytics/
    └── ... 

/var/log/
├── db-backup-sync-prod. log
├── db-backup-sync-staging.log
└── db-backup-sync-analytics. log

/root/. ssh/
├── id_backup_sync                     # Clave privada para Servidor A
├── id_backup_sync.pub
├── id_backup_staging                  # Clave privada para Servidor B
└── id_backup_staging.pub

/usr/local/bin/
└── sync-db-backup -> /opt/db-backup-sync/bin/sync-db-backup.sh
```

---

## 🔍 Diagnóstico de problemas

### ❌ Error: "El archivo remoto no existe"

**Causa:** El nombre del archivo no coincide con el formato esperado. 

**Solución:**

1.  Listar archivos reales en el servidor remoto: 
   ```bash
   sudo ssh -i /root/.ssh/id_backup_sync appuser@192.168.1.100 \
     "sudo ls -lh /var/backups/db/"
   ```

2. Verificar el formato esperado:  `{YYYYMMDD}{HHmm}.{DB_NAME}. sql.gz`
   - Ejemplo correcto: `202601100300.produccion.sql.gz`
   - Ejemplo incorrecto:  `20260110_0300_produccion.sql.gz`

3. Ajustar variables en el `.conf`:
   ```bash
   DB_NAME="produccion"
   BACKUP_TIME="0300"
   ```

### ❌ Error: "sudo: no tty present and no askpass program specified"

**Causa:** El usuario no tiene permisos sudo configurados correctamente.

**Solución:**

1. En el servidor remoto, verificar configuración sudo:
   ```bash
   sudo -l -U appuser
   ```

2. Debe mostrar: 
   ```
   User appuser may run the following commands: 
       (root) NOPASSWD: /usr/bin/test -f /var/backups/db/*.sql. gz
       (root) NOPASSWD: /usr/bin/cat /var/backups/db/*.sql.gz
   ```

3. Si no aparece, revisar y corregir `/etc/sudoers` con `sudo visudo`

### ❌ Error:  "Permission denied (publickey)"

**Causa:** La clave SSH no está autorizada en el servidor remoto. 

**Solución:**

1. Re-copiar la clave pública: 
   ```bash
   sudo ssh-copy-id -i /root/.ssh/id_backup_sync.pub appuser@192.168.1.100
   ```

2. Verificar que quedó registrada: 
   ```bash
   sudo ssh -i /root/.ssh/id_backup_sync appuser@192.168.1.100 \
     "cat ~/. ssh/authorized_keys"
   ```

3. Verificar permisos en el servidor remoto:
   ```bash
   # Los permisos deben ser: 
   # ~/. ssh/                    700
   # ~/.ssh/authorized_keys     600
   ```

### ❌ Error:  "El archivo descargado está vacío"

**Causa:** El comando `sudo cat` falló o el archivo original está corrupto.

**Solución:**

1. Probar descarga manual:
   ```bash
   sudo ssh -i /root/.ssh/id_backup_sync appuser@192.168.1.100 \
     "sudo cat /var/backups/db/202601100300.produccion.sql.gz" > /tmp/test.sql. gz
   ```

2. Verificar tamaño del archivo descargado:
   ```bash
   ls -lh /tmp/test.sql.gz
   ```

3. Validar integridad: 
   ```bash
   gzip -t /tmp/test.sql.gz
   ```

### ❌ Error: "gzip: stdin: not in gzip format"

**Causa:** El archivo no es un gzip válido.

**Solución:**

1. Verificar tipo de archivo:
   ```bash
   file /var/backups/remote-db/produccion/202601100300.produccion.sql. gz
   ```

2. Si no es gzip, verificar el proceso de generación del backup en el servidor remoto

### ❌ Cron no ejecuta el script

**Causa:** Variables de entorno o rutas incorrectas en cron.

**Solución:**

1. Verificar que el cron está activo:
   ```bash
   sudo systemctl status cron
   ```

2. Revisar logs del sistema:
   ```bash
   sudo grep CRON /var/log/syslog | tail -20
   ```

3. Probar el comando exacto del cron manualmente:
   ```bash
   sudo /usr/local/bin/sync-db-backup -env /opt/db-backup-sync/etc/db-prod-serverA.conf
   ```

4. Verificar que el symlink existe:
   ```bash
   ls -l /usr/local/bin/sync-db-backup
   ```

---

## 🔐 Seguridad

### Mejores prácticas implementadas

✅ **Claves SSH dedicadas**:  Una clave por servidor/entorno  
✅ **Permisos restrictivos**: Archivos `.conf` con chmod 600  
✅ **Sudo granular**: Solo comandos específicos permitidos  
✅ **Rutas absolutas**: En sudoers para evitar ataques PATH  
✅ **BatchMode SSH**: No solicita contraseñas interactivas  
✅ **Validación de integridad**: Verifica formato gzip  
✅ **Descarga atómica**: Archivo temporal + renombrado  

### Auditoría

**Ver intentos de sudo en servidor remoto:**

```bash
sudo grep appuser /var/log/auth.log | tail -20
```

**Ver conexiones SSH:**

```bash
sudo grep "Accepted publickey" /var/log/auth.log | grep appuser
```

**Verificar permisos de archivos sensibles:**

```bash
# En Servidor B
sudo find /opt/db-backup-sync/etc -type f -ls
sudo find /root/.ssh -type f -name "id_backup*" -ls
```

---

## 📈 Monitoreo y Alertas

### Script de verificación de estado

Crear `/opt/db-backup-sync/bin/check-backups.sh`:

```bash
#!/usr/bin/env bash
#
# check-backups.sh - Verifica el estado de todos los backups
#

echo "🔍 Verificando estado de backups..."
echo ""

check_backup() {
  local name="$1"
  local dir="$2"
  local max_age_hours="${3:-25}"
  
  echo "📦 $name"
  echo "   Directorio: $dir"
  
  if [[ !  -d "$dir" ]]; then
    echo "   ❌ Directorio no existe"
    return 1
  fi
  
  local latest=$(ls -t "$dir"/*. sql.gz 2>/dev/null | head -1)
  
  if [[ -z "$latest" ]]; then
    echo "   ❌ No se encontraron backups"
    return 1
  fi
  
  local age=$(($(date +%s) - $(stat -c %Y "$latest")))
  local age_hours=$((age / 3600))
  local size=$(du -h "$latest" | awk '{print $1}')
  
  echo "   📄 Último:  $(basename "$latest")"
  echo "   📏 Tamaño: $size"
  echo "   ⏰ Antigüedad: ${age_hours}h"
  
  if [[ $age_hours -gt $max_age_hours ]]; then
    echo "   ⚠️ ALERTA: Backup tiene más de ${max_age_hours}h"
    return 1
  else
    echo "   ✅ OK"
  fi
  
  echo ""
}

# Verificar cada configuración
check_backup "Producción" "/var/backups/remote-db/produccion" 25
check_backup "Staging" "/var/backups/remote-db/staging" 25
check_backup "Analytics" "/var/backups/remote-db/analytics" 25

echo "✅ Verificación completada"
```

**Hacer ejecutable:**

```bash
sudo chmod +x /opt/db-backup-sync/bin/check-backups.sh
```

**Ejecutar:**

```bash
sudo /opt/db-backup-sync/bin/check-backups. sh
```

**Agregar a cron (verificación diaria a las 9:00 AM):**

```cron
0 9 * * * /opt/db-backup-sync/bin/check-backups.sh | mail -s "Estado Backups DB" admin@example.com
```

---

## 📝 Mantenimiento

### Rotación de logs

Crear `/etc/logrotate.d/db-backup-sync`:

```
/var/log/db-backup-sync-*. log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 640 root root
}
```

**Aplicar inmediatamente:**

```bash
sudo logrotate -f /etc/logrotate. d/db-backup-sync
```

### Actualizar el script

```bash
# Editar script
sudo nano /opt/db-backup-sync/bin/sync-db-backup.sh

# Verificar sintaxis
bash -n /opt/db-backup-sync/bin/sync-db-backup.sh

# Probar manualmente
sudo sync-db-backup -env /opt/db-backup-sync/etc/db-prod-serverA. conf
```

### Agregar nueva configuración

```bash
# 1. Copiar template
sudo cp /opt/db-backup-sync/etc/db-prod-serverA.conf \
        /opt/db-backup-sync/etc/db-new-serverD.conf

# 2. Editar valores
sudo nano /opt/db-backup-sync/etc/db-new-serverD.conf

# 3. Crear directorio local
sudo mkdir -p /var/backups/remote-db/new_db

# 4. Generar clave SSH
sudo ssh-keygen -t ed25519 -f /root/. ssh/id_backup_new -C "backup-sync-new" -N ""
sudo ssh-copy-id -i /root/.ssh/id_backup_new. pub user@servidor-d

# 5. Configurar sudo en servidor remoto
# (ver sección "Configurar permisos sudo")

# 6. Probar
sudo sync-db-backup -env /opt/db-backup-sync/etc/db-new-serverD. conf

# 7. Agregar a cron
sudo crontab -e
# 20 22 * * * /usr/local/bin/sync-db-backup -env /opt/db-backup-sync/etc/db-new-serverD.conf
```

---

## 🚀 Instalación rápida (script automatizado)

Crear `/tmp/install-db-backup-sync.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "🔧 Instalando DB Backup Sync..."

# Crear estructura
mkdir -p /opt/db-backup-sync/{bin,etc}
mkdir -p /var/backups/remote-db
mkdir -p /var/log

# Descargar script principal
curl -sSL https://raw.githubusercontent.com/tu-repo/db-backup-sync/main/bin/sync-db-backup.sh \
  -o /opt/db-backup-sync/bin/sync-db-backup.sh

chmod 750 /opt/db-backup-sync/bin/sync-db-backup.sh
chown root:root /opt/db-backup-sync/bin/sync-db-backup.sh

# Crear symlink
ln -sf /opt/db-backup-sync/bin/sync-db-backup.sh /usr/local/bin/sync-db-backup

echo "✅ Instalación completada"
echo ""
echo "📌 Próximos pasos:"
echo "1. Crear archivos de configuración en /opt/db-backup-sync/etc/"
echo "2. Generar claves SSH"
echo "3. Configurar sudo en servidores remotos"
echo "4. Probar: sync-db-backup -env /opt/db-backup-sync/etc/tu-config.conf"
echo "5. Configurar cron"
```

**Ejecutar:**

```bash
sudo bash /tmp/install-db-backup-sync.sh
```

---

## 📄 Licencia

Este proyecto es de uso interno. Ajustar según necesidades de tu organización.

---

## 👤 Contacto

**Mantenedor:** Equipo de Infraestructura  
**Email:** sysadmin@tuempresa.com  
**Documentación:** https://wiki.tuempresa.com/db-backup-sync

---

## 🔗 Referencias

- [OpenSSH Manual](https://www.openssh.com/manual.html)
- [Sudo Manual](https://www.sudo.ws/docs/man/sudoers.man/)
- [Cron HowTo](https://help.ubuntu.com/community/CronHowto)
- [Bash Best Practices](https://bertvv.github.io/cheat-sheets/Bash. html)
- [MySQL Backup Best Practices](https://dev.mysql.com/doc/refman/8.0/en/backup-methods.html)

---

## 📌 Changelog

### v1.0.0 (2026-01-10)
- ✅ Versión inicial
- ✅ Soporte multi-servidor con parámetro `-env`
- ✅ Validación de integridad gzip
- ✅ Política de retención configurable
- ✅ Logs separados por configuración
- ✅ Descarga atómica con archivos temporales