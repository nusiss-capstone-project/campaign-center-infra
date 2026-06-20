#!/usr/bin/env bash
# Install Provectus Kafka UI and expose via Traefik at kafka.<base-domain>.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${ANSIBLE_DIR}/.." && pwd)"

usage() {
  echo "Usage: $(basename "$0") <env>"
  echo ""
  echo "Installs Kafka UI (Provectus) into namespace 'messaging' and routes via Traefik."
  echo "Requires Kafka broker (install-kafka.sh) and Traefik (install-traefik.sh)."
  echo ""
  echo "Environment:"
  echo "  KAFKA_UI_HOST  Kafka UI hostname (default: kafka.<master_public_ip>.sslip.io)"
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
require_cmd curl "Install curl: brew install curl"

[[ -f "${INV_FILE}" ]] || { echo "ERROR: Inventory not found: ${INV_FILE}" >&2; exit 1; }
[[ -f "${KUBECONFIG_PATH}" ]] || { echo "ERROR: Kubeconfig not found: ${KUBECONFIG_PATH}" >&2; exit 1; }

if ! ansible-galaxy collection list 2>/dev/null | grep -q 'kubernetes\.core'; then
  echo "==> Installing Ansible collection kubernetes.core"
  ansible-galaxy collection install -r "${ANSIBLE_DIR}/requirements.yml"
fi

export KUBECONFIG="${KUBECONFIG_PATH}"
cd "${ANSIBLE_DIR}"

echo "==> Installing Kafka UI (env=${ENV})"
ansible-playbook -i "inventories/${ENV}/hosts.yml" playbooks/install-kafka-ui.yml

echo "==> Verifying Kafka UI (env=${ENV})"
ansible-playbook -i "inventories/${ENV}/hosts.yml" playbooks/verify-kafka-ui.yml

echo ""
echo "Done. Open Kafka UI:"
echo "  http://kafka.<master_public_ip>.sslip.io  (or your KAFKA_UI_HOST)"
echo "  export KUBECONFIG=${KUBECONFIG_PATH}"
