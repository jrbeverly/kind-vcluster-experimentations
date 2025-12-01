#!/usr/bin/env bash
set -euo pipefail

BASE="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$BASE/.work/host"
CLUSTER_NAME="kind-vcluster-lab"
VCLUSTER_NS="vc-app"
VCLUSTER_RELEASE="app-vcluster"
HOST_KUBECONFIG="$WORK/host.kubeconfig"
VCLUSTER_KUBECONFIG="$WORK/vcluster.kubeconfig"
PORT_FORWARD_PID_FILE="$WORK/port-forward.pid"

mkdir -p "$WORK"

echo "=== prerequisites ==="
docker --version
kind --version
kubectl version --client
helm version --short
vcluster version

echo ""
echo "=== helm repo ==="
helm repo add loft-sh https://charts.loft.sh --force-update
helm repo update loft-sh

echo ""
echo "=== create kind cluster ==="
kind create cluster \
  --name "$CLUSTER_NAME" \
  --config "$BASE/kind.yaml" \
  --kubeconfig "$HOST_KUBECONFIG"

echo ""
echo "=== host node ready ==="
KUBECONFIG="$HOST_KUBECONFIG" kubectl wait --for=condition=Ready nodes --all --timeout=120s
KUBECONFIG="$HOST_KUBECONFIG" kubectl get nodes -o wide

echo ""
echo "=== apply infra manifests to host cluster ==="
KUBECONFIG="$HOST_KUBECONFIG" kubectl apply -f "$BASE/manifests/infra.yaml"

echo ""
echo "=== wait for infra Deployment ==="
KUBECONFIG="$HOST_KUBECONFIG" kubectl wait deployment/infra-nginx \
  -n infra \
  --for=condition=Available \
  --timeout=120s \
  | tee "$WORK/evidence-infra-ready.txt"

echo ""
echo "=== host infra resources ==="
KUBECONFIG="$HOST_KUBECONFIG" kubectl get all -n infra

echo ""
echo "=== discover infra Service address ==="
INFRA_IP=$(KUBECONFIG="$HOST_KUBECONFIG" kubectl get svc infra-nginx -n infra -o jsonpath='{.spec.clusterIP}')
INFRA_PORT=$(KUBECONFIG="$HOST_KUBECONFIG" kubectl get svc infra-nginx -n infra -o jsonpath='{.spec.ports[0].port}')
echo "infra-nginx ClusterIP: $INFRA_IP"
echo "infra-nginx port:      $INFRA_PORT"
echo "$INFRA_IP" > "$WORK/infra-address.txt"
echo "$INFRA_PORT" > "$WORK/infra-port.txt"
{
  echo "ClusterIP: $INFRA_IP"
  echo "port:      $INFRA_PORT"
  KUBECONFIG="$HOST_KUBECONFIG" kubectl get svc infra-nginx -n infra -o wide
} | tee "$WORK/evidence-service.txt"

echo ""
echo "=== install vcluster in host namespace $VCLUSTER_NS ==="
KUBECONFIG="$HOST_KUBECONFIG" kubectl create namespace "$VCLUSTER_NS"
KUBECONFIG="$HOST_KUBECONFIG" helm upgrade --install "$VCLUSTER_RELEASE" loft-sh/vcluster \
  --version 0.37.0 \
  --namespace "$VCLUSTER_NS" \
  --kubeconfig "$HOST_KUBECONFIG" \
  -f "$BASE/vcluster.yaml" \
  --wait --timeout 5m

echo ""
echo "=== vcluster pods (host view) ==="
KUBECONFIG="$HOST_KUBECONFIG" kubectl get pods -n "$VCLUSTER_NS" -o wide

echo ""
echo "=== start port-forward ==="
KUBECONFIG="$HOST_KUBECONFIG" kubectl port-forward \
  -n "$VCLUSTER_NS" \
  svc/"$VCLUSTER_RELEASE" \
  8443:443 \
  >/dev/null 2>&1 &
echo $! > "$PORT_FORWARD_PID_FILE"
echo "port-forward PID: $(cat "$PORT_FORWARD_PID_FILE")"

sleep 4

echo ""
echo "=== export vcluster kubeconfig ==="
KUBECONFIG="$HOST_KUBECONFIG" kubectl get secret vc-"$VCLUSTER_RELEASE" \
  -n "$VCLUSTER_NS" \
  -o jsonpath='{.data.config}' | base64 -d > "$VCLUSTER_KUBECONFIG"
echo "kubeconfig written to $VCLUSTER_KUBECONFIG"

echo ""
echo "=== virtual API: nodes ==="
KUBECONFIG="$VCLUSTER_KUBECONFIG" kubectl get nodes

echo ""
echo "=== apply app manifests to vcluster ==="
KUBECONFIG="$VCLUSTER_KUBECONFIG" kubectl apply -f "$BASE/manifests/app.yaml"

echo ""
echo "=== wait for probe Pod ready ==="
KUBECONFIG="$VCLUSTER_KUBECONFIG" kubectl wait pod/probe \
  -n probe \
  --for=condition=Ready \
  --timeout=120s \
  | tee "$WORK/evidence-probe-ready.txt"

echo ""
echo "=== API-scoped listings ==="
{
  echo "=== host API: Deployments (all namespaces) ==="
  KUBECONFIG="$HOST_KUBECONFIG" kubectl get deployments --all-namespaces
  echo ""
  echo "=== app vcluster API: Deployments (all namespaces) ==="
  KUBECONFIG="$VCLUSTER_KUBECONFIG" kubectl get deployments --all-namespaces
  echo ""
  echo "=== host API: Pods (all namespaces) ==="
  KUBECONFIG="$HOST_KUBECONFIG" kubectl get pods --all-namespaces
  echo ""
  echo "=== app vcluster API: Pods (all namespaces) ==="
  KUBECONFIG="$VCLUSTER_KUBECONFIG" kubectl get pods --all-namespaces
} | tee "$WORK/evidence-listings.txt"

echo ""
echo "=== HTTP probe from app Pod to host infra ==="
set +e
PROBE_OUTPUT=$(KUBECONFIG="$VCLUSTER_KUBECONFIG" kubectl exec -n probe probe -- curl -s "http://$INFRA_IP:$INFRA_PORT/" 2>&1)
PROBE_EXIT=$?
set -e
{
  echo "command: curl -s http://$INFRA_IP:$INFRA_PORT/"
  echo "response: $PROBE_OUTPUT"
  echo "exit code: $PROBE_EXIT"
} | tee "$WORK/evidence-probe.txt"

echo ""
echo "=== done ==="
echo "host kubeconfig:     $HOST_KUBECONFIG"
echo "vcluster kubeconfig: $VCLUSTER_KUBECONFIG"
echo "port-forward PID:    $(cat "$PORT_FORWARD_PID_FILE" 2>/dev/null || echo gone)"
echo "infra address:       $INFRA_IP:$INFRA_PORT"
