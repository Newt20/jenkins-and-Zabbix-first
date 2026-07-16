#!/bin/bash
# Single-node Kubernetes (kubeadm) setup for Ubuntu 22.04/24.04 on EC2.
# Run as root: sudo bash k8s-setup.sh
set -euxo pipefail

K8S_VERSION="v1.33"   # pkgs.k8s.io minor-version repo

# --- 1. Prerequisites -------------------------------------------------------
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

cat <<EOF >/etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

cat <<EOF >/etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

# --- 2. Docker Engine + containerd ------------------------------------------
apt-get update -y
apt-get install -y ca-certificates curl gpg apt-transport-https

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
  >/etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io
usermod -aG docker ubuntu

# Configure containerd as the Kubernetes CRI (docker's containerd.io ships with CRI disabled)
containerd config default >/etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd docker

# --- 3. kubeadm / kubelet / kubectl ------------------------------------------
curl -fsSL "https://pkgs.k8s.io/core:/stable:/$K8S_VERSION/deb/Release.key" |
  gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
  https://pkgs.k8s.io/core:/stable:/$K8S_VERSION/deb/ /" \
  >/etc/apt/sources.list.d/kubernetes.list
apt-get update -y
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
systemctl enable kubelet

# --- 4. Initialize the cluster ----------------------------------------------
# Public IP via IMDSv2 so the API server cert is also valid for remote kubectl
TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/public-ipv4)

kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --apiserver-cert-extra-sans="$PUBLIC_IP"

# kubectl for root (this shell) and the ubuntu user
export KUBECONFIG=/etc/kubernetes/admin.conf
mkdir -p /home/ubuntu/.kube
cp /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
chown -R ubuntu:ubuntu /home/ubuntu/.kube

# --- 5. CNI (Flannel) + allow scheduling on the control plane ----------------
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true

# --- 6. Production namespace --------------------------------------------------
kubectl create namespace production

echo "=== Kubernetes single-node cluster ready ==="
kubectl get nodes
