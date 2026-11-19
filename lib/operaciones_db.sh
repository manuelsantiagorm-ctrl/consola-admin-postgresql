#!/usr/bin/env bash
# =============================================================================
#  MÓDULO: OPERACIONES DE BASE DE DATOS MTI JERM
# =============================================================================

# -----------------------------------------------------------------------------
#  create_database - Crear nueva base de datos
# -----------------------------------------------------------------------------
create_database() {
    header
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║                CREAR NUEVA BASE DE DATOS                  ║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    $PGUSER_VALID || { echo_error "Sin conexión"; pause; return; }
    
    read -p "Nombre: " new_db
    [ -z "$new_db" ] && { echo_error "Nombre requerido"; pause; return; }
    
    if run_psql psql -U "$PGUSER" -h "$PGHOST" -p "$PGPORT" -d "$DEFAULT_DB" -tA -c "SELECT 1 FROM pg_database WHERE datname = '$new_db';" 2>/dev/null | grep -q 1; then
        echo_error "Ya existe"
        pause
        return
    fi
    
    read -p "Dueño [${PGUSER}]: " owner
    [ -z "$owner" ] && owner="$PGUSER"
    
    if run_psql psql -U "$PGUSER" -h "$PGHOST" -p "$PGPORT" -d "$DEFAULT_DB" -c "CREATE DATABASE \"$new_db\" OWNER \"$owner\" ENCODING 'UTF8';" 2>/dev/null; then
        echo_success "Base '$new_db' creada"
    else
        echo_error "Error al crear"
    fi
    
    pause
}

# -----------------------------------------------------------------------------
#  backup_database - Respaldar base de datos
# -----------------------------------------------------------------------------
backup_database() {
    header
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║                    RESPALDO DE BASE                      ║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    $PGUSER_VALID || { echo_error "Sin conexión"; pause; return; }
    
    select_database || { pause; return; }
    
    local timestamp filename filepath
    timestamp=$(date +%Y%m%d_%H%M%S)
    filename="${SELECTED_DB}_${timestamp}.backup"
    filepath="$BACKUP_DIR/$filename"
    
    mkdir -p "$BACKUP_DIR"
    
    echo ""
    echo_info "Base: $SELECTED_DB"
    echo_info "Archivo: $filename"
    read -p "Confirmar? (s/n): " confirm
    [[ "${confirm,,}" != "s" ]] && return
    
    echo ""
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
    echo -e "${CYAN}  PROCESANDO RESPALDO...${NC}"
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
    echo ""
    
    # Ejecutar backup mostrando toda la salida verbose
    run_pg_dump pg_dump \
        -U "$PGUSER" -h "$PGHOST" -p "$PGPORT" \
        -F c -v --no-owner --no-privileges \
        -d "$SELECTED_DB" -f "$filepath" 2>&1
    
    local exit_code=$?
    
    echo ""
    if [ $exit_code -eq 0 ]; then
        local size
        size=$(du -h "$filepath" | cut -f1)
        echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
        echo_success "Respaldo completado: $filename ($size)"
    else
        echo_error "Error en respaldo (código: $exit_code)"
    fi
    
    echo ""
    echo "Presione ENTER para continuar..."
    read
}

# -----------------------------------------------------------------------------
#  restore_database - Restaurar base de datos
# -----------------------------------------------------------------------------
restore_database() {
    header
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║               RESTAURAR BASE DE DATOS                    ║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    $PGUSER_VALID || { echo_error "Sin conexión"; pause; return; }
    
    select_backup_file || { pause; return; }
    select_database || { pause; return; }
    
    local backup_size
    backup_size=$(du -h "$SELECTED_FILE" | cut -f1)
    
    echo ""
    echo_info "Archivo: $(basename "$SELECTED_FILE") ($backup_size)"
    echo_info "Base destino: $SELECTED_DB"
    echo ""
    echo_warn "Esto puede modificar datos existentes"
    read -p "Confirmar? (s/n): " confirm
    [[ "${confirm,,}" != "s" ]] && return
    
    echo ""
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
    echo -e "${CYAN}  PROCESANDO RESTAURACIÓN...${NC}"
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
    echo ""
    
    # Ejecutar restore mostrando toda la salida verbose
    run_pg_restore pg_restore \
        -U "$PGUSER" -h "$PGHOST" -p "$PGPORT" \
        --clean --if-exists -v \
        -d "$SELECTED_DB" "$SELECTED_FILE" 2>&1
    
    local exit_code=$?
    
    echo ""
    if [ $exit_code -eq 0 ]; then
        echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
        echo_success "Restauración completada"
    else
        echo_error "Error en restauración (código: $exit_code)"
    fi
    
    echo ""
    echo "Presione ENTER para continuar..."
    read
}

# -----------------------------------------------------------------------------
#  delete_database - Eliminar base de datos
# -----------------------------------------------------------------------------
delete_database() {
    header
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║                ELIMINAR BASE DE DATOS                    ║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    $PGUSER_VALID || { echo_error "Sin conexión"; pause; return; }
    
    select_database || { pause; return; }
    
    echo ""
    echo_warn "SE ELIMINARÁ: $SELECTED_DB"
    read -p "Escriba el nombre para confirmar: " confirm
    [ "$confirm" != "$SELECTED_DB" ] && { echo_info "Cancelado"; pause; return; }
    
    echo_info "Cerrando sesiones..."
    run_psql psql -U "$PGUSER" -h "$PGHOST" -p "$PGPORT" -d "$DEFAULT_DB" -c "
        SELECT pg_terminate_backend(pid)
        FROM pg_stat_activity
        WHERE datname = '$SELECTED_DB' AND pid <> pg_backend_pid();
    " 2>/dev/null || true
    
    sleep 1
    
    if run_psql psql -U "$PGUSER" -h "$PGHOST" -p "$PGPORT" -d "$DEFAULT_DB" -c "DROP DATABASE \"$SELECTED_DB\";" 2>/dev/null; then
        echo_success "Base eliminada"
    else
        echo_error "No se pudo eliminar"
    fi
    
    pause
}

# -----------------------------------------------------------------------------
#  list_databases - Listar bases de datos
# -----------------------------------------------------------------------------
list_databases() {
    header
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║                 LISTAR BASES DE DATOS                    ║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    $PGUSER_VALID || { echo_error "Sin conexión"; pause; return; }
    
    local dbs
    dbs=$(run_psql psql -U "$PGUSER" -h "$PGHOST" -p "$PGPORT" -d "$DEFAULT_DB" -tA -c "
        SELECT 
            d.datname as base,
            COALESCE(pg_size_pretty(pg_database_size(d.datname)), 'N/A') as size,
            COALESCE(r.rolname, 'N/A') as owner
        FROM pg_database d
        LEFT JOIN pg_roles r ON d.datdba = r.oid
        WHERE d.datistemplate = false
        ORDER BY pg_database_size(d.datname) DESC;
    ")
    
    echo -e "${CYAN}Base           | Tamaño   | Dueño${NC}"
    echo -e "${CYAN}----------------|----------|------------${NC}"
    echo "$dbs" | while IFS='|' read -r base size owner; do
        printf "%-15s | %-8s | %s\n" "${base:0:15}" "${size:0:8}" "$owner"
    done
    
    pause
}

# -----------------------------------------------------------------------------
#  cleanup_old_backups - Eliminar backups
# -----------------------------------------------------------------------------
cleanup_old_backups() {
    while true; do
        header
        echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${MAGENTA}║            LIMPIEZA DE BACKUPS                          ║${NC}"
        echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        $PGUSER_VALID || { echo_error "Sin conexión"; pause; return; }
        
        # Mostrar todos los backups disponibles
        local files
        files=$(find "$BACKUP_DIR" -maxdepth 1 -type f \( -name "*.backup" -o -name "*.dump" -o -name "*.sql" \) -printf "%f\n" 2>/dev/null | sort)
        
        if [ -z "$files" ]; then
            echo_info "No hay archivos de backup en: $BACKUP_DIR"
            pause
            return
        fi
        
        mapfile -t file_array <<< "$files"
        
        echo -e "${CYAN}Archivos disponibles:${NC}"
        echo ""
        for i in "${!file_array[@]}"; do
            local full_path="$BACKUP_DIR/${file_array[$i]}"
            local size date
            size=$(du -h "$full_path" 2>/dev/null | cut -f1)
            date=$(stat -c "%y" "$full_path" 2>/dev/null | cut -d' ' -f1 || stat -f "%Sm" -t "%Y-%m-%d" "$full_path" 2>/dev/null)
            [ -z "$date" ] && date=$(ls -la --time-style=+%Y-%m-%d "$full_path" 2>/dev/null | awk '{print $6}')
            echo -e "  ${GREEN}$((i+1))${NC}) ${file_array[$i]} | $size | $date"
        done
        
        echo ""
        echo -e "${CYAN}Opciones:${NC}"
        echo -e "  ${GREEN}1-${#file_array[@]}${NC}) Seleccionar archivo(s)"
        echo -e "  ${GREEN}F${NC}) Filtrar por fecha"
        echo -e "  ${GREEN}A${NC}) Seleccionar todos"
        echo -e "  ${GREEN}0${NC}) Volver"
        echo ""
        
        read -p "# " selection
        
        case "$selection" in
            0) return ;;
            F|f)
                cleanup_by_date
                ;;
            A|a)
                # Seleccionar todos
                declare -a SELECTED_FILES=()
                for f in "${file_array[@]}"; do
                    SELECTED_FILES+=("$BACKUP_DIR/$f")
                done
                confirm_delete
                ;;
            *)
                # Procesar selección por número
                declare -a SELECTED_FILES=()
                for sel in $(echo "$selection" | tr ',' '\n'); do
                    if [[ "$sel" =~ ^[0-9]+-[0-9]+$ ]]; then
                        local start end
                        start=$(echo "$sel" | cut -d'-' -f1)
                        end=$(echo "$sel" | cut -d'-' -f2)
                        for i in $(seq "$start" "$end"); do
                            [ "$i" -ge 1 ] && [ "$i" -le ${#file_array[@]} ] || continue
                            SELECTED_FILES+=("$BACKUP_DIR/${file_array[$((i-1))]}")
                        done
                    elif [[ "$sel" =~ ^[0-9]+$ ]]; then
                        [ "$sel" -ge 1 ] && [ "$sel" -le ${#file_array[@]} ] || continue
                        SELECTED_FILES+=("$BACKUP_DIR/${file_array[$((sel-1))]}")
                    fi
                done
                
                if [ ${#SELECTED_FILES[@]} -eq 0 ]; then
                    echo_error "Selección inválida"
                    sleep 1
                    continue
                fi
                
                confirm_delete
                ;;
        esac
    done
}

# -----------------------------------------------------------------------------
#  cleanup_by_date - Filtrar y eliminar por fecha
# -----------------------------------------------------------------------------
cleanup_by_date() {
    header
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║            FILTRAR BACKUPS POR FECHA                    ║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo "Ingrese fecha límite (archivos anteriores a esta fecha se eliminarán)"
    echo "Formato: YYYY-MM-DD"
    echo ""
    read -p "Fecha: " target_date
    
    if [ -z "$target_date" ]; then
        return
    fi
    
    # Validar formato de fecha
    if ! [[ "$target_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        echo_error "Formato inválido. Use YYYY-MM-DD"
        pause
        return
    fi
    
    # Listar archivos y filtrar por fecha
    local filtered=""
    while IFS= read -r line; do
        # Obtener nombre de archivo
        filename=$(echo "$line" | awk '{print $NF}')
        [ -z "$filename" ] && continue
        
        fullpath="$BACKUP_DIR/$filename"
        [ ! -f "$fullpath" ] && continue
        
        # Obtener fecha del archivo de forma portable
        filedate=$(ls -la --time-style=+%Y-%m-%d "$fullpath" 2>/dev/null | awk '{print $6}')
        
        if [ -n "$filedate" ] && [[ "$filedate" < "$target_date" ]]; then
            filtered="$filtered$filename"$'\n'
        fi
    done < <(ls -la "$BACKUP_DIR"/{*.backup,*.dump,*.sql} 2>/dev/null)
    
    if [ -z "$filtered" ]; then
        echo_info "No hay archivos anteriores a: $target_date"
        pause
        return
    fi
    
    mapfile -t file_array <<< "$filtered"
    
    echo ""
    echo -e "${YELLOW}Archivos anteriores a $target_date:${NC}"
    echo ""
    for i in "${!file_array[@]}"; do
        local full_path="$BACKUP_DIR/${file_array[$i]}"
        local size
        size=$(du -h "$full_path" 2>/dev/null | cut -f1)
        echo -e "  ${GREEN}$((i+1))${NC}) ${file_array[$i]} | $size"
    done
    
    echo ""
    echo -e "  ${GREEN}A${NC}) Eliminar todos"
    echo -e "  ${GREEN}0${NC}) Cancelar"
    echo ""
    
    read -p "# " confirm
    
    if [ "$confirm" = "0" ] || [ -z "$confirm" ]; then
        return
    fi
    
    if [ "${confirm,,}" = "a" ]; then
        declare -a SELECTED_FILES=()
        for f in "${file_array[@]}"; do
            SELECTED_FILES+=("$BACKUP_DIR/$f")
        done
        confirm_delete
    fi
}

# -----------------------------------------------------------------------------
#  confirm_delete - Confirmar eliminación de archivos
# -----------------------------------------------------------------------------
confirm_delete() {
    echo ""
    echo_warn "Se eliminarán ${#SELECTED_FILES[@]} archivo(s):"
    for f in "${SELECTED_FILES[@]}"; do
        echo "  - $(basename "$f")"
    done
    echo ""
    read -p "Confirmar eliminación? (s/n): " confirm
    [[ "${confirm,,}" != "s" ]] && { echo_info "Cancelado"; return; }
    
    local deleted=0
    for f in "${SELECTED_FILES[@]}"; do
        rm -f "$f" && ((deleted++)) || true
    done
    
    echo ""
    echo_success "$deleted archivo(s) eliminado(s)"
    pause
}
