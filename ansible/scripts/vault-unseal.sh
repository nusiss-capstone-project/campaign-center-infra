#!/usr/bin/env bash
# Unseal Vault using the key from vault-init.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

usage() {
  echo "Usage: $(basename "$0") <env>"
  echo ""
  echo "Unseals vault-0 using vault-keys/<env>/unseal.key or VAULT_UNSEAL_KEY."
  echo "Re-run after every pod restart until auto-unseal is configured (not enabled in dev)."
  echo ""
  echo "Example: $(basename "$0") dev"
  exit 1
}

[[ $# -eq 1 ]] || usage
ENV="$1"

KUBECONFIG_PATH="${REPO_ROOT}/kubeconfigs/${ENV}.yaml"
KEYS_DIR="${REPO_ROOT}/vault-keys/${ENV}"
VAULT_POD="vault-0"
VAULT_NS="vault"

[[ -f "${KUBECONFIG_PATH}" ]] || { echo "ERROR: Kubeconfig not found: ${KUBECONFIG_PATH}" >&2; exit 1; }
export KUBECONFIG="${KUBECONFIG_PATH}"

UNSEAL_KEY="${VAULT_UNSEAL_KEY:-}"
if [[ -z "${UNSEAL_KEY}" && -f "${KEYS_DIR}/unseal.key" ]]; then
  UNSEAL_KEY="$(tr -d '\n' < "${KEYS_DIR}/unseal.key")"
fi

if [[ -z "${UNSEAL_KEY}" ]]; then
  echo "ERROR: Unseal key not found. Set VAULT_UNSEAL_KEY or run vault-init.sh ${ENV}." >&2
  exit 1
fi

vault_status() {
  kubectl exec -n "${VAULT_NS}" "${VAULT_POD}" -- \
    sh -c 'VAULT_ADDR=http://127.0.0.1:8200 vault status -format=json' 2>/dev/null || true
}

if command -v jq >/dev/null 2>&1; then
  SEALED="$(vault_status | jq -r '.sealed // "true"')"
  if [[ "${SEALED}" == "false" ]]; then
    echo "Vault is already unsealed."
    exit 0
  fi
fi

echo "==> Unsealing Vault (${VAULT_POD})"
kubectl exec -n "${VAULT_NS}" "${VAULT_POD}" -- \
  sh -c "VAULT_ADDR=http://127.0.0.1:8200 vault operator unseal '${UNSEAL_KEY}'"

if command -v jq >/dev/null 2>&1; then
  SEALED="$(vault_status | jq -r '.sealed')"
  if [[ "${SEALED}" != "false" ]]; then
    echo "ERROR: Vault is still sealed. Check unseal threshold / key." >&2
    exit 1
  fi
fi

echo "Vault unsealed."
echo "Next: ./ansible/scripts/vault-bootstrap.sh ${ENV}"
