# LXC/LXD multi kubernetes with metallb and local nfs-server


Hi, this script is heavily influenced by 
https://github.com/corneliusweig/kubernetes-lxd
thanks for your great work!

## prerequisites
ubuntu focal host system, administrator privileges

## what does this repository provide?
1. **optional**: install LXD by code, configure it by code
2. fully automated 2 lxc container kubernetes cluster with kubeadm install
3. fully automated metallb loadbalancer installation
4. more or less fully automated nfs server configuration and 
   providing of storage class
   
## disclaimer
execute with caution, on your own behalf

## contribute
if you want to contribute: 
- We can surely improve the automation script.
- install a nfs-server in a container with e.g. user namespace nfs-server

## part 1: automatically install lxd in ubuntu

