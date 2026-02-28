#/bin/bash

## edit the /etc/cloud/templates/hosts.debian.tmpl to match
sudo sh -c 'echo "192.168.8.144   rpimaster rpimaster" >> /etc/cloud/templates/hosts.debian.tmpl'
sudo sh -c 'echo "192.168.1.143   rpinode1  rpinode1" >> /etc/cloud/templates/hosts.debian.tmpl'
sudo sh -c 'echo "192.168.1.142   rpinode2  rpinode2" >> /etc/cloud/templates/hosts.debian.tmpl'

sudo sh -c 'echo "192.168.8.144   rpimaster rpimaster" >> /etc/hosts'
sudo sh -c 'echo "192.168.1.143   rpinode1  rpinode1" >> /etc/hosts'
sudo sh -c 'echo "192.168.1.142   rpinode2  rpinode2" >> /etc/hosts'


## load kernel modules
sudo tee /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
rbd
ceph
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
sudo modprobe rbd
sudo modprobe ceph


## kernel params for k8s
sudo tee /etc/sysctl.d/kubernetes.conf <<EOT
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOT


sudo sysctl --system

## install contianerd run time
sudo apt install -y curl gnupg2 software-properties-common apt-transport-https ca-certificates lvm2
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmour -o /etc/apt/trusted.gpg.d/docker.gpg
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
sudo apt update
sudo apt install -y containerd.io
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null 2>&1
sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

## Add Apt Repository for Kubernetes

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

sudo apt update
sudo apt upgrade -y
