#!/usr/bin/env bash
# Install HashiCorp Vault + External Secrets Operator for campaign-center.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${ANSIBLE_DIR}/.." && pwd)"

usage() {
  echo "Usage: $(basename "$0") <env>"
  echo ""
  echo "Installs Vault (standalone, PVC) and External Secrets Operator."
  echo "After install, run (one-time per cluster):"
  echo "  ./ansible/scripts/vault-init.sh <env>"
  echo "  ./ansible/scripts/vault-unseal.sh <env>"
  echo "  ./ansible/scripts/vault-bootstrap.sh <env>"
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
require_cmd helm "Install Helm: brew install helm"

[[ -f "${INV_FILE}" ]] || { echo "ERROR: Inventory not found: ${INV_FILE}" >&2; exit 1; }
[[ -f "${KUBECONFIG_PATH}" ]] || { echo "ERROR: Kubeconfig not found: ${KUBECONFIG_PATH}" >&2; exit 1; }

if ! ansible-galaxy collection list 2>/dev/null | grep -q 'kubernetes\.core'; then
  echo "==> Installing Ansible collection kubernetes.core"
  ansible-galaxy collection install -r "${ANSIBLE_DIR}/requirements.yml"
fi

export KUBECONFIG="${KUBECONFIG_PATH}"
cd "${ANSIBLE_DIR}"

echo "==> Installing Vault + External Secrets (env=${ENV})"
ansible-playbook -i "inventories/${ENV}/hosts.yml" playbooks/install-vault.yml

echo "==> Verifying installation (env=${ENV})"
ansible-playbook -i "inventories/${ENV}/hosts.yml" playbooks/verify-vault.yml

echo ""
echo "Done. Next steps (one-time):"
echo "  ./ansible/scripts/vault-init.sh ${ENV}"
echo "  ./ansible/scripts/vault-unseal.sh ${ENV}"
echo "  ./ansible/scripts/vault-bootstrap.sh ${ENV}"
echo ""
echo "Documentation: ${REPO_ROOT}/README-Vault.md"
echo "  export KUBECONFIG=${KUBECONFIG_PATH}"
