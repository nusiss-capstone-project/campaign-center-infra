#!/usr/bin/env bash
# Expose Vault UI via Traefik Ingress (HTTPS + access control required).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${ANSIBLE_DIR}/.." && pwd)"

usage() {
  echo "Usage: $(basename "$0") <env>"
  echo ""
  echo "Creates Traefik Ingress for Vault UI in namespace vault."
  echo "Requires HTTPS (cert-manager ClusterIssuer or pre-created TLS secret) and access control."
  echo ""
  echo "Environment:"
  echo "  VAULT_INGRESS_HOST                  Hostname (default: vault.dev.example.com)"
  echo "  VAULT_INGRESS_BASIC_AUTH_PASSWORD   Required for basicauth (default auth mode)"
  echo "  VAULT_INGRESS_CLUSTER_ISSUER        cert-manager ClusterIssuer name (if installed)"
  echo "  VAULT_INGRESS_TLS_SECRET            TLS secret name (default: vault-ingress-tls)"
  echo "  VAULT_INGRESS_AUTH_MODE             basicauth | ipallowlist | both (default: basicauth)"
  echo "  VAULT_INGRESS_IP_ALLOWLIST          Comma-separated CIDRs (for ipallowlist/both)"
  echo ""
  echo "Examples:"
  echo "  # cert-manager + BasicAuth"
  echo "  VAULT_INGRESS_BASIC_AUTH_PASSWORD='changeme' \\"
  echo "  VAULT_INGRESS_CLUSTER_ISSUER=letsencrypt-prod \\"
  echo "  $(basename "$0") dev"
  echo ""
  echo "  # Manual TLS secret (no cert-manager)"
  echo "  kubectl create secret tls vault-ingress-tls -n vault --cert=tls.crt --key=tls.key"
  echo "  VAULT_INGRESS_BASIC_AUTH_PASSWORD='changeme' $(basename "$0") dev"
  exit 1
}

[[ $# -eq 1 ]] || usage
ENV="$1"

KUBECONFIG_PATH="${REPO_ROOT}/kubeconfigs/${ENV}.yaml"
[[ -f "${KUBECONFIG_PATH}" ]] || { echo "ERROR: Kubeconfig not found: ${KUBECONFIG_PATH}" >&2; exit 1; }

if [[ -z "${VAULT_INGRESS_BASIC_AUTH_PASSWORD:-}" && "${VAULT_INGRESS_AUTH_MODE:-basicauth}" =~ ^(basicauth|both)$ ]]; then
  echo "ERROR: VAULT_INGRESS_BASIC_AUTH_PASSWORD is not set for the script process." >&2
  echo "" >&2
  echo "If you assigned it in a previous shell line, you must export it:" >&2
  echo "  export VAULT_INGRESS_BASIC_AUTH_PASSWORD='your-password'" >&2
  echo "" >&2
  echo "Or pass it inline on the same line as the script:" >&2
  echo "  VAULT_INGRESS_BASIC_AUTH_PASSWORD='your-password' $(basename "$0") ${ENV}" >&2
  exit 1
fi

export KUBECONFIG="${KUBECONFIG_PATH}"
cd "${ANSIBLE_DIR}"

ansible-playbook -i "inventories/${ENV}/hosts.yml" playbooks/configure-vault-ingress.yml

echo ""
echo "Vault UI: https://${VAULT_INGRESS_HOST:-vault.dev.example.com}/ui"
echo "Ensure DNS points to your Traefik public IP and TLS certificate is Ready."
