#!/usr/bin/env bash
# Generate Ansible inventory from Terraform outputs for a given environment.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${ANSIBLE_DIR}/.." && pwd)"

usage() {
  echo "Usage: $(basename "$0") <env>"
  echo "Example: $(basename "$0") dev"
  exit 1
}

[[ $# -eq 1 ]] || usage
ENV="$1"

TF_DIR="${REPO_ROOT}/terraform/environments/${ENV}"
INV_DIR="${ANSIBLE_DIR}/inventories/${ENV}"
INV_FILE="${INV_DIR}/hosts.yml"

if [[ ! -d "${TF_DIR}" ]]; then
  echo "ERROR: Terraform environment not found: ${TF_DIR}" >&2
  exit 1
fi

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required." >&2; exit 1; }
command -v terraform >/dev/null 2>&1 || { echo "ERROR: terraform is required." >&2; exit 1; }

echo "==> Reading Terraform outputs from ${TF_DIR}"
TF_ERR="$(mktemp)"
TF_JSON="$(terraform -chdir="${TF_DIR}" output -json 2>"${TF_ERR}")" || {
  echo "ERROR: Failed to read terraform outputs. Run 'terraform apply' in ${TF_DIR} first." >&2
  cat "${TF_ERR}" >&2
  rm -f "${TF_ERR}"
  exit 1
}
if [[ -s "${TF_ERR}" ]]; then
  echo "==> terraform warnings:" >&2
  cat "${TF_ERR}" >&2
fi
rm -f "${TF_ERR}"

if ! echo "${TF_JSON}" | jq empty 2>/dev/null; then
  echo "ERROR: terraform output -json did not return valid JSON:" >&2
  echo "${TF_JSON}" >&2
  exit 1
fi

# Single jq pass: read actual terraform output keys (k3s_* first), normalize to string arrays.
EXTRACTED="$(echo "${TF_JSON}" | jq -c '
  def out($root; $k): ($root[$k].value // null);
  def as_array:
    if . == null or . == "" then []
    elif type == "array" then [.[] | select(. != null and . != "")]
    elif type == "string" then [.] else [] end;
  def first_array($root; $keys):
    reduce $keys[] as $k ([]; if length == 0 then (out($root; $k) | as_array) else . end);
  def ssh_public_ip($root):
    (out($root; "ssh_command") // "") |
    if test("root@[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+")
    then [capture("root@(?<ip>[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+)").ip]
    else [] end;
  def worker_priv_from_map($root):
    (out($root; "k3s_node_private_ips") // out($root; "instance_private_ips") // {}) |
    if type == "object" then
      [to_entries[] | select(.key | startswith("worker-")) | .value | select(. != null and . != "")]
    else [] end;

  . as $root |
  (first_array($root; [
    "k3s_master_public_ips", "master_public_ips",
    "k3s_master_public_ip",  "master_public_ip"
  ])) as $pub |
  (if ($pub | length) > 0 then $pub else ssh_public_ip($root) end) as $master_pub |
  (first_array($root; [
    "k3s_master_private_ips", "master_private_ips",
    "k3s_master_private_ip",  "master_private_ip"
  ])) as $master_priv |
  (first_array($root; [
    "k3s_worker_public_ips", "worker_public_ips",
    "k3s_worker_public_ip",  "worker_public_ip"
  ])) as $worker_pub |
  (first_array($root; [
    "k3s_worker_private_ips", "worker_private_ips",
    "k3s_worker_private_ip",  "worker_private_ip"
  ])) as $worker_priv |
  (if ($worker_priv | length) > 0 then $worker_priv else worker_priv_from_map($root) end) as $worker_priv_final |
  {
    master_public_ips: $master_pub,
    master_private_ips: $master_priv,
    worker_public_ips: $worker_pub,
    worker_private_ips: $worker_priv_final
  }
')"

MASTER_PUBLIC_IPS="$(echo "${EXTRACTED}" | jq -c '.master_public_ips')"
MASTER_PRIVATE_IPS="$(echo "${EXTRACTED}" | jq -c '.master_private_ips')"
WORKER_PUBLIC_IPS="$(echo "${EXTRACTED}" | jq -c '.worker_public_ips')"
WORKER_PRIVATE_IPS="$(echo "${EXTRACTED}" | jq -c '.worker_private_ips')"

MASTER_PUBLIC_COUNT="$(echo "${MASTER_PUBLIC_IPS}" | jq 'length')"
MASTER_PRIVATE_COUNT="$(echo "${MASTER_PRIVATE_IPS}" | jq 'length')"
WORKER_PRIVATE_COUNT="$(echo "${WORKER_PRIVATE_IPS}" | jq 'length')"

if [[ "${MASTER_PRIVATE_COUNT}" -eq 0 ]]; then
  echo "ERROR: No master private IPs found in Terraform outputs." >&2
  echo "       Expected: k3s_master_private_ips (or master_private_ips)" >&2
  echo "       Raw k3s_master_private_ips=$(echo "${TF_JSON}" | jq -c '.k3s_master_private_ips.value // "missing"')" >&2
  echo "       Available outputs:" >&2
  echo "${TF_JSON}" | jq -r 'keys[]' | sed 's/^/         - /' >&2
  exit 1
fi

if [[ "${MASTER_PUBLIC_COUNT}" -eq 0 ]]; then
  echo "ERROR: No master public IP found in Terraform outputs." >&2
  echo "       Expected: k3s_master_public_ip (or master_public_ips / ssh_command)" >&2
  echo "       Raw k3s_master_public_ip=$(echo "${TF_JSON}" | jq -c '.k3s_master_public_ip.value // "missing"')" >&2
  echo "       create_eip=$(echo "${TF_JSON}" | jq -r '.create_eip.value // "unknown"')" >&2
  exit 1
fi

resolve_ssh_key() {
  if [[ -n "${SSH_PRIVATE_KEY:-}" ]]; then
    echo "${SSH_PRIVATE_KEY}"
    return
  fi
  local candidates=(
    "${HOME}/.ssh/campaign-center-key.pem"
    "${HOME}/.ssh/campaign-center-key"
    "${HOME}/.ssh/id_rsa"
  )
  local path
  for path in "${candidates[@]}"; do
    if [[ -f "${path}" ]]; then
      echo "${path}"
      return
    fi
  done
  echo "${HOME}/.ssh/campaign-center-key.pem"
}

SSH_KEY="$(resolve_ssh_key)"
if [[ ! -f "${SSH_KEY}" ]]; then
  echo "ERROR: SSH private key not found: ${SSH_KEY}" >&2
  echo "       Export the key path used with ECS key pair, e.g.:" >&2
  echo "       export SSH_PRIVATE_KEY=~/.ssh/campaign-center-key.pem" >&2
  exit 1
fi
echo "==> Using SSH key: ${SSH_KEY}"
K3S_VERSION="${K3S_VERSION:-v1.30.5+k3s1}"
FIRST_MASTER_PRIVATE="$(echo "${MASTER_PRIVATE_IPS}" | jq -r '.[0]')"

pad2() { printf '%02d' "$1"; }

mkdir -p "${INV_DIR}"

{
  cat <<EOF
# GENERATED FILE — do not edit manually.
# Regenerate: ansible/scripts/generate-inventory.sh ${ENV}
all:
  vars:
    ansible_user: root
    ansible_ssh_private_key_file: ${SSH_KEY}
    k3s_version: "${K3S_VERSION}"
    k3s_api_port: 6443
    k3s_token_file: /var/lib/rancher/k3s/server/node-token
    k3s_first_server_private_ip: ${FIRST_MASTER_PRIVATE}
    k3s_env: ${ENV}
  children:
    k3s_servers:
      hosts:
EOF

  for ((i = 0; i < MASTER_PRIVATE_COUNT; i++)); do
    idx="$(pad2 $((i + 1)))"
    priv="$(echo "${MASTER_PRIVATE_IPS}" | jq -r ".[${i}]")"
    if [[ "${i}" -lt "${MASTER_PUBLIC_COUNT}" ]]; then
      pub="$(echo "${MASTER_PUBLIC_IPS}" | jq -r ".[${i}]")"
    else
      pub="${priv}"
      echo "# WARNING: master-${idx} has no public IP; using private IP for ansible_host" >&2
    fi
    cat <<EOF
        master-${idx}:
          ansible_host: ${pub}
          private_ip: ${priv}
          node_role: server
EOF
  done

  cat <<EOF
    k3s_agents:
      hosts:
EOF

  if [[ "${WORKER_PRIVATE_COUNT}" -gt 0 ]]; then
    for ((i = 0; i < WORKER_PRIVATE_COUNT; i++)); do
      idx="$(pad2 $((i + 1)))"
      priv="$(echo "${WORKER_PRIVATE_IPS}" | jq -r ".[${i}]")"
      worker_pub_count="$(echo "${WORKER_PUBLIC_IPS}" | jq 'length')"
      if [[ "${i}" -lt "${worker_pub_count}" ]]; then
        pub="$(echo "${WORKER_PUBLIC_IPS}" | jq -r ".[${i}]")"
        [[ -z "${pub}" || "${pub}" == "null" ]] && pub="${priv}"
      else
        pub="${priv}"
        echo "# NOTE: worker-${idx} has no public IP; using private IP" >&2
      fi
      cat <<EOF
        worker-${idx}:
          ansible_host: ${pub}
          private_ip: ${priv}
          node_role: agent
EOF
    done
  fi
} > "${INV_FILE}"

echo "==> Wrote ${INV_FILE}"
echo "    Masters: ${MASTER_PRIVATE_COUNT}, Workers: ${WORKER_PRIVATE_COUNT}"
echo "    Master public IP(s): $(echo "${MASTER_PUBLIC_IPS}" | jq -r 'join(", ")')"
