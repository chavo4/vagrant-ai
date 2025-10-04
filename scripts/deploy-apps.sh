#!/bin/bash
set -e

export KUBECONFIG=/etc/kubernetes/admin.conf

echo "================================"
echo "Deploying Ollama and LLM UI"
echo "================================"

# Deploy Ollama
echo "Deploying Ollama service..."
kubectl apply -f /vagrant/scripts/ollama-deploy.yaml

# Build LLM Prompt UI Docker image
echo "Building LLM Prompt UI Docker image..."
cd /vagrant/llm-prompt-app
docker build -t llm-prompt-local:latest .

# Save and import image to containerd
echo "Importing image to containerd..."
docker save -o /tmp/llm-prompt-local.tar llm-prompt-local:latest
ctr -n k8s.io images import /tmp/llm-prompt-local.tar
rm -f /tmp/llm-prompt-local.tar

# Deploy LLM Prompt UI
echo "Deploying LLM Prompt UI..."
kubectl apply -f /vagrant/scripts/llm-prompt-deploy.yaml

# Wait for deployments
echo "Waiting for Ollama deployment..."
kubectl wait --for=condition=available deployment/ollama -n ollama --timeout=120s || true

echo "Waiting for LLM Prompt UI deployment..."
kubectl wait --for=condition=available deployment/llm-prompt -n llm --timeout=120s || true

# Pull tinyllama model
echo "Pulling tinyllama model (this may take a while)..."
OLLAMA_POD=$(kubectl get pod -n ollama -l app=ollama -o jsonpath='{.items[0].metadata.name}')
if [ ! -z "$OLLAMA_POD" ]; then
  kubectl exec -n ollama $OLLAMA_POD -- ollama pull tinyllama || echo "Model pull will happen on first request"
fi

echo ""
echo "================================"
echo "Deployment Complete!"
echo "================================"
echo ""
echo "Access the services:"
echo "  - Ollama API: http://192.168.56.11:31134"
echo "  - LLM Prompt UI: http://192.168.56.11:30080"
echo ""
echo "Kubernetes Dashboard:"
kubectl get pods --all-namespaces
echo ""
echo "Services:"
kubectl get svc --all-namespaces
echo ""