#!/usr/bin/env bash
# Tear down a non-dev runtime env created by provision-env.sh.
#
# SAFETY: deletes ONLY resources that provision-env.sh / its root app create for <env>.
# Never deletes platform services, shared secrets, other envs, or campaign-dev.
#
# Allowed deletions (whitelist):
#   1) ArgoCD Application: campaign-gitops-root-<env>
#      (cascade prune removes ONLY objects owned by that Application)
#   2) Orphan workloads in campaign-<env>: deploy / svc / ingressroute
#      (leftovers when Argo prune is incomplete; never touches campaign-dev)
#   3) Vault KV: secret/campaign-center/<env>/  (via vault-kv-env.sh delete)
#   4) Kafka topics: exactly <env>.<name> for the fixed business whitelist
#      (skip if topic does not exist; broker CLI fallback if kafka-ui restricts delete)
#   5) Secrets in campaign-<env> (campaignhub-origin-tls, acr-secret)
#      and ONLY if labeled app.kubernetes.io/managed-by=provision-env
#
# Explicitly NEVER deleted by this script:
#   - Kafka / Vault / ArgoCD / Linkerd / Traefik / any platform Helm release
#   - Application/campaign-gitops-root (dev root)
#   - Namespace campaign-dev or Secret therein
#   - Vault secret/campaign-center/dev/
#   - Kafka topics without the <env>. prefix, or topics not on the whitelist
#   - Secrets in campaign-<env> without managed-by=provision-env
#   - Namespace campaign-<env> itself (operator may delete empty ns later)
#
# Usage:
#   CONFIRM_TEARDOWN=true ./ansible/scripts/teardown-env.sh <env> [--cluster-env <kubeconfig-env>]
#
# Example:
#   CONFIRM_TEARDOWN=true ./ansible/scripts/teardown-env.sh demo
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=lib/env-bootstrap-common.sh
source "${SCRIPT_DIR}/lib/env-bootstrap-common.sh"

usage() {
  sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

TARGET_ENV=""
CLUSTER_ENV="dev"

while [[ $# -gt 0 ]]; do
  case "$1" in
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
load_kubeconfig "${CLUSTER_ENV}"

ROOT_APP="$(root_app_name "${TARGET_ENV}")"
WORKLOAD_NS="$(workload_ns "${TARGET_ENV}")"
assert_safe_root_app "${ROOT_APP}"
assert_safe_workload_ns "${WORKLOAD_NS}"

if [[ "${CONFIRM_TEARDOWN:-}" != "true" ]]; then
  echo "Refusing to tear down env='${TARGET_ENV}' without CONFIRM_TEARDOWN=true" >&2
  echo
  echo "This would remove ONLY provision-owned resources for that env:" >&2
  echo "  - Application/${ROOT_APP} (Argo cascade prune of its children only)" >&2
  echo "  - Orphan ${WORKLOAD_ORPHAN_KINDS[*]} in ${WORKLOAD_NS}" >&2
  echo "  - Vault secret/campaign-center/${TARGET_ENV}/" >&2
  echo "  - Kafka topics ${TARGET_ENV}.<whitelist> (only if present)" >&2
  echo "  - Secrets in ${WORKLOAD_NS} (if managed-by=provision-env): ${PROVISION_COPIED_SECRETS[*]}" >&2
  echo
  echo "It will NOT touch platform services, ${PROTECTED_NS}, ${PROTECTED_ROOT_APP}, or other envs." >&2
  exit 1
fi

echo "==> Teardown env=${TARGET_ENV} (cluster kubeconfig=${CLUSTER_ENV})"
echo "    Scope: provision-owned resources only. No platform / other-env deletes."
echo

# --- 1) ArgoCD root Application (cascade prune of that app's children only) ---
echo "==> [1/5] Delete ArgoCD Application ${ROOT_APP} (if present)"
if kubectl -n "${ARGOCD_NS}" get application "${ROOT_APP}" >/dev/null 2>&1; then
  # Extra guard: only delete if provision-env labeled it (or name matches pattern already checked)
  MANAGED="$(kubectl -n "${ARGOCD_NS}" get application "${ROOT_APP}" \
    -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}' 2>/dev/null || true)"
  if [[ -n "${MANAGED}" && "${MANAGED}" != "provision-env" ]]; then
    echo "ERROR: Application ${ROOT_APP} exists but managed-by='${MANAGED}' (not provision-env). Abort." >&2
    exit 1
  fi
  kubectl -n "${ARGOCD_NS}" delete application "${ROOT_APP}" --wait=true
  echo "    deleted ${ROOT_APP}"
else
  echo "    skip: Application ${ROOT_APP} not found"
fi

# --- 2) Orphan workloads left when Argo prune is incomplete ---
echo "==> [2/5] Cleanup orphan workloads in ${WORKLOAD_NS}: ${WORKLOAD_ORPHAN_KINDS[*]}"
cleanup_workload_ns_orphans "${WORKLOAD_NS}"

# --- 3) Vault KV for this env only ---
echo "==> [3/5] Delete Vault KV secret/campaign-center/${TARGET_ENV}/"
CONFIRM_DELETE=true "${SCRIPT_DIR}/vault-kv-env.sh" "${CLUSTER_ENV}" delete "${TARGET_ENV}"

# --- 4) Kafka topics: whitelist + exist-only ---
echo "==> [4/5] Delete Kafka topics with prefix '${TARGET_ENV}.' (exist-only, whitelist)"
require_cmd curl
kafka_ui_pf_start
EXISTING_TOPICS=""
USE_TOPIC_LIST=0
if EXISTING_TOPICS="$(kafka_ui_list_topic_names)"; then
  USE_TOPIC_LIST=1
else
  echo "    warning: topic list failed; will probe each whitelist topic"
fi
for base in "${ENV_KAFKA_TOPICS[@]}"; do
  topic="${TARGET_ENV}.${base}"
  # Refuse anything that does not look like our prefixed topic
  if [[ "${topic}" != "${TARGET_ENV}."* ]]; then
    echo "ERROR: internal guard failed for topic '${topic}'." >&2
    exit 1
  fi
  if [[ "${USE_TOPIC_LIST}" -eq 1 ]]; then
    if ! printf '%s\n' "${EXISTING_TOPICS}" | grep -qxF "${topic}"; then
      echo "    skip (missing): ${topic}"
      continue
    fi
  fi
  echo "    delete: ${topic}"
  rc=0
  kafka_ui_delete_topic "${topic}" || rc=$?
  if [[ "${rc}" -eq 2 ]]; then
    echo "    skip (missing): ${topic}"
  elif [[ "${rc}" -ne 0 ]]; then
    exit 1
  fi
done
kafka_ui_pf_stop

# --- 5) Secrets copied by provision (label-gated) ---
echo "==> [5/5] Delete secrets in ${WORKLOAD_NS} (provision-owned only): ${PROVISION_COPIED_SECRETS[*]}"
for secret_name in "${PROVISION_COPIED_SECRETS[@]}"; do
  delete_provision_secret "${secret_name}" "${WORKLOAD_NS}"
done

echo
echo "Teardown complete for env=${TARGET_ENV}."
echo "Left untouched on purpose: platform services, ${PROTECTED_NS}, ${PROTECTED_ROOT_APP},"
echo "Vault ${PROTECTED_ENV}/, Kafka broker, and namespace ${WORKLOAD_NS} itself."
