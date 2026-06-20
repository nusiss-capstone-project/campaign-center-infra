#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
  echo "Usage: $(basename "$0") <env>"
  exit 1
}

[[ $# -eq 1 ]] || usage
ENV="$1"

command -v ansible-playbook >/dev/null 2>&1 || {
  echo "ERROR: ansible-playbook not found. Install Ansible first." >&2
  exit 1
}

"${SCRIPT_DIR}/generate-inventory.sh" "${ENV}"

cd "${ANSIBLE_DIR}"
echo "==> Installing K3s (env=${ENV})"
ansible-playbook -i "inventories/${ENV}/hosts.yml" playbooks/install-k3s.yml

echo "==> Verifying K3s cluster"
ansible-playbook -i "inventories/${ENV}/hosts.yml" playbooks/verify-k3s.yml

KUBECONFIG_PATH="$(cd "${ANSIBLE_DIR}/.." && pwd)/kubeconfigs/${ENV}.yaml"
echo ""
echo "Done. Use kubeconfig:"
echo "  export KUBECONFIG=${KUBECONFIG_PATH}"
echo "  kubectl get nodes"
