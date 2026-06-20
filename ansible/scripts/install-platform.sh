#!/usr/bin/env bash
# Install full dev platform stack: Traefik → Headlamp → Kafka → Kafka UI
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${ANSIBLE_DIR}/.." && pwd)"

usage() {
  echo "Usage: $(basename "$0") <env>"
  echo ""
  echo "Requires K3s already installed (install-k3s.sh)."
  echo "Runs: Traefik config → Headlamp → Kafka → Kafka UI"
  echo ""
  echo "Example: $(basename "$0") dev"
  exit 1
}

[[ $# -eq 1 ]] || usage
ENV="$1"

KUBECONFIG_PATH="${REPO_ROOT}/kubeconfigs/${ENV}.yaml"
[[ -f "${KUBECONFIG_PATH}" ]] || {
  echo "ERROR: Kubeconfig not found. Run ./ansible/scripts/install-k3s.sh ${ENV} first." >&2
  exit 1
}

export KUBECONFIG="${KUBECONFIG_PATH}"

"${SCRIPT_DIR}/install-traefik.sh" "${ENV}"
"${SCRIPT_DIR}/install-headlamp.sh" "${ENV}"
"${SCRIPT_DIR}/install-kafka.sh" "${ENV}"
"${SCRIPT_DIR}/install-kafka-ui.sh" "${ENV}"

echo ""
echo "Platform stack installed for env=${ENV}"
