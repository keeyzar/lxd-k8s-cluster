node="k8s-controlplane"
node_worker_one="k8s-workernode"
function install_k8s_in_lxc(){
  node=$1
  node_worker_one=$2
  overwrite_kubeconfig=$3

echo "launching lxc container ubuntu focal"
lxc launch images:ubuntu/focal "$node"

#when creating your lxc config for the containers, you need to disable apparmor,
#allow nesting, and make privileged, true, and much more...
#update k8s-lxconfig
#the virtual machine needs some config updates
#some may be obsolete, I was trying to set up a multi host (i.e. 2 pcs with lxd interconnected) kubernetes cluster
echo "configuring container config, e.g. allow nesting, make container privileged"
lxc config set "$node" linux.kernel_modules=ip_tables,ip6_tables,netlink_diag,nf_nat,overlay,xt_conntrack,br_netfilter
#we need to make printf, because otherwise we can't format this stuff correctly, always missconfigured lxc config, not enabling all the necessary information
printf 'lxc.apparmor.profile=unconfined\nlxc.cap.drop= \nlxc.cgroup.devices.allow=a\nlxc.mount.auto=proc:rw sys:rw\nlxc.mount.entry=/dev/kmsg dev/kmsg none defaults,bind,create=file' | lxc config set $node raw.lxc -
lxc config set "$node" security.privileged="true"
lxc config set "$node" security.nesting="true"
lxc config set "$node" limits.memory=4GB
lxc config set "$node" limits.cpu=4
lxc restart "$node"

#we can't use lxc.kmsg=1 -- first; it's default; second it's not even working
#because the kubelet wont start without this file
echo "enable kmsg"
lxc exec "$node" -- /bin/bash -c "echo 'L /dev/kmsg - - - - /dev/console' > /etc/tmpfiles.d/kmsg.conf"

#configure docker daemon, which later will be installed to use the correct cgroupdriver
echo "preconfigure docker, i.e. change storage driver and cgroupdriver"
cat << EOF >> daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF

lxc exec $node -- /bin/bash -c 'mkdir /etc/docker' &&\
lxc file push daemon.json $node/etc/docker/ &&\
rm daemon.json


#now install k8s and docker on guest vm
echo "installing software: k8s, kubeadm, docker into guest system"
lxc exec $node -- /bin/bash -c '\
apt-get install -y apt-transport-https ca-certificates curl gnupg2 software-properties-common conntrack &&\
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add - &&\
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add - &&\
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" &&\
add-apt-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main" &&\
apt-get update &&\
apt-get install -y docker-ce kubelet kubeadm kubectl &&\
apt-mark hold kubelet kubeadm kubectl docker-ce &&\
sudo systemctl enable kubelet &&\
sudo systemctl start kubelet'


#as the boot files are not present, but kubeadm does check for them, copy
#the actual kernel files into vm
#copy kernel config 4 kubeadm to read, or kubeadm will throw an error:
echo "pushing kernel files into the container"
lxc file push /boot/config-"$(uname -r)" "$node"/boot/

#create copy of lxc vm, because now is the time where they'll differ
echo "making a copy of the container, because now the configuration starts to differ"
lxc copy "$node" "$node_worker_one"

#start utilizing kubeadm for kubernetes master
kmasterip=$(lxc info "$node" | grep eth0 | head -1 | awk '{print $3}')

echo "triggering kubeadm init"
ipPoolCidr="10.244.0.0/16"
#install kubeadm with config
cat << EOF > config.yaml
apiVersion: kubeadm.k8s.io/v1beta2
kind: ClusterConfiguration
kubernetesVersion: v1.20.0
networking:
  podSubnet: $ipPoolCidr
apiServer:
  extraArgs:
    advertise-address: $kmasterip
    service-account-issuer: kubernetes.default.svc
    service-account-signing-key-file: /etc/kubernetes/pki/sa.key
    service-account-api-audiences: api
EOF
lxc file push config.yaml "$node"/home/
lxc exec "$node" -- /bin/bash -c 'sudo kubeadm init --v=5 --config /home/config.yaml'
rm config.yaml

  echo "starting worker node"
  lxc start "$node_worker_one"

  echo "joining worker node"
  joincmd=$(lxc exec "$node" -- /bin/bash -c 'sudo kubeadm token create --print-join-command | grep kubeadm')
  lxc exec "$node_worker_one" -- bash -c "sudo $joincmd"

if [[ "x$overwrite_kubeconfig" = "xTrue" ]]; then
  echo "pulling kubeconfig file, possibly overwriting existing one"
  lxc file pull "$node"/etc/kubernetes/admin.conf ~/.kube/config
  sudo chmod 600 /home/$(whoami)/.kube/config
else
  echo "skipping setting up kubeconfig, you may do it by yourself with the following commands"
  echo "lxc file pull $node/etc/kubernetes/admin.conf ~/.kube/config"
  echo "sudo chmod 600 /home/$(whoami)/.kube/config"
fi
}

function setup_calico(){
  echo "installing calico into cluster configured in ~/.kube/config"
  ipPoolCidr="10.244.0.0/16"
  kubectl create -f https://docs.projectcalico.org/manifests/tigera-operator.yaml
  curl https://docs.projectcalico.org/manifests/custom-resources.yaml > calico-resource.yaml
  #ipPoolCidr="10.244.0.0/16"
  sed -i "s_192.168.0.0/16_${ipPoolCidr}_" calico-resource.yaml
  kubectl apply -f calico-resource.yaml
  rm calico-resource.yaml
}

function utilize_control_plane_as_worker(){
  kubectl taint nodes k8s-control-plane node-role.kubernetes.io/master-
}
