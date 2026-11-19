#!/usr/bin/env bash
# =============================================================================
#  SCRIPT PRINCIPAL DE ADMINISTRACIÓN POSTGRESQL
# =============================================================================
#
#  CURSO:        Administración de Bases de Datos
#  COMPATIBLE:   Debian 13 (Trixie) 
#
#  Este script carga los módulos de funcionalidad:
#    - utilitarias.sh    : Utilidades y conexión
#    - operaciones_db.sh : Backup, restore, create, delete, list
#    - gestion_sesiones.sh: Monitoreo y terminación de sesiones
#    - gestion_usuarios.sh : Gestión de usuarios y permisos
#
#  MODO DE USO:
#    chmod +x Adm_db.sh
#    ./Adm_db.sh
#    MTI JERM fines academicos 
# =============================================================================

# Modo de depuración
set -euo pipefail

# =============================================================================
#  CONFIGURACIÓN GLOBAL
# =============================================================================

# Parámetros de conexión PostgreSQL
PGHOST="${PGHOST:-localhost}"
PGPORT="${PGPORT:-5432}"
DEFAULT_DB="postgres"

# Directorios
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${BACKUP_DIR:-$SCRIPT_DIR/backups}"

# Usuario
PGUSER=""
PGPASSWORD=""
PGUSER_VALID=false

# Variables para selections
SELECTED_DB=""
SELECTED_FILE=""
SELECTED_USER=""
TARGET_USER=""

# =============================================================================
#  COLORES ANSI
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

# =============================================================================
#  CARGAR MÓDULOS
# =============================================================================
source "${SCRIPT_DIR}/lib/utilitarias.sh"
source "${SCRIPT_DIR}/lib/operaciones_db.sh"
source "${SCRIPT_DIR}/lib/gestion_sesiones.sh"
source "${SCRIPT_DIR}/lib/gestion_usuarios.sh"

# =============================================================================
#  PUNTO DE ENTRADA
# =============================================================================
mkdir -p "$BACKUP_DIR"

check_dependencies
ask_for_credentials

if $PGUSER_VALID; then
    show_main_menu
else
    echo_error "No se pudo establecer conexión"
    exit 1
fi
