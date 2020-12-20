#!/usr/bin/env bash

#TODO unfortunately we may utilize IPs already in use by LXC
#we should find a free ip range, i.e. telling lxc not to use some ips
#or finding a range of 5 ips or whatever, where no ip is used by lxc

function install_metallb(){
  kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.9.3/manifests/namespace.yaml
  kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.9.3/manifests/metallb.yaml
  # On first install only
  kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)"
}

function configure_metallb(){
  cat << EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
      - 10.115.69.240-10.115.69.240
EOF
}


function check_functionality_of_metallb(){
echo "creating and exposing nginx with loadbalancer"
kubectl run nginx --image nginx --labels app=nginx
kubectl expose pod nginx --type=LoadBalancer --port=80
count=0
external_ip="";
while true; do
  sleep 1
  external_ip=$(kubectl get svc nginx --template="{{range .status.loadBalancer.ingress}}{{.ip}}{{end}}");
  echo "uhm"
  echo $external_ip
  if [[ -n "$external_ip" ]]; then
    count=$((count+1))
    break
  fi
  echo "buhm"
  if [[ $count -gt 3 ]]; then
    echo "we waited long enough for the ip address, should already be finished.. stopping"
    return 1
  fi
done;


works=0
echo "checking whether or not load balancer is accessible"
curl --connect-timeout 10 "$external_ip" > /dev/null 2>&1 && works=1

echo "deleting pod and service in background"
kubectl delete pod nginx > /dev/null 2>&1 &
kubectl delete service nginx > /dev/null 2>&1 &

if [[ $works -eq 1 ]]; then
  echo "metallb works"
  return 0
else
  echo "metallb not working"
  return 1
fi
}
