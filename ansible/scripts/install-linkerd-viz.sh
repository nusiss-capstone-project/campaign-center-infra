#!/usr/bin/env bash
# Install Linkerd CLI (local laptop) + Linkerd Viz (in-cluster Helm).
#
# CLI does NOT need to run on the k3s server. Install it on your workstation.
# Viz pods are scheduled with soft-prefer workers (same pattern as control plane).
#
# Prerequisites: control plane already installed (./ansible/scripts/install-linkerd.sh).
#
# Usage:
#   ./ansible/scripts/install-linkerd-viz.sh <env>
#
# Environment:
#   LINKERD_CLI_VERSION     CLI tag (default: edge-26.8.1, matches chart 2026.8.1)
#   LINKERD_VIZ_CHART_VER   Helm chart version (default: 2026.8.1)
#   SKIP_CLI=true           Only install viz Helm release
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${ANSIBLE_DIR}/.." && pwd)"

LINKERD_CLI_VERSION="${LINKERD_CLI_VERSION:-edge-26.8.1}"
LINKERD_VIZ_CHART_VER="${LINKERD_VIZ_CHART_VER:-2026.8.1}"
LINKERD_VIZ_NS="${LINKERD_VIZ_NS:-linkerd-viz}"
LINKERD_NS="${LINKERD_NS:-linkerd}"
CHART_DIR="/tmp/linkerd-charts"
VALUES_FILE="${ANSIBLE_DIR}/roles/linkerd-viz/templates/values.yaml"

usage() {
  cat <<EOF
Usage: $(basename "$0") <env>

Installs:
  1) linkerd CLI on this machine (~/.linkerd2/bin)
  2) linkerd-viz Helm release in namespace ${LINKERD_VIZ_NS}

Does not install/replace the control plane. Viz is NOT required to run on the
k3s server node — pods soft-prefer workers.

Example:
  $(basename "$0") dev
  SKIP_CLI=true $(basename "$0") dev
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

install_cli() {
  local dest="${HOME}/.linkerd2/bin"
  mkdir -p "${dest}"
  if [[ -x "${dest}/linkerd" ]] && "${dest}/linkerd" version --client --short 2>/dev/null | grep -q "${LINKERD_CLI_VERSION}"; then
    echo "==> CLI already ${LINKERD_CLI_VERSION} at ${dest}/linkerd"
    return 0
  fi

  local os arch asset
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  case "$(uname -m)" in
    x86_64|amd64) arch="amd64" ;;
    arm64|aarch64) arch="arm64" ;;
    *)
      echo "ERROR: unsupported arch $(uname -m)" >&2
      exit 1
      ;;
  esac
  case "${os}" in
    darwin) asset="linkerd2-cli-${LINKERD_CLI_VERSION}-darwin-${arch}" ;;
    linux) asset="linkerd2-cli-${LINKERD_CLI_VERSION}-linux-${arch}" ;;
    *)
      echo "ERROR: unsupported OS ${os}" >&2
      exit 1
      ;;
  esac

  local url="https://github.com/linkerd/linkerd2/releases/download/${LINKERD_CLI_VERSION}/${asset}"
  echo "==> Downloading Linkerd CLI ${LINKERD_CLI_VERSION}"
  curl -4 -fL --retry 5 --retry-delay 2 -o "${dest}/linkerd" "${url}"
  chmod +x "${dest}/linkerd"
  echo "==> Installed ${dest}/linkerd"
  echo "    Add to PATH: export PATH=${dest}:\$PATH"
}

download_viz_chart() {
  mkdir -p "${CHART_DIR}"
  local f="linkerd-viz-${LINKERD_VIZ_CHART_VER}.tgz"
  if [[ -s "${CHART_DIR}/${f}" ]]; then
    echo "==> Using cached chart ${CHART_DIR}/${f}"
    return 0
  fi
  echo "==> Downloading ${f} (curl -4)..."
  curl -4 -fL --retry 5 --retry-delay 2 \
    -o "${CHART_DIR}/${f}" \
    "https://helm.linkerd.io/edge/${f}"
}

[[ $# -eq 1 ]] || usage
ENV="$1"

KUBECONFIG_PATH="${KUBECONFIG:-${REPO_ROOT}/kubeconfigs/${ENV}.yaml}"
require_cmd kubectl "Install kubectl: brew install kubectl"
require_cmd helm "Install Helm: brew install helm"
require_cmd curl "Install curl"
[[ -f "${KUBECONFIG_PATH}" ]] || { echo "ERROR: Kubeconfig not found: ${KUBECONFIG_PATH}" >&2; exit 1; }
[[ -f "${VALUES_FILE}" ]] || { echo "ERROR: values file not found: ${VALUES_FILE}" >&2; exit 1; }
export KUBECONFIG="${KUBECONFIG_PATH}"

if [[ "${SKIP_CLI:-}" != "true" ]]; then
  install_cli
fi

echo "==> Checking Linkerd control plane in ${LINKERD_NS}"
kubectl -n "${LINKERD_NS}" get deploy linkerd-destination >/dev/null

download_viz_chart

echo "==> Installing linkerd-viz (chart ${LINKERD_VIZ_CHART_VER}, ns=${LINKERD_VIZ_NS})"
helm upgrade --install linkerd-viz \
  "${CHART_DIR}/linkerd-viz-${LINKERD_VIZ_CHART_VER}.tgz" \
  --namespace "${LINKERD_VIZ_NS}" \
  --create-namespace \
  --values "${VALUES_FILE}" \
  --wait=false

echo "==> Waiting for viz Deployments"
sleep 5
kubectl -n "${LINKERD_VIZ_NS}" get deploy -o name | while read -r obj; do
  kubectl -n "${LINKERD_VIZ_NS}" rollout status "${obj}" --timeout=300s
done

echo ""
echo "Linkerd Viz ready (pods soft-prefer workers)."
kubectl -n "${LINKERD_VIZ_NS}" get pods -o wide
echo ""
echo "CLI (local): ~/.linkerd2/bin/linkerd"
echo "Dashboard:   ~/.linkerd2/bin/linkerd viz dashboard"
echo "Check:       ~/.linkerd2/bin/linkerd viz check"
echo ""
echo "Uninstall: CONFIRM_UNINSTALL=true ./ansible/scripts/uninstall-linkerd-viz.sh ${ENV}"
