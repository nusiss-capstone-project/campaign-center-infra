#!/usr/bin/env bash
# Install Headlamp UI and expose it via K3s Traefik. Removes legacy Rancher if present.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${ANSIBLE_DIR}/.." && pwd)"

usage() {
  echo "Usage: $(basename "$0") <env>"
  echo ""
  echo "Environment variables:"
  echo "  HEADLAMP_HOST  Headlamp hostname (default: headlamp.<master_public_ip>.sslip.io)"
  echo ""
  echo "Prerequisites: K3s installed, Traefik configured (install-traefik.sh)"
  echo ""
  echo "Example: $(basename "$0") dev"
  exit 1
}

require_cmd() {
  local cmd="$1"
  local install_hint="$2"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "ERROR: '${cmd}' not found." >&2
    echo "${install_hint}" >&2
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

if [[ ! -f "${INV_FILE}" ]]; then
  echo "ERROR: Inventory not found: ${INV_FILE}" >&2
  exit 1
fi

if [[ ! -f "${KUBECONFIG_PATH}" ]]; then
  echo "ERROR: Kubeconfig not found: ${KUBECONFIG_PATH}" >&2
  exit 1
fi

if ! ansible-galaxy collection list 2>/dev/null | grep -q 'kubernetes\.core'; then
  echo "==> Installing Ansible collection kubernetes.core"
  ansible-galaxy collection install -r "${ANSIBLE_DIR}/requirements.yml"
fi

export KUBECONFIG="${KUBECONFIG_PATH}"

cd "${ANSIBLE_DIR}"

echo "==> Installing Headlamp (env=${ENV})"
ansible-playbook -i "inventories/${ENV}/hosts.yml" playbooks/install-headlamp.yml

echo "==> Verifying Headlamp (env=${ENV})"
ansible-playbook -i "inventories/${ENV}/hosts.yml" playbooks/verify-headlamp.yml

echo ""
echo "Done. Open Headlamp and log in with a service account token:"
echo "  kubectl -n headlamp create token headlamp-dev"
echo "  export KUBECONFIG=${KUBECONFIG_PATH}"
