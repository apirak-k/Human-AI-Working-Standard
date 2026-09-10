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
  elif [ -r /dev/tty ]; then
    IFS= read -r key < /dev/tty || key=""
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

  _ui_cursor_render() {
    local row_id row_label row_detail
    # A real terminal receives one replacement screen per key press.  Fixture
    # output deliberately omits control codes so tests remain readable.
    echo ""
    echo "=== ${title} ==="
    for i in "${!records[@]}"; do
      IFS=$'\t' read -r row_id row_label row_detail <<EOF
${records[$i]}
EOF
      [ "${i}" = "${cursor}" ] && printf '> ' || printf '  '
      printf '%s) %s' "$((i + 1))" "${row_label:-${row_id}}"
      [ -n "${row_detail:-}" ] && printf '  %s' "${row_detail}"
      printf '\n'
    done
    echo ""
    echo "Up/Down Move   Enter Select   Q Back"
  }

  _ui_cursor_read_key() {
    if [ -n "${HAWS_TEST_KEYS:-}" ]; then
      ui_next_key >/dev/null 2>&1 || return 1
      UI_CURSOR_KEY="${UI_LAST_KEY:-}"
      return 0
    fi
    local raw rest
    IFS= read -rsn1 raw < /dev/tty || return 1
    if [ "${raw}" = $'\x1b' ]; then
      IFS= read -rsn2 rest < /dev/tty || true
      case "${rest}" in '[A') UI_CURSOR_KEY=up ;; '[B') UI_CURSOR_KEY=down ;; *) UI_CURSOR_KEY=esc ;; esac
    elif [ -z "${raw}" ]; then
      UI_CURSOR_KEY=enter
    else
      UI_CURSOR_KEY="${raw}"
    fi
  }

  while true; do
    _ui_cursor_render
    _ui_cursor_read_key || return 1
    key="${UI_CURSOR_KEY:-}"
    case "${key}" in
      up|k) cursor=$(( (cursor - 1 + count) % count )) ;;
      down|j) cursor=$(( (cursor + 1) % count )) ;;
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
          if [ "${key}" = "${id}" ]; then UI_MENU_RESULT="${id}"; export UI_MENU_RESULT; return 0; fi
        done
        ;;
    esac
  done
}

ui_checklist() {
  local title="${1:-Select}"; shift || true
  local records=("$@") i id label detail selected key cursor=0 count="${#@}" cancelled=0
  UI_CHECKLIST_RESULT=""
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
  _ui_checklist_render() {
    local all=1 any=0 mark
    for i in "${!records[@]}"; do
      IFS=$'\t' read -r _ _ _ selected <<EOF
${records[$i]}
EOF
      [ "${selected:-0}" = 1 ] && any=1 || all=0
    done
    [ "${all}" = 1 ] && mark='[x]' || { [ "${any}" = 1 ] && mark='[-]' || mark='[ ]'; }
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
  _ui_checklist_toggle_cursor() {
    if [ "${cursor}" = 0 ]; then _ui_checklist_toggle_all; return; fi
    i=$((cursor - 1)); IFS=$'\t' read -r id label detail selected <<EOF
${records[$i]}
EOF
    [ "${selected:-0}" = 1 ] && selected=0 || selected=1
    records[$i]="${id}"$'\t'"${label}"$'\t'"${detail}"$'\t'"${selected}"
  }
  if [ -n "${HAWS_TEST_KEYS:-}" ]; then
    _ui_checklist_render >&2
    while ui_next_key >/dev/null 2>&1; do
      key="${UI_LAST_KEY:-}"
      case "${key}" in
        a|A) for i in "${!records[@]}"; do records[$i]="${records[$i]%$'\t'*}"$'\t'"1"; done ;;
        c|C|clear) for i in "${!records[@]}"; do records[$i]="${records[$i]%$'\t'*}"$'\t'"0"; done ;;
        space|Space|" ") _ui_checklist_toggle_cursor ;;
        down|j) cursor=$(( (cursor + 1) % (count + 1) )) ;;
        up|k) cursor=$(( (cursor - 1 + count + 1) % (count + 1) )) ;;
        enter|Enter|"") break ;;
        cancel|q|quit) return 1 ;;
      esac
      [ -z "${_HAWS_UI_KEYS_REMAINING:-}" ] && break
    done
    _ui_checklist_render >&2
  else
    while true; do
      _ui_checklist_render
      IFS= read -rsn1 key < /dev/tty || return 1
      case "${key}" in
        $'\x1b') IFS= read -rsn2 key < /dev/tty || true; [ "${key}" = '[A' ] && cursor=$(( (cursor - 1 + count + 1) % (count + 1) )); [ "${key}" = '[B' ] && cursor=$(( (cursor + 1) % (count + 1) )) ;;
        ' '|x|X) _ui_checklist_toggle_cursor ;;
        a|A) for i in "${!records[@]}"; do records[$i]="${records[$i]%$'\t'*}"$'\t'"1"; done ;;
        c|C) for i in "${!records[@]}"; do records[$i]="${records[$i]%$'\t'*}"$'\t'"0"; done ;;
        '') break ;;
        q|Q) cancelled=1; break ;;
      esac
    done
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
  local plan="${1:-}" key apply_label="Apply Update" cancel_label="Cancel Update"
  [ -s "$(_haws_state_dir)/install.complete" ] || { apply_label="Install HAWS"; cancel_label="Cancel Setup"; }
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
