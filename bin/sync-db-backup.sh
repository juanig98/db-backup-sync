#!/usr/bin/env bash
#
# sync-db-backup.sh
# Sincroniza backup de base de datos desde servidor remoto
#
# Uso: sync-db-backup.sh -env /ruta/al/archivo. conf
#
set -euo pipefail

# ============================================================
# Constantes
# ============================================================
SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="1.0.0"

# ============================================================
# Funciones auxiliares
# ============================================================
usage() {
  cat <<EOF
Uso: $SCRIPT_NAME -env <archivo_configuracion>

Sincroniza backups de base de datos desde un servidor remoto. 

Opciones:
  -env FILE     Archivo de configuración (requerido)
  -h, --help    Muestra esta ayuda

Ejemplo:
  $SCRIPT_NAME -env /opt/db-backup-sync/etc/db-prod. conf

EOF
  exit 0
}

log() {
  echo "[$(date -Iseconds)] $*" | tee -a "$LOG_FILE"
}

error() {
  echo "[$(date -Iseconds)] ERROR: $*" | tee -a "$LOG_FILE" >&2
}

# ============================================================
# Parseo de argumentos
# ============================================================
CONFIG_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -env)
      CONFIG_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "ERROR: Opción desconocida: $1" >&2
      echo "Usa -h para ver la ayuda" >&2
      exit 1
      ;;
  esac
done

# Validar que se pasó el archivo de configuración
if [[ -z "$CONFIG_FILE" ]]; then
  echo "ERROR:  Debes especificar un archivo de configuración con -env" >&2
  echo "Ejemplo: $SCRIPT_NAME -env /opt/db-backup-sync/etc/db-prod.conf" >&2
  exit 1
fi

# ============================================================
# Carga y validación de configuración
# ============================================================
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "ERROR: Archivo de configuración no encontrado: $CONFIG_FILE" >&2
  exit 1
fi

if [[ ! -r "$CONFIG_FILE" ]]; then
  echo "ERROR: No se puede leer el archivo de configuración: $CONFIG_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

# Variables requeridas
REQUIRED_VARS=(
  REMOTE_USER
  REMOTE_HOST
  SSH_KEY
  SSH_PORT
  REMOTE_DIR
  DB_NAME
  BACKUP_TIME
  LOCAL_DIR
  LOG_FILE
)

for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: Variable requerida '$var' no definida en $CONFIG_FILE" >&2
    exit 1
  fi
done

# Validar que la clave SSH existe
if [[ !  -f "$SSH_KEY" ]]; then
  echo "ERROR:  Clave SSH no encontrada:  $SSH_KEY" >&2
  exit 1
fi

# ============================================================
# Preparación
# ============================================================
TMP_DIR="${LOCAL_DIR}/.tmp"
mkdir -p "$LOCAL_DIR" "$TMP_DIR"
touch "$LOG_FILE"

# Construir nombre del archivo
TODAY_DATE=$(date +%Y%m%d)
REMOTE_FILE="${TODAY_DATE}${BACKUP_TIME}.${DB_NAME}.sql.gz"
REMOTE_FULL_PATH="${REMOTE_DIR}/${REMOTE_FILE}"

# Puerto SSH (opcional, por defecto 22)
SSH_PORT="${SSH_PORT:-22}"

log "====== Inicio de sincronización ======"
log "Versión: $SCRIPT_VERSION"
log "Configuración: $CONFIG_FILE"
log "Servidor remoto: ${REMOTE_USER}@${REMOTE_HOST}:${SSH_PORT}"
log "Archivo remoto: ${REMOTE_FULL_PATH}"

# ============================================================
# 1) Verificar existencia del archivo remoto
# ============================================================
log "Verificando existencia del archivo..."

if !  ssh -i "$SSH_KEY" \
     -p "$SSH_PORT" \
     -o BatchMode=yes \
     -o StrictHostKeyChecking=accept-new \
     -o ConnectTimeout=10 \
     "${REMOTE_USER}@${REMOTE_HOST}" \
     "sudo test -f '${REMOTE_FULL_PATH}'" 2>> "$LOG_FILE"; then
  error "El archivo no existe en el servidor remoto:  ${REMOTE_FULL_PATH}"
  exit 1
fi

log "✓ Archivo verificado en servidor remoto"

# ============================================================
# 2) Obtener información del archivo remoto
# ============================================================
REMOTE_SIZE=$(ssh -i "$SSH_KEY" \
     -p "$SSH_PORT" \
     -o BatchMode=yes \
     -o StrictHostKeyChecking=accept-new \
     "${REMOTE_USER}@${REMOTE_HOST}" \
     "sudo du -h '${REMOTE_FULL_PATH}'" 2>> "$LOG_FILE" | awk '{print $1}')

log "Tamaño remoto: ${REMOTE_SIZE}"

# ============================================================
# 3) Descargar archivo
# ============================================================
LOCAL_TMP="${TMP_DIR}/${REMOTE_FILE}. partial"
LOCAL_FINAL="${LOCAL_DIR}/${REMOTE_FILE}"

# Verificar si ya existe localmente
if [[ -f "$LOCAL_FINAL" ]]; then
  log "⚠️  El archivo ya existe localmente:  $LOCAL_FINAL"
  log "Saltando descarga..."
  log "====== Sincronización completada (archivo ya existente) ======"
  exit 0
fi

log "Descargando → ${LOCAL_FINAL}"

if ssh -i "$SSH_KEY" \
     -p "$SSH_PORT" \
     -o BatchMode=yes \
     -o StrictHostKeyChecking=accept-new \
     -o ConnectTimeout=10 \
     -o ServerAliveInterval=30 \
     -o ServerAliveCountMax=3 \
     -o Compression=yes \
     "${REMOTE_USER}@${REMOTE_HOST}" \
     "sudo cat '${REMOTE_FULL_PATH}'" > "$LOCAL_TMP" 2>> "$LOG_FILE"; then
  
  # Verificar que el archivo descargado no esté vacío
  if [[ !  -s "$LOCAL_TMP" ]]; then
    error "El archivo descargado está vacío"
    rm -f "$LOCAL_TMP"
    exit 1
  fi
  
  # Mover atómicamente
  mv -f "$LOCAL_TMP" "$LOCAL_FINAL"
  
  # Información del archivo descargado
  FILE_SIZE=$(du -h "$LOCAL_FINAL" | awk '{print $1}')
  
  # Validar que es un archivo gzip válido (opcional)
  if command -v gzip &> /dev/null; then
    if gzip -t "$LOCAL_FINAL" 2>> "$LOG_FILE"; then
      log "✓ Archivo gzip válido"
    else
      error "El archivo descargado no es un gzip válido"
      exit 1
    fi
  fi
  
  log "✓ Descarga exitosa:  ${REMOTE_FILE}"
  log "  Tamaño local: ${FILE_SIZE}"
else
  error "Falló la descarga de ${REMOTE_FILE}"
  rm -f "$LOCAL_TMP"
  exit 1
fi

# ============================================================
# 4) Limpieza de backups antiguos (retención)
# ============================================================
if [[ -n "${RETENTION_DAYS:-}" ]] && [[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]]; then
  log "Aplicando política de retención:  ${RETENTION_DAYS} días"
  
  # Buscar archivos antiguos
  OLD_FILES=$(find "$LOCAL_DIR" -maxdepth 1 -type f -name "*.sql.gz" \
              -mtime "+${RETENTION_DAYS}" -print)
  
  if [[ -n "$OLD_FILES" ]]; then
    DELETED=0
    while IFS= read -r file; do
      log "  Eliminando:  $(basename "$file")"
      rm -f "$file"
      ((DELETED++))
    done <<< "$OLD_FILES"
    
    log "✓ Eliminados ${DELETED} backup(s) antiguo(s)"
  else
    log "  No hay backups para eliminar"
  fi
fi

# ============================================================
# Finalización
# ============================================================
log "====== Sincronización completada exitosamente ======"
exit 0