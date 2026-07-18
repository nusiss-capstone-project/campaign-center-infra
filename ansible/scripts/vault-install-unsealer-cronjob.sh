#!/usr/bin/env bash
# Deploy a Kubernetes CronJob that auto-unseals Vault after pod restarts.
#
# DEV ONLY — stores the unseal key in a Kubernetes Secret. Do not use in production.
# Prefer AliCloud KMS auto-unseal for staging/prod (see README-Vault.md).
#
# Usage on ECS (k3s master):
#   export VAULT_UNSEAL_KEY='your-base64-unseal-key'
#   ./vault-install-unsealer-cronjob.sh install
#
# Or from laptop (with kubeconfig):
#   export KUBECONFIG=$(pwd)/kubeconfigs/dev.yaml
#   ./vault-install-unsealer-cronjob.sh install --key-file vault-keys/dev/unseal.key
#
# Commands: install | uninstall | status | run-now
set -euo pipefail

CRONJOB_NAME="vault-unsealer"
SECRET_NAME="vault-unseal-key"
SA_NAME="vault-unsealer"
VAULT_NS="${VAULT_NAMESPACE:-vault}"
VAULT_ADDR="${VAULT_ADDR:-http://vault.vault.svc.cluster.local:8200}"
VAULT_IMAGE="${VAULT_UNSEALER_IMAGE:-hashicorp/vault:1.17.6}"
CRON_SCHEDULE="${VAULT_UNSEALER_SCHEDULE:-*/2 * * * *}"

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [options]

Commands:
  install     Create Secret + CronJob (auto-unseal every 2 minutes)
  uninstall   Remove CronJob, Secret, ServiceAccount
  status      Show CronJob / recent jobs / Vault seal state
  run-now     Trigger a one-off unseal job immediately

Options (install):
  --key-file PATH   Read unseal key from file (default: vault-keys/dev/unseal.key if present)
  --namespace NS    Vault namespace (default: vault)

Environment:
  VAULT_UNSEAL_KEY          Unseal key (alternative to --key-file)
  VAULT_NAMESPACE           Target namespace (default: vault)
  VAULT_UNSEALER_SCHEDULE   Cron schedule (default: */2 * * * *)
  VAULT_UNSEALER_IMAGE      Vault CLI image (default: hashicorp/vault:1.17.6)
  KUBECONFIG                Used when not on k3s node

Examples (ECS):
  export VAULT_UNSEAL_KEY="\$(cat /root/vault-unseal.key)"
  ./vault-install-unsealer-cronjob.sh install

  ./vault-install-unsealer-cronjob.sh status
  ./vault-install-unsealer-cronjob.sh run-now

Examples (laptop):
  export KUBECONFIG=\$(pwd)/kubeconfigs/dev.yaml
  ./vault-install-unsealer-cronjob.sh install --key-file vault-keys/dev/unseal.key
EOF
  exit 1
}

kubectl_cmd() {
  if command -v k3s >/dev/null 2>&1 && k3s kubectl version --client >/dev/null 2>&1; then
    k3s kubectl "$@"
  else
    command kubectl "$@"
  fi
}

require_kubectl() {
  if ! kubectl_cmd version --client >/dev/null 2>&1; then
    echo "ERROR: kubectl not available (install k3s or set KUBECONFIG)." >&2
    exit 1
  fi
}

read_unseal_key() {
  local key_file="${1:-}"

  if [[ -n "${key_file}" ]]; then
    [[ -f "${key_file}" ]] || { echo "ERROR: Key file not found: ${key_file}" >&2; exit 1; }
    tr -d '\n' < "${key_file}"
    return
  fi

  if [[ -n "${VAULT_UNSEAL_KEY:-}" ]]; then
    printf '%s' "${VAULT_UNSEAL_KEY}"
    return
  fi

  echo "ERROR: Provide unseal key via VAULT_UNSEAL_KEY or --key-file." >&2
  exit 1
}

cmd_install() {
  local key_file=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --key-file) key_file="$2"; shift 2 ;;
      --namespace) VAULT_NS="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; usage ;;
    esac
  done

  require_kubectl

  local unseal_key
  unseal_key="$(read_unseal_key "${key_file}")"
  [[ -n "${unseal_key}" ]] || { echo "ERROR: Unseal key is empty." >&2; exit 1; }

  kubectl_cmd get namespace "${VAULT_NS}" >/dev/null 2>&1 || {
    echo "ERROR: Namespace ${VAULT_NS} not found. Install Vault first." >&2
    exit 1
  }

  echo "==> Creating ServiceAccount ${SA_NAME} in ${VAULT_NS}"
  kubectl_cmd apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${SA_NAME}
  namespace: ${VAULT_NS}
  labels:
    app.kubernetes.io/name: vault-unsealer
    app.kubernetes.io/component: auto-unseal
EOF

  echo "==> Creating Secret ${SECRET_NAME} (unseal key)"
  kubectl_cmd create secret generic "${SECRET_NAME}" \
    --namespace="${VAULT_NS}" \
    --from-literal=unseal.key="${unseal_key}" \
    --dry-run=client -o yaml | kubectl_cmd apply -f -

  echo "==> Creating CronJob ${CRONJOB_NAME} (schedule: ${CRON_SCHEDULE})"
  kubectl_cmd apply -f - <<EOF
apiVersion: batch/v1
kind: CronJob
metadata:
  name: ${CRONJOB_NAME}
  namespace: ${VAULT_NS}
  labels:
    app.kubernetes.io/name: vault-unsealer
    app.kubernetes.io/component: auto-unseal
spec:
  schedule: "${CRON_SCHEDULE}"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: 2
      activeDeadlineSeconds: 120
      template:
        metadata:
          labels:
            app.kubernetes.io/name: vault-unsealer
        spec:
          serviceAccountName: ${SA_NAME}
          restartPolicy: OnFailure
          containers:
            - name: unseal
              image: ${VAULT_IMAGE}
              imagePullPolicy: IfNotPresent
              env:
                - name: VAULT_ADDR
                  value: "${VAULT_ADDR}"
                - name: VAULT_UNSEAL_KEY
                  valueFrom:
                    secretKeyRef:
                      name: ${SECRET_NAME}
                      key: unseal.key
              command:
                - /bin/sh
                - -ec
                - |
                  echo "Checking Vault at \${VAULT_ADDR} ..."
                  status_out=\$(vault status 2>&1) || {
                    echo "\${status_out}"
                    echo "Vault API unreachable — will retry next schedule"
                    exit 1
                  }
                  echo "\${status_out}"
                  echo "\${status_out}" | grep -q 'Initialized.*true' || {
                    echo "Vault not initialized — nothing to unseal"
                    exit 0
                  }
                  if echo "\${status_out}" | grep -q 'Sealed.*false'; then
                    echo "Vault already unsealed"
                    exit 0
                  fi
                  echo "Unsealing Vault ..."
                  vault operator unseal "\${VAULT_UNSEAL_KEY}"
                  vault status
EOF

  echo ""
  echo "Installed. Vault will be unsealed within ~2 minutes if sealed."
  echo "  $(basename "$0") status"
  echo "  $(basename "$0") run-now    # trigger immediately"
  echo ""
  echo "WARNING: unseal key is stored in Secret ${SECRET_NAME} — dev only."
}

cmd_uninstall() {
  require_kubectl
  echo "==> Removing CronJob, Secret, ServiceAccount"
  kubectl_cmd delete cronjob "${CRONJOB_NAME}" -n "${VAULT_NS}" --ignore-not-found
  kubectl_cmd delete secret "${SECRET_NAME}" -n "${VAULT_NS}" --ignore-not-found
  kubectl_cmd delete serviceaccount "${SA_NAME}" -n "${VAULT_NS}" --ignore-not-found
  kubectl_cmd delete jobs -n "${VAULT_NS}" -l "job-name=${CRONJOB_NAME}" --ignore-not-found 2>/dev/null || true
  echo "Removed."
}

cmd_status() {
  require_kubectl
  echo "==> CronJob"
  kubectl_cmd get cronjob "${CRONJOB_NAME}" -n "${VAULT_NS}" 2>/dev/null || echo "(not installed)"
  echo ""
  echo "==> Recent jobs"
  kubectl_cmd get jobs -n "${VAULT_NS}" -l "app.kubernetes.io/name=vault-unsealer" --sort-by=.metadata.creationTimestamp 2>/dev/null | tail -5 || true
  echo ""
  echo "==> Vault pod"
  kubectl_cmd get pod -n "${VAULT_NS}" -l "app.kubernetes.io/name=vault" 2>/dev/null || kubectl_cmd get pod vault-0 -n "${VAULT_NS}" 2>/dev/null || true
  echo ""
  echo "==> Vault seal status (via exec vault-0)"
  if kubectl_cmd get pod vault-0 -n "${VAULT_NS}" >/dev/null 2>&1; then
    kubectl_cmd exec -n "${VAULT_NS}" vault-0 -- \
      sh -c 'VAULT_ADDR=http://127.0.0.1:8200 vault status' 2>/dev/null || echo "(vault exec failed)"
  else
    echo "(vault-0 not found)"
  fi
}

cmd_run_now() {
  require_kubectl
  local job_name="${CRONJOB_NAME}-manual-$(date +%s)"
  echo "==> Creating one-off job ${job_name}"
  kubectl_cmd create job "${job_name}" \
    --from=cronjob/"${CRONJOB_NAME}" \
    -n "${VAULT_NS}"
  echo "Waiting for job ..."
  kubectl_cmd wait --for=condition=complete "job/${job_name}" -n "${VAULT_NS}" --timeout=90s || {
    echo "Job logs:"
    kubectl_cmd logs -n "${VAULT_NS}" "job/${job_name}" --tail=30 || true
    exit 1
  }
  kubectl_cmd logs -n "${VAULT_NS}" "job/${job_name}"
}

[[ $# -ge 1 ]] || usage
COMMAND="$1"
shift

case "${COMMAND}" in
  install) cmd_install "$@" ;;
  uninstall) cmd_uninstall "$@" ;;
  status) cmd_status "$@" ;;
  run-now) cmd_run_now "$@" ;;
  -h|--help) usage ;;
  *) echo "Unknown command: ${COMMAND}" >&2; usage ;;
esac
