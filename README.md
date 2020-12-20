# LXC/LXD multi kubernetes with metallb and local nfs-server


Hi, this script is heavily influenced by 
https://github.com/corneliusweig/kubernetes-lxd
thanks for your great work!

Please read the corresponding code before you execute anything
from the web.

## prerequisites
> :warning: this script is ONLY testet on 
> ❯ uname -r
> 5.8.0-33-generic
> it should work with a greater variety, but no promises
> administrator privileges are necessary,
> i.e. for setting chmod on kubeconfig file
> or for installing nfs server, lxd etc.



## what does this repository provide?
1. **optional**: install LXD by code, configure it by code
2. fully automated 2 lxc container kubernetes cluster with kubeadm install
3. fully automated metallb loadbalancer installation
4. more or less fully automated nfs server configuration and 
   providing of storage class
   
## disclaimer
execute with caution, on your own behalf

## DESTROYING
> :warning: this installation will overwrite YOUR ACUTAL ~/.kube/config file
save it, or it'll be removed


> :warning: this script installs lxd on your HOST system


> :warning: this script installs nfs-kernel-server on your HOST system

## contribute
if you want to contribute: 
- We can surely improve the automation script.
- install a nfs-server in a container with e.g. user namespace nfs-server
- if it's possible to remove sudo calls, we should try
- make the installation script more configurable, i.e. do not overwrite
kube config file


## installation possibilites
1. you may copy paste each function on your own and run it from install-script.sh
(as seen in this file)
2. you can install all 4 components lxd, k8s, metallb, nfs-server
3. you can install 3 components k8s, metallb, nfs-server

## part 1: automatically install everything

> :warning: THIS WILL CHANGE YOUR HOST SYSTEM - PROCEED WITH CARE

```
git clone https://github.com/keeyzar/lxd-k8s-cluster
cd lxd-k8s-cluster

chmod +x install-script.sh
install_lxd=True
./install-script.sh $install_lxd 
```

## part 2: automatically install everything EXCEPT lxd
```
git clone https://github.com/keeyzar/lxd-k8s-cluster
cd lxd-k8s-cluster

chmod +x install-script.sh
install_lxd=False
./install-script.sh $install_lxd
```

## part 3: running the function calls of install script by hand
first, set source some files for getting all functions
```
git clone https://github.com/keeyzar/lxd-k8s-cluster
cd lxd-k8s-cluster

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
subdir="script-files"

#no worries, everything is packed into functions
source "${DIR}/${subdir}/lxd-install.sh"
source "${DIR}/${subdir}/install-kubernetes-cluster.sh"
source "${DIR}/${subdir}/install-metallb.sh"
source "${DIR}/${subdir}/install-nfs.sh"

node="k8s-control-plane"
worker="k8s-worker"

```

now you can either install each component on it's own
each of these functions are independently executable, but of course
the last two calls install metallb and full install need a working kube config file
```
#if you want to install lxd
install_lxd_fully

#if you want to only use lxc and install k8s cluster
setup_k8s_cluster

#if you want to install the metallb into the k8s cluster
install_metallb_fully

#if you want to install nfs on your system and in the k8s cluster as SC
full_install_nfs
```

## part 4: highly detailled function execution on it's own
this is, if you want to go step by step and verify each step
with higher granularity.

again, source the code
```
git clone https://github.com/keeyzar/lxd-k8s-cluster
cd lxd-k8s-cluster

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
subdir="script-files"

#no worries, everything is packed into functions
source "${DIR}/${subdir}/lxd-install.sh"
source "${DIR}/${subdir}/install-kubernetes-cluster.sh"
source "${DIR}/${subdir}/install-metallb.sh"
source "${DIR}/${subdir}/install-nfs.sh"

node="k8s-control-plane"
worker="k8s-worker"
```


now we're going to do everything by hand, what the other methods have done
at ***part 3***

```
#install lxd on your host system
install_lxd

#add some kernel parameters and install conntrack
configure_host_system_for_lxd

#configure lxd (lxd init, with preseed, so you do not need to configure it interactive)
configure_lxd

#### lxd part is finished, of course you can modify each file or
##   look deeper into the files, which you should definitely do, be4 you
##   execute any code found in the world wide web


#do we want to override the kubeconfig file existing at the moment?
#yes, or metallb and storage class functionality is not possible
overwrite_kubeconfig="True"

#well this is a full blown installation of 2 nodes.
#download k8s, set up with kubeadm as a cluster
install_k8s_in_lxc $node $worker $overwrite_kubeconfig

#we need an overlay network for a working kubernetes cluster.
#this step does not work, if you skipped overwrite kubeconfig
setup_calico

#untaint control plane, so it's usable as worker, too
utilize_control_plane_as_worker 

#well.. apply some resources from www
install_metallb

#set up metallb to use x.x.x.240 - x.x.x.249 as IP pool,
#so you can have up to 10 ips for loadbalancers
configure_metallb

#make sure metallb works as expected (gives out some ips to nginx service)
check_functionality_of_metallb


#### now the metallb is installed, last but not least the storage provider as nfs

#install nfs server components on HOST system
install_nfs_server_on_host_and_start

#we overwrite the actual nfs server configuration files,
#only the two nodes are allowed to access a specific, freshly created folder
configure_access_to_nfs_from_nodes $node $worker

#now the guest container need some software installed
#as nfs provisioner pod will utilize the "host" i.e. one of the two containers
#for mounting
configure_hosts $node $worker

#well. for nfs
make_storage_class_and_rbac_rules

#last but not least, install the pod provisioner deployment
install_nfs_pod_provisioner

#checking if PVC can be bound
verify_functionality

```

**Congratulation**
Installation was *hopefully* successful
