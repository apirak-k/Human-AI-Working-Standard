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
    printf '\033[H\033[2J'
    echo "=== ${title} ==="
    echo "Controls: [↑/↓] Navigate | [Space] Toggle | [Enter] Confirm & Save | [q] Cancel"
    [ "${cursor}" = 0 ] && printf '> %s [Toggle All: Select All / Deselect All]\n' "${mark}" || printf '  %s [Toggle All: Select All / Deselect All]\n' "${mark}"
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
  local plan="${1:-}" key
  echo "Review planned changes:"
  [ -f "${plan}" ] && cat "${plan}"
  echo "Save & Apply? [yes/no]"
  if [ -n "${HAWS_TEST_KEYS:-}" ]; then
    ui_next_key >/dev/null 2>&1 || true
    key="${UI_LAST_KEY:-}"
    case "${key}" in no|n|cancel|q) return 1 ;; *) return 0 ;; esac
  fi
  ui_next_key >/dev/null 2>&1 || true
  key="${UI_LAST_KEY:-}"
  case "${key}" in yes|y|Y|on|1|"" ) return 0 ;; *) return 1 ;; esac
}
