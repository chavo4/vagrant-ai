# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  config.vm.box = "chavo1/rockylinux-9.5-aarch64"
  config.vm.hostname = "k8s-ollama-master"
  config.vm.network "private_network", ip: "192.168.56.11"
  
  config.vm.provider "virtualbox" do |vb|
    vb.name = "k8s-ollama-cluster"
    vb.memory = "16384"
    vb.cpus = 8
  end
  
  # Provision Kubernetes and dependencies
  config.vm.provision "shell", path: "scripts/k8s-centos.sh"
  
  # Build and deploy applications after VM is ready
  config.vm.provision "shell", path: "scripts/deploy-apps.sh", run: "always"
end