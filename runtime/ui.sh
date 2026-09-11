#!/usr/bin/env bash
# Dependency-free terminal UI primitives.  HAWS_TEST_KEYS is intentionally
# supported only as a test seam; normal usage reads from /dev/tty.

_HAWS_UI_KEYS_REMAINING="${HAWS_TEST_KEYS:-}"

ui_next_key() {
  local key=""
  if [ -n "${HAWS_TEST_KEYS:-}" ]; then
    [ -n "${_HAWS_UI_KEYS_REMAINING:-}" ] || return 1
    key="${_HAWS_UI_KEYS_REMAINING%%,*}"
    if [ "${_HAWS_UI_KEYS_REMAINING}" = "${key}" ]; then
      _HAWS_UI_KEYS_REMAINING=""
    else
      _HAWS_UI_KEYS_REMAINING="${_HAWS_UI_KEYS_REMAINING#*,}"
    fi
  elif [ -t 0 ]; then
    IFS= read -r key || key=""
  else
    return 1
  fi
  key="${key#${key%%[![:space:]]*}}"
  key="${key%${key##*[![:space:]]}}"
  UI_LAST_KEY="${key}"
  export UI_LAST_KEY
  printf '%s\n' "${key}"
}

ui_menu() {
  local title="${1:-Menu}"; shift || true
  local items=("$@") choice index=0
  echo "${title}"
  for choice in "${items[@]}"; do
    printf '  %s\n' "${choice}"
  done
  ui_next_key || return 1
}

# Keyboard-first single-select menu. Records use id<TAB>label<TAB>detail;
# callers consume UI_MENU_RESULT rather than display text.
ui_cursor_menu() {
  local title="${1:-Menu}"; shift || true
  local records=("$@") cursor=0 count="${#@}" key i id label detail
  UI_MENU_RESULT=""
  [ "${count}" -gt 0 ] || return 1

  local q_action="Back"
  for ((i=0; i<count; i++)); do
    IFS=$'\t' read -r r_id _ _ <<EOF
${records[$i]}
EOF
    if [ "${r_id}" = "cancel" ]; then
      q_action="Cancel"
      break
    elif [ "${r_id}" = "exit" ]; then
      q_action="Exit"
    fi
  done

  _ui_cursor_render_row() {
    local idx="$1" is_curr="$2"
    local ptr="  "
    [ "${is_curr}" -eq 1 ] && ptr="> "
    local r_id r_label r_detail
    IFS=$'\t' read -r r_id r_label r_detail <<EOF
${records[$idx]}
EOF
    printf '\033[2K\r%s%s' "${ptr}" "${r_label:-${r_id}}"
    [ -n "${r_detail:-}" ] && printf '  %s' "${r_detail}"
    printf '\n'
  }

  _ui_cursor_render_all() {
    local r_id r_label r_detail
    echo ""
    echo "=== ${title} ==="
    for ((i=0; i<count; i++)); do
      IFS=$'\t' read -r r_id r_label r_detail <<EOF
${records[$i]}
EOF
      [ "${i}" = "${cursor}" ] && printf '> ' || printf '  '
      printf '%s' "${r_label:-${r_id}}"
      [ -n "${r_detail:-}" ] && printf '  %s' "${r_detail}"
      printf '\n'
    done
    echo ""
    echo "Up/Down Move   Enter Select   Q ${q_action}"
  }

  if [ -n "${HAWS_TEST_KEYS:-}" ]; then
    _ui_cursor_render_all
    while ui_next_key >/dev/null 2>&1; do
      key="${UI_LAST_KEY:-}"
      case "${key}" in
        up|k|K) cursor=$(( (cursor - 1 + count) % count )) ;;
        down|j|J) cursor=$(( (cursor + 1) % count )) ;;
        enter|Enter|"")
          IFS=$'\t' read -r id label detail <<EOF
${records[$cursor]}
EOF
          UI_MENU_RESULT="${id}"
          export UI_MENU_RESULT
          return 0
          ;;
        q|Q|esc|cancel|back) return 1 ;;
        *)
          if [[ "${key}" =~ ^[1-9][0-9]*$ ]] && [ "${key}" -le "${count}" ]; then
            i=$((key - 1))
            IFS=$'\t' read -r id label detail <<EOF
${records[$i]}
EOF
            UI_MENU_RESULT="${id}"
            export UI_MENU_RESULT
            return 0
          fi
          for i in "${!records[@]}"; do
            IFS=$'\t' read -r id label detail <<EOF
${records[$i]}
EOF
            if [ "${key}" = "${id}" ]; then
              UI_MENU_RESULT="${id}"
              export UI_MENU_RESULT
              return 0
            fi
          done
          ;;
      esac
      [ -z "${_HAWS_UI_KEYS_REMAINING:-}" ] && break
    done
    return 0
  elif [ -t 0 ]; then
    echo ""
    echo "=== ${title} ==="
    for ((i=0; i<count; i++)); do
      local is_c=0
      [ "${i}" -eq "${cursor}" ] && is_c=1
      _ui_cursor_render_row "${i}" "${is_c}"
    done
    echo ""
    echo "Up/Down Move   Enter Select   Q ${q_action}"

    trap 'printf "\033[?25h" 2>/dev/null || true' INT TERM
    printf "\033[?25l" 2>/dev/null || true

    while true; do
      local raw="" rest=""
      IFS= read -rsn1 raw || break

      if [[ "${raw}" == $'\x1b' ]]; then
        read -rsn2 -t 0.1 rest || rest=""
        case "${rest}" in
          "[A"|"[a"|"OA"|"oa")
            cursor=$(( (cursor - 1 + count) % count ))
            ;;
          "[B"|"[b"|"OB"|"ob")
            cursor=$(( (cursor + 1) % count ))
            ;;
          "")
            printf "\033[?25h" 2>/dev/null || true
            return 1
            ;;
          *)
            continue
            ;;
        esac
      elif [[ "${raw}" == "k" || "${raw}" == "K" ]]; then
        cursor=$(( (cursor - 1 + count) % count ))
      elif [[ "${raw}" == "j" || "${raw}" == "J" ]]; then
        cursor=$(( (cursor + 1) % count ))
      elif [[ -z "${raw}" ]]; then
        IFS=$'\t' read -r id label detail <<EOF
${records[$cursor]}
EOF
        UI_MENU_RESULT="${id}"
        export UI_MENU_RESULT
        printf "\033[?25h" 2>/dev/null || true
        return 0
      elif [[ "${raw}" == "q" || "${raw}" == "Q" ]]; then
        printf "\033[?25h" 2>/dev/null || true
        return 1
      else
        continue
      fi

      printf "\033[%dA" "$((count + 2))"
      for ((i=0; i<count; i++)); do
        local is_c=0
        [ "${i}" -eq "${cursor}" ] && is_c=1
        _ui_cursor_render_row "${i}" "${is_c}"
      done
      printf '\033[2K\r\n'
      printf '\033[2K\rUp/Down Move   Enter Select   Q %s\n' "${q_action}"
    done

    printf "\033[?25h" 2>/dev/null || true
    return 1
  else
    return 1
  fi
}

ui_checklist() {
  local title="${1:-Select}"; shift || true
  local records=("$@") i id label detail selected key cursor=0 count="${#@}" cancelled=0
  UI_CHECKLIST_RESULT=""
  [ "${count}" -gt 0 ] || return 0
  local total=$((count + 1))

  _ui_checklist_toggle_all() {
    local next=0
    for i in "${!records[@]}"; do
      IFS=$'\t' read -r _ _ _ selected <<EOF
${records[$i]}
EOF
      [ "${selected:-0}" = 0 ] && { next=1; break; }
    done
    for i in "${!records[@]}"; do records[$i]="${records[$i]%$'\t'*}"$'\t'"${next}"; done
  }

  _ui_checklist_toggle_cursor() {
    if [ "${cursor}" = 0 ]; then _ui_checklist_toggle_all; return; fi
    local target_idx=$((cursor - 1))
    IFS=$'\t' read -r id label detail selected <<EOF
${records[$target_idx]}
EOF
    [ "${selected:-0}" = 1 ] && selected=0 || selected=1
    records[$target_idx]="${id}"$'\t'"${label}"$'\t'"${detail}"$'\t'"${selected}"
  }

  _ui_checklist_render_all() {
    local all=1 any=0 mark
    for i in "${!records[@]}"; do
      IFS=$'\t' read -r _ _ _ selected <<EOF
${records[$i]}
EOF
      [ "${selected:-0}" = 1 ] && any=1 || all=0
    done
    [ "${all}" = 1 ] && mark='[x]' || { [ "${any}" = 1 ] && mark='[-]'; [ "${all}" = 0 ] && [ "${any}" = 0 ] && mark='[ ]'; }
    echo "=== ${title} ==="
    echo "Up/Down Move   Space Toggle   Enter Select   Q Cancel"
    [ "${cursor}" = 0 ] && printf '> %s Select All\n' "${mark}" || printf '  %s Select All\n' "${mark}"
    for i in "${!records[@]}"; do
      IFS=$'\t' read -r id label detail selected <<EOF
${records[$i]}
EOF
      [ "$((i + 1))" = "${cursor}" ] && printf '> ' || printf '  '
      [ "${selected:-0}" = 1 ] && printf '[x] ' || printf '[ ] '
      printf '%s (%s)\n' "${label:-${id}}" "${detail:-}"
    done
  }

  _ui_checklist_render_row() {
    local idx="$1" is_curr="$2"
    local ptr="  "
    [ "${is_curr}" -eq 1 ] && ptr="> "
    if [ "${idx}" -eq 0 ]; then
      local all=1 any=0 mark
      for i in "${!records[@]}"; do
        IFS=$'\t' read -r _ _ _ selected <<EOF
${records[$i]}
EOF
        [ "${selected:-0}" = 1 ] && any=1 || all=0
      done
      [ "${all}" = 1 ] && mark='[x]' || { [ "${any}" = 1 ] && mark='[-]'; [ "${all}" = 0 ] && [ "${any}" = 0 ] && mark='[ ]'; }
      printf '\033[2K\r%s%s Select All\n' "${ptr}" "${mark}"
    else
      local real_idx=$((idx - 1))
      local r_id r_label r_detail r_selected r_mark='[ ]'
      IFS=$'\t' read -r r_id r_label r_detail r_selected <<EOF
${records[$real_idx]}
EOF
      [ "${r_selected:-0}" = 1 ] && r_mark='[x]'
      printf '\033[2K\r%s%s %s' "${ptr}" "${r_mark}" "${r_label:-${r_id}}"
      [ -n "${r_detail:-}" ] && printf ' (%s)' "${r_detail}"
      printf '\n'
    fi
  }

  if [ -n "${HAWS_TEST_KEYS:-}" ]; then
    _ui_checklist_render_all >&2
    while ui_next_key >/dev/null 2>&1; do
      key="${UI_LAST_KEY:-}"
      case "${key}" in
        a|A) for i in "${!records[@]}"; do records[$i]="${records[$i]%$'\t'*}"$'\t'"1"; done ;;
        c|C|clear) for i in "${!records[@]}"; do records[$i]="${records[$i]%$'\t'*}"$'\t'"0"; done ;;
        space|Space|" ") _ui_checklist_toggle_cursor ;;
        down|j) cursor=$(( (cursor + 1) % total )) ;;
        up|k) cursor=$(( (cursor - 1 + total) % total )) ;;
        enter|Enter|"") break ;;
        cancel|q|Q|quit) return 1 ;;
      esac
      [ -z "${_HAWS_UI_KEYS_REMAINING:-}" ] && break
    done
    _ui_checklist_render_all >&2
  elif [ -t 0 ]; then
    echo "=== ${title} ===" >&2
    echo "Up/Down Move   Space Toggle   Enter Select   Q Cancel" >&2
    for ((i=0; i<total; i++)); do
      local is_c=0
      [ "${i}" -eq "${cursor}" ] && is_c=1
      _ui_checklist_render_row "${i}" "${is_c}" >&2
    done

    trap 'printf "\033[?25h" >&2 2>/dev/null || true' INT TERM
    printf "\033[?25l" >&2 2>/dev/null || true

    while true; do
      local raw="" rest=""
      IFS= read -rsn1 raw || break

      if [[ "${raw}" == $'\x1b' ]]; then
        read -rsn2 -t 0.1 rest || rest=""
        case "${rest}" in
          "[A"|"[a"|"OA"|"oa")
            cursor=$(( (cursor - 1 + total) % total ))
            ;;
          "[B"|"[b"|"OB"|"ob")
            cursor=$(( (cursor + 1) % total ))
            ;;
          "")
            cancelled=1
            break
            ;;
          *)
            continue
            ;;
        esac
      elif [[ "${raw}" == "k" || "${raw}" == "K" ]]; then
        cursor=$(( (cursor - 1 + total) % total ))
      elif [[ "${raw}" == "j" || "${raw}" == "J" ]]; then
        cursor=$(( (cursor + 1) % total ))
      elif [[ "${raw}" == " " || "${raw}" == "x" || "${raw}" == "X" ]]; then
        _ui_checklist_toggle_cursor
      elif [[ "${raw}" == "a" || "${raw}" == "A" ]]; then
        for ((j=0; j<count; j++)); do
          records[$j]="${records[$j]%$'\t'*}"$'\t'"1"
        done
      elif [[ "${raw}" == "c" || "${raw}" == "C" ]]; then
        for ((j=0; j<count; j++)); do
          records[$j]="${records[$j]%$'\t'*}"$'\t'"0"
        done
      elif [[ -z "${raw}" ]]; then
        break
      elif [[ "${raw}" == "q" || "${raw}" == "Q" ]]; then
        cancelled=1
        break
      else
        continue
      fi

      printf "\033[%dA" "${total}" >&2
      for ((i=0; i<total; i++)); do
        local is_c=0
        [ "${i}" -eq "${cursor}" ] && is_c=1
        _ui_checklist_render_row "${i}" "${is_c}" >&2
      done
    done

    printf "\033[?25h" >&2 2>/dev/null || true
  else
    return 1
  fi

  [ "${cancelled}" = 0 ] || return 1
  for i in "${!records[@]}"; do
    IFS=$'\t' read -r id _ _ selected <<EOF
${records[$i]}
EOF
    [ "${selected:-0}" = 1 ] && UI_CHECKLIST_RESULT="${UI_CHECKLIST_RESULT}${id}"$'\n'
  done
  printf '%b' "${UI_CHECKLIST_RESULT}"
}

ui_boolean() {
  local title="${1:-Value}" value="${2:-off}" key
  echo "${title}: ${value} (On/Off)"
  ui_next_key >/dev/null 2>&1 || true
  key="${UI_LAST_KEY:-}"
  case "${key}" in
    on|On|ON|1|yes|y) printf 'on\n' ;;
    off|Off|OFF|0|no|n) printf 'off\n' ;;
    *) printf '%s\n' "${value}" ;;
  esac
}

ui_review() {
  local plan="${1:-}" key apply_label="Apply Update" cancel_label="Cancel Update" is_installed=0
  if type install_is_complete >/dev/null 2>&1; then
    install_is_complete && is_installed=1
  elif [ -s "$(_haws_state_dir 2>/dev/null)/install.complete" ] || [ -s "${HOME}/.haws_manifest" ]; then
    is_installed=1
  fi
  if [ "${is_installed}" -eq 0 ]; then
    apply_label="Install HAWS"
    cancel_label="Cancel Setup"
  fi
  echo "Current settings:"
  echo "  Not changed values remain unchanged."
  echo "Review planned changes:"
  [ -f "${plan}" ] && cat "${plan}"
  if [ -n "${HAWS_TEST_KEYS:-}" ] && { [ -z "${_HAWS_UI_KEYS_REMAINING:-}" ] || [ "${_HAWS_UI_KEYS_REMAINING:-}" = yes ] || [ "${_HAWS_UI_KEYS_REMAINING:-}" = y ]; }; then
    [ -n "${_HAWS_UI_KEYS_REMAINING:-}" ] && ui_next_key >/dev/null 2>&1 || true
    return 0
  fi
  local records=($'apply\t'"${apply_label}"$'\t' $'back\tBack to Settings\t' $'cancel\t'"${cancel_label}"$'\t')
  ui_cursor_menu "Review changes" "${records[@]}" || return 1
  key="${UI_MENU_RESULT:-cancel}"
  case "${key}" in apply|yes|y) return 0 ;; back) return 2 ;; *) return 1 ;; esac
}
