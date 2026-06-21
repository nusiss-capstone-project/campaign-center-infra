#!/usr/bin/env bash
# Initialize Vault (generate unseal key + root token). Run once per cluster.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

usage() {
  echo "Usage: $(basename "$0") <env>"
  echo ""
  echo "Initializes Vault on vault-0 and stores keys under vault-keys/<env>/ (gitignored)."
  echo "Dev default: 1 unseal key share, threshold 1. Override with VAULT_INIT_SHARES / VAULT_INIT_THRESHOLD."
  echo ""
  echo "Example: $(basename "$0") dev"
  exit 1
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "ERROR: '${cmd}' not found." >&2
    exit 1
  fi
}

[[ $# -eq 1 ]] || usage
ENV="$1"

KUBECONFIG_PATH="${REPO_ROOT}/kubeconfigs/${ENV}.yaml"
KEYS_DIR="${REPO_ROOT}/vault-keys/${ENV}"
VAULT_POD="vault-0"
VAULT_NS="vault"
VAULT_INIT_SHARES="${VAULT_INIT_SHARES:-1}"
VAULT_INIT_THRESHOLD="${VAULT_INIT_THRESHOLD:-1}"

require_cmd kubectl

[[ -f "${KUBECONFIG_PATH}" ]] || { echo "ERROR: Kubeconfig not found: ${KUBECONFIG_PATH}" >&2; exit 1; }
export KUBECONFIG="${KUBECONFIG_PATH}"

if [[ -f "${KEYS_DIR}/init.json" ]]; then
  echo "ERROR: Vault already initialized for env=${ENV} (${KEYS_DIR}/init.json exists)." >&2
  echo "To re-init you must wipe Vault data (destructive). See README-Vault.md." >&2
  exit 1
fi

kubectl get pod "${VAULT_POD}" -n "${VAULT_NS}" >/dev/null 2>&1 || {
  echo "ERROR: Pod ${VAULT_POD} not found in namespace ${VAULT_NS}. Run install-vault.sh first." >&2
  exit 1
}

mkdir -p "${KEYS_DIR}"
chmod 700 "${KEYS_DIR}"

echo "==> Initializing Vault (shares=${VAULT_INIT_SHARES}, threshold=${VAULT_INIT_THRESHOLD})"

INIT_OUTPUT="$(kubectl exec -n "${VAULT_NS}" "${VAULT_POD}" -- \
  sh -c "VAULT_ADDR=http://127.0.0.1:8200 vault operator init \
    -key-shares=${VAULT_INIT_SHARES} \
    -key-threshold=${VAULT_INIT_THRESHOLD} \
    -format=json")"

printf '%s\n' "${INIT_OUTPUT}" > "${KEYS_DIR}/init.json"
chmod 600 "${KEYS_DIR}/init.json"

if command -v jq >/dev/null 2>&1; then
  jq -r '.unseal_keys_b64[0]' "${KEYS_DIR}/init.json" > "${KEYS_DIR}/unseal.key"
  jq -r '.root_token' "${KEYS_DIR}/init.json" > "${KEYS_DIR}/root.token"
  chmod 600 "${KEYS_DIR}/unseal.key" "${KEYS_DIR}/root.token"
else
  echo "WARN: jq not installed — keys are only in ${KEYS_DIR}/init.json" >&2
fi

echo ""
echo "Vault initialized. Keys saved to: ${KEYS_DIR}/"
echo "  init.json   — full init output (keep offline and encrypted)"
echo "  unseal.key  — unseal key (if jq available)"
echo "  root.token  — root token (if jq available)"
echo ""
echo "Next: ./ansible/scripts/vault-unseal.sh ${ENV}"
