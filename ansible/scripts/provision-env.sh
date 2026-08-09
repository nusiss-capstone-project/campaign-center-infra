#!/usr/bin/env bash
# Provision a non-dev runtime env on the shared cluster (Vault KV + Argo root + Kafka topics + TLS secret).
#
# Creates ONLY:
#   1) Vault KV: secret/campaign-center/<env>/  (copy from --from, default:dev)
#   2) ArgoCD Application: campaign-gitops-root-<env> (targetRevision=<env>)
#   3) Kafka topics: <env>.<name> for the fixed business whitelist
#   4) Secrets in campaign-<env> copied from campaign-dev:
#        campaignhub-origin-tls, acr-secret
#
# Does NOT create/modify: Vault platform, Kafka broker, ArgoCD install, campaign-dev, or any other env.
#
# Usage:
#   ./ansible/scripts/provision-env.sh <env> [--from <source-env>] [--cluster-env <kubeconfig-env>]
#
# Example:
#   ./ansible/scripts/provision-env.sh demo
#   ./ansible/scripts/provision-env.sh demo --from dev --cluster-env dev
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=lib/env-bootstrap-common.sh
source "${SCRIPT_DIR}/lib/env-bootstrap-common.sh"

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

TARGET_ENV=""
FROM_ENV="dev"
CLUSTER_ENV="dev"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from)
      FROM_ENV="${2:?}"
      shift 2
      ;;
    --cluster-env)
      CLUSTER_ENV="${2:?}"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    -*)
      echo "ERROR: unknown flag: $1" >&2
      usage
      ;;
    *)
      if [[ -z "${TARGET_ENV}" ]]; then
        TARGET_ENV="$1"
        shift
      else
        echo "ERROR: unexpected argument: $1" >&2
        usage
      fi
      ;;
  esac
done

[[ -n "${TARGET_ENV}" ]] || usage
assert_safe_env "${TARGET_ENV}"
require_cmd kubectl
require_cmd python3
load_kubeconfig "${CLUSTER_ENV}"

ROOT_APP="$(root_app_name "${TARGET_ENV}")"
WORKLOAD_NS="$(workload_ns "${TARGET_ENV}")"
assert_safe_root_app "${ROOT_APP}"
assert_safe_workload_ns "${WORKLOAD_NS}"

echo "==> Provision env=${TARGET_ENV} (cluster kubeconfig=${CLUSTER_ENV})"
echo "    Will create ONLY:"
echo "      - Vault: secret/campaign-center/${TARGET_ENV}/ (from ${FROM_ENV})"
echo "      - ArgoCD Application: ${ROOT_APP} (revision=${TARGET_ENV})"
echo "      - Kafka topics: ${TARGET_ENV}.<whitelist>"
echo "      - Secrets in ${WORKLOAD_NS} (from ${SECRET_SOURCE_NS}): ${PROVISION_COPIED_SECRETS[*]}"
echo

# --- 1) Vault KV copy (never touches ${FROM_ENV} except as read source) ---
echo "==> [1/4] Vault KV copy ${FROM_ENV} -> ${TARGET_ENV}"
"${SCRIPT_DIR}/vault-kv-env.sh" "${CLUSTER_ENV}" copy \
  --from "${FROM_ENV}" \
  --to "${TARGET_ENV}"

# --- 2) ArgoCD root Application ---
echo "==> [2/4] Apply ArgoCD Application ${ROOT_APP}"
kubectl get ns "${ARGOCD_NS}" >/dev/null
if kubectl -n "${ARGOCD_NS}" get application "${ROOT_APP}" >/dev/null 2>&1; then
  echo "    Application already exists; updating in place."
fi

kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${ROOT_APP}
  namespace: ${ARGOCD_NS}
  labels:
    app.kubernetes.io/managed-by: provision-env
    campaign-center/env: ${TARGET_ENV}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: ${GITOPS_REPO_URL}
    targetRevision: ${TARGET_ENV}
    path: ${GITOPS_PATH}
    directory:
      recurse: false
  destination:
    server: https://kubernetes.default.svc
    namespace: ${ARGOCD_NS}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

# --- 3) Kafka topics (via existing kafka-ui API; no broker exec) ---
echo "==> [3/4] Create Kafka topics with prefix '${TARGET_ENV}.' (via kafka-ui)"
require_cmd curl
kafka_ui_pf_start
for base in "${ENV_KAFKA_TOPICS[@]}"; do
  topic="${TARGET_ENV}.${base}"
  echo "    create: ${topic}"
  rc=0
  kafka_ui_create_topic "${topic}" || rc=$?
  if [[ "${rc}" -eq 2 ]]; then
    echo "    skip (exists): ${topic}"
  elif [[ "${rc}" -ne 0 ]]; then
    exit 1
  fi
done
kafka_ui_pf_stop

# --- 4) Secrets copied from campaign-dev into workload namespace ---
echo "==> [4/4] Copy secrets ${SECRET_SOURCE_NS} -> ${WORKLOAD_NS}: ${PROVISION_COPIED_SECRETS[*]}"
for secret_name in "${PROVISION_COPIED_SECRETS[@]}"; do
  echo "    copy: ${secret_name}"
  copy_provision_secret "${secret_name}" "${WORKLOAD_NS}" "${TARGET_ENV}"
done

echo
echo "Provision complete for env=${TARGET_ENV}."
echo "Owned resources (safe for teardown-env.sh):"
echo "  - Application/${ROOT_APP} in ${ARGOCD_NS}"
echo "  - Vault path secret/campaign-center/${TARGET_ENV}/"
echo "  - Kafka topics ${TARGET_ENV}.<whitelist>"
echo "  - Secrets in ${WORKLOAD_NS}: ${PROVISION_COPIED_SECRETS[*]}"
echo
echo "Note: GitOps branch '${TARGET_ENV}' and apps under ${GITOPS_PATH} must already exist in ${GITOPS_REPO_URL}."
