#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
  echo "Usage: $(basename "$0") <env>"
  exit 1
}

[[ $# -eq 1 ]] || usage
ENV="$1"

INV="${ANSIBLE_DIR}/inventories/${ENV}/hosts.yml"
if [[ ! -f "${INV}" ]]; then
  "${SCRIPT_DIR}/generate-inventory.sh" "${ENV}"
fi

cd "${ANSIBLE_DIR}"
ansible-playbook -i "inventories/${ENV}/hosts.yml" playbooks/verify-k3s.yml
