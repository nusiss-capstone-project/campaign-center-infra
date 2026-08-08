#!/usr/bin/env bash
# Enable Vault sidecar auto-unseal (dev only).
# Creates Secret vault-unseal-key and upgrades Helm with an unsealer sidecar.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${ANSIBLE_DIR}/.." && pwd)"

usage() {
  cat <<EOF
Usage: $(basename "$0") <env>

DEV ONLY: stores the Shamir unseal key in a Kubernetes Secret and injects a
sidecar into vault-0 that polls sealed status and runs vault operator unseal.

Prerequisites:
  - Vault installed and initialized (vault-init.sh)
  - Local key file vault-keys/<env>/unseal.key (or VAULT_UNSEAL_KEY_FILE)

Do not run alongside the CronJob unsealer. If present:
  ./ansible/scripts/vault-install-unsealer-cronjob.sh uninstall

Example:
  export KUBECONFIG=\$(pwd)/kubeconfigs/dev.yaml
  $(basename "$0") dev
EOF
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
DEFAULT_KEY_FILE="${REPO_ROOT}/vault-keys/${ENV}/unseal.key"

require_cmd ansible-playbook "Install Ansible: brew install ansible"
require_cmd kubectl "Install kubectl: brew install kubectl"
require_cmd helm "Install Helm: brew install helm"

[[ -f "${INV_FILE}" ]] || { echo "ERROR: Inventory not found: ${INV_FILE}" >&2; exit 1; }
[[ -f "${KUBECONFIG_PATH}" ]] || { echo "ERROR: Kubeconfig not found: ${KUBECONFIG_PATH}" >&2; exit 1; }

KEY_FILE="${VAULT_UNSEAL_KEY_FILE:-${DEFAULT_KEY_FILE}}"
if [[ ! -f "${KEY_FILE}" ]]; then
  echo "ERROR: Unseal key not found: ${KEY_FILE}" >&2
  echo "Run ./ansible/scripts/vault-init.sh ${ENV} first." >&2
  exit 1
fi

if ! ansible-galaxy collection list 2>/dev/null | grep -q 'kubernetes\.core'; then
  echo "==> Installing Ansible collection kubernetes.core"
  ansible-galaxy collection install -r "${ANSIBLE_DIR}/requirements.yml"
fi

# Avoid double-unseal with the CronJob helper
if kubectl --kubeconfig="${KUBECONFIG_PATH}" get cronjob vault-unsealer -n vault >/dev/null 2>&1; then
  echo "==> Removing existing CronJob vault-unsealer (sidecar replaces it)"
  "${SCRIPT_DIR}/vault-install-unsealer-cronjob.sh" uninstall || true
fi

export KUBECONFIG="${KUBECONFIG_PATH}"
export ENV
export VAULT_UNSEAL_KEY_FILE="${KEY_FILE}"

cd "${ANSIBLE_DIR}"

echo "==> Configuring Vault unsealer sidecar (env=${ENV}, key=${KEY_FILE})"
ansible-playbook -i "inventories/${ENV}/hosts.yml" playbooks/configure-vault-unsealer.yml

echo ""
echo "Done. Sidecar will unseal vault-0 after restarts."
echo "  kubectl -n vault get pod vault-0"
echo "  kubectl -n vault logs vault-0 -c unsealer --tail=30"
echo ""
echo "WARNING: unseal key is in Secret vault/vault-unseal-key — use only for dev."
