#!/usr/bin/env bash
# Reconfigure Argo CD scheduling (prefer worker nodes) and roll pods.
# Thin wrapper around install-argocd.sh — safe / idempotent Helm upgrade.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  echo "Usage: $(basename "$0") <env>"
  echo ""
  echo "Applies Argo CD Helm values with soft worker-node preference, then"
  echo "restarts Argo CD workloads so pods reschedule off the control-plane when possible."
  echo ""
  echo "Example: $(basename "$0") dev"
  exit 1
}

[[ $# -eq 1 ]] || usage

exec "${SCRIPT_DIR}/install-argocd.sh" "$1"
