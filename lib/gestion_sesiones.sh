#!/usr/bin/env bash
# =============================================================================
#  MÓDULO: GESTIÓN DE SESIONES  MTI JERM
# =============================================================================

# -----------------------------------------------------------------------------
#  monitor_sessions - Monitorear y terminar sesiones
# -----------------------------------------------------------------------------
monitor_sessions() {
    while true; do
        header
        echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${MAGENTA}║              MONITOREO DE SESIONES ACTIVAS                ║${NC}"
        echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        $PGUSER_VALID || { echo_error "Sin conexión"; pause; return; }
        
        # Obtener sesiones (sin filtro estricto para mostrar más opciones)
        local sessions_data
        sessions_data=$(run_psql psql -U "$PGUSER" -h "$PGHOST" -p "$PGPORT" -d "$DEFAULT_DB" -tA -c "
            SELECT 
                pid::text,
                COALESCE(datname, 'N/A') as base,
                COALESCE(usename, 'N/A') as usuario,
                COALESCE(state, 'N/A') as estado,
                COALESCE(client_addr::text, 'local') as cliente
            FROM pg_stat_activity
            WHERE pid <> pg_backend_pid()
              AND usename IS NOT NULL
              AND state != 'disabled'
            ORDER BY state, pid;
        ")
        
        if [ -z "$sessions_data" ]; then
            echo_info "No hay sesiones activas"
            echo ""
            echo -e "  ${GREEN}R${NC}) Actualizar"
            echo -e "  ${GREEN}0${NC}) Volver"
            read -p "# " op
            [ "$op" = "0" ] && return
            continue
        fi
        
        mapfile -t session_lines <<< "$sessions_data"
        
        echo -e "${CYAN}╔═══════╦═════════════════╦══════════╦═════════╦════════════╗${NC}"
        echo -e "${CYAN}║ ${BOLD}PID   ${NC}${CYAN}║ ${BOLD}Base         ${NC}${CYAN}║ ${BOLD}Usuario ${NC}${CYAN}║ ${BOLD}Estado ${NC}${CYAN}║ ${BOLD}Cliente ${NC}${CYAN}║${NC}"
        echo -e "${CYAN}╠═══════╬═════════════════╬══════════╬═════════╬════════════╣${NC}"
        
        for line in "${session_lines[@]}"; do
            IFS='|' read -r pid base usuario estado cliente <<< "$line"
            printf "${CYAN}║${NC} %-5s ${CYAN}║${NC} %-13s ${CYAN}║${NC} %-8s ${CYAN}║${NC} %-7s ${CYAN}║${NC} %-10s ${CYAN}║${NC}\n" \
                "$pid" "${base:0:13}" "${usuario:0:8}" "${estado:0:7}" "${cliente:0:10}"
        done
        echo -e "${CYAN}╚═══════╩═════════════════╩══════════╩═════════╩════════════╝${NC}"
        
        echo ""
        echo_info "Total: ${#session_lines[@]} sesiones"
        echo ""
        echo -e "  ${GREEN}R${NC}) Actualizar"
        echo -e "  ${GREEN}T${NC}) Terminar sesión(es)"
        echo -e "  ${GREEN}A${NC}) Terminar TODAS"
        echo -e "  ${GREEN}0${NC}) Volver"
        echo ""
        
        read -p "# " op
        
        case "$op" in
            R|r) continue ;;
            T|t) terminate_sessions ;;
            A|a) terminate_all_sessions ;;
            0) return ;;
            *) echo_error "Inválida"; sleep 1 ;;
        esac
    done
}

# -----------------------------------------------------------------------------
#  terminate_sessions - Terminar sesiones seleccionadas
# -----------------------------------------------------------------------------
terminate_sessions() {
    while true; do
        header
        echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${MAGENTA}║            TERMINAR SESIONES SELECCIONADAS                ║${NC}"
        echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        local sessions
        sessions=$(run_psql psql -U "$PGUSER" -h "$PGHOST" -p "$PGPORT" -d "$DEFAULT_DB" -tA -c "
            SELECT 
                pid::text,
                COALESCE(datname, 'N/A') as base,
                COALESCE(usename, 'N/A') as usuario,
                COALESCE(state, 'N/A') as estado
            FROM pg_stat_activity
            WHERE pid <> pg_backend_pid()
              AND usename IS NOT NULL
              AND state != 'disabled'
            ORDER BY state, pid;
        " 2>/dev/null) || sessions=""
        
        if [ -z "$sessions" ]; then
            echo_info "No hay sesiones"
            echo ""
            echo -e "  ${GREEN}0${NC}) Volver"
            read -p "# " op
            return
        fi
        
        mapfile -t session_lines <<< "$sessions"
        
        echo "Seleccione (número, coma, o rango):"
        echo ""
        for i in "${!session_lines[@]}"; do
            IFS='|' read -r pid base usuario estado <<< "${session_lines[$i]}"
            echo -e "  ${GREEN}$((i+1))${NC}) PID: $pid | $usuario | $estado"
        done
        echo ""
        echo -e "  ${GREEN}0${NC}) Volver"
        echo ""
        
        read -p "# " selection
        
        [ "$selection" = "0" ] || [ -z "$selection" ] && return
        
        # Procesar selección
        declare -a SELECTED_PIDS=()
        for sel in $(echo "$selection" | tr ',' '\n'); do
            if [[ "$sel" =~ ^[0-9]+-[0-9]+$ ]]; then
                local start end
                start=$(echo "$sel" | cut -d'-' -f1)
                end=$(echo "$sel" | cut -d'-' -f2)
                for i in $(seq "$start" "$end"); do
                    [ "$i" -ge 1 ] && [ "$i" -le ${#session_lines[@]} ] || continue
                    IFS='|' read -r pid _ _ _ <<< "${session_lines[$((i-1))]}"
                    SELECTED_PIDS+=("$pid")
                done
            elif [[ "$sel" =~ ^[0-9]+$ ]]; then
                [ "$sel" -ge 1 ] && [ "$sel" -le ${#session_lines[@]} ] || continue
                IFS='|' read -r pid _ _ _ <<< "${session_lines[$((sel-1))]}"
                SELECTED_PIDS+=("$pid")
            fi
        done
        
        [ ${#SELECTED_PIDS[@]} -eq 0 ] && { echo_error "Selección inválida"; sleep 1; continue; }
        
        echo ""
        echo_warn "Terminar ${#SELECTED_PIDS[@]} sesión(es)?"
        read -p "(s/n): " confirm
        [[ "${confirm,,}" != "s" ]] && { echo_info "Cancelado"; sleep 1; continue; }
        
        # Desactivar modo estricto para esta parte
        set +e
        local ok=0 fail=0
        for pid in "${SELECTED_PIDS[@]}"; do
            if run_psql psql -U "$PGUSER" -h "$PGHOST" -p "$PGPORT" -d "$DEFAULT_DB" -c "SELECT pg_terminate_backend($pid);" 2>/dev/null; then
                echo_success "PID $pid terminado"
                ((ok++)) || true
            else
                echo_error "Error PID $pid"
                ((fail++)) || true
            fi
        done
        set -e
        
        echo ""
        echo_info "Resumen: $ok terminadas, $fail fallidas"
        echo ""
        echo -e "  ${GREEN}C${NC}) Continuar"
        echo -e "  ${GREEN}0${NC}) Volver"
        echo ""
        read -p "# " op
        case "$op" in
            C|c) continue ;;
            0) return ;;
            *) continue ;;
        esac
    done
}

# -----------------------------------------------------------------------------
#  terminate_all_sessions - Terminar todas las sesiones
# -----------------------------------------------------------------------------
terminate_all_sessions() {
    header
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║            TERMINAR TODAS LAS SESIONES                    ║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    local count
    count=$(run_psql psql -U "$PGUSER" -h "$PGHOST" -p "$PGPORT" -d "$DEFAULT_DB" -tA -c "
        SELECT count(*) 
        FROM pg_stat_activity 
        WHERE pid <> pg_backend_pid()
          AND usename IS NOT NULL
          AND state != 'disabled';
    " 2>/dev/null) || count=0
    
    [ -z "$count" ] || [ "$count" -eq 0 ] && { echo_info "No hay sesiones"; pause; return; }
    
    echo_warn "$count sesión(es) serán terminadas"
    read -p "Escriba 'SI' para confirmar: " confirm
    [ "$confirm" != "SI" ] && { echo_info "Cancelado"; pause; return; }
    
    # Desactivar modo estricto
    set +e
    run_psql psql -U "$PGUSER" -h "$PGHOST" -p "$PGPORT" -d "$DEFAULT_DB" -c "
        SELECT pg_terminate_backend(pid)
        FROM pg_stat_activity
        WHERE pid <> pg_backend_pid()
          AND usename IS NOT NULL
          AND state != 'disabled';
    " 2>/dev/null
    set -e
    
    echo_success "Sesiones terminadas"
    pause
}
