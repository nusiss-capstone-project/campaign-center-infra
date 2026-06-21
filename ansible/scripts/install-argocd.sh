#!/usr/bin/env bash
# Install Argo CD via Helm and bootstrap campaign-gitops-root (app-of-apps).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${ANSIBLE_DIR}/.." && pwd)"

usage() {
  echo "Usage: $(basename "$0") <env>"
  echo ""
  echo "Installs Argo CD into namespace argocd and bootstraps the root Application."
  echo ""
  echo "Environment:"
  echo "  ARGOCD_HOST            Hostname (default: argocd.<master_public_ip>.sslip.io)"
  echo "  ARGOCD_CLUSTER_ISSUER  cert-manager ClusterIssuer (optional)"
  echo ""
  echo "Prerequisites: K3s, Traefik (install-traefik.sh)"
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

echo "==> Installing Argo CD (env=${ENV})"
ansible-playbook -i "inventories/${ENV}/hosts.yml" playbooks/install-argocd.yml

echo "==> Verifying Argo CD (env=${ENV})"
ansible-playbook -i "inventories/${ENV}/hosts.yml" playbooks/verify-argocd.yml

echo ""
echo "Done. Argo CD UI: https://argocd.<master_public_ip>.sslip.io (or your ARGOCD_HOST)"
echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo "  export KUBECONFIG=${KUBECONFIG_PATH}"
