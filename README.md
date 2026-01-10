# 🔄 DB Backup Sync

Sistema automatizado para sincronizar backups de bases de datos desde un servidor remoto mediante SSH/SFTP con elevación de privilegios (sudo).

## 📋 Descripción

Este proyecto permite descargar automáticamente backups de bases de datos desde un servidor remoto (origen) a un servidor local (destino) cuando el backup está generado por root pero el acceso SSH es mediante un usuario sin privilegios.

**Características:**
- ✅ Acceso mediante SSH con clave pública
- ✅ Elevación de privilegios con sudo en servidor remoto
- ✅ Verificación de existencia del archivo antes de descargar
- ✅ Descarga atómica (archivo temporal → renombrado final)
- ✅ Política de retención configurable
- ✅ Logs detallados con timestamps
- ✅ Validación de archivos vacíos

---

## 🏗️ Arquitectura

```
┌─────────────────────────┐         SSH + sudo cat          ┌──────────────────────────┐
│  Servidor A (Origen)    │ ◄─────────────────────────────  │  Servidor B (Destino)   │
│                         │                                  │                          │
│  /var/backups/db/       │                                  │  /var/backups/remote-db/ │
│  └─ 202601100300prod...  │                                  │  └─ backups descargados  │
│                         │                                  │                          │
│  Usuario: appuser       │                                  │  Usuario:  root (cron)    │
│  Backup owner: root     │                                  │                          │
└─────────────────────────┘                                  └──────────────────────────┘
```

---

## 📦 Instalación

### 1️⃣ En Servidor B (Destino)

#### a) Crear estructura de directorios

```bash
sudo mkdir -p /opt/db-backup-sync/bin
sudo mkdir -p /var/backups/remote-db
sudo mkdir -p /var/log
```

#### b) Copiar el script principal

```bash
sudo nano /opt/db-backup-sync/bin/sync-db-backup.sh
```

Pegar el contenido del script y guardar.

**Establecer permisos:**

```bash
sudo chmod 750 /opt/db-backup-sync/bin/sync-db-backup.sh
sudo chown root:root /opt/db-backup-sync/bin/sync-db-backup.sh
```

#### c) Crear symlink para facilitar ejecución

```bash
sudo ln -sf /opt/db-backup-sync/bin/sync-db-backup.sh /usr/local/bin/sync-db-backup
```

#### d) Crear archivo de configuración

```bash
sudo nano /etc/db-backup-sync.conf
```

**Contenido mínimo:**

```bash
# === Servidor remoto (origen) ===
REMOTE_USER="appuser"
REMOTE_HOST="192.168.1.100"
SSH_KEY="/root/.ssh/id_backup_sync"
REMOTE_DIR="/var/backups/db"

# === Configuración del backup ===
DB_NAME="produccion"
BACKUP_TIME="0300"

# === Almacenamiento local ===
LOCAL_DIR="/var/backups/remote-db"
LOG_DIR="/var/log/db-backup-sync"

# === Retención (días) ===
RETENTION_DAYS="7"
```

**Establecer permisos (archivo contiene rutas sensibles):**

```bash
sudo chmod 600 /etc/db-backup-sync.conf
sudo chown root:root /etc/db-backup-sync.conf
```

#### e) Generar par de claves SSH

```bash
sudo ssh-keygen -t ed25519 -f /root/.ssh/id_backup_sync -C "backup-sync" -N ""
```

Copiar la clave pública al servidor remoto: 

```bash
sudo ssh-copy-id -i /root/.ssh/id_backup_sync. pub appuser@192.168.1.100
```

**Probar conexión:**

```bash
sudo ssh -i /root/.ssh/id_backup_sync appuser@192.168.1.100 "echo 'Conexión OK'"
```

---

### 2️⃣ En Servidor A (Origen/Remoto)

#### a) Configurar permisos sudo para appuser

Editar configuración de sudoers:

```bash
sudo visudo
```

**Agregar al final del archivo:**

```sudoers
# Permitir a appuser leer backups de DB sin contraseña
appuser ALL=(root) NOPASSWD: /usr/bin/test -f /var/backups/db/*. sql.gz
appuser ALL=(root) NOPASSWD: /usr/bin/cat /var/backups/db/*. sql.gz
```

> ⚠️ **Importante:** Ajustar la ruta `/var/backups/db/` según tu configuración real.

**Validar sintaxis:**

```bash
sudo visudo -c
```

#### b) Probar permisos desde Servidor B

Desde el **Servidor B**, ejecutar: 

```bash
# Probar test
sudo ssh -i /root/.ssh/id_backup_sync appuser@192.168.1.100 \
  "sudo test -f /var/backups/db/test.sql.gz && echo 'OK' || echo 'FAIL'"

# Probar cat (si existe un backup)
sudo ssh -i /root/.ssh/id_backup_sync appuser@192.168.1.100 \
  "sudo cat /var/backups/db/202601100300produccion.sql.gz" | head -c 100
```

---

## ⚙️ Configuración del archivo `.conf`

| Variable | Descripción | Ejemplo |
|----------|-------------|---------|
| `REMOTE_USER` | Usuario SSH en servidor origen | `appuser` |
| `REMOTE_HOST` | IP o hostname del servidor origen | `192.168.1.100` o `db-server.example.com` |
| `SSH_KEY` | Ruta a la clave privada SSH | `/root/.ssh/id_backup_sync` |
| `REMOTE_DIR` | Directorio donde están los backups en origen | `/var/backups/db` |
| `DB_NAME` | Nombre de la base de datos (para construir el nombre del archivo) | `produccion` |
| `BACKUP_TIME` | Hora de generación del backup (formato HHmm) | `0300` (3:00 AM) |
| `LOCAL_DIR` | Directorio local donde guardar los backups | `/var/backups/remote-db` |
| `LOG_DIR` | Ruta donde se guardarán los logs | `/var/log/db-backup-sync` |
| `RETENTION_DAYS` | Días de retención (dejar vacío para no borrar) | `7`, `14`, `30` |

### Formato del nombre del archivo de backup

El script construye el nombre del archivo como: 

```
{YYYYMMDD}{HHmm}.{DB_NAME}.sql.gz
```

**Ejemplo:**
- Fecha: 10 de enero de 2026
- Hora: 03:00 AM
- Base:  `produccion`
- **Resultado:** `202601100300.produccion.sql.gz`

---

## ⏰ Configuración de Cron

### En Servidor B (Destino) - Ejecutar sincronización

Editar crontab de root:

```bash
sudo crontab -e
```

**Agregar línea para ejecutar todos los días a las 22:05:**

```cron
# Sincronizar backup de DB desde servidor remoto
5 22 * * * /usr/local/bin/sync-db-backup >> /var/log/db-backup-sync.log 2>&1
```

**Verificar crontab:**

```bash
sudo crontab -l
```

---

## 🧪 Pruebas

### 1. Prueba manual

```bash
sudo /usr/local/bin/sync-db-backup
```

### 2. Ver logs en tiempo real

```bash
sudo tail -f /var/log/db-backup-sync.log
```

### 3. Verificar backups descargados

```bash
ls -lh /var/backups/remote-db/
```

### 4. Probar con archivo de configuración alternativo

```bash
sudo sync-db-backup /etc/db-backup-sync-test.conf
```

---

## 📊 Estructura de archivos

```
/opt/db-backup-sync/
├── bin/
│   └── sync-db-backup.sh          # Script principal

/etc/
└── db-backup-sync.conf             # Configuración

/var/
├── backups/
│   └── remote-db/                  # Backups descargados
│       ├── 202601090300.produccion.sql.gz
│       ├── 202601100300.produccion.sql.gz
│       ├── 202601110300.produccion.sql.gz
│       └── . tmp/                   # Temporales durante descarga
└── log/
    └── db-backup-sync
        └── 202601090305.log          # Logs del sistema
        └── 202601100305.log          # Logs del sistema
        └── 202601110305.log          # Logs del sistema

/root/. ssh/
└── id_backup_sync                  # Clave privada SSH
```

---

## 🔍 Diagnóstico de problemas

### ❌ Error:  "El archivo remoto no existe"

**Causa:** El nombre del archivo no coincide con lo esperado. 

**Solución:**
1. Listar archivos en el servidor remoto:
   ```bash
   sudo ssh -i /root/.ssh/id_backup_sync appuser@192.168.1.100 \
     "sudo ls -lh /var/backups/db/"
   ```
2. Verificar que el nombre coincida con el patrón:  `{FECHA}{HORA}{NOMBRE}. sql.gz`
3. Ajustar variables `DB_NAME` y `BACKUP_TIME` en `/etc/db-backup-sync. conf`

### ❌ Error: "sudo: no tty present and no askpass program specified"

**Causa:** El usuario no tiene permisos sudo sin contraseña.

**Solución:**
- Verificar configuración en servidor A:
  ```bash
  sudo -l -U appuser
  ```
- Debe mostrar las líneas del `visudo` configuradas. 

### ❌ Error:  "Permission denied (publickey)"

**Causa:** La clave SSH no está configurada correctamente.

**Solución:**
1. Verificar que la clave pública esté en el servidor remoto: 
   ```bash
   sudo ssh -i /root/.ssh/id_backup_sync appuser@192.168.1.100 \
     "cat ~/. ssh/authorized_keys"
   ```
2. Re-copiar la clave: 
   ```bash
   sudo ssh-copy-id -i /root/.ssh/id_backup_sync.pub appuser@192.168.1.100
   ```

### ❌ El archivo descargado está vacío

**Causa:** El comando `sudo cat` falló silenciosamente.

**Solución:**
- Probar manualmente: 
  ```bash
  sudo ssh -i /root/.ssh/id_backup_sync appuser@192.168.1.100 \
    "sudo cat /var/backups/db/archivo.sql.gz" | file -
  ```
- Verificar permisos del archivo en servidor remoto:
  ```bash
  sudo ssh -i /root/.ssh/id_backup_sync appuser@192.168.1.100 \
    "sudo ls -lh /var/backups/db/archivo.sql.gz"
  ```

---

## 🔐 Seguridad

### Recomendaciones

1. **Clave SSH dedicada:** Usar una clave exclusiva para este proceso
2. **Permisos restrictivos en sudoers:** Solo comandos específicos (`test`, `cat`)
3. **Rutas absolutas en sudoers:** Evitar que se ejecuten comandos alternativos
4. **Archivo . conf con permisos 600:** Solo root puede leerlo
5. **Logs protegidos:** Verificar que no contengan información sensible

### Auditoría

Ver intentos de uso de sudo en servidor A:

```bash
sudo grep appuser /var/log/auth.log | tail -20
```

---

## 📈 Monitoreo y alertas (opcional)

### Crear script de verificación

```bash
#!/bin/bash
LATEST=$(ls -t /var/backups/remote-db/*. sql.gz 2>/dev/null | head -1)
AGE=$(($(date +%s) - $(stat -c %Y "$LATEST" 2>/dev/null || echo 0)))

if [ $AGE -gt 90000 ]; then  # 25 horas
  echo "⚠️  ALERTA: Último backup tiene más de 25 horas"
  # Enviar notificación (email, Telegram, etc.)
fi
```

---

## 📝 Mantenimiento

### Rotación de logs

Crear `/etc/logrotate.d/db-backup-sync`:

```
/var/log/db-backup-sync.log {
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
}
```

### Actualizar el script

```bash
sudo nano /opt/db-backup-sync/bin/sync-db-backup.sh
# Hacer cambios
sudo chmod 750 /opt/db-backup-sync/bin/sync-db-backup.sh
```

---

## 📄 Licencia

Este proyecto es de uso interno.  Ajustar según necesidades de tu organización.

---

## 👤 Autor

**Contacto:** juanigalarza98@gmail.com

---

## 🔗 Referencias

- [OpenSSH Documentation](https://www.openssh.com/manual.html)
- [Sudo Manual](https://www.sudo.ws/docs/man/sudoers.man/)
- [Cron HowTo](https://help.ubuntu.com/community/CronHowto)