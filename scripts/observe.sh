#!/usr/bin/env bash
set -euo pipefail

SCENARIO="${1:-}"
BASE="$(cd "$(dirname "$0")/.." && pwd)"

# ── scenario branches ────────────────────────────────────────────────────────

if [ "$SCENARIO" = "host" ]; then
  WORK="$BASE/.work/host"
  HOST_KUBECONFIG="$WORK/host.kubeconfig"
  APP_KUBECONFIG="$WORK/vcluster.kubeconfig"
  OWNER_KUBECONFIG="$HOST_KUBECONFIG"
  OWNER_LABEL="host-api"
  APP_PF_PID="$WORK/port-forward.pid"
  APP_PF_NS="vc-app"
  APP_PF_SVC="app-vcluster"
  APP_PF_PORT="8443"

elif [ "$SCENARIO" = "isolated" ]; then
  WORK="$BASE/.work/isolated"
  HOST_KUBECONFIG="$WORK/host.kubeconfig"
  INFRA_KUBECONFIG="$WORK/infra.kubeconfig"
  APP_KUBECONFIG="$WORK/app.kubeconfig"
  OWNER_KUBECONFIG="$INFRA_KUBECONFIG"
  OWNER_LABEL="infra-vcluster-api"
  APP_PF_PID="$WORK/app-pf.pid"
  APP_PF_NS="vc-app"
  APP_PF_SVC="app-vcluster"
  APP_PF_PORT="8444"

else
  echo "usage: observe.sh <host|isolated>" >&2
  exit 1
fi

for f in "$HOST_KUBECONFIG" "$APP_KUBECONFIG" "$OWNER_KUBECONFIG"; do
  [ -f "$f" ] || { echo "missing: $f — run scripts/up-${SCENARIO}.sh first" >&2; exit 1; }
done

BASELINE_EV="$WORK/observe-baseline.txt"
SCALEDOWN_EV="$WORK/observe-scale-down.txt"
SCALEUP_EV="$WORK/observe-scale-up.txt"

# ── port-forward guard ───────────────────────────────────────────────────────
# The app vCluster API is reachable only via a port-forward. It can die between
# phases. This helper restarts it when needed so kubectl exec calls succeed.

_ensure_app_pf() {
  if [ -f "$APP_PF_PID" ]; then
    local pid
    pid=$(cat "$APP_PF_PID")
    if kill -0 "$pid" 2>/dev/null; then
      return
    fi
  fi
  KUBECONFIG="$HOST_KUBECONFIG" kubectl port-forward \
    -n "$APP_PF_NS" svc/"$APP_PF_SVC" "${APP_PF_PORT}:443" \
    >/dev/null 2>&1 &
  echo $! > "$APP_PF_PID"
  sleep 3
}

# ── context ──────────────────────────────────────────────────────────────────
# Variables are always set in the main shell before being written to evidence.
# { echo "$VAR"; } | tee -a only reads variables, never sets them.
# Loops and probe captures run in the main shell to remain visible to the summary.

{
  echo "=== scenario: $SCENARIO ==="
  echo "host-kubeconfig:  $HOST_KUBECONFIG (host inspection only)"
  echo "owner-kubeconfig: $OWNER_KUBECONFIG ($OWNER_LABEL — scale operations)"
  echo "app-kubeconfig:   $APP_KUBECONFIG (exec into probe Pod)"
  echo ""
} | tee "$BASELINE_EV"

# ── discover infra address ───────────────────────────────────────────────────

if [ "$SCENARIO" = "host" ]; then
  INFRA_IP=$(KUBECONFIG="$HOST_KUBECONFIG" kubectl get svc infra-nginx -n infra \
    -o jsonpath='{.spec.clusterIP}')
  INFRA_PORT=$(KUBECONFIG="$HOST_KUBECONFIG" kubectl get svc infra-nginx -n infra \
    -o jsonpath='{.spec.ports[0].port}')
else
  INFRA_IP=$(KUBECONFIG="$HOST_KUBECONFIG" kubectl get svc infra-nginx-x-infra-x-infra-vcluster \
    -n vc-infra -o jsonpath='{.spec.clusterIP}')
  INFRA_PORT=$(KUBECONFIG="$HOST_KUBECONFIG" kubectl get svc infra-nginx-x-infra-x-infra-vcluster \
    -n vc-infra -o jsonpath='{.spec.ports[0].port}')
fi

{ echo "infra target: $INFRA_IP:$INFRA_PORT"; echo ""; } | tee -a "$BASELINE_EV"

# ── phase 1: baseline ────────────────────────────────────────────────────────

echo "=== phase 1: baseline ===" | tee -a "$BASELINE_EV"
echo "" | tee -a "$BASELINE_EV"

echo "--- owner API ($OWNER_LABEL): Deployments ---" | tee -a "$BASELINE_EV"
KUBECONFIG="$OWNER_KUBECONFIG" kubectl get deployments --all-namespaces | tee -a "$BASELINE_EV"
echo "" | tee -a "$BASELINE_EV"

# app API visibility: absence vs Forbidden vs unreachable are distinct outcomes
echo "--- app vCluster API: infra Deployment visibility ---" | tee -a "$BASELINE_EV"
_ensure_app_pf
set +e
APP_DEPL_OUT=$(KUBECONFIG="$APP_KUBECONFIG" kubectl get deployment/infra-nginx -n infra 2>&1)
APP_DEPL_EXIT=$?
set -e
if [ "$APP_DEPL_EXIT" -eq 0 ]; then
  APP_DEPL_CLASS="present"
elif echo "$APP_DEPL_OUT" | grep -qi "not found"; then
  APP_DEPL_CLASS="absent (object or namespace not found in app vCluster API)"
elif echo "$APP_DEPL_OUT" | grep -qi "forbidden\|unauthorized"; then
  APP_DEPL_CLASS="forbidden"
else
  APP_DEPL_CLASS="unreachable or other error"
fi
{
  echo "command: kubectl get deployment/infra-nginx -n infra [app-kubeconfig]"
  echo "exit: $APP_DEPL_EXIT"
  echo "output: $APP_DEPL_OUT"
  echo "classification: $APP_DEPL_CLASS"
  echo ""
} | tee -a "$BASELINE_EV"

echo "--- app vCluster API: Deployments (all namespaces) ---" | tee -a "$BASELINE_EV"
_ensure_app_pf
KUBECONFIG="$APP_KUBECONFIG" kubectl get deployments --all-namespaces | tee -a "$BASELINE_EV"
echo "" | tee -a "$BASELINE_EV"

echo "--- host API: Pods (all namespaces) ---" | tee -a "$BASELINE_EV"
KUBECONFIG="$HOST_KUBECONFIG" kubectl get pods --all-namespaces -o wide | tee -a "$BASELINE_EV"
echo "" | tee -a "$BASELINE_EV"

echo "--- host API: Services (all namespaces) ---" | tee -a "$BASELINE_EV"
KUBECONFIG="$HOST_KUBECONFIG" kubectl get svc --all-namespaces | tee -a "$BASELINE_EV"
echo "" | tee -a "$BASELINE_EV"

echo "--- owner API ($OWNER_LABEL): infra-nginx endpoints ---" | tee -a "$BASELINE_EV"
KUBECONFIG="$OWNER_KUBECONFIG" kubectl get endpoints/infra-nginx -n infra -o wide | tee -a "$BASELINE_EV"
echo "" | tee -a "$BASELINE_EV"

echo "--- baseline HTTP probe ---" | tee -a "$BASELINE_EV"
_ensure_app_pf
set +e
BASELINE_RESPONSE=$(KUBECONFIG="$APP_KUBECONFIG" kubectl exec -n probe probe -- \
  curl -s --max-time 5 "http://$INFRA_IP:$INFRA_PORT/" 2>&1)
BASELINE_EXIT=$?
set -e
{
  echo "command: kubectl exec -n probe probe -- curl -s --max-time 5 http://$INFRA_IP:$INFRA_PORT/ [app-kubeconfig]"
  echo "response: $BASELINE_RESPONSE"
  echo "exit: $BASELINE_EXIT"
  echo ""
} | tee -a "$BASELINE_EV"

# ── phase 2: scale down ──────────────────────────────────────────────────────

{
  echo "=== phase 2: scale down ==="
  echo "scenario: $SCENARIO"
  echo "owner-api: $OWNER_LABEL"
  echo ""
} | tee "$SCALEDOWN_EV"

echo "--- scale infra-nginx to 0 via $OWNER_LABEL ---" | tee -a "$SCALEDOWN_EV"
{ echo "command: kubectl scale deployment/infra-nginx -n infra --replicas=0 [$OWNER_LABEL]"; } | tee -a "$SCALEDOWN_EV"
KUBECONFIG="$OWNER_KUBECONFIG" kubectl scale deployment/infra-nginx -n infra --replicas=0 | tee -a "$SCALEDOWN_EV"
echo "" | tee -a "$SCALEDOWN_EV"

echo "--- waiting for endpoints to clear (60s) ---" | tee -a "$SCALEDOWN_EV"
ELAPSED=0
ENDPOINTS_CLEARED=false
while [ "$ELAPSED" -lt 60 ]; do
  set +e
  SUBSETS=$(KUBECONFIG="$OWNER_KUBECONFIG" kubectl get endpoints/infra-nginx -n infra \
    -o jsonpath='{.subsets}' 2>/dev/null)
  set -e
  if [ -z "$SUBSETS" ]; then
    echo "endpoints cleared at ${ELAPSED}s" | tee -a "$SCALEDOWN_EV"
    ENDPOINTS_CLEARED=true
    break
  fi
  sleep 2
  ELAPSED=$((ELAPSED + 2))
done
if [ "$ENDPOINTS_CLEARED" = "false" ]; then
  echo "endpoints did not clear within 60s (last subsets: $SUBSETS)" | tee -a "$SCALEDOWN_EV"
fi
echo "" | tee -a "$SCALEDOWN_EV"

echo "--- owner API: endpoints after scale-down ---" | tee -a "$SCALEDOWN_EV"
KUBECONFIG="$OWNER_KUBECONFIG" kubectl get endpoints/infra-nginx -n infra -o wide | tee -a "$SCALEDOWN_EV"
echo "" | tee -a "$SCALEDOWN_EV"

echo "--- host API: Pods (all namespaces) after scale-down ---" | tee -a "$SCALEDOWN_EV"
KUBECONFIG="$HOST_KUBECONFIG" kubectl get pods --all-namespaces -o wide | tee -a "$SCALEDOWN_EV"
echo "" | tee -a "$SCALEDOWN_EV"

echo "--- outage HTTP probe ---" | tee -a "$SCALEDOWN_EV"
_ensure_app_pf
set +e
OUTAGE_RESPONSE=$(KUBECONFIG="$APP_KUBECONFIG" kubectl exec -n probe probe -- \
  curl -s --max-time 5 "http://$INFRA_IP:$INFRA_PORT/" 2>&1)
OUTAGE_EXIT=$?
set -e
{
  echo "command: kubectl exec -n probe probe -- curl -s --max-time 5 http://$INFRA_IP:$INFRA_PORT/ [app-kubeconfig]"
  echo "response: $OUTAGE_RESPONSE"
  echo "exit: $OUTAGE_EXIT"
  echo ""
} | tee -a "$SCALEDOWN_EV"

echo "--- owner API: events for infra-nginx ---" | tee -a "$SCALEDOWN_EV"
set +e
KUBECONFIG="$OWNER_KUBECONFIG" kubectl get events -n infra \
  --field-selector involvedObject.name=infra-nginx 2>&1 | tee -a "$SCALEDOWN_EV" || true
set -e
echo "" | tee -a "$SCALEDOWN_EV"

# ── phase 3: scale up ────────────────────────────────────────────────────────

{
  echo "=== phase 3: scale up ==="
  echo "scenario: $SCENARIO"
  echo "owner-api: $OWNER_LABEL"
  echo ""
} | tee "$SCALEUP_EV"

echo "--- scale infra-nginx to 1 via $OWNER_LABEL ---" | tee -a "$SCALEUP_EV"
{ echo "command: kubectl scale deployment/infra-nginx -n infra --replicas=1 [$OWNER_LABEL]"; } | tee -a "$SCALEUP_EV"
KUBECONFIG="$OWNER_KUBECONFIG" kubectl scale deployment/infra-nginx -n infra --replicas=1 | tee -a "$SCALEUP_EV"
echo "" | tee -a "$SCALEUP_EV"

echo "--- owner API: waiting for infra-nginx Available (120s) ---" | tee -a "$SCALEUP_EV"
KUBECONFIG="$OWNER_KUBECONFIG" kubectl wait deployment/infra-nginx -n infra \
  --for=condition=Available --timeout=120s | tee -a "$SCALEUP_EV"
echo "" | tee -a "$SCALEUP_EV"

echo "--- waiting for endpoints to be ready (60s) ---" | tee -a "$SCALEUP_EV"
ELAPSED=0
ENDPOINTS_READY=false
while [ "$ELAPSED" -lt 60 ]; do
  set +e
  SUBSETS=$(KUBECONFIG="$OWNER_KUBECONFIG" kubectl get endpoints/infra-nginx -n infra \
    -o jsonpath='{.subsets}' 2>/dev/null)
  set -e
  if [ -n "$SUBSETS" ]; then
    echo "endpoints ready at ${ELAPSED}s" | tee -a "$SCALEUP_EV"
    ENDPOINTS_READY=true
    break
  fi
  sleep 2
  ELAPSED=$((ELAPSED + 2))
done
if [ "$ENDPOINTS_READY" = "false" ]; then
  echo "endpoints not ready within 60s" | tee -a "$SCALEUP_EV"
fi
echo "" | tee -a "$SCALEUP_EV"

echo "--- owner API: endpoints after scale-up ---" | tee -a "$SCALEUP_EV"
KUBECONFIG="$OWNER_KUBECONFIG" kubectl get endpoints/infra-nginx -n infra -o wide | tee -a "$SCALEUP_EV"
echo "" | tee -a "$SCALEUP_EV"

echo "--- host API: Pods (all namespaces) after scale-up ---" | tee -a "$SCALEUP_EV"
KUBECONFIG="$HOST_KUBECONFIG" kubectl get pods --all-namespaces -o wide | tee -a "$SCALEUP_EV"
echo "" | tee -a "$SCALEUP_EV"

echo "--- recovery HTTP probe ---" | tee -a "$SCALEUP_EV"
_ensure_app_pf
set +e
RECOVERY_RESPONSE=$(KUBECONFIG="$APP_KUBECONFIG" kubectl exec -n probe probe -- \
  curl -s --max-time 5 "http://$INFRA_IP:$INFRA_PORT/" 2>&1)
RECOVERY_EXIT=$?
set -e
{
  echo "command: kubectl exec -n probe probe -- curl -s --max-time 5 http://$INFRA_IP:$INFRA_PORT/ [app-kubeconfig]"
  echo "response: $RECOVERY_RESPONSE"
  echo "exit: $RECOVERY_EXIT"
  echo ""
} | tee -a "$SCALEUP_EV"

# ── summary ──────────────────────────────────────────────────────────────────

echo "=== summary ==="
echo "scenario:       $SCENARIO"
echo "owner-api:      $OWNER_LABEL"
echo "baseline probe: exit=$BASELINE_EXIT  response=$BASELINE_RESPONSE"
echo "outage probe:   exit=$OUTAGE_EXIT  response=$OUTAGE_RESPONSE"
echo "recovery probe: exit=$RECOVERY_EXIT  response=$RECOVERY_RESPONSE"
echo ""
echo "evidence:"
echo "  $BASELINE_EV"
echo "  $SCALEDOWN_EV"
echo "  $SCALEUP_EV"
