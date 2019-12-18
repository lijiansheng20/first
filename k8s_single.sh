#!/bin/bash

cat >self_centos7.repo <<EOF
[centos7]
name=centos7 Repo
baseurl=http://172.29.115.113:8081/repository/yum/$releasever/os/$basearch
gpgcheck=0
enable=1
EOF

cat >self_kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes Repo
baseurl=http://172.29.115.113:8081/repository/yum
gpgcheck=0
enable=1
EOF
cat >self_docker_ce.repo <<EOF
[docker-ce-stable]
name=Docker CE Stable - $basearch
baseurl=http://172.29.115.113:8081/repository/yum
enabled=1
gpgcheck=0
EOF


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





yum remove -y docker  docker-common docker-selinux docker-engine 
yum install -y yum-utils device-mapper-persistent-data lvm2
yum install -y docker-ce-19.03.5
systemctl enable docker
systemctl start docker
gpasswd -a clouder docker
newgrp docker

cat << END >/etc/docker/daemon.json
{
  "insecure-registries":["172.29.115.113:8082],
  "registry-mirrors": ["http://172.29.115.113:8082"],
  "exec-opts":["native.cgroupdriver=systemd"]
}
systemctl daemon-reload
systemctl restart docker

kubetool_ver=1.17.0
yum install -y kubeadm-${kubetool_ver}  kubelet-${kubetool_ver} kubectl-${kubetool_ver}
systemctl enable kubelet.service

cat >/etc/sysconfig/kubelet <<EOF
KUBELET_EXTRA_ARGS="--fail-swap-on=false --feature-gates SupportPodPidsLimit=false --feature-gates SupportNodePidsLimit=false"
EOF

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

kubeadm init --pod-network-cidr=192.168.0.0/16 --kubernetes-version=v1.17.0 --ignore-preflight-errors=Swap --upload-certs
mkdir -p $HOME/.kube
cp  /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

mkdir -p /home/clouder/.kube
cp  /etc/kubernetes/admin.conf /home/clouder/.kube/config
chown -R clouder:clouder /home/clouder/.kube

#calico
calico/cni:v3.8.5
calico/pod2daemon-flexvol:v3.8.5
calico/node:v3.8.5
calico/kube-controllers:v3.8.5
#wget  https://docs.projectcalico.org/v3.8/manifests/calico.yaml
kubectl apply -f calico.yaml 

#ingress-nginx
docker pull kubernetes-ingress-controller/nginx-ingress-controller:0.26.1
docker tag kubernetes-ingress-controller/nginx-ingress-controller:0.26.1 quay.io/kubernetes-ingress-controller/nginx-ingress-controller:0.26.1
docker rmi kubernetes-ingress-controller/nginx-ingress-controller:0.26.1
#ingerss nodeport
#https://github.com/kubernetes/ingress-nginx/blob/nginx-0.26.1/deploy/static/mandatory.yaml
kubectl apply -f ingress-service-nodeport.yaml

