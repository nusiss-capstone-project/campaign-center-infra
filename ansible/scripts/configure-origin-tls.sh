#!/usr/bin/env bash
# Apply Cloudflare Origin CA TLS secret(s) for Traefik HTTPS termination.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${ANSIBLE_DIR}/.." && pwd)"

usage() {
  cat <<EOF
Usage: $(basename "$0") <env>

Applies a kubernetes.io/tls Secret from ansible/secrets/origin-tls.<env>/{tls.crt,tls.key}
into target namespaces (default: headlamp).

Environment:
  ORIGIN_TLS_DIR           Override cert directory (default: ansible/secrets/origin-tls.<env>)
  ORIGIN_TLS_SECRET_NAME   Secret name (default: campaignhub-origin-tls)
  ORIGIN_TLS_NAMESPACES    Comma-separated namespaces (default: headlamp)

Prerequisites:
  1. Create a Cloudflare Origin CA cert for *.campaignhub.best (or specific hosts)
  2. Save PEM files as tls.crt / tls.key under the secrets directory
  3. Cloudflare SSL/TLS mode: Full (strict); DNS A/CNAME → master EIP (proxied)

Example:
  mkdir -p ansible/secrets/origin-tls.dev
  # copy Origin CA files to tls.crt and tls.key
  $(basename "$0") dev

  HEADLAMP_HOST=headlamp.campaignhub.best HEADLAMP_TLS=true \\
    ./ansible/scripts/install-headlamp.sh dev
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

[[ $# -eq 1 ]] || usage
ENV="$1"

INV_FILE="${ANSIBLE_DIR}/inventories/${ENV}/hosts.yml"
KUBECONFIG_PATH="${REPO_ROOT}/kubeconfigs/${ENV}.yaml"
DEFAULT_CERT_DIR="${ANSIBLE_DIR}/secrets/origin-tls.${ENV}"

require_cmd ansible-playbook "Install Ansible: brew install ansible"
require_cmd kubectl "Install kubectl: brew install kubectl"

[[ -f "${INV_FILE}" ]] || { echo "ERROR: Inventory not found: ${INV_FILE}" >&2; exit 1; }
[[ -f "${KUBECONFIG_PATH}" ]] || { echo "ERROR: Kubeconfig not found: ${KUBECONFIG_PATH}" >&2; exit 1; }

CERT_DIR="${ORIGIN_TLS_DIR:-${DEFAULT_CERT_DIR}}"
if [[ ! -f "${CERT_DIR}/tls.crt" || ! -f "${CERT_DIR}/tls.key" ]]; then
  echo "ERROR: Missing ${CERT_DIR}/tls.crt or tls.key" >&2
  echo "See docs/linkerd-origin-tls.md" >&2
  exit 1
fi

if ! ansible-galaxy collection list 2>/dev/null | grep -q 'kubernetes\.core'; then
  echo "==> Installing Ansible collection kubernetes.core"
  ansible-galaxy collection install -r "${ANSIBLE_DIR}/requirements.yml"
fi

export KUBECONFIG="${KUBECONFIG_PATH}"
export ENV
export ORIGIN_TLS_DIR="${CERT_DIR}"

cd "${ANSIBLE_DIR}"

echo "==> Applying origin TLS secrets (env=${ENV}, dir=${CERT_DIR})"
ansible-playbook -i "inventories/${ENV}/hosts.yml" playbooks/configure-origin-tls.yml

echo ""
echo "Origin TLS secret applied. Reconfigure Headlamp HTTPS if needed:"
echo "  HEADLAMP_HOST=headlamp.campaignhub.best HEADLAMP_TLS=true ./ansible/scripts/install-headlamp.sh ${ENV}"
