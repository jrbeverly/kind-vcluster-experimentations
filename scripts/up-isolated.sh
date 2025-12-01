#!/usr/bin/env bash
set -euo pipefail

BASE="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$BASE/.work/isolated"
CLUSTER_NAME="kind-vcluster-lab"
INFRA_NS="vc-infra"
INFRA_RELEASE="infra-vcluster"
APP_NS="vc-app"
APP_RELEASE="app-vcluster"
HOST_KUBECONFIG="$WORK/host.kubeconfig"
INFRA_KUBECONFIG="$WORK/infra.kubeconfig"
APP_KUBECONFIG="$WORK/app.kubeconfig"
INFRA_PF_PID="$WORK/infra-pf.pid"
APP_PF_PID="$WORK/app-pf.pid"

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
echo "=== install infra vCluster ($INFRA_RELEASE in $INFRA_NS) ==="
KUBECONFIG="$HOST_KUBECONFIG" kubectl create namespace "$INFRA_NS"
KUBECONFIG="$HOST_KUBECONFIG" helm upgrade --install "$INFRA_RELEASE" loft-sh/vcluster \
  --version 0.37.0 \
  --namespace "$INFRA_NS" \
  --kubeconfig "$HOST_KUBECONFIG" \
  -f "$BASE/vcluster.yaml" \
  --wait --timeout 5m

echo ""
echo "=== install app vCluster ($APP_RELEASE in $APP_NS) ==="
KUBECONFIG="$HOST_KUBECONFIG" kubectl create namespace "$APP_NS"
KUBECONFIG="$HOST_KUBECONFIG" helm upgrade --install "$APP_RELEASE" loft-sh/vcluster \
  --version 0.37.0 \
  --namespace "$APP_NS" \
  --kubeconfig "$HOST_KUBECONFIG" \
  -f "$BASE/vcluster.yaml" \
  --wait --timeout 5m

echo ""
echo "=== host: vCluster pods ==="
KUBECONFIG="$HOST_KUBECONFIG" kubectl get pods --all-namespaces

echo ""
echo "=== port-forward infra vCluster → localhost:8443 ==="
KUBECONFIG="$HOST_KUBECONFIG" kubectl port-forward \
  -n "$INFRA_NS" \
  svc/"$INFRA_RELEASE" \
  8443:443 \
  >/dev/null 2>&1 &
echo $! > "$INFRA_PF_PID"
echo "infra port-forward PID: $(cat "$INFRA_PF_PID")"

sleep 4

echo ""
echo "=== export infra kubeconfig ==="
KUBECONFIG="$HOST_KUBECONFIG" kubectl get secret vc-"$INFRA_RELEASE" \
  -n "$INFRA_NS" \
  -o jsonpath='{.data.config}' | base64 -d > "$INFRA_KUBECONFIG"
echo "infra kubeconfig: $INFRA_KUBECONFIG"

echo ""
echo "=== port-forward app vCluster → localhost:8444 ==="
KUBECONFIG="$HOST_KUBECONFIG" kubectl port-forward \
  -n "$APP_NS" \
  svc/"$APP_RELEASE" \
  8444:443 \
  >/dev/null 2>&1 &
echo $! > "$APP_PF_PID"
echo "app port-forward PID: $(cat "$APP_PF_PID")"

sleep 4

echo ""
echo "=== export app kubeconfig (localhost:8444) ==="
KUBECONFIG="$HOST_KUBECONFIG" kubectl get secret vc-"$APP_RELEASE" \
  -n "$APP_NS" \
  -o jsonpath='{.data.config}' | base64 -d | \
  sed 's/localhost:8443/localhost:8444/' > "$APP_KUBECONFIG"
echo "app kubeconfig: $APP_KUBECONFIG"

echo ""
echo "=== infra vCluster API: nodes ==="
KUBECONFIG="$INFRA_KUBECONFIG" kubectl get nodes

echo ""
echo "=== app vCluster API: nodes ==="
KUBECONFIG="$APP_KUBECONFIG" kubectl get nodes

echo ""
echo "=== apply infra manifests via infra vCluster API ==="
KUBECONFIG="$INFRA_KUBECONFIG" kubectl apply -f "$BASE/manifests/infra.yaml"

echo ""
echo "=== wait for infra Deployment (infra vCluster) ==="
KUBECONFIG="$INFRA_KUBECONFIG" kubectl wait deployment/infra-nginx \
  -n infra \
  --for=condition=Available \
  --timeout=120s \
  | tee "$WORK/evidence-infra-ready.txt"

echo ""
echo "=== infra vCluster API: all resources ==="
KUBECONFIG="$INFRA_KUBECONFIG" kubectl get all -n infra

echo ""
echo "=== apply app manifests via app vCluster API ==="
KUBECONFIG="$APP_KUBECONFIG" kubectl apply -f "$BASE/manifests/app.yaml"

echo ""
echo "=== wait for probe Pod (app vCluster) ==="
KUBECONFIG="$APP_KUBECONFIG" kubectl wait pod/probe \
  -n probe \
  --for=condition=Ready \
  --timeout=120s \
  | tee "$WORK/evidence-probe-ready.txt"

echo ""
echo "=== discover synced infra Service on host ==="
# vCluster syncs objects as <virtual-name>-x-<virtual-namespace>-x-<release>
SYNCED_SVC="infra-nginx-x-infra-x-${INFRA_RELEASE}"
{
  echo "=== host: services in $INFRA_NS ==="
  KUBECONFIG="$HOST_KUBECONFIG" kubectl get svc -n "$INFRA_NS" --show-labels
  echo ""
  echo "virtual:  infra-nginx in namespace infra (infra vCluster API)"
  echo "host:     $SYNCED_SVC in namespace $INFRA_NS"
  echo ""
  echo "=== infra vCluster API: services ==="
  KUBECONFIG="$INFRA_KUBECONFIG" kubectl get svc -n infra --show-labels
} | tee "$WORK/evidence-service-mapping.txt"

INFRA_IP=$(KUBECONFIG="$HOST_KUBECONFIG" kubectl get svc "$SYNCED_SVC" \
  -n "$INFRA_NS" -o jsonpath='{.spec.clusterIP}')
INFRA_PORT=$(KUBECONFIG="$HOST_KUBECONFIG" kubectl get svc "$SYNCED_SVC" \
  -n "$INFRA_NS" -o jsonpath='{.spec.ports[0].port}')
{
  echo "host synced service: $SYNCED_SVC"
  echo "host namespace:      $INFRA_NS"
  echo "ClusterIP:           $INFRA_IP"
  echo "port:                $INFRA_PORT"
} | tee "$WORK/evidence-address.txt"
echo "discovered: $INFRA_IP:$INFRA_PORT"

echo ""
echo "=== API-scoped listings ==="
{
  echo "=== host API: Deployments (all namespaces) ==="
  KUBECONFIG="$HOST_KUBECONFIG" kubectl get deployments --all-namespaces
  echo ""
  echo "=== infra vCluster API: Deployments (all namespaces) ==="
  KUBECONFIG="$INFRA_KUBECONFIG" kubectl get deployments --all-namespaces
  echo ""
  echo "=== app vCluster API: Deployments (all namespaces) ==="
  KUBECONFIG="$APP_KUBECONFIG" kubectl get deployments --all-namespaces
  echo ""
  echo "=== host API: Pods (all namespaces) ==="
  KUBECONFIG="$HOST_KUBECONFIG" kubectl get pods --all-namespaces
  echo ""
  echo "=== infra vCluster API: Pods (all namespaces) ==="
  KUBECONFIG="$INFRA_KUBECONFIG" kubectl get pods --all-namespaces
  echo ""
  echo "=== app vCluster API: Pods (all namespaces) ==="
  KUBECONFIG="$APP_KUBECONFIG" kubectl get pods --all-namespaces
  echo ""
  echo "=== host API: Services (all namespaces) ==="
  KUBECONFIG="$HOST_KUBECONFIG" kubectl get svc --all-namespaces
} | tee "$WORK/evidence-listings.txt"

echo ""
echo "=== HTTP probe: app Pod → host infra ClusterIP ==="
set +e
PROBE_OUTPUT=$(KUBECONFIG="$APP_KUBECONFIG" kubectl exec -n probe probe -- \
  curl -s "http://$INFRA_IP:$INFRA_PORT/" 2>&1)
PROBE_EXIT=$?
set -e
{
  echo "command: curl -s http://$INFRA_IP:$INFRA_PORT/"
  echo "response: $PROBE_OUTPUT"
  echo "exit code: $PROBE_EXIT"
} | tee "$WORK/evidence-probe.txt"

echo ""
echo "=== extra steps vs scenario A (host baseline) ==="
{
  echo "additional vCluster: $INFRA_RELEASE in $INFRA_NS"
  echo "two port-forwards: infra → localhost:8443, app → localhost:8444"
  echo "app kubeconfig server patched from :8443 to :8444"
  echo "infra Deployment owned by infra vCluster API (absent from host Deployment list)"
  echo "synced Service on host: $SYNCED_SVC in $INFRA_NS"
  echo "probe target: host ClusterIP of synced Service ($INFRA_IP:$INFRA_PORT)"
} | tee "$WORK/evidence-extra-steps.txt"

echo ""
echo "=== done ==="
echo "host kubeconfig:  $HOST_KUBECONFIG"
echo "infra kubeconfig: $INFRA_KUBECONFIG"
echo "app kubeconfig:   $APP_KUBECONFIG"
echo "infra PF PID:     $(cat "$INFRA_PF_PID" 2>/dev/null || echo gone)"
echo "app PF PID:       $(cat "$APP_PF_PID" 2>/dev/null || echo gone)"
echo "infra address:    $INFRA_IP:$INFRA_PORT"
