#!/usr/bin/env bash
# =============================================================================
#  MÓDULO: GESTIÓN DE USUARIOS - VERSIÓN SEGURA Y CORREGIDA MTI JERM
# =============================================================================

# Variable global para almacenar el usuario seleccionado
CURRENT_TARGET_USER=""

user_management() {
    while true; do
        header
        echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${MAGENTA}║         GESTIÓN DE USUARIOS Y PERMISOS                   ║${NC}"
        echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "  ${GREEN}1${NC}) Crear usuario"
        echo -e "  ${GREEN}2${NC}) Listar usuarios"
        echo -e "  ${GREEN}3${NC}) Modificar usuario"
        echo -e "  ${GREEN}4${NC}) Eliminar usuario"
        echo -e "  ${GREEN}5${NC}) [GRANT] Conceder permisos (+)"
        echo -e "  ${GREEN}6${NC}) [REVOKE] Revocar permisos (-)"
        echo -e "  ${GREEN}7${NC}) Ver permisos de usuario"
        echo ""
        echo -e "  ${YELLOW}0${NC}) Volver al menú principal"
        echo ""
        
        read -p "Seleccione opción: " op
        
        case "$op" in
            1) create_user ;;
            2) list_users ;;
            3) modify_user ;;
            4) drop_user ;;
            5) grant_permissions_main ;;
            6) revoke_permissions_main ;;
            7) view_permissions_main ;;
            0) return ;;
            *) echo_error "Opción inválida"; sleep 1 ;;
        esac
    done
}

# =============================================================================
#  FUNCIONES AUXILIARES
# =============================================================================

select_target_user() {
    echo ""
    echo "Seleccione el usuario:"
    echo ""
    
    if ! select_user_from_list; then
        return 1
    fi
    
    CURRENT_TARGET_USER="$SELECTED_USER"
    echo -e "${CYAN}Usuario seleccionado: $CURRENT_TARGET_USER${NC}"
    echo ""
    return 0
}

confirm_and_execute() {
    local sql_command="$1"
    local success_msg="$2"
    local error_msg="$3"
    
    echo ""
    echo_warn "COMANDO SQL QUE SE EJECUTARÁ:"
    echo -e "${CYAN}$sql_command${NC}"
    echo ""
    read -p "¿Está seguro? (escriba 'SI' para confirmar): " confirm
    
    # Convertir a mayúsculas para comparación case-insensitive
    local confirm_upper="${confirm^^}"
    if [ "$confirm_upper" != "SI" ]; then
        echo_info "Operación cancelada"
        return 1
    fi
    
    if run_psql psql -U "$PGUSER" -h "$PGHOST" -p "$PGPORT" -d "$DEFAULT_DB" -c "$sql_command" 2>/dev/null; then
        echo_success "$success_msg"
        return 0
    else
        echo_error "$error_msg"
        return 1
    fi
}

# =============================================================================
#  GESTIÓN DE USUARIOS BÁSICA
# =============================================================================

create_user() {
    header
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║                CREAR NUEVO USUARIO                       ║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    $PGUSER_VALID || { echo_error "Sin conexión"; pause; return; }
    
    read -p "Nombre del usuario: " new_user
    [ -z "$new_user" ] && { echo_error "El nombre es requerido"; pause; return; }
    
    if run_psql psql -U "$PGUSER" -h "$PGHOST" -p "$PGPORT" -d "$DEFAULT_DB" -tA -c "SELECT 1 FROM pg_roles WHERE rolname = '$new_user';" 2>/dev/null | grep -q 1; then
        echo_error "El usuario '$new_user' ya existe"
        pause
        return
    fi
    
    read -s -p "Password: " new_password
    echo ""
    [ -z "$new_password" ] && new_password="$new_user"
    
    echo ""
    echo -e "Tipo de usuario:"
    echo -e "  ${GREEN}1${NC}) Normal (solo LOGIN)"
    echo -e "  ${GREEN}2${NC}) Superuser (SUPERUSER)"
    echo -e "  ${GREEN}3${NC}) Creador de BD (CREATEDB)"
    echo -e "  ${GREEN}4${NC}) Creador de roles (CREATEROLE)"
    echo -e "  ${GREEN}5${NC}) Replicación (REPLICATION)"
    read -p "Seleccione [1]: " rol_type
    [ -z "$rol_type" ] && rol_type=1
    
    local role_opts="LOGIN PASSWORD '$new_password'"
    case "$rol_type" in
        2) role_opts="$role_opts SUPERUSER" ;;
        3) role_opts="$role_opts CREATEDB" ;;
        4) role_opts="$role_opts CREATEROLE" ;;
        5) role_opts="$role_opts REPLICATION" ;;
    esac
    
    confirm_and_execute \
        "CREATE ROLE $new_user $role_opts;" \
        "Usuario '$new_user' creado exitosamente" \
        "Error al crear el usuario"
    
    pause
}

list_users() {
    header
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║                   LISTA DE USUARIOS                      ║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    $PGUSER_VALID || { echo_error "Sin conexión"; pause; return; }
    
    run_psql psql -U "$PGUSER" -h "$PGHOST" -p "$PGPORT" -d "$DEFAULT_DB" -c "
        SELECT 
            rolname AS \"Usuario\",
            CASE WHEN rolsuper THEN 'Sí' ELSE 'No' END AS \"Super\",
            CASE WHEN rolcreatedb THEN 'Sí' ELSE 'No' END AS \"Crear BD\",
            CASE WHEN rolcanlogin THEN 'Sí' ELSE 'No' END AS \"Login\",
            COALESCE(rolvaliduntil::text, 'Nunca') AS \"Expira\"
        FROM pg_roles 
        WHERE rolname NOT LIKE 'pg_%'
        ORDER BY rolname;
    " 2>/dev/null
    
    pause
}

modify_user() {
    header
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║                 MODIFICAR USUARIO                        ║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    $PGUSER_VALID || { echo_error "Sin conexión"; pause; return; }
    
    select_target_user || { pause; return; }
    
    echo ""
    echo -e "¿Qué desea modificar?"
    echo -e "  ${GREEN}1${NC}) Cambiar password"
    echo -e "  ${GREEN}2${NC}) Agregar SUPERUSER"
    echo -e "  ${GREEN}3${NC}) Quitar SUPERUSER"
    echo -e "  ${GREEN}4${NC}) Bloquear usuario (NOLOGIN)"
    echo -e "  ${GREEN}5${NC}) Desbloquear usuario (LOGIN)"
    echo ""
    read -p "Seleccione: " action
    
    case "$action" in
        1)
            read -s -p "Nuevo password: " new_pass
            echo ""
            confirm_and_execute \
                "ALTER USER $CURRENT_TARGET_USER PASSWORD '$new_pass';" \
                "Password actualizado" \
                "Error al cambiar password"
            ;;
        2)
            confirm_and_execute \
                "ALTER USER $CURRENT_TARGET_USER SUPERUSER;" \
                "SUPERUSER agregado" \
                "Error"
            ;;
        3)
            confirm_and_execute \
                "ALTER USER $CURRENT_TARGET_USER NOSUPERUSER;" \
                "SUPERUSER removido" \
                "Error"
            ;;
        4)
            confirm_and_execute \
                "ALTER USER $CURRENT_TARGET_USER NOLOGIN;" \
                "Usuario bloqueado" \
                "Error"
            ;;
        5)
            confirm_and_execute \
                "ALTER USER $CURRENT_TARGET_USER LOGIN;" \
                "Usuario desbloqueado" \
                "Error"
            ;;
        *)
            echo_error "Opción inválida"
            ;;
    esac
    
    pause
}

drop_user() {
    header
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║                ELIMINAR USUARIO                          ║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    $PGUSER_VALID || { echo_error "Sin conexión"; pause; return; }
    
    select_target_user || { pause; return; }
    
    echo ""
    echo_warn "ADVERTENCIA: Se eliminará el usuario '$CURRENT_TARGET_USER'"
    echo_warn "y todos sus objetos serán eliminados (CASCADE)"
    echo ""
    read -p "Escriba '$CURRENT_TARGET_USER' para confirmar: " confirm
    
    if [ "$confirm" != "$CURRENT_TARGET_USER" ]; then
        echo_info "Operación cancelada"
        pause
        return
    fi
    
    confirm_and_execute \
        "DROP OWNED BY $CURRENT_TARGET_USER CASCADE; DROP USER $CURRENT_TARGET_USER;" \
        "Usuario eliminado correctamente" \
        "Error al eliminar usuario"
    
    pause
}

# =============================================================================
#  [GRANT] CONCEDER PERMISOS
# =============================================================================

grant_permissions_main() {
    while true; do
        header
        echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${MAGENTA}║  [GRANT] CONCEDER PERMISOS                             ║${NC}"
        echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        $PGUSER_VALID || { echo_error "Sin conexión"; pause; return; }
        
        select_target_user || { pause; return; }
        
        while true; do
            header
            echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════╗${NC}"
            echo -e "${MAGENTA}║  [GRANT] CONCEDER PERMISOS A: ${CYAN}$CURRENT_TARGET_USER${NC}"
            echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════╝${NC}"
            echo ""
            echo -e "  ${GREEN}1${NC}) Permiso en Base de Datos"
            echo -e "  ${GREEN}2${NC}) Permiso en Esquema"
            echo -e "  ${GREEN}3${NC}) Permiso en Tabla"
            echo -e "  ${GREEN}4${NC}) Permiso en Secuencia"
            echo -e "  ${GREEN}5${NC}) Asignar Rol (GRANT role TO user)"
            echo ""
            echo -e "  ${YELLOW}0${NC}) Volver"
            echo ""
            
            read -p "Seleccione: " level
            
            case "$level" in
                1) grant_database_perm ;;
                2) grant_schema_perm ;;
                3) grant_table_perm ;;
                4) grant_sequence_perm ;;
                5) grant_role_perm ;;
                0) break ;;
                *) echo_error "Inválida"; sleep 1 ;;
            esac
        done
    done
}

grant_database_perm() {
    header
    echo -e "${CYAN}[GRANT] PERMISO EN BASE DE DATOS${NC}"
    echo ""
    
    select_database || return
    
    echo ""
    echo -e "Permisos disponibles:"
    echo -e "  ${GREEN}1${NC}) CONNECT - Conectar a la base"
    echo -e "  ${GREEN}2${NC}) CREATE  - Crear objetos"
    echo -e "  ${GREEN}3${NC}) ALL     - Todos los permisos"
    read -p "Seleccione permiso: " perm_opt
    
    case "$perm_opt" in
        1) perm="CONNECT" ;;
        2) perm="CREATE" ;;
        3) perm="ALL" ;;
        *) perm="CONNECT" ;;
    esac
    
    confirm_and_execute \
        "GRANT $perm ON DATABASE \"$SELECTED_DB\" TO $CURRENT_TARGET_USER;" \
        "Permiso '$perm' concedido en base '$SELECTED_DB'" \
        "Error al conceder permiso"
    
    pause
}

grant_schema_perm() {
    header
    echo -e "${CYAN}[GRANT] PERMISO EN ESQUEMA${NC}"
    echo ""
    
    select_database || return
    
    echo ""
    echo "Esquemas disponibles en la base '$SELECTED_DB':"
    echo ""
    
    local schemas
    schemas=$(run_psql psql -U "$PGUSER" -h "$PGHOST" -p "$PGPORT" -d "$SELECTED_DB" -tA -c "SELECT nspname FROM pg_namespace WHERE nspname NOT LIKE 'pg_%' AND nspname != 'information_schema' ORDER BY nspname;" 2>/dev/null)
    
    if [ -z "$schemas" ]; then
        echo_error "No hay esquemas disponibles en esta base de datos."
        pause
        return
    fi
    
    # Crear array de esquemas
    local schema_array=()
    local i=1
    while IFS= read -r sch; do
        [ -z "$sch" ] && continue
        schema_array+=("$sch")
        printf "  %2d) %s\n" "$i" "$sch"
        ((i++))
    done <<< "$schemas"
    
    echo ""
    read -p "Seleccione número de esquema (1-$((i-1))): " schema_num
    
    # Validar que sea un número
    if ! [[ "$schema_num" =~ ^[0-9]+$ ]]; then
        echo_error "Debe ingresar un número válido"
        pause
        return
    fi
    
    # Validar rango
    if [ "$schema_num" -lt 1 ] || [ "$schema_num" -gt "$((i-1))" ]; then
        echo_error "Número fuera de rango"
        pause
        return
    fi
    
    local schema="${schema_array[$((schema_num-1))]}"
    echo ""
    echo -e "Esquema seleccionado: ${CYAN}$schema${NC}"
    echo ""
    
    echo -e "Permisos disponibles:"
    echo -e "  ${GREEN}1${NC}) USAGE   - Usar objetos"
    echo -e "  ${GREEN}2${NC}) CREATE  - Crear objetos"
    echo -e "  ${GREEN}3${NC}) ALL     - Todos"
    read -p "Seleccione permiso (1-3): " perm_opt
    
    case "$perm_opt" in
        1) perm="USAGE" ;;
        2) perm="CREATE" ;;
        3) perm="ALL" ;;
        *) perm="USAGE" ;;
    esac
    
    confirm_and_execute \
        "GRANT $perm ON SCHEMA $schema TO $CURRENT_TARGET_USER;" \
        "Permiso '$perm' concedido en esquema '$schema'" \
        "Error"
    
    pause
}

grant_table_perm() {
    header
    echo -e "${CYAN}[GRANT] PERMISO EN TABLA${NC}"
    echo ""
    
    select_database || return
    
    echo ""
    echo "Tablas disponibles en la base '$SELECTED_DB':"
    echo ""
    
    local tables
    tables=$(run_psql psql -U "$PGUSER" -h "$PGHOST" -p "$PGPORT" -d "$SELECTED_DB" -tA -c "SELECT schemaname || '.' || tablename FROM pg_tables WHERE schemaname NOT LIKE 'pg_%' AND schemaname != 'information_schema' ORDER BY schemaname, tablename LIMIT 50;" 2>/dev/null)
    
    if [ -z "$tables" ]; then
        echo_error "No hay tablas disponibles en esta base de datos."
        pause
        return
    fi
    
    # Crear array de tablas
    local table_array=()
    local i=1
    while IFS= read -r tbl; do
        [ -z "$tbl" ] && continue
        table_array+=("$tbl")
        printf "  %2d) %s\n" "$i" "$tbl"
        ((i++))
    done <<< "$tables"
    
    echo ""
    read -p "Seleccione lista de tablas (ej: 1,2,3): " table_input
    
    # Procesar selección múltiple de tablas
    local selected_tables=""
    local table_list=""
    IFS=',' read -ra table_numbers <<< "$table_input"
    for num in "${table_numbers[@]}"; do
        num=$(echo "$num" | tr -d ' ')
        if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -lt "$i" ]; then
            local tbl="${table_array[$((num-1))]}"
            selected_tables="$selected_tables$tbl, "
            table_list="$table_list  • $tbl\n"
        fi
    done
    
    # Eliminar última coma y espacio
    selected_tables="${selected_tables%, }"
    
    if [ -z "$selected_tables" ]; then
        echo_error "No se seleccionaron tablas válidas"
        pause
        return
    fi
    
    echo ""
    echo -e "${CYAN}Tablas seleccionadas:${NC}"
    echo -e "$table_list"
    echo ""
    
    echo -e "Permisos CRUD (puede seleccionar múltiples separados por coma, ej: 1,2,3):"
    echo -e "  ${GREEN}1${NC}) SELECT"
    echo -e "  ${GREEN}2${NC}) INSERT"
    echo -e "  ${GREEN}3${NC}) UPDATE"
    echo -e "  ${GREEN}4${NC}) DELETE"
    echo -e "  ${GREEN}5${NC}) ALL (todos)"
    read -p "Seleccione permisos (ej: 1,2,3): " perm_input
    
    # Procesar selección múltiple de permisos
    local perm=""
    local has_all=false
    
    IFS=',' read -ra perm_numbers <<< "$perm_input"
    for num in "${perm_numbers[@]}"; do
        num=$(echo "$num" | tr -d ' ')
        case "$num" in
            1) perm="${perm}SELECT, " ;;
            2) perm="${perm}INSERT, " ;;
            3) perm="${perm}UPDATE, " ;;
            4) perm="${perm}DELETE, " ;;
            5) has_all=true ;;
        esac
    done
    
    # Si se seleccionó ALL (5), ignorar los demás
    if [ "$has_all" = true ]; then
        perm="ALL"
    else
        perm="${perm%, }"
    fi
    
    # Si no se seleccionó nada válido, usar SELECT por defecto
    [ -z "$perm" ] && perm="SELECT"
    
    # Crear lista de tablas en array para procesar individualmente
    IFS=', ' read -ra selected_table_array <<< "$selected_tables"
    
    echo ""
    echo_warn "COMANDOS SQL QUE SE EJECUTARÁN:"
    for tbl in "${selected_table_array[@]}"; do
        echo -e "  ${CYAN}GRANT $perm ON $tbl TO $CURRENT_TARGET_USER;${NC}"
    done
    echo ""
    read -p "¿Está seguro? (escriba 'SI' para confirmar): " confirm
    
    # Convertir a mayúsculas para comparación case-insensitive
    local confirm_upper="${confirm^^}"
    if [ "$confirm_upper" != "SI" ]; then
        echo_info "Operación cancelada"
        pause
        return
    fi
    
    # Ejecutar GRANT para cada tabla individualmente
    local success_count=0
    local error_count=0
    for tbl in "${selected_table_array[@]}"; do
        if run_psql psql -U "$PGUSER" -h "$PGHOST" -p "$PGPORT" -d "$SELECTED_DB" -c "GRANT $perm ON $tbl TO $CURRENT_TARGET_USER;" 2>/dev/null; then
            echo_success "Permiso '$perm' concedido en tabla '$tbl'"
            success_count=$((success_count + 1))
        else
            echo_error "Error al conceder permiso en tabla '$tbl'"
            error_count=$((error_count + 1))
        fi
    done
    
    echo ""
    echo_info "Resultado: $success_count éxitos, $error_count errores"
    
    pause
}

grant_sequence_perm() {
    header
    echo -e "${CYAN}[GRANT] PERMISO EN SECUENCIA${NC}"
    echo ""
    
    select_database || return
    
    echo ""
    echo "Secuencias disponibles en la base '$SELECTED_DB':"
    echo ""
    
    local sequences
    sequences=$(run_psql psql -U "$PGUSER" -h "$PGHOST" -p "$PGPORT" -d "$SELECTED_DB" -tA -c "SELECT sequence_schema || '.' || sequence_name FROM information_schema.sequences WHERE sequence_schema NOT LIKE 'pg_%' AND sequence_schema != 'information_schema' ORDER BY sequence_schema, sequence_name LIMIT 50;" 2>/dev/null)
    
    if [ -z "$sequences" ]; then
        echo_error "No hay secuencias disponibles en esta base de datos."
        pause
        return
    fi
    
    # Crear array de secuencias
    local seq_array=()
    local i=1
    while IFS= read -r seq; do
        [ -z "$seq" ] && continue
        seq_array+=("$seq")
        printf "  %2d) %s\n" "$i" "$seq"
        ((i++))
    done <<< "$sequences"
    
    echo ""
    read -p "Seleccione número de secuencia (1-$((i-1))): " seq_num
    
    # Validar que sea un número
    if ! [[ "$seq_num" =~ ^[0-9]+$ ]]; then
        echo_error "Debe ingresar un número válido"
        pause
        return
    fi
    
    # Validar rango
    if [ "$seq_num" -lt 1 ] || [ "$seq_num" -gt "$((i-1))" ]; then
        echo_error "Número fuera de rango"
        pause
        return
    fi
    
    local seq_name="${seq_array[$((seq_num-1))]}"
    echo ""
    echo -e "Secuencia seleccionada: ${CYAN}$seq_name${NC}"
    echo ""
    
    echo -e "Permisos disponibles:"
    echo -e "  ${GREEN}1${NC}) USAGE"
    echo -e "  ${GREEN}2${NC}) SELECT"
    echo -e "  ${GREEN}3${NC}) UPDATE"
    echo -e "  ${GREEN}4${NC}) ALL"
    read -p "Seleccione permiso (1-4): " perm_opt
    
    case "$perm_opt" in
        1) perm="USAGE" ;;
        2) perm="SELECT" ;;
        3) perm="UPDATE" ;;
        4) perm="ALL" ;;
        *) perm="USAGE" ;;
    esac
    
    confirm_and_execute \
        "GRANT $perm ON $seq_name TO $CURRENT_TARGET_USER;" \
        "Permiso '$perm' concedido en secuencia '$seq_name'" \
        "Error"
    
    pause
}

grant_role_perm() {
    header
    echo -e "${CYAN}[GRANT] ASIGNAR ROL A USUARIO${NC}"
    echo ""
    
    local roles
    roles=$(run_psql psql -U "$PGUSER" -h "$PGHOST" -p "$PGPORT" -d "$DEFAULT_DB" -tA -c "SELECT rolname FROM pg_roles WHERE rolname NOT LIKE 'pg_%' AND rolname != '$CURRENT_TARGET_USER' ORDER BY rolname;" 2>/dev/null)
    
    if [ -z "$roles" ]; then
        echo_error "No hay roles disponibles"
        pause
        return
    fi
    
    # Crear array de roles
    local role_array=()
    local i=1
    while IFS= read -r rol; do
        [ -z "$rol" ] && continue
        role_array+=("$rol")
        printf "  %2d) %s\n" "$i" "$rol"
        ((i++))
    done <<< "$roles"
    
    echo ""
    read -p "Seleccione número de rol (1-$((i-1))): " role_num
    
    # Validar que sea un número
    if ! [[ "$role_num" =~ ^[0-9]+$ ]]; then
        echo_error "Debe ingresar un número válido"
        pause
        return
    fi
    
    # Validar rango
    if [ "$role_num" -lt 1 ] || [ "$role_num" -gt "$((i-1))" ]; then
        echo_error "Número fuera de rango"
        pause
        return
    fi
    
    local role_name="${role_array[$((role_num-1))]}"
    echo ""
    echo -e "Rol seleccionado: ${CYAN}$role_name${NC}"
    echo ""
    
    confirm_and_execute \
        "GRANT $role_name TO $CURRENT_TARGET_USER;" \
        "Rol '$role_name' asignado a '$CURRENT_TARGET_USER'" \
        "Error"
    
    pause
}

# =============================================================================
#  [REVOKE] REVOCAR PERMISOS
# =============================================================================

revoke_permissions_main() {
    while true; do
        header
        echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${MAGENTA}║  [REVOKE] REVOCAR PERMISOS                             ║${NC}"
        echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        $PGUSER_VALID || { echo_error "Sin conexión"; pause; return; }
        
        select_target_user || { pause; return; }
        
        while true; do
            header
            echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════╗${NC}"
            echo -e "${MAGENTA}║  [REVOKE] REVOCAR PERMISOS DE: ${CYAN}$CURRENT_TARGET_USER${NC}"
            echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════╝${NC}"
            echo ""
            echo -e "  ${RED}1${NC}) Revocar permiso en Base de Datos"
            echo -e "  ${RED}2${NC}) Revocar permiso en Esquema"
            echo -e "  ${RED}3${NC}) Revocar permiso en Tabla"
            echo -e "  ${RED}4${NC}) Revocar permiso en Secuencia"
            echo -e "  ${RED}5${NC}) Revocar Rol asignado"
            echo ""
            echo -e "  ${YELLOW}0${NC}) Volver"
            echo ""
            
            read -p "Seleccione: " level
            
            case "$level" in
                1) revoke_database_perm ;;
                2) revoke_schema_perm ;;
                3) revoke_table_perm ;;
                4) revoke_sequence_perm ;;
                5) revoke_role_perm ;;
                0) break ;;
                *) echo_error "Inválida"; sleep 1 ;;
            esac
        done
    done
}

revoke_database_perm() {
    header
    echo -e "${RED}[REVOKE] REVOCAR PERMISO EN BASE DE DATOS${NC}"
    echo ""
    
    select_database || return
    
    echo -e "Permiso a revocar:"
    echo -e "  ${GREEN}1${NC}) CONNECT"
    echo -e "  ${GREEN}2${NC}) CREATE"
    echo -e "  ${GREEN}3${NC}) ALL (todos)"
    read -p "Seleccione: " perm_opt
    
    case "$perm_opt" in
        1) perm="CONNECT" ;;
        2) perm="CREATE" ;;
        3) perm="ALL" ;;
        *) perm="ALL" ;;
    esac
    
    confirm_and_execute \
        "REVOKE $perm ON DATABASE \"$SELECTED_DB\" FROM $CURRENT_TARGET_USER;" \
        "Permiso '$perm' revocado de base '$SELECTED_DB'" \
        "Error al revocar permiso"
    
    pause
}

revoke_schema_perm() {
    header
    echo -e "${RED}[REVOKE] REVOCAR PERMISO EN ESQUEMA${NC}"
    echo ""
    
    select_database || return
    
    echo ""
    echo "Esquemas donde el usuario tiene permisos en '$SELECTED_DB':"
    echo ""
    
    # Obtener esquemas donde el usuario tiene permisos
    local schemas
    schemas=$(run_psql psql -U "$PGUSER" -h "$PGHOST" -p "$PGPORT" -d "$SELECTED_DB" -tA -c "
        SELECT DISTINCT n.nspname
        FROM pg_namespace n
        JOIN pg_class c ON c.relnamespace = n.oid
        WHERE n.nspname NOT LIKE 'pg_%'
        AND n.nspname != 'information_schema'
        AND has_schema_privilege('$CURRENT_TARGET_USER', n.nspname, 'USAGE')
        ORDER BY n.nspname
        LIMIT 50;
    " 2>/dev/null)
    
    if [ -z "$schemas" ]; then
        echo_info "El usuario '$CURRENT_TARGET_USER' no tiene permisos en ningún esquema de esta base de datos."
        pause
        return
    fi
    
    # Crear array de esquemas
    local schema_array=()
    local i=1
    while IFS= read -r sch; do
        [ -z "$sch" ] && continue
        schema_array+=("$sch")
        printf "  %2d) %s\n" "$i" "$sch"
        ((i++))
    done <<< "$schemas"
    
    echo ""
    read -p "Seleccione número de esquema (1-$((i-1))): " schema_num
    
    # Validar que sea un número
    if ! [[ "$schema_num" =~ ^[0-9]+$ ]]; then
        echo_error "Debe ingresar un número válido"
        pause
        return
    fi
    
    # Validar rango
    if [ "$schema_num" -lt 1 ] || [ "$schema_num" -gt "$((i-1))" ]; then
        echo_error "Número fuera de rango"
        pause
        return
    fi
    
    local schema="${schema_array[$((schema_num-1))]}"
    echo ""
    echo -e "Esquema seleccionado: ${CYAN}$schema${NC}"
    echo ""
    
    echo -e "Permiso a revocar:"
    echo -e "  ${GREEN}1${NC}) USAGE"
    echo -e "  ${GREEN}2${NC}) CREATE"
    echo -e "  ${GREEN}3${NC}) ALL (todos)"
    read -p "Seleccione permiso (1-3): " perm_opt
    
    case "$perm_opt" in
        1) perm="USAGE" ;;
        2) perm="CREATE" ;;
        3) perm="ALL" ;;
        *) perm="ALL" ;;
    esac
    
    confirm_and_execute \
        "REVOKE $perm ON SCHEMA $schema FROM $CURRENT_TARGET_USER;" \
        "Permiso '$perm' revocado de esquema '$schema'" \
        "Error"
    
    pause
}

revoke_table_perm() {
    header
    echo -e "${RED}[REVOKE] REVOCAR PERMISO EN TABLA${NC}"
    echo ""
    
    select_database || return
    
    echo ""
    echo "Tablas disponibles en la base '$SELECTED_DB':"
    echo ""
    
    # Obtener lista de tablas con permisos del usuario
    local tables
    tables=$(run_psql psql -U "$PGUSER" -h "$PGHOST" -p "$PGPORT" -d "$SELECTED_DB" -tA -c "
        SELECT DISTINCT table_schema || '.' || table_name 
        FROM information_schema.table_privileges 
        WHERE grantee = '$CURRENT_TARGET_USER' 
        AND table_schema NOT IN ('pg_catalog', 'information_schema')
        ORDER BY table_schema || '.' || table_name 
        LIMIT 50;
    " 2>/dev/null)
    
    if [ -z "$tables" ]; then
        echo_info "El usuario '$CURRENT_TARGET_USER' no tiene permisos en ninguna tabla de esta base de datos."
        pause
        return
    fi
    
    # Crear array de tablas
    local table_array=()
    local i=1
    while IFS= read -r tbl; do
        [ -z "$tbl" ] && continue
        table_array+=("$tbl")
        printf "  %2d) %s\n" "$i" "$tbl"
        ((i++))
    done <<< "$tables"
    
    echo ""
    read -p "Seleccione lista de tablas (ej: 1,2,3): " table_input
    
    # Procesar selección múltiple de tablas
    local selected_tables=""
    local table_list=""
    IFS=',' read -ra table_numbers <<< "$table_input"
    for num in "${table_numbers[@]}"; do
        num=$(echo "$num" | tr -d ' ')
        if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -lt "$i" ]; then
            local tbl="${table_array[$((num-1))]}"
            selected_tables="$selected_tables$tbl, "
            table_list="$table_list  • $tbl\n"
        fi
    done
    
    # Eliminar última coma y espacio
    selected_tables="${selected_tables%, }"
    
    if [ -z "$selected_tables" ]; then
        echo_error "No se seleccionaron tablas válidas"
        pause
        return
    fi
    
    echo ""
    echo -e "${CYAN}Tablas seleccionadas:${NC}"
    echo -e "$table_list"
    echo ""
    
    echo -e "Permisos a revocar (puede seleccionar múltiples separados por coma, ej: 1,2,3):"
    echo -e "  ${GREEN}1${NC}) SELECT"
    echo -e "  ${GREEN}2${NC}) INSERT"
    echo -e "  ${GREEN}3${NC}) UPDATE"
    echo -e "  ${GREEN}4${NC}) DELETE"
    echo -e "  ${GREEN}5${NC}) ALL (todos)"
    read -p "Seleccione permisos (ej: 1,2,3): " perm_input
    
    # Procesar selección múltiple de permisos
    local perm=""
    local has_all=false
    
    IFS=',' read -ra perm_numbers <<< "$perm_input"
    for num in "${perm_numbers[@]}"; do
        num=$(echo "$num" | tr -d ' ')
        case "$num" in
            1) perm="${perm}SELECT, " ;;
            2) perm="${perm}INSERT, " ;;
            3) perm="${perm}UPDATE, " ;;
            4) perm="${perm}DELETE, " ;;
            5) has_all=true ;;
        esac
    done
    
    # Si se seleccionó ALL (5), ignorar los demás
    if [ "$has_all" = true ]; then
        perm="ALL"
    else
        perm="${perm%, }"
    fi
    
    # Si no se seleccionó nada válido, usar ALL por defecto
    [ -z "$perm" ] && perm="ALL"
    
    # Crear lista de tablas en array para procesar individualmente
    IFS=', ' read -ra selected_table_array <<< "$selected_tables"
    
    echo ""
    echo_warn "COMANDOS SQL QUE SE EJECUTARÁN:"
    for tbl in "${selected_table_array[@]}"; do
        echo -e "  ${CYAN}REVOKE $perm ON $tbl FROM $CURRENT_TARGET_USER;${NC}"
    done
    echo ""
    read -p "¿Está seguro? (escriba 'SI' para confirmar): " confirm
    
    # Convertir a mayúsculas para comparación case-insensitive
    local confirm_upper="${confirm^^}"
    if [ "$confirm_upper" != "SI" ]; then
        echo_info "Operación cancelada"
        pause
        return
    fi
    
    # Ejecutar REVOKE para cada tabla individualmente
    local success_count=0
    local error_count=0
    for tbl in "${selected_table_array[@]}"; do
        if run_psql psql -U "$PGUSER" -h "$PGHOST" -p "$PGPORT" -d "$SELECTED_DB" -c "REVOKE $perm ON $tbl FROM $CURRENT_TARGET_USER;" 2>/dev/null; then
            echo_success "Permiso '$perm' revocado de tabla '$tbl'"
            success_count=$((success_count + 1))
        else
            echo_error "Error al revocar permiso de tabla '$tbl'"
            error_count=$((error_count + 1))
        fi
    done
    
    echo ""
    echo_info "Resultado: $success_count éxitos, $error_count errores"
    
    pause
}

revoke_sequence_perm() {
    header
    echo -e "${RED}[REVOKE] REVOCAR PERMISO EN SECUENCIA${NC}"
    echo ""
    
    select_database || return
    
    echo ""
    echo "Secuencias donde el usuario tiene permisos en '$SELECTED_DB':"
    echo ""
    
    # Obtener secuencias donde el usuario tiene permisos
    local sequences
    sequences=$(run_psql psql -U "$PGUSER" -h "$PGHOST" -p "$PGPORT" -d "$SELECTED_DB" -tA -c "
        SELECT DISTINCT schemaname || '.' || sequencename
        FROM pg_sequences
        WHERE schemaname NOT LIKE 'pg_%'
        AND schemaname != 'information_schema'
        AND has_sequence_privilege('$CURRENT_TARGET_USER', schemaname || '.' || sequencename, 'USAGE')
        ORDER BY schemaname, sequencename
        LIMIT 50;
    " 2>/dev/null)
    
    if [ -z "$sequences" ]; then
        echo_info "El usuario '$CURRENT_TARGET_USER' no tiene permisos en ninguna secuencia de esta base de datos."
        pause
        return
    fi
    
    # Crear array de secuencias
    local seq_array=()
    local i=1
    while IFS= read -r seq; do
        [ -z "$seq" ] && continue
        seq_array+=("$seq")
        printf "  %2d) %s\n" "$i" "$seq"
        ((i++))
    done <<< "$sequences"
    
    echo ""
    read -p "Seleccione número de secuencia (1-$((i-1))): " seq_num
    
    # Validar que sea un número
    if ! [[ "$seq_num" =~ ^[0-9]+$ ]]; then
        echo_error "Debe ingresar un número válido"
        pause
        return
    fi
    
    # Validar rango
    if [ "$seq_num" -lt 1 ] || [ "$seq_num" -gt "$((i-1))" ]; then
        echo_error "Número fuera de rango"
        pause
        return
    fi
    
    local seq_name="${seq_array[$((seq_num-1))]}"
    echo ""
    echo -e "Secuencia seleccionada: ${CYAN}$seq_name${NC}"
    echo ""
    
    echo -e "Permiso a revocar:"
    echo -e "  ${GREEN}1${NC}) USAGE"
    echo -e "  ${GREEN}2${NC}) SELECT"
    echo -e "  ${GREEN}3${NC}) UPDATE"
    echo -e "  ${GREEN}4${NC}) ALL (todos)"
    read -p "Seleccione permiso (1-4): " perm_opt
    
    case "$perm_opt" in
        1) perm="USAGE" ;;
        2) perm="SELECT" ;;
        3) perm="UPDATE" ;;
        4) perm="ALL" ;;
        *) perm="ALL" ;;
    esac
    
    confirm_and_execute \
        "REVOKE $perm ON $seq_name FROM $CURRENT_TARGET_USER;" \
        "Permiso '$perm' revocado de secuencia '$seq_name'" \
        "Error"
    
    pause
}

revoke_role_perm() {
    header
    echo -e "${RED}[REVOKE] REVOCAR ROL ASIGNADO${NC}"
    echo ""
    
    local roles
    roles=$(run_psql psql -U "$PGUSER" -h "$PGHOST" -p "$PGPORT" -d "$DEFAULT_DB" -tA -c "SELECT r.rolname FROM pg_roles r JOIN pg_auth_members m ON r.oid = m.roleid JOIN pg_roles u ON m.member = u.oid WHERE u.rolname = '$CURRENT_TARGET_USER';" 2>/dev/null)
    
    if [ -z "$roles" ]; then
        echo_info "El usuario no tiene roles asignados"
        pause
        return
    fi
    
    # Crear array de roles
    local role_array=()
    local i=1
    while IFS= read -r rol; do
        [ -z "$rol" ] && continue
        role_array+=("$rol")
        printf "  %2d) %s\n" "$i" "$rol"
        ((i++))
    done <<< "$roles"
    
    echo ""
    read -p "Seleccione número de rol a revocar (1-$((i-1))): " role_num
    
    # Validar que sea un número
    if ! [[ "$role_num" =~ ^[0-9]+$ ]]; then
        echo_error "Debe ingresar un número válido"
        pause
        return
    fi
    
    # Validar rango
    if [ "$role_num" -lt 1 ] || [ "$role_num" -gt "$((i-1))" ]; then
        echo_error "Número fuera de rango"
        pause
        return
    fi
    
    local role_name="${role_array[$((role_num-1))]}"
    echo ""
    echo -e "Rol seleccionado: ${CYAN}$role_name${NC}"
    echo ""
    
    confirm_and_execute \
        "REVOKE $role_name FROM $CURRENT_TARGET_USER;" \
        "Rol '$role_name' revocado de '$CURRENT_TARGET_USER'" \
        "Error"
    
    pause
}

# =============================================================================
#  VER PERMISOS
# =============================================================================

view_permissions_main() {
    header
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║           VER PERMISOS DE USUARIO                        ║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    $PGUSER_VALID || { echo_error "Sin conexión"; pause; return; }
    
    select_target_user || { pause; return; }
    
    header
    echo -e "${CYAN}INFORMACIÓN DEL USUARIO: $CURRENT_TARGET_USER${NC}"
    echo ""
    
    echo -e "${CYAN}--- Roles del sistema ---${NC}"
    run_psql psql -U "$PGUSER" -h "$PGHOST" -p "$PGPORT" -d "$DEFAULT_DB" -c "
        SELECT 
            CASE WHEN rolsuper THEN 'Sí' ELSE 'No' END AS \"Superusuario\",
            CASE WHEN rolcreatedb THEN 'Sí' ELSE 'No' END AS \"Crear BD\",
            CASE WHEN rolcanlogin THEN 'Sí' ELSE 'No' END AS \"Puede hacer login\"
        FROM pg_roles WHERE rolname = '$CURRENT_TARGET_USER';
    " 2>/dev/null || echo "  (Error al consultar roles)"
    
    echo ""
    echo -e "${CYAN}--- Roles asignados ---${NC}"
    local roles
    roles=$(run_psql psql -U "$PGUSER" -h "$PGHOST" -p "$PGPORT" -d "$DEFAULT_DB" -tA -c "SELECT r.rolname FROM pg_roles r JOIN pg_auth_members m ON r.oid = m.roleid JOIN pg_roles u ON m.member = u.oid WHERE u.rolname = '$CURRENT_TARGET_USER';" 2>/dev/null) || roles=""
    
    if [ -z "$roles" ]; then
        echo "  (Ningún rol asignado)"
    else
        while IFS= read -r rol; do
            [ -n "$rol" ] && echo "  • $rol"
        done <<< "$roles"
    fi
    
    echo ""
    echo -e "${CYAN}--- Permisos en bases de datos ---${NC}"
    local db_perms
    db_perms=$(run_psql psql -U "$PGUSER" -h "$PGHOST" -p "$PGPORT" -d "$DEFAULT_DB" -tA -c "
        SELECT d.datname || ': ' || STRING_AGG(DISTINCT p.privilege_type, ', ')
        FROM pg_database d
        CROSS JOIN LATERAL (
            SELECT unnest(array['CONNECT', 'CREATE', 'TEMPORARY']) as privilege_type
        ) p
        WHERE has_database_privilege('$CURRENT_TARGET_USER', d.datname, p.privilege_type)
        AND d.datallowconn = true
        GROUP BY d.datname
        ORDER BY d.datname
        LIMIT 30;
    " 2>/dev/null) || db_perms=""
    
    if [ -z "$db_perms" ]; then
        echo "  (Sin permisos específicos en bases de datos)"
    else
        while IFS= read -r line; do
            [ -n "$line" ] && echo "  • $line"
        done <<< "$db_perms"
    fi
    
    echo ""
    read -p "¿Ver permisos de tablas en una base específica? (s/n): " check_tables
    
    if [[ "${check_tables,,}" = "s" ]]; then
        select_database || { pause; return; }
        
        echo ""
        echo -e "${CYAN}--- Permisos en tablas (Base: $SELECTED_DB) ---${NC}"
        local table_perms
        table_perms=$(run_psql psql -U "$PGUSER" -h "$PGHOST" -p "$PGPORT" -d "$SELECTED_DB" -tA -c "
            SELECT table_schema || '.' || table_name || ': ' || STRING_AGG(privilege_type, ', ')
            FROM information_schema.table_privileges
            WHERE grantee = '$CURRENT_TARGET_USER' 
            AND table_schema NOT IN ('pg_catalog', 'information_schema')
            GROUP BY table_schema, table_name
            ORDER BY table_schema, table_name
            LIMIT 30;
        " 2>/dev/null) || table_perms=""
        
        if [ -z "$table_perms" ]; then
            echo "  (Sin permisos en tablas de esta base)"
        else
            while IFS= read -r line; do
                [ -n "$line" ] && echo "  • $line"
            done <<< "$table_perms"
        fi
    fi
    
    pause
}
