#!/usr/bin/env bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
subdir="script-files"

#no worries, everything is packed into functions
source "${DIR}/${subdir}/lxd-install"

function install_lxd() {
  if install_lxd; then

  fi
  configure_host_system_for_lxd
  configure_lxd
}