#!/usr/bin/env bash
# Install or uninstall Argo Rollouts controller (Helm: argo/argo-rollouts).
#
# Usage:
#   ./ansible/scripts/configure-argo-rollouts.sh <env> install
#   CONFIRM_UNINSTALL=true ./ansible/scripts/configure-argo-rollouts.sh <env> uninstall
#
# Environment (install):
#   ARGO_ROLLOUTS_PREFER_WORKERS   Soft-prefer workers (default: true)
#   ARGO_ROLLOUTS_DASHBOARD        Enable dashboard (default: false)
#   ARGO_ROLLOUTS_CHART_VERSION    Pin Helm chart version (optional)
#
# Environment (uninstall):
#   CONFIRM_UNINSTALL=true         Required
#   CONFIRM_DELETE_CRDS=true       Also delete Rollouts CRDs (optional; default leaves CRDs)
#
# Does NOT install/modify Argo CD. App Rollout CRs live in GitOps.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${ANSIBLE_DIR}/.." && pwd)"

usage() {
  cat <<EOF
Usage: $(basename "$0") <env> <install|uninstall>

Installs or removes the Argo Rollouts controller (namespace argo-rollouts).

Examples:
  $(basename "$0") dev install
  CONFIRM_UNINSTALL=true $(basename "$0") dev uninstall
  CONFIRM_UNINSTALL=true CONFIRM_DELETE_CRDS=true $(basename "$0") dev uninstall

Environment (install):
  ARGO_ROLLOUTS_PREFER_WORKERS   default: true
  ARGO_ROLLOUTS_DASHBOARD        default: false
  ARGO_ROLLOUTS_CHART_VERSION    optional chart pin

Environment (uninstall):
  CONFIRM_UNINSTALL=true         required
  CONFIRM_DELETE_CRDS=true       also remove Rollouts CRDs (not Argo CD CRDs)
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

[[ $# -eq 2 ]] || usage
ENV="$1"
ACTION="$2"

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

case "${ACTION}" in
  install)
    echo "==> Installing Argo Rollouts (env=${ENV})"
    ansible-playbook -i "inventories/${ENV}/hosts.yml" playbooks/install-argo-rollouts.yml
    echo ""
    echo "Argo Rollouts controller ready."
    kubectl -n argo-rollouts get pods -o wide 2>/dev/null || true
    echo ""
    echo "GitOps: define Rollout CRs in campaign-gitops; controller watches cluster-wide by default."
    ;;
  uninstall)
    if [[ "${CONFIRM_UNINSTALL:-}" != "true" ]]; then
      echo "Refusing uninstall without CONFIRM_UNINSTALL=true" >&2
      echo "  CONFIRM_UNINSTALL=true $0 ${ENV} uninstall" >&2
      echo "Optional: CONFIRM_DELETE_CRDS=true to also remove Rollouts CRDs" >&2
      exit 1
    fi
    echo "==> Uninstalling Argo Rollouts (env=${ENV}, delete_crds=${CONFIRM_DELETE_CRDS:-false})"
    ansible-playbook -i "inventories/${ENV}/hosts.yml" playbooks/uninstall-argo-rollouts.yml
    echo ""
    echo "Argo Rollouts removed."
    ;;
  *)
    echo "ERROR: unknown action '${ACTION}' (use install|uninstall)" >&2
    usage
    ;;
esac
