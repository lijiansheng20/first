#!/bin/bash

log_file=/var/log/k8s.log
nexus_server=172.29.115.113
echo "begin install `date`" >> ${log_file}
echo "begin config yum repo... `date`" >> ${log_file}
mv /etc/yum.repos.d /etc/yum.repos.d.bak
mkdir /etc/yum.repos.d
cp CentOS-Base.repo /etc/yum.repos.d/
cat >/etc/yum.repos.d/self_centos7.repo <<EOF
[centos7]
name=centos7 Repo
baseurl=http://${nexus_server}:8081/repository/yum/\$releasever/os/\$basearch
gpgcheck=0
enable=1
EOF

cat >/etc/yum.repos.d/self_kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes Repo
baseurl=http://${nexus_server}:8081/repository/yum/kubernetes/yum/repos/kubernetes-el7-x86_64/
gpgcheck=0
enable=1
EOF
cat >/etc/yum.repos.d/self_docker_ce.repo <<EOF
[docker-ce-stable]
name=Docker CE Stable - $basearch
baseurl=http://${nexus_server}:8081/repository/yum/docker-ce/linux/centos/7/\$basearch/stable
enabled=1
gpgcheck=0
EOF

echo "begin prerequire `date`" >> ${log_file}
#hostname
# 修改 hostname
#hostnamectl set-hostname your-new-host-name
# 查看修改结果
hostnamectl status
# 设置 hostname 解析
echo "127.0.0.1   $(hostname)" >> /etc/hosts

#firewall
#systemctl disable firewalld
#systemctl stop firewalld
#setenforce 0
#vi /etc/selinux/config
#修改"SELINUX=disabled"为"SELINUX=disabled"
#getenforce
sed -i 's#SELINUX=enforcing#SELINUX=disabled#g' /etc/selinux/config
setenforce 0

echo "vm.swappiness = 0">> /etc/sysctl.conf  
swapoff -a

cat  <<END >>/etc/sysctl.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
END
sysctl -p




echo "begin uninstall docker `date`" >> ${log_file}
yum remove -y docker  docker-common docker-selinux docker-engine 
yum install -y yum-utils device-mapper-persistent-data lvm2
yum install -y docker-ce-19.03.5
systemctl enable docker
systemctl restart docker
gpasswd -a clouder docker
#newgrp docker

cat <<EOF >/etc/docker/daemon.json
{
  "insecure-registries":["${nexus_server}:8082"],
  "registry-mirrors": ["http://${nexus_server}:8082"],
  "exec-opts":["native.cgroupdriver=systemd"]
}
EOF
echo "begin restart docker `date`" >> ${log_file}
systemctl daemon-reload
systemctl restart docker
echo "begin install k8s `date`" >> ${log_file}
kubetool_ver=1.17.0
yum install -y kubeadm-${kubetool_ver}  kubelet-${kubetool_ver} kubectl-${kubetool_ver}
systemctl enable kubelet.service

cat >/etc/sysconfig/kubelet <<EOF
KUBELET_EXTRA_ARGS="--fail-swap-on=false --feature-gates SupportPodPidsLimit=false --feature-gates SupportNodePidsLimit=false"
EOF

echo "begin pull images of k8s `date`" >> ${log_file}
kubernetes_ver=v1.17.0

docker pull google_containers/kube-apiserver-amd64:v1.17.0
docker pull google_containers/kube-controller-manager-amd64:v1.17.0
docker pull google_containers/kube-scheduler-amd64:v1.17.0
docker pull google_containers/kube-proxy-amd64:v1.17.0
docker pull google_containers/pause:3.1
docker pull google_containers/etcd-amd64:3.4.3-0
docker pull coredns/coredns:1.6.5

docker tag google_containers/kube-apiserver-amd64:v1.17.0            k8s.gcr.io/kube-apiserver:v1.17.0   
docker tag google_containers/kube-controller-manager-amd64:v1.17.0   k8s.gcr.io/kube-controller-manager:v1.17.0
docker tag google_containers/kube-scheduler-amd64:v1.17.0            k8s.gcr.io/kube-scheduler:v1.17.0
docker tag google_containers/kube-proxy-amd64:v1.17.0                k8s.gcr.io/kube-proxy:v1.17.0
docker tag google_containers/pause:3.1                               k8s.gcr.io/pause:3.1
docker tag google_containers/etcd-amd64:3.4.3-0                      k8s.gcr.io/etcd:3.4.3-0
docker tag dcoredns/coredns:1.6.5                                    k8s.gcr.io/coredns:1.6.5

docker rmi google_containers/kube-apiserver-amd64:v1.17.0
docker rmi google_containers/kube-controller-manager-amd64:v1.17.0
docker rmi google_containers/kube-scheduler-amd64:v1.17.0
docker rmi google_containers/kube-proxy-amd64:v1.17.0
docker rmi google_containers/pause:3.1
docker rmi google_containers/etcd-amd64:3.4.3-0
docker rmi coredns/coredns:1.6.5
echo "begin kubeadm init `date`" >> ${log_file}
kubeadm init --pod-network-cidr=192.168.0.0/16 --kubernetes-version=v1.17.0 --ignore-preflight-errors=Swap --upload-certs
mkdir -p $HOME/.kube
cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

mkdir -p /home/clouder/.kube
cp -f /etc/kubernetes/admin.conf /home/clouder/.kube/config
chown -R clouder:clouder /home/clouder/.kube
kubectl taint nodes --all node-role.kubernetes.io/master-
echo "begin pull images of calico `date`" >> ${log_file}
#calico
docker pull calico/cni:v3.8.5
docker pull calico/pod2daemon-flexvol:v3.8.5
docker pull calico/node:v3.8.5
docker pull calico/kube-controllers:v3.8.5
#wget  https://docs.projectcalico.org/v3.8/manifests/calico.yaml
echo "begin apply calico `date`" >> ${log_file}
kubectl apply -f calico.yaml 

echo "begin pull images of ingress-nginx `date`" >> ${log_file}
#ingress-nginx
docker pull kubernetes-ingress-controller/nginx-ingress-controller:0.26.1
docker tag kubernetes-ingress-controller/nginx-ingress-controller:0.26.1 quay.io/kubernetes-ingress-controller/nginx-ingress-controller:0.26.1
docker rmi kubernetes-ingress-controller/nginx-ingress-controller:0.26.1
#ingerss nodeport
#https://github.com/kubernetes/ingress-nginx/blob/nginx-0.26.1/deploy/static/mandatory.yaml
echo "begin apply ingress-nginx `date`" >> ${log_file}
kubectl apply -f mandatory.yaml
#kubectl apply -f ingress-service-nodeport.yaml
kubectl apply -f ingress-service-normal.yaml
echo "end install `date`" >> ${log_file}
kubectl get pod --all-namespaces
newgrp docker
