#!/bin/bash
set -e

echo "================================"
echo "Starting Kubernetes Installation"
echo "================================"

# Disable SELinux
setenforce 0 || true
sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

# Disable swap
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

# Disable firewall for simplicity
systemctl stop firewalld || true
systemctl disable firewalld || true

echo "Installing containerd..."
# Install containerd
yum install -y yum-utils device-mapper-persistent-data lvm2
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
yum install -y containerd.io

# Configure containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml

# Enable SystemdCgroup
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

# Restart containerd
systemctl daemon-reload
systemctl enable containerd
systemctl restart containerd

# Verify containerd is running
systemctl status containerd --no-pager

echo "Installing Docker for image building..."
# Install Docker for building images (separate from k8s runtime)
yum install -y docker-ce docker-ce-cli
systemctl enable docker
systemctl start docker

echo "Configuring kernel modules..."
# Enable kernel modules
modprobe br_netfilter
modprobe overlay

# Persist modules
cat <<EOF > /etc/modules-load.d/k8s.conf
br_netfilter
overlay
EOF

# Set sysctl params
cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
sysctl --system

echo "Adding Kubernetes repository..."
# Add Kubernetes repo
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

echo "Installing Kubernetes components..."
# Install Kubernetes
yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
systemctl enable kubelet
systemctl start kubelet

echo "Initializing Kubernetes cluster..."
# Initialize cluster
kubeadm init --apiserver-advertise-address=192.168.56.11 \
  --pod-network-cidr=192.168.0.0/16 \
  --ignore-preflight-errors=NumCPU

# Set up kubeconfig for root
mkdir -p /root/.kube
cp /etc/kubernetes/admin.conf /root/.kube/config

# Set up kubeconfig for vagrant user
mkdir -p /home/vagrant/.kube
cp /etc/kubernetes/admin.conf /home/vagrant/.kube/config
chown -R vagrant:vagrant /home/vagrant/.kube

# Set KUBECONFIG for this session
export KUBECONFIG=/etc/kubernetes/admin.conf

echo "Removing control-plane taint to allow pod scheduling..."
# Remove control-plane taint (single-node cluster)
kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true
kubectl taint nodes --all node-role.kubernetes.io/master- || true

echo "Installing Calico CNI..."
# Install Calico CNI
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml

echo "Waiting for Calico pods to be ready..."
# Wait for Calico to be ready (give it time to create pods first)
sleep 30
kubectl wait --for=condition=ready pod -l k8s-app=calico-node -n kube-system --timeout=300s || echo "Calico pods not ready yet, continuing..."

echo "Installing Helm..."
# Install Helm with proper error handling (non-fatal)
(
  curl -fsSL -o /tmp/get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
  chmod 700 /tmp/get_helm.sh
  
  # Run helm install script
  HELM_INSTALL_DIR=/usr/local/bin /tmp/get_helm.sh || echo "Helm install script had warnings"
  
  # Add to PATH if not already there
  if ! grep -q "/usr/local/bin" /root/.bashrc; then
      echo 'export PATH=$PATH:/usr/local/bin' >> /root/.bashrc
  fi
  if ! grep -q "/usr/local/bin" /home/vagrant/.bashrc; then
      echo 'export PATH=$PATH:/usr/local/bin' >> /home/vagrant/.bashrc
  fi
  
  # Export for current session
  export PATH=$PATH:/usr/local/bin
  
  # Verify helm installation
  if /usr/local/bin/helm version &>/dev/null; then
      echo "✅ Helm installed successfully: $(/usr/local/bin/helm version --short)"
  else
      echo "⚠️  Helm installation had issues, but this is not critical for our setup"
  fi
  
  rm -f /tmp/get_helm.sh
) || echo "⚠️  Helm installation skipped (not required for this setup)"

echo "Creating namespaces..."
# Create namespaces
kubectl create namespace ollama || true
kubectl create namespace llm || true

echo "Verifying containerd installation..."
# Verify ctr is available
which ctr
ctr version

echo "================================"
echo "Kubernetes Installation Complete"
echo "================================"
echo ""
echo "Cluster Info:"
kubectl cluster-info
echo ""
echo "Nodes:"
kubectl get nodes -o wide
echo ""
echo "System Pods:"
kubectl get pods -n kube-system
echo ""