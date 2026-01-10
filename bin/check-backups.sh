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
  
  if [[ ! -d "$dir" ]]; then
    echo "   ❌ Directorio no existe"
    return 1
  fi
  
  local latest=$(ls -t "$dir"/*.sql.gz 2>/dev/null | head -1)
  
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
    echo "   ⚠️  ALERTA: Backup tiene más de ${max_age_hours}h"
    return 1
  else
    echo "   ✅ OK"
  fi
  
  echo ""
}

# Verificar cada configuración
# check_backup "Producción" "/var/backups/remote-db/produccion" 25
# check_backup "Staging" "/var/backups/remote-db/staging" 25
# check_backup "Analytics" "/var/backups/remote-db/analytics" 25

echo "✅ Verificación completada"