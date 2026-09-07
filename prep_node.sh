#!/bin/bash


#######
###  Preparation of the nodes for kubeadm initialization and joining
###  using the following ami - ami-04a30c3f913434cfb
###  https://containerd.io/releases/ - compatibility matrix
###  run as root
######

### prepare
swapoff -a
sed -i '/swap/d' /etc/fstab
setenforce 0
sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
yum -y install wget
### tripped over the below upon first kubeadm init launch
sysctl net.ipv4.ip_forward=1

### failed first Flannel launch because of below
modprobe br_netfilter
sysctl net.bridge.bridge-nf-call-iptables=1

### make those permanent
tee /etc/sysctl.d/ip_forward.conf << 'EOF'
net.ipv4.ip_forward = 1
sysctl net.bridge.bridge-nf-call-iptables=1
EOF

sysctl --system

### install containerd, runc, and cni-plugins
cd /tmp
wget https://github.com/containerd/containerd/releases/download/v2.3.2/containerd-2.3.2-linux-amd64.tar.gz   	###download and install containerd
tar Cxzvf /usr/local containerd-2.3.2-linux-amd64.tar.gz  								### 
wget https://raw.githubusercontent.com/containerd/containerd/main/containerd.service  	### containerd.service for systemd
mv containerd.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now containerd

wget https://github.com/opencontainers/runc/releases/download/v1.4.2/runc.amd64
install -m 755 runc.amd64 /usr/local/sbin/runc

wget https://github.com/containernetworking/plugins/releases/download/v1.9.0/cni-plugins-linux-amd64-v1.9.0.tgz
mkdir -p /opt/cni/bin
tar Cxzvf /opt/cni/bin cni-plugins-linux-amd64-v1.9.0.tgz 


### create deafult config and change settings
mkdir /etc/containerd
/usr/local/bin/containerd config default > /etc/containerd/config.toml

sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
systemctl restart containerd


### add repo and install kubeadm, kubectl, and kubelet; using 1.36

cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.36/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.36/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF


yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
systemctl enable --now kubelet


