#!/usr/bin/env bash
# =============================================================================
#  MÓDULO: UTILERÍAS Y FUNCIONES AUXILIARES MTI JERM
# =============================================================================

# -----------------------------------------------------------------------------
#  header - Limpia pantalla y muestra información del sistema
# -----------------------------------------------------------------------------
header() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║         ADMINISTRADOR DE BASES DE DATOS POSTGRESQL          ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${CYAN}Usuario:${NC} ${PGUSER:-No configurado}"
    echo -e "  ${CYAN}Servidor:${NC} ${PGHOST}:${PGPORT}"
    echo -e "  ${CYAN}Backups:${NC} ${BACKUP_DIR}"
    echo -e "  ${CYAN}Estado:${NC} $(if $PGUSER_VALID; then echo -e "${GREEN}Conectado${NC}"; else echo -e "${RED}Desconectado${NC}"; fi)"
    echo ""
    echo -e "${BLUE}────────────────────────────────────────────────────────────────${NC}"
}

# -----------------------------------------------------------------------------
#  pause - Pausa hasta presionar ENTER
# -----------------------------------------------------------------------------
pause() {
    echo ""
    echo -e "${YELLOW}Presiona ${BOLD}ENTER${NC} ${YELLOW}para continuar...${NC}"
    read -r
}

# -----------------------------------------------------------------------------
#  Funciones de mensajes
# -----------------------------------------------------------------------------
echo_error()   { echo -e "  ${RED}✗${NC} $1"; }
echo_success() { echo -e "  ${GREEN}✓${NC} $1"; }
echo_info()    { echo -e "  ${CYAN}➜${NC} $1"; }
echo_warn()    { echo -e "  ${YELLOW}⚠${NC} $1"; }

# -----------------------------------------------------------------------------
#  processing - Indicador de progreso
# -----------------------------------------------------------------------------
processing() {
    local delay=0.3
    echo -ne "${YELLOW}"
    for i in {1..5}; do
        echo -ne "▓"
        sleep "$delay"
    done
    echo -ne "${NC} "
}

# -----------------------------------------------------------------------------
#  check_dependencies - Verifica herramientas instaladas
# -----------------------------------------------------------------------------
check_dependencies() {
    local deps=("psql" "pg_dump" "pg_restore")
    local missing=()
    
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        echo_error "Faltan dependencias:"
        echo "  Instale con: sudo apt install postgresql-client"
        exit 1
    fi
}

# =============================================================================
#  CAPA DE ACCESO A DATOS
# =============================================================================

# -----------------------------------------------------------------------------
#  run_psql - Ejecuta psql con contraseña de forma segura
# -----------------------------------------------------------------------------
run_psql() {
    if [ -n "$PGPASSWORD" ]; then
        PGPASSWORD="$PGPASSWORD" "$@"
    else
        "$@"
    fi
}

# -----------------------------------------------------------------------------
#  run_pg_dump - Ejecuta pg_dump
# -----------------------------------------------------------------------------
run_pg_dump() {
    if [ -n "$PGPASSWORD" ]; then
        PGPASSWORD="$PGPASSWORD" "$@"
    else
        "$@"
    fi
}

# -----------------------------------------------------------------------------
#  run_pg_restore - Ejecuta pg_restore
# -----------------------------------------------------------------------------
run_pg_restore() {
    if [ -n "$PGPASSWORD" ]; then
        PGPASSWORD="$PGPASSWORD" "$@"
    else
        "$@"
    fi
}

# -----------------------------------------------------------------------------
#  get_database_list - Lista bases de datos
# -----------------------------------------------------------------------------
get_database_list() {
    run_psql psql -U "$PGUSER" -h "$PGHOST" -p "$PGPORT" -d "$DEFAULT_DB" -tA -c "
        SELECT datname 
        FROM pg_database 
        WHERE datistemplate = false 
        AND datname NOT IN ('postgres')
        ORDER BY datname;
    "
}

# -----------------------------------------------------------------------------
#  get_backup_files - Lista archivos de backup
# -----------------------------------------------------------------------------
get_backup_files() {
    find "$BACKUP_DIR" -maxdepth 1 -type f \( -name "*.backup" -o -name "*.dump" -o -name "*.sql" \) 2>/dev/null | sort
}

# =============================================================================
#  FUNCIONES DE SELECCIÓN
# =============================================================================

# -----------------------------------------------------------------------------
#  select_database - Seleccionar base de datos por número
# -----------------------------------------------------------------------------
select_database() {
    header
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║              SELECCIONAR BASE DE DATOS                  ║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    local dbs
    dbs=$(get_database_list)
    
    if [ -z "$dbs" ]; then
        echo_error "No se encontraron bases de datos"
        return 1
    fi
    
    mapfile -t db_array <<< "$dbs"
    
    echo -e "${CYAN}Bases de datos:${NC}"
    echo ""
    for i in "${!db_array[@]}"; do
        echo -e "  ${GREEN}$((i+1))${NC}) ${db_array[$i]}"
    done
    echo ""
    echo -e "  ${GREEN}0${NC}) Cancelar"
    echo ""
    
    read -p "# " selection
    
    if [ "$selection" = "0" ] || [ -z "$selection" ]; then
        return 1
    fi
    
    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le ${#db_array[@]} ]; then
        SELECTED_DB="${db_array[$((selection-1))]}"
        return 0
    else
        echo_error "Selección inválida"
        return 1
    fi
}

# -----------------------------------------------------------------------------
#  select_backup_file - Seleccionar archivo de backup
# -----------------------------------------------------------------------------
select_backup_file() {
    header
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║            SELECCIONAR ARCHIVO DE RESPALDO               ║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    mkdir -p "$BACKUP_DIR"
    local files
    files=$(get_backup_files)
    
    if [ -z "$files" ]; then
        echo_error "No hay archivos en: $BACKUP_DIR"
        return 1
    fi
    
    mapfile -t file_array <<< "$files"
    
    echo -e "${CYAN}Archivos disponibles:${NC}"
    echo ""
    for i in "${!file_array[@]}"; do
        local filename size
        filename=$(basename "${file_array[$i]}")
        size=$(du -h "${file_array[$i]}" | cut -f1)
        echo -e "  ${GREEN}$((i+1))${NC}) $filename ($size)"
    done
    echo ""
    echo -e "  ${GREEN}0${NC}) Cancelar"
    echo ""
    
    read -p "# " selection
    
    if [ "$selection" = "0" ] || [ -z "$selection" ]; then
        return 1
    fi
    
    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le ${#file_array[@]} ]; then
        SELECTED_FILE="${file_array[$((selection-1))]}"
        return 0
    else
        return 1
    fi
}

# -----------------------------------------------------------------------------
#  select_user_from_list - Seleccionar usuario por número
# -----------------------------------------------------------------------------
select_user_from_list() {
    local users
    users=$(run_psql psql -U "$PGUSER" -h "$PGHOST" -p "$PGPORT" -d "$DEFAULT_DB" -tA -c "
        SELECT rolname FROM pg_roles 
        WHERE rolname NOT LIKE 'pg_%' 
        ORDER BY rolname;
    " 2>/dev/null)
    
    [ -z "$users" ] && return 1
    
    mapfile -t user_array <<< "$users"
    
    for i in "${!user_array[@]}"; do
        echo -e "  ${GREEN}$((i+1))${NC}) ${user_array[$i]}"
    done
    echo ""
    echo -e "  ${GREEN}0${NC}) Cancelar"
    echo ""
    
    read -p "# " selection
    
    if [ "$selection" = "0" ] || [ -z "$selection" ]; then
        return 1
    fi
    
    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le ${#user_array[@]} ]; then
        SELECTED_USER="${user_array[$((selection-1))]}"
        return 0
    else
        return 1
    fi
}

# =============================================================================
#  FUNCIONES DE CONEXIÓN
# =============================================================================

ask_for_credentials() {
    header
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║              CONFIGURAR CONEXIÓN A POSTGRESQL             ║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    read -p "Host [${PGHOST}]: " input_host
    [ -n "$input_host" ] && PGHOST="$input_host"
    
    read -p "Puerto [${PGPORT}]: " input_port
    [ -n "$input_port" ] && PGPORT="$input_port"
    
    while [ -z "$PGUSER" ]; do
        read -p "Usuario PostgreSQL: " PGUSER
    done
    
    while [ -z "$PGPASSWORD" ]; do
        read -s -p "Password (obligatorio): " PGPASSWORD
        echo ""
        [ -z "$PGPASSWORD" ] && echo_error "Password es obligatorio"
    done
    
    validate_connection
}

validate_connection() {
    header
    echo_info "Validando conexión..."
    echo ""
    
    if PGPASSWORD="$PGPASSWORD" psql -U "$PGUSER" -h "$PGHOST" -p "$PGPORT" -d "$DEFAULT_DB" -c "SELECT 1;" &>/dev/null; then
        PGUSER_VALID=true
        echo_success "Conexión establecida"
    else
        PGUSER_VALID=false
        echo_error "No se pudo conectar"
        echo_warn "Verifique: servidor activo, usuario y contraseña"
    fi
    
    pause
}

# =============================================================================
#  MENÚ PRINCIPAL
# =============================================================================

show_main_menu() {
    while true; do
        header
        echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${MAGENTA}║                       MENÚ PRINCIPAL                      ║${NC}"
        echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "  ${CYAN}Operaciones de Base de Datos:${NC}"
        echo -e "    ${GREEN}1${NC}) + Crear base"
        echo -e "    ${GREEN}2${NC}) ⬇ Respaldar"
        echo -e "    ${GREEN}3${NC}) ⬆ Restaurar"
        echo -e "    ${GREEN}4${NC}) ✕ Eliminar base"
        echo -e "    ${GREEN}5${NC}) ▣ Listar bases"
        echo ""
        echo -e "  ${CYAN}Monitoreo:${NC}"
        echo -e "    ${GREEN}6${NC}) Sesiones activas"
        echo -e "    ${GREEN}7${NC}) 🧹 Limpiar backups"
        echo ""
        echo -e "  ${CYAN}Gestión de Usuarios:${NC}"
        echo -e "    ${GREEN}A${NC}) 👤 Administrar usuarios"
        echo ""
        echo -e "  ${CYAN}Configuración:${NC}"
        echo -e "    ${GREEN}8${NC}) Cambiar conexión"
        echo -e "    ${GREEN}9${NC}) Carpeta backups"
        echo ""
        echo -e "  ${YELLOW}0${NC}) Salir"
        echo ""
        
        read -p "# " op
        
        case "$op" in
            1) create_database ;;
            2) backup_database ;;
            3) restore_database ;;
            4) delete_database ;;
            5) list_databases ;;
            6) monitor_sessions ;;
            7) cleanup_old_backups ;;
            A|a) user_management ;;
            8) ask_for_credentials ;;
            9) change_backup_dir ;;
            0) 
                echo ""
                echo_info "Gracias por usar el administrador"
                exit 0 
                ;;
            *) echo_error "Opción inválida"; sleep 1 ;;
        esac
    done
}

change_backup_dir() {
    header
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║              CAMBIAR CARPETA DE BACKUPS                    ║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "Actual: ${CYAN}${BACKUP_DIR}${NC}"
    echo ""
    read -p "Nueva carpeta: " new_dir
    
    [ -z "$new_dir" ] && { echo_error "Inválida"; pause; return; }
    
    if [ ! -d "$new_dir" ]; then
        read -p "Crear carpeta? (s/n): " confirm
        [ "${confirm,,}" != "s" ] && return
        mkdir -p "$new_dir"
    fi
    
    BACKUP_DIR="$new_dir"
    echo_success "Carpeta actualizada"
    pause
}
