#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Script:  Descargar backup de DB desde servidor remoto (A) a local (B)
# Uso: ./pull_db_backup_from_A.sh [/ruta/al/archivo. env]
# ============================================================

CONFIG_FILE="${1:-./pull.conf}"

# Verificar que existe el archivo de configuración
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "ERROR: Config file not found: $CONFIG_FILE" >&2
  exit 1
fi

# Cargar variables desde el archivo
# shellcheck disable=SC1090
source "$CONFIG_FILE"

# Validar variables obligatorias
REQUIRED_VARS=(
  REMOTE_USER
  REMOTE_HOST
  SSH_KEY
  REMOTE_DIR
  DB_NAME
  BACKUP_TIME
  LOCAL_DIR
  LOG_DIR
)

for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: Variable $var no está definida en $CONFIG_FILE" >&2
    exit 1
  fi
done

TODAY_DATE=$(date +%Y%m%d)
NOW=$(date +%Y%m%d%H%M)

# Crear directorios si no existen
LOG_FILE="${LOG_DIR}/${NOW}.log"
TMP_DIR="${LOCAL_DIR}/tmp"
mkdir -p "$LOCAL_DIR" "$TMP_DIR"
touch "$LOG_FILE"

# ============================================================
# Construir el nombre del archivo remoto con la fecha de hoy
# ============================================================
# Formato: YYYYMMddHHmm + DB_NAME + .sql.gz
# Ejemplo: 202601100300mi_base_de_datos.sql.gz
REMOTE_FILE="${TODAY_DATE}${BACKUP_TIME}.${DB_NAME}.sql.gz"
REMOTE_FULL_PATH="${REMOTE_DIR}/${REMOTE_FILE}"

echo "[$(date -Is)] ====== Iniciando descarga de backup ======" >> "$LOG_FILE"
echo "[$(date -Is)] Archivo remoto: ${REMOTE_FULL_PATH}" >> "$LOG_FILE"

# ============================================================
# 1) Verificar que el archivo existe (con sudo en remoto)
# ============================================================
if ! ssh -p"$REMOTE_PORT" -i "$SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
  "${REMOTE_USER}@${REMOTE_HOST}" \
  "sudo test -f ${REMOTE_FULL_PATH}" 2>> "$LOG_FILE"; then
  echo "[$(date -Is)] ERROR: El archivo remoto no existe: ${REMOTE_FULL_PATH}" >> "$LOG_FILE"
  exit 1
fi

# ============================================================
# 2) Descargar usando sudo cat en remoto y redirección local
# ============================================================
LOCAL_TMP="${TMP_DIR}/${REMOTE_FILE}.partiasudl"
LOCAL_FINAL="${LOCAL_DIR}/${REMOTE_FILE}"

echo "[$(date -Is)] Descargando a:  ${LOCAL_FINAL}" >> "$LOG_FILE"

if ssh -p"$REMOTE_PORT" -i "$SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
  "${REMOTE_USER}@${REMOTE_HOST}" \
  "sudo cat ${REMOTE_FULL_PATH}" > "$LOCAL_TMP" 2>> "$LOG_FILE"; then
  
  mv -f "$LOCAL_TMP" "$LOCAL_FINAL"
  
  FILE_SIZE=$(du -h "$LOCAL_FINAL" | cut -f1)
  
  echo "[$(date -Is)] ✓ OK: Descargado ${REMOTE_FILE} (${FILE_SIZE})" >> "$LOG_FILE"
else
  echo "[$(date -Is)] ✗ ERROR: Fallo en la descarga de ${REMOTE_FILE}" >> "$LOG_FILE"
  rm -f "$LOCAL_TMP"
  exit 1
fi

# ============================================================
# 3) Opcional: Limpiar backups antiguos
# ============================================================
if [[ -n "${RETENTION_DAYS:-}" ]] && [[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]]; then
  echo "[$(date -Is)] Limpiando backups con más de ${RETENTION_DAYS} días..." >> "$LOG_FILE"
  find "$LOCAL_DIR" -maxdepth 1 -type f -name "*.sql.gz" -mtime "+${RETENTION_DAYS}" -delete
  echo "[$(date -Is)] Limpieza completada" >> "$LOG_FILE"
fi

echo "[$(date -Is)] ====== Proceso finalizado correctamente ======" >> "$LOG_FILE"