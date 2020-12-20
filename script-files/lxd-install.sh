#configure pc:
#install lxc 4.0, conntrack
function install_lxd() {
  sudo apt update && \
  sudo apt upgrade -y && \
  sudo apt install lxc=1:4.0.2-0ubuntu1 lxd=1:0.9 -y
  #(choose 4.0 aus)
  sudo adduser $(whoami) lxd
  #make groupe immediately effective without relogin
  newgrp lxd
}

function configure_host_system_for_lxd() {
  #configure some kernel parameters, may not even necessary
  sudo sysctl fs.inotify.max_user_instances=1048576
  sudo sysctl fs.inotify.max_queued_events=1048576
  sudo sysctl fs.inotify.max_user_watches=1048576
  sudo sysctl vm.max_map_count=262144

  #disable swap space, because kubeadm does not like swap space.
  #on each restart required to redisable swap space!
  sudo swapoff -a

  #increase usable num of uids and gids, because we are going to nest muuch.

  echo "increasing uid and gid space for root and user in /etc/subuid and /etc/subgid"
  sudo sed -i '/root/d' /etc/subuid /etc/subgid
  sudo sed -i "/$(whoami)/d" /etc/subuid /etc/subgid

  cat <<EOF | sudo tee -a /etc/subuid /etc/subgid
root:100000:1000000000
$(whoami):100000:1000000000
EOF

  echo "installing conntrack"
  #now install conntrack, if not yet installed on your system
  sudo apt install conntrack -y
}

function configure_lxd() {
  #finally configure lxd via lxd init
  sudo mkdir -p /opt/lxd/storage-pools/default
  cat <<EOF | lxd init --preseed
config: {}
networks:
- config:
    ipv4.address: 10.115.69.1/24
    ipv4.nat: "true"
    ipv6.address: fd42:8e8:bfdd:ebf8::1/64
    ipv6.nat: "true"
  description: ""
  name: lxdbr0
  type: bridge
storage_pools:
- config:
    source: /opt/lxd/storage-pools/default
  description: ""
  name: default
  driver: dir
profiles:
- config: {}
  description: Default LXD profile
  devices:
    eth0:
      name: eth0
      network: lxdbr0
      type: nic
    root:
      path: /
      pool: default
      type: disk
  name: default
EOF
}

