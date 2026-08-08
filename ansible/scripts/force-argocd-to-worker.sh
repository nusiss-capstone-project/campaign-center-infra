#!/usr/bin/env bash
# Force Argo CD workloads onto worker nodes (after affinity is in Helm values).
# Use when pods are still stuck on control-plane after reconfigure-argocd-nodes.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

usage() {
  echo "Usage: $(basename "$0") <env>"
  echo ""
  echo "1) Ensures Helm values include worker affinity (runs install playbook helm path lightly)"
  echo "2) Deletes Argo CD pods so they reschedule onto workers"
  echo ""
  echo "Example: $(basename "$0") dev"
  exit 1
}

[[ $# -eq 1 ]] || usage
ENV="$1"
KUBECONFIG_PATH="${REPO_ROOT}/kubeconfigs/${ENV}.yaml"
[[ -f "${KUBECONFIG_PATH}" ]] || { echo "ERROR: missing ${KUBECONFIG_PATH}" >&2; exit 1; }
export KUBECONFIG="${KUBECONFIG_PATH}"

NS=argocd

echo "==> Current pods"
kubectl get pods -n "${NS}" -o wide

echo ""
echo "==> Check affinity on application-controller (should mention control-plane DoesNotExist)"
if kubectl get sts -n "${NS}" argocd-application-controller >/dev/null 2>&1; then
  kubectl get sts -n "${NS}" argocd-application-controller -o jsonpath='{.spec.template.spec.affinity}{"\n"}' || true
elif kubectl get deploy -n "${NS}" argocd-application-controller >/dev/null 2>&1; then
  kubectl get deploy -n "${NS}" argocd-application-controller -o jsonpath='{.spec.template.spec.affinity}{"\n"}' || true
else
  echo "(controller workload name may differ — listing)"
  kubectl get deploy,sts -n "${NS}"
fi

echo ""
echo "==> Rollout restart all Argo CD deploy/sts"
kubectl -n "${NS}" get deploy,sts -l app.kubernetes.io/instance=argocd -o name 2>/dev/null | while read -r obj; do
  echo "restart ${obj}"
  kubectl -n "${NS}" rollout restart "${obj}" || true
done

echo ""
echo "==> Delete pods to force reschedule (StatefulSet controller included)"
kubectl delete pods -n "${NS}" --all --wait=false

echo ""
echo "==> Waiting for pods (timeout 5m)..."
sleep 5
kubectl wait --for=condition=Ready pod -n "${NS}" --all --timeout=300s || {
  echo "WARN: not all Ready yet — showing status"
  kubectl get pods -n "${NS}" -o wide
  kubectl describe pod -n "${NS}" -l app.kubernetes.io/name=argocd-application-controller | tail -40 || true
  exit 1
}

echo ""
echo "==> Final placement"
kubectl get pods -n "${NS}" -o wide

echo ""
echo "Done. Pods should be on worker (non control-plane) if affinity is set and worker has capacity."
