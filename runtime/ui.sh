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
  local records=("$@") i id label detail selected key
  UI_CHECKLIST_RESULT=""
  echo "${title}"
  echo "Space: toggle   A: all   C: clear   Enter: continue"
  for i in "${!records[@]}"; do
    IFS="	" read -r id label detail selected <<EOF
${records[$i]}
EOF
    [ "${selected:-0}" = 1 ] && printf '[x] ' || printf '[ ] '
    printf '%s — %s\n' "${label:-${id}}" "${detail:-}"
  done
  if [ -n "${HAWS_TEST_KEYS:-}" ]; then
    while ui_next_key >/dev/null 2>&1; do
      key="${UI_LAST_KEY:-}"
      case "${key}" in
        a|A) for i in "${!records[@]}"; do records[$i]="${records[$i]%	*}	1"; done ;;
        c|C) for i in "${!records[@]}"; do records[$i]="${records[$i]%	*}	0"; done ;;
        space|Space|" ")
          i=0
          [ "${#records[@]}" -gt 0 ] && { IFS="	" read -r id label detail selected <<EOF
${records[0]}
EOF
            [ "${selected:-0}" = 1 ] && selected=0 || selected=1
            records[0]="${id}	${label}	${detail}	${selected}"; }
          ;;
        enter|Enter|"" ) break ;;
        cancel|q|quit) return 1 ;;
        *) ;;
      esac
      [ -z "${_HAWS_UI_KEYS_REMAINING:-}" ] && break
    done
  else
    ui_next_key >/dev/null || return 1
  fi
  for i in "${!records[@]}"; do
    IFS="	" read -r id label detail selected <<EOF
${records[$i]}
EOF
    [ "${selected:-0}" = 1 ] && UI_CHECKLIST_RESULT="${UI_CHECKLIST_RESULT}${id}\n"
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
