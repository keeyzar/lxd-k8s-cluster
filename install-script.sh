#!/usr/bin/env bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
subdir="script-files"

#no worries, everything is packed into functions
source "${DIR}/${subdir}/lxd-install.sh"
source "${DIR}/${subdir}/install-kubernetes-cluster.sh"
source "${DIR}/${subdir}/install-metallb.sh"
source "${DIR}/${subdir}/install-nfs.sh"

node="k8s-control-plane"
worker="k8s-worker"

function install_lxd_fully() {
  if install_lxd; then
    echo "successfully installed lxd"
  else
    echo "errors found while installing lxd, stopping"
    return 1
  fi


  if configure_host_system_for_lxd; then
    echo "successfully configured host system"
  else
    echo "errors found while configuring host system, stopping"
    return 1
  fi


  if configure_lxd; then
    echo "successfully initialized lxd"
  else
    echo "errors found while setting up lxd, stopping"
    return 1
  fi
}

function setup_k8s_cluster(){
  overwrite_kubeconfig="True"
  if install_k8s_in_lxc $node $worker $overwrite_kubeconfig; then
    echo "successfully installed k8s nodes"
  else
    echo "kubernetes nodes were not successfully installed, stopping"
    return 1
  fi

  if setup_calico; then
    echo "successfully installed calico"
  else
    echo "calico was not installed, stopping"
  fi

  if utilize_control_plane_as_worker; then
    echo "successfully setup control plane as worker "
  else
    echo "wow a single command failed, i.e. untainting the control plane. something's fishy, stopping! "
    return 1
  fi
}

function install_metallb_fully(){
  if install_metallb; then
    echo "successfully installed metallb"
  else
    echo "couldn't install metallb - no access to the api-server? - stopping"
    return 1
  fi

  if configure_metallb; then
    echo "successfully configured metallb"
  else
    echo "configuration failed - no access to the api-server? - stopping"
    return 1
  fi

  if check_functionality_of_metallb; then
    echo "successful check of metallb functionality! "
  else
    echo "couldn't reach the nginx ... metallb is not correctly configured"
    return 1
  fi

  echo "metallb does work as expected, happy load balancing!"
}

function full_install_nfs(){
  echo "beginning configuring HOST system! "
  if install_nfs_server_on_host_and_start; then
    echo "successfully installed nfs components on HOST system! "
  else
    echo "something went wrong while installing HOST system components, stopping installation"
    return 1
  fi

  if configure_access_to_nfs_from_nodes $node $worker; then
    echo "allowed access for ips $node and $worker (lxc container ips) to nfs shared directory"
  else
    echo "couldn't set up access to nfs shared directory on HOST - stopping installation"
    return 1
  fi

  if configure_hosts $node $worker; then
    echo "Successfully installed nfs mount software in guest containers"
  else
    echo "couldn't install guest container software for nfs mounting - stopping installation"
    return 1
  fi


  if make_storage_class_and_rbac_rules; then
    echo "Storage class and rbac rules were created, nfs pod is allowed to create sc and more"
  else
    echo "was not able to create storage class and rbac rules - is access to kube api-server given?"
    return 1
  fi

  if install_nfs_pod_provisioner; then
    echo "nfs pod provisioner was installed"
  else
    echo "nfs pod provisioner was not installed - this may have many possible root causes - stopping installation"
    return 1
  fi

  if verify_functionality; then
    echo "functionality was verified - full installation successful, nfs volume binding is possible! "
  else
    echo "final check was not successful - 'stopping' installation. lol."
    return 1
  fi
}

if [[ x"$1" -eq "xTrue" ]]; then
  echo "requested to install lxd, starting."
  if ! install_lxd_fully; then
    echo "could not install lxd, stopping installation"
    return 2
  fi
else
  echo "skipped installation of lxd!"
fi

if ! setup_k8s_cluster; then
  echo "setup k8s cluster failed, stopping installation"
  return 3
fi

if ! install_metallb_fully; then
  echo "setup metallb failed, stopping installation"
  return 4
fi

if ! full_install_nfs; then
  echo "setup nfs failed, stopping installation"
  return 5
fi