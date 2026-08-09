#!/usr/bin/env bash
# Copy or delete Vault KV trees under secret/campaign-center/<env>/.
# Never writes or deletes under secret/campaign-center/dev/ (protected).
#
# Usage:
#   ./ansible/scripts/vault-kv-env.sh [cluster-env] copy --to <env> [--from <env>]
#   ./ansible/scripts/vault-kv-env.sh [cluster-env] delete <env>
#
# cluster-env selects kubeconfig + root token (default: dev).
# --from defaults to "dev". Target of copy/delete must not be "dev".
#
# Examples:
#   export KUBECONFIG=$(pwd)/kubeconfigs/dev.yaml
#   ./ansible/scripts/vault-kv-env.sh copy --to demo
#   ./ansible/scripts/vault-kv-env.sh copy --from staging --to demo
#   ./ansible/scripts/vault-kv-env.sh delete demo
#   CONFIRM_DELETE=true ./ansible/scripts/vault-kv-env.sh delete demo
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

MOUNT="secret"
PREFIX="campaign-center"
PROTECTED_ENV="dev"
VAULT_POD="${VAULT_POD:-vault-0}"
VAULT_NS="${VAULT_NS:-vault}"

usage() {
  cat <<EOF
Usage:
  $(basename "$0") [cluster-env] copy --to <env> [--from <env>]
  $(basename "$0") [cluster-env] delete <env>

cluster-env   Infra env for kubeconfig + vault-keys (default: dev)
copy          Recursively copy KV v2 paths:
                ${MOUNT}/${PREFIX}/<from>/...  ->  ${MOUNT}/${PREFIX}/<to>/...
delete        Recursively delete ${MOUNT}/${PREFIX}/<env>/...

Safety:
  - Refuses any write/delete under ${MOUNT}/${PREFIX}/${PROTECTED_ENV}/
  - copy --to ${PROTECTED_ENV} and delete ${PROTECTED_ENV} are blocked
  - delete requires CONFIRM_DELETE=true

Environment:
  KUBECONFIG          Optional; else kubeconfigs/<cluster-env>.yaml
  VAULT_ROOT_TOKEN    Optional; else vault-keys/<cluster-env>/root.token
  CONFIRM_DELETE      Must be true for delete
  VAULT_POD / VAULT_NS  Defaults: vault-0 / vault

Examples:
  $(basename "$0") copy --to demo
  $(basename "$0") copy --from staging --to demo
  CONFIRM_DELETE=true $(basename "$0") delete demo
EOF
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: '$1' not found." >&2
    exit 1
  }
}

assert_safe_env_name() {
  local name="$1"
  local role="$2"
  if [[ -z "${name}" ]]; then
    echo "ERROR: ${role} env name is empty." >&2
    exit 1
  fi
  if [[ ! "${name}" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
    echo "ERROR: invalid ${role} env name '${name}' (use alphanumeric / _ / -)." >&2
    exit 1
  fi
  if [[ "${name}" == "${PROTECTED_ENV}" ]]; then
    echo "ERROR: refusing to modify ${MOUNT}/${PREFIX}/${PROTECTED_ENV}/ (${role}=${name})." >&2
    exit 1
  fi
}

assert_not_protected_path() {
  local logical="$1"
  # logical like campaign-center/demo/foo (no mount prefix)
  case "${logical}" in
    "${PREFIX}/${PROTECTED_ENV}"|"${PREFIX}/${PROTECTED_ENV}/"*)
      echo "ERROR: refusing operation on protected path ${MOUNT}/${logical}" >&2
      exit 1
      ;;
  esac
}

load_vault_token() {
  local keys_dir="${REPO_ROOT}/vault-keys/${CLUSTER_ENV}"
  VAULT_ROOT_TOKEN="${VAULT_ROOT_TOKEN:-}"
  if [[ -z "${VAULT_ROOT_TOKEN}" && -f "${keys_dir}/root.token" ]]; then
    VAULT_ROOT_TOKEN="$(tr -d '\n' < "${keys_dir}/root.token")"
  fi
  if [[ -z "${VAULT_ROOT_TOKEN}" ]]; then
    echo "ERROR: Root token not found. Set VAULT_ROOT_TOKEN or run vault-init.sh ${CLUSTER_ENV}." >&2
    exit 1
  fi
}

vault_exec() {
  kubectl exec -n "${VAULT_NS}" "${VAULT_POD}" -c vault -- \
    env VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN="${VAULT_ROOT_TOKEN}" vault "$@"
}

# Pipe stdin into vault in the pod (needed for kv put @/dev/stdin).
vault_exec_i() {
  kubectl exec -i -n "${VAULT_NS}" "${VAULT_POD}" -c vault -- \
    env VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN="${VAULT_ROOT_TOKEN}" vault "$@"
}

# List immediate children under mount/path (KV v2). Prints names; dirs end with /.
kv_list() {
  local path="$1"
  vault_exec kv list -format=json -mount="${MOUNT}" "${path}" 2>/dev/null \
    | jq -r '.[]?' 2>/dev/null || true
}

# Recursively collect leaf secret paths (no trailing slash), relative to PREFIX/env
collect_leaves() {
  local base="$1" # e.g. campaign-center/dev
  local prefix="${2:-}" # relative under base
  local full="${base}"
  [[ -n "${prefix}" ]] && full="${base}/${prefix}"

  local entry child
  while IFS= read -r entry; do
    [[ -z "${entry}" ]] && continue
    if [[ "${entry}" == */ ]]; then
      child="${entry%/}"
      if [[ -n "${prefix}" ]]; then
        collect_leaves "${base}" "${prefix}/${child}"
      else
        collect_leaves "${base}" "${child}"
      fi
    else
      if [[ -n "${prefix}" ]]; then
        printf '%s\n' "${prefix}/${entry}"
      else
        printf '%s\n' "${entry}"
      fi
    fi
  done < <(kv_list "${full}")
}

cmd_copy() {
  local from_env="${PROTECTED_ENV}"
  local to_env=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --from)
        from_env="${2:-}"
        shift 2
        ;;
      --to)
        to_env="${2:-}"
        shift 2
        ;;
      -h|--help) usage ;;
      *)
        echo "ERROR: unknown copy option: $1" >&2
        usage
        ;;
    esac
  done

  assert_safe_env_name "${to_env}" "copy target (--to)"
  if [[ -z "${from_env}" ]]; then
    echo "ERROR: --from is empty." >&2
    exit 1
  fi
  if [[ ! "${from_env}" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
    echo "ERROR: invalid --from env name '${from_env}'." >&2
    exit 1
  fi
  if [[ "${from_env}" == "${to_env}" ]]; then
    echo "ERROR: --from and --to must differ." >&2
    exit 1
  fi

  local src_base="${PREFIX}/${from_env}"
  local dst_base="${PREFIX}/${to_env}"
  assert_not_protected_path "${dst_base}"

  echo "==> Listing secrets under ${MOUNT}/${src_base}/"
  local leaves
  leaves="$(collect_leaves "${src_base}" || true)"
  if [[ -z "${leaves}" ]]; then
    echo "ERROR: no secrets found under ${MOUNT}/${src_base}/ (or path missing)." >&2
    exit 1
  fi

  local count
  count="$(printf '%s\n' "${leaves}" | grep -c . || true)"
  echo "    found ${count} secret path(s)"
  echo "==> Copying ${MOUNT}/${src_base}/ -> ${MOUNT}/${dst_base}/"

  local rel src_path dst_path
  while IFS= read -r rel; do
    [[ -z "${rel}" ]] && continue
    src_path="${src_base}/${rel}"
    dst_path="${dst_base}/${rel}"
    assert_not_protected_path "${dst_path}"

    echo "    ${src_path} -> ${dst_path}"
    # kv put "-" expects KEY=value lines; JSON must use @/dev/stdin
    vault_exec kv get -format=json -mount="${MOUNT}" "${src_path}" \
      | jq -c '.data.data // {}' \
      | vault_exec_i kv put -mount="${MOUNT}" "${dst_path}" @/dev/stdin >/dev/null
  done <<< "${leaves}"

  echo "Done. Copied ${count} path(s) to ${MOUNT}/${dst_base}/"
}

cmd_delete() {
  local target_env="${1:-}"
  [[ -n "${target_env}" ]] || usage
  shift || true
  [[ $# -eq 0 ]] || usage

  assert_safe_env_name "${target_env}" "delete target"

  if [[ "${CONFIRM_DELETE:-}" != "true" ]]; then
    echo "ERROR: refusing delete without CONFIRM_DELETE=true" >&2
    echo "  CONFIRM_DELETE=true $0 ${CLUSTER_ENV} delete ${target_env}" >&2
    exit 1
  fi

  local base="${PREFIX}/${target_env}"
  assert_not_protected_path "${base}"

  echo "==> Listing secrets under ${MOUNT}/${base}/"
  local leaves
  leaves="$(collect_leaves "${base}" || true)"
  if [[ -z "${leaves}" ]]; then
    echo "Nothing to delete (path empty or missing): ${MOUNT}/${base}/"
    exit 0
  fi

  local count
  count="$(printf '%s\n' "${leaves}" | grep -c . || true)"
  echo "    deleting ${count} secret path(s) under ${MOUNT}/${base}/"

  local rel path
  while IFS= read -r rel; do
    [[ -z "${rel}" ]] && continue
    path="${base}/${rel}"
    assert_not_protected_path "${path}"
    echo "    metadata delete ${path}"
    # Removes all versions + metadata for this path
    vault_exec kv metadata delete -mount="${MOUNT}" "${path}" >/dev/null
  done <<< "${leaves}"

  echo "Done. Deleted ${count} path(s) under ${MOUNT}/${base}/"
}

# --- argv ---
require_cmd kubectl
require_cmd jq

CLUSTER_ENV="dev"
COMMAND=""

if [[ $# -lt 1 ]]; then
  usage
fi

case "$1" in
  copy|delete|-h|--help)
    COMMAND="$1"
    shift
    ;;
  *)
    CLUSTER_ENV="$1"
    shift
    [[ $# -ge 1 ]] || usage
    COMMAND="$1"
    shift
    ;;
esac

[[ "${COMMAND}" != "-h" && "${COMMAND}" != "--help" ]] || usage

KUBECONFIG_PATH="${KUBECONFIG:-${REPO_ROOT}/kubeconfigs/${CLUSTER_ENV}.yaml}"
[[ -f "${KUBECONFIG_PATH}" ]] || {
  echo "ERROR: Kubeconfig not found: ${KUBECONFIG_PATH}" >&2
  exit 1
}
export KUBECONFIG="${KUBECONFIG_PATH}"

load_vault_token

echo "==> cluster-env=${CLUSTER_ENV} vault=${VAULT_NS}/${VAULT_POD}"

case "${COMMAND}" in
  copy) cmd_copy "$@" ;;
  delete) cmd_delete "$@" ;;
  *) usage ;;
esac
