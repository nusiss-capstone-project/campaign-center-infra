#!/usr/bin/env bash
# DESTRUCTIVE: uninstall K3s from all nodes in the environment inventory.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
  echo "Usage: CONFIRM_RESET=true $(basename "$0") <env>"
  echo ""
  echo "This will uninstall K3s from all servers and agents. Data will be lost."
  exit 1
}

[[ $# -eq 1 ]] || usage
ENV="$1"

if [[ "${CONFIRM_RESET:-}" != "true" ]]; then
  echo "ERROR: Destructive reset aborted." >&2
  echo "Set CONFIRM_RESET=true to proceed." >&2
  usage
fi

command -v ansible-playbook >/dev/null 2>&1 || {
  echo "ERROR: ansible-playbook not found." >&2
  exit 1
}

INV="${ANSIBLE_DIR}/inventories/${ENV}/hosts.yml"
if [[ ! -f "${INV}" ]]; then
  "${SCRIPT_DIR}/generate-inventory.sh" "${ENV}"
fi

cd "${ANSIBLE_DIR}"
ansible-playbook -i "inventories/${ENV}/hosts.yml" playbooks/reset-k3s.yml

echo "==> K3s reset complete for env=${ENV}"
