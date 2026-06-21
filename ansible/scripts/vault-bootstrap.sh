#!/usr/bin/env bash
# Bootstrap Vault: KV v2, Kubernetes auth, campaign-center policy + role.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

usage() {
  echo "Usage: $(basename "$0") <env>"
  echo ""
  echo "Configures Vault after init/unseal:"
  echo "  - enable KV v2 at secret/"
  echo "  - enable Kubernetes auth"
  echo "  - write campaign-center policy"
  echo "  - create campaign-center role (External Secrets + future workloads)"
  echo ""
  echo "Uses vault-keys/<env>/root.token or VAULT_ROOT_TOKEN."
  echo ""
  echo "Example: $(basename "$0") dev"
  exit 1
}

vault_exec() {
  kubectl exec -n "${VAULT_NS}" "${VAULT_POD}" -- \
    env VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN="${VAULT_ROOT_TOKEN}" vault "$@"
}

auth_enabled() {
  vault_exec auth list -format=json 2>/dev/null | grep -q '"kubernetes/"' || return 1
}

secrets_enabled() {
  vault_exec secrets list -format=json 2>/dev/null | grep -q '"secret/"' || return 1
}

[[ $# -eq 1 ]] || usage
ENV="$1"

KUBECONFIG_PATH="${REPO_ROOT}/kubeconfigs/${ENV}.yaml"
KEYS_DIR="${REPO_ROOT}/vault-keys/${ENV}"
POLICY_FILE="${REPO_ROOT}/ansible/roles/vault/files/campaign-center-policy.hcl"
VAULT_POD="vault-0"
VAULT_NS="vault"
ESO_NS="external-secrets"
ESO_SA="external-secrets-vault"
REVIEWER_SA="vault-auth-reviewer"
K8S_AUTH_MOUNT="kubernetes"
VAULT_ROLE="campaign-center"
VAULT_POLICY="campaign-center"

[[ -f "${KUBECONFIG_PATH}" ]] || { echo "ERROR: Kubeconfig not found: ${KUBECONFIG_PATH}" >&2; exit 1; }
[[ -f "${POLICY_FILE}" ]] || { echo "ERROR: Policy file not found: ${POLICY_FILE}" >&2; exit 1; }
export KUBECONFIG="${KUBECONFIG_PATH}"

VAULT_ROOT_TOKEN="${VAULT_ROOT_TOKEN:-}"
if [[ -z "${VAULT_ROOT_TOKEN}" && -f "${KEYS_DIR}/root.token" ]]; then
  VAULT_ROOT_TOKEN="$(tr -d '\n' < "${KEYS_DIR}/root.token")"
fi

if [[ -z "${VAULT_ROOT_TOKEN}" ]]; then
  echo "ERROR: Root token not found. Set VAULT_ROOT_TOKEN or run vault-init.sh ${ENV}." >&2
  exit 1
fi

echo "==> Checking Vault is unsealed"
SEALED="$(kubectl exec -n "${VAULT_NS}" "${VAULT_POD}" -- \
  sh -c 'VAULT_ADDR=http://127.0.0.1:8200 vault status -format=json' 2>/dev/null | \
  { command -v jq >/dev/null && jq -r '.sealed' || echo true; })"
if [[ "${SEALED}" == "true" ]]; then
  echo "ERROR: Vault is sealed. Run vault-unseal.sh ${ENV} first." >&2
  exit 1
fi

echo "==> Enabling KV v2 at secret/"
if secrets_enabled; then
  echo "    secret/ already enabled"
else
  vault_exec secrets enable -path=secret kv-v2
fi

echo "==> Writing policy ${VAULT_POLICY}"
kubectl cp "${POLICY_FILE}" "${VAULT_NS}/${VAULT_POD}:/tmp/campaign-center-policy.hcl"
vault_exec policy write "${VAULT_POLICY}" /tmp/campaign-center-policy.hcl

echo "==> Enabling Kubernetes auth at ${K8S_AUTH_MOUNT}/"
if auth_enabled; then
  echo "    kubernetes auth already enabled"
else
  vault_exec auth enable -path="${K8S_AUTH_MOUNT}" kubernetes
fi

echo "==> Configuring Kubernetes auth"
REVIEWER_TOKEN="$(kubectl create token "${REVIEWER_SA}" -n "${VAULT_NS}" --duration=8760h)"
kubectl exec -n "${VAULT_NS}" "${VAULT_POD}" -- \
  env VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN="${VAULT_ROOT_TOKEN}" \
  vault write "auth/${K8S_AUTH_MOUNT}/config" \
    token_reviewer_jwt="${REVIEWER_TOKEN}" \
    kubernetes_host="https://kubernetes.default.svc:443" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
    disable_iss_validation=true

echo "==> Creating Kubernetes auth role ${VAULT_ROLE}"
vault_exec write "auth/${K8S_AUTH_MOUNT}/role/${VAULT_ROLE}" \
  bound_service_account_names="${ESO_SA},${REVIEWER_SA}" \
  bound_service_account_namespaces="${ESO_NS},${VAULT_NS}" \
  policies="${VAULT_POLICY}" \
  ttl=24h

echo ""
echo "Bootstrap complete."
echo ""
echo "ClusterSecretStore 'vault-backend' should become Ready within ~1 minute."
echo "Verify:"
echo "  kubectl get clustersecretstore vault-backend"
echo "  kubectl describe clustersecretstore vault-backend"
echo ""
echo "Example — store MYSQL_DSN for task-mservice (dev):"
echo "  export VAULT_ADDR=http://127.0.0.1:8200"
echo "  export VAULT_TOKEN=\$(cat ${KEYS_DIR}/root.token)"
echo "  kubectl port-forward -n vault svc/vault 8200:8200"
echo "  read -rs MYSQL_DSN && vault kv put secret/campaign-center/dev/task-mservice MYSQL_DSN=\"\${MYSQL_DSN}\""
