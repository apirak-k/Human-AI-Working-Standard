#!/usr/bin/env bash
# Portable filesystem primitives used by the HAWS CLI.
# This module deliberately contains no user workflow or remote operations.

platform_id() {
  case "$(uname -s 2>/dev/null || echo unknown)" in
    MINGW*|MSYS*|CYGWIN*) echo windows-git-bash ;;
    Darwin*) echo macos ;;
    *) echo linux ;;
  esac
}

canonical_path() {
  local input="${1:-}"
  [ -n "${input}" ] || return 1

  if [ -d "${input}" ]; then
    (cd -P "${input}" 2>/dev/null && pwd -P)
    return $?
  fi

  local parent base
  parent="$(dirname "${input}")"
  base="$(basename "${input}")"
  if [ -d "${parent}" ]; then
    parent="$(cd -P "${parent}" 2>/dev/null && pwd -P)" || return 1
  else
    case "${parent}" in
      /*) : ;;
      *) parent="$(pwd -P)/${parent}" ;;
    esac
  fi
  case "${parent}" in
    /) printf '/%s\n' "${base}" ;;
    *) printf '%s/%s\n' "${parent}" "${base}" ;;
  esac
}

atomic_replace() {
  local source="${1:-}" destination="${2:-}"
  [ -f "${source}" ] || return 1
  [ -n "${destination}" ] || return 1
  local parent temp
  parent="$(dirname "${destination}")"
  mkdir -p "${parent}" || return 1
  temp="${destination}.tmp.$$"
  rm -f "${temp}"
  cp "${source}" "${temp}" || { rm -f "${temp}"; return 1; }
  mv -f "${temp}" "${destination}" || { rm -f "${temp}"; return 1; }
}

create_managed_link() {
  local source="${1:-}" destination="${2:-}"
  [ -e "${source}" ] || [ -L "${source}" ] || return 1
  [ -n "${destination}" ] || return 1
  local parent existing_target source_canonical
  parent="$(dirname "${destination}")"
  mkdir -p "${parent}" || return 1
  source_canonical="$(canonical_path "${source}")" || return 1

  if [ -e "${destination}" ] || [ -L "${destination}" ]; then
    [ -L "${destination}" ] || return 2
    existing_target="$(canonical_path "${destination}")" || return 2
    [ "${existing_target}" = "${source_canonical}" ] || return 2
    printf 'symlink\t%s\n' "${source_canonical}"
    return 0
  fi

  case "$(platform_id)" in
    windows-git-bash)
      # Git Bash's ln is portable and avoids shell quoting differences in cmd.exe.
      ln -s "${source_canonical}" "${destination}" || return 1 ;;
    *) ln -s "${source_canonical}" "${destination}" || return 1 ;;
  esac
  printf 'symlink\t%s\n' "${source_canonical}"
}
