#!/usr/bin/env bash
# Uninstall Linkerd Viz (Helm release + namespace). Does NOT remove the control plane.
#
# Usage:
#   CONFIRM_UNINSTALL=true ./ansible/scripts/uninstall-linkerd-viz.sh <env>
#
# Environment:
#   CONFIRM_UNINSTALL=true   Required
#   REMOVE_CLI=true          Also delete ~/.linkerd2 (optional)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${ANSIBLE_DIR}/.." && pwd)"

LINKERD_VIZ_NS="${LINKERD_VIZ_NS:-linkerd-viz}"

usage() {
  cat <<EOF
Usage: CONFIRM_UNINSTALL=true $(basename "$0") <env>

Removes:
  - Helm release linkerd-viz
  - Namespace ${LINKERD_VIZ_NS}

Leaves untouched:
  - Linkerd control plane (namespace linkerd)
  - App mesh inject / proxy sidecars
  - CLI at ~/.linkerd2 (unless REMOVE_CLI=true)

Example:
  CONFIRM_UNINSTALL=true $(basename "$0") dev
EOF
  exit 1
}

[[ $# -eq 1 ]] || usage
ENV="$1"

if [[ "${CONFIRM_UNINSTALL:-}" != "true" ]]; then
  echo "Refusing uninstall without CONFIRM_UNINSTALL=true" >&2
  echo "  CONFIRM_UNINSTALL=true $0 ${ENV}" >&2
  exit 1
fi

KUBECONFIG_PATH="${KUBECONFIG:-${REPO_ROOT}/kubeconfigs/${ENV}.yaml}"
[[ -f "${KUBECONFIG_PATH}" ]] || { echo "ERROR: Kubeconfig not found: ${KUBECONFIG_PATH}" >&2; exit 1; }
export KUBECONFIG="${KUBECONFIG_PATH}"

command -v helm >/dev/null 2>&1 || { echo "ERROR: helm not found." >&2; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "ERROR: kubectl not found." >&2; exit 1; }

echo "==> Uninstalling linkerd-viz (env=${ENV})"
if helm status linkerd-viz -n "${LINKERD_VIZ_NS}" >/dev/null 2>&1; then
  helm uninstall linkerd-viz -n "${LINKERD_VIZ_NS}" --wait
else
  echo "    Helm release linkerd-viz not found; continuing"
fi

kubectl delete namespace "${LINKERD_VIZ_NS}" --wait=true --ignore-not-found

if [[ "${REMOVE_CLI:-}" == "true" ]]; then
  echo "==> Removing local CLI ~/.linkerd2"
  rm -rf "${HOME}/.linkerd2"
fi

echo ""
echo "Linkerd Viz removed. Control plane in namespace linkerd is unchanged."
