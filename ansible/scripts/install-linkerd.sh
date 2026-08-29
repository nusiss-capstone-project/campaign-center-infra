#!/usr/bin/env bash
# Install Linkerd control plane (Helm CRDs + control-plane). App inject stays in GitOps.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${ANSIBLE_DIR}/.." && pwd)"

usage() {
  cat <<EOF
Usage: $(basename "$0") <env>

Installs Linkerd into namespace linkerd via Helm (edge charts, pinned versions).
Generates identity certs under ansible/secrets/linkerd.<env>/ if missing.

Environment:
  LINKERD_IDENTITY_DIR     Override identity cert directory
  LINKERD_PREFER_WORKERS   Soft-prefer workers (default: true)

Charts (pinned edge 2026.8.1):
  Prefers local tarballs under /tmp/linkerd-charts/ (downloaded with curl -4
  if missing) to avoid flaky helm.linkerd.io / IPv6 resets from Helm itself.

Does NOT mesh app namespaces. In campaign-gitops, annotate namespaces e.g.:
  kubectl annotate ns campaign-dev linkerd.io/inject=enabled

Do not inject platform namespaces (messaging, vault, kube-system, etc.).
Kafka Service is annotated with opaque-ports for meshed→unmeshed access.

Example:
  $(basename "$0") dev
EOF
  exit 1
}

download_linkerd_charts() {
  local ver="2026.8.1"
  local dir="/tmp/linkerd-charts"
  local base="https://helm.linkerd.io/edge"
  mkdir -p "${dir}"
  local f
  for f in "linkerd-crds-${ver}.tgz" "linkerd-control-plane-${ver}.tgz"; do
    if [[ -s "${dir}/${f}" ]]; then
      echo "==> Using cached chart ${dir}/${f}"
      continue
    fi
    echo "==> Downloading ${f} (curl -4)..."
    curl -4 -fL --proto '=https' --tlsv1.2 --retry 5 --retry-delay 2 -o "${dir}/${f}" "${base}/${f}"
  done
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
require_cmd openssl "Install OpenSSL"
require_cmd curl "Install curl"

[[ -f "${INV_FILE}" ]] || { echo "ERROR: Inventory not found: ${INV_FILE}" >&2; exit 1; }
[[ -f "${KUBECONFIG_PATH}" ]] || { echo "ERROR: Kubeconfig not found: ${KUBECONFIG_PATH}" >&2; exit 1; }

if ! ansible-galaxy collection list 2>/dev/null | grep -q 'kubernetes\.core'; then
  echo "==> Installing Ansible collection kubernetes.core"
  ansible-galaxy collection install -r "${ANSIBLE_DIR}/requirements.yml"
fi

download_linkerd_charts

export KUBECONFIG="${KUBECONFIG_PATH}"
export ENV

cd "${ANSIBLE_DIR}"

echo "==> Installing Linkerd (env=${ENV})"
ansible-playbook -i "inventories/${ENV}/hosts.yml" playbooks/install-linkerd.yml

echo "==> Verifying Linkerd (env=${ENV})"
ansible-playbook -i "inventories/${ENV}/hosts.yml" playbooks/verify-linkerd.yml

echo ""
echo "Linkerd control plane ready."
echo "Next (GitOps): enable inject on app namespaces only, e.g. campaign-dev / campaign-prod."
echo "Docs: docs/linkerd-origin-tls.md"
