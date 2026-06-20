#!/usr/bin/env bash
# Configure K3s built-in Traefik hostPort exposure (dev mode). Does not install Traefik.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${ANSIBLE_DIR}/.." && pwd)"

usage() {
  echo "Usage: $(basename "$0") <env>"
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

echo "==> Configuring Traefik exposure (env=${ENV}, mode=hostport)"
ansible-playbook -i "inventories/${ENV}/hosts.yml" playbooks/install-traefik.yml

echo "==> Verifying Traefik exposure (env=${ENV})"
ansible-playbook -i "inventories/${ENV}/hosts.yml" playbooks/verify-traefik.yml

echo ""
echo "Done. Next: ./ansible/scripts/install-headlamp.sh ${ENV}"
