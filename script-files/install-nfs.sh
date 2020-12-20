#!/usr/bin/env bash
nfs_dir="/var/nfs/custom_nfs"
hostipAddr=$(hostname -I | awk '{print $1}')

function install_nfs_server_on_host_and_start() {
  echo "installing nfs software"
  sudo apt -y install nfs-kernel-server nfs-common portmap
  sudo systemctl start nfs-server

  #configure acces TODO make secure, don't know how.. for example 777 should NOT be useable..
  echo "creating dir at $nfs_dir for mounting, caution setting chmod 777 on this dir!"
  sudo mkdir -p "$nfs_dir"
  sudo chmod 777 "$nfs_dir"
}


function configure_access_to_nfs_from_nodes() {
  node=$1
  node_worker_one=$2

  ipmaster=$(lxc info "$node" | grep -e "eth0:[[:space:]]inet[[:space:]]" | cut -f3)
  ipworker=$(lxc info "$node_worker_one" | grep -e "eth0:[[:space:]]inet[[:space:]]" | cut -f3)

  echo "configuring access to $nfs_dir only by $ipmaster and $ipworker"
  cat <<EOF | sudo tee /etc/exports
$nfs_dir $ipworker(rw,sync,no_subtree_check,no_root_squash,insecure)
$nfs_dir $ipmaster(rw,sync,no_subtree_check,no_root_squash,insecure)
EOF

  sudo exportfs -rv
}

function configure_hosts() {
  node=$1
  node_worker_one=$2

  function setup_server() {
    which_node=$1

    lxc exec "$which_node" -- bash -c '\
sudo apt -y install nfs-common &&\
guestPath="/test/mydir"
sudo mkdir -p $guestPath &&\
sudo mount -t nfs '$hostipAddr:$nfs_dir' $guestPath &&\
touch $guestPath/hiUser.txt
sudo umount $guestPath'
  }

  echo "installing nfs-mount software on all nodes"
  setup_server "$node"
  setup_server "$node_worker_one"
}

function make_storage_class_and_rbac_rules(){
  echo "creating storage class"
  curl https://raw.githubusercontent.com/justmeandopensource/kubernetes/master/yamls/nfs-provisioner/default-sc.yaml >default-sc.yaml
  kubectl apply -f default-sc.yaml
  rm default-sc.yaml

  echo "creating rbac rules, so the provisioner pod is allowed to create pvc etc"
  curl https://raw.githubusercontent.com/justmeandopensource/kubernetes/master/yamls/nfs-provisioner/rbac.yaml >rbac.yaml
  kubectl apply -f rbac.yaml
  rm rbac.yaml
}

function install_nfs_pod_provisioner(){
  echo "installing and configuring pod nfs provisioner"
  curl https://raw.githubusercontent.com/justmeandopensource/kubernetes/master/yamls/nfs-provisioner/deployment.yaml > nfs-deploy.yaml
  sed -i "s/<<NFS Server IP>>/${hostipAddr}/" nfs-deploy.yaml
  sed -i "s|/srv/nfs/kubedata|${nfs_dir}|" nfs-deploy.yaml
  kubectl apply -f nfs-deploy.yaml
  rm nfs-deploy.yaml
}

function verify_functionality(){
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 200Mi
EOF
  sleep 5
  found=0
  if kubectl get pvc | grep -q Bound; then
    echo "found a bound pvc, nice!"
  else
    echo "found no bound pvc... bad!"
    found=1
  fi
  kubectl delete pvc test-pvc
  return $found
}

