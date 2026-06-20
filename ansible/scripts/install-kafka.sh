#!/usr/bin/env bash
# Install lightweight Kafka (Apache official image, KRaft) — cluster-internal only.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${ANSIBLE_DIR}/.." && pwd)"

usage() {
  echo "Usage: $(basename "$0") <env>"
  echo ""
  echo "Installs a single-broker Apache Kafka (KRaft, no ZooKeeper) into namespace 'messaging'."
  echo "Bootstrap (in-cluster): kafka.messaging.svc.cluster.local:9092"
  echo ""
  echo "Example: $(basename "$0") dev"
  exit 1
}

require_cmd() {
  local cmd="$1"
  local hint="$2"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "ERROR: '${cmd}' not found." >&2
    echo "${hint}" >&2
    exit 1
  fi
}

[[ $# -eq 1 ]] || usage
ENV="$1"

INV_FILE="${ANSIBLE_DIR}/inventories/${ENV}/hosts.yml"
KUBECONFIG_PATH="${REPO_ROOT}/kubeconfigs/${ENV}.yaml"

require_cmd ansible-playbook "Install Ansible: brew install ansible"
require_cmd kubectl "Install kubectl: brew install kubectl"

[[ -f "${INV_FILE}" ]] || { echo "ERROR: Inventory not found: ${INV_FILE}" >&2; exit 1; }
[[ -f "${KUBECONFIG_PATH}" ]] || { echo "ERROR: Kubeconfig not found: ${KUBECONFIG_PATH}" >&2; exit 1; }

if ! ansible-galaxy collection list 2>/dev/null | grep -q 'kubernetes\.core'; then
  echo "==> Installing Ansible collection kubernetes.core"
  ansible-galaxy collection install -r "${ANSIBLE_DIR}/requirements.yml"
fi

export KUBECONFIG="${KUBECONFIG_PATH}"
cd "${ANSIBLE_DIR}"

echo "==> Installing Kafka (env=${ENV})"
ansible-playbook -i "inventories/${ENV}/hosts.yml" playbooks/install-kafka.yml

echo "==> Verifying Kafka (env=${ENV})"
ansible-playbook -i "inventories/${ENV}/hosts.yml" playbooks/verify-kafka.yml

echo ""
echo "Done. In-cluster bootstrap:"
echo "  kafka.messaging.svc.cluster.local:9092"
echo ""
echo "Local dev (from laptop):"
echo "  kubectl port-forward -n messaging svc/kafka 9092:9092"
echo "  # or run CLI inside the pod (recommended for topic tests)"
echo "  export KUBECONFIG=${KUBECONFIG_PATH}"
