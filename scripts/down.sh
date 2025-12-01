#!/usr/bin/env bash
set -euo pipefail

BASE="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$BASE/.work"
CLUSTER_NAME="kind-vcluster-lab"

echo "=== stop connection processes ==="
while IFS= read -r -d '' pidfile; do
  PID=$(cat "$pidfile")
  if kill -0 "$PID" 2>/dev/null; then
    kill "$PID"
    echo "stopped (PID $PID) from $pidfile"
  else
    echo "PID $PID not running (from $pidfile)"
  fi
  rm "$pidfile"
done < <(find "$WORK" -name "*.pid" -print0 2>/dev/null)
echo "connection processes done"

echo ""
echo "=== delete kind cluster ==="
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  kind delete cluster --name "$CLUSTER_NAME"
  echo "deleted $CLUSTER_NAME"
else
  echo "$CLUSTER_NAME not found (already gone)"
fi

echo ""
echo "=== remove credentials ==="
find "$WORK" -name "*.kubeconfig" -delete 2>/dev/null
echo "kubeconfigs removed"

echo ""
echo "=== after: named container ==="
docker ps --filter "name=${CLUSTER_NAME}-control-plane" --format "table {{.Names}}\t{{.Status}}" 2>/dev/null || true
echo "(no rows = clean)"
