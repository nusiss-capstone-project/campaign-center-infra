#!/usr/bin/env bash
# Shared helpers for provision-env.sh / teardown-env.sh
# shellcheck shell=bash

PROTECTED_ENV="dev"
PROTECTED_NS="campaign-dev"
PROTECTED_ROOT_APP="campaign-gitops-root"
SECRET_SOURCE_NS="campaign-dev"
# Secrets copied from campaign-dev into campaign-<env> by provision-env.sh
PROVISION_COPIED_SECRETS=(
  campaignhub-origin-tls
  acr-secret
)
ARGOCD_NS="argocd"
KAFKA_NS="messaging"
KAFKA_POD="${KAFKA_POD:-kafka-0}"
KAFKA_BOOTSTRAP="${KAFKA_BOOTSTRAP:-localhost:9092}"
# kafka-topics CLI inside broker (delete fallback when kafka-ui restricts deletion).
# Keep heap small so the tool JVM does not fight the broker for memory.
KAFKA_TOOLS_HEAP_OPTS="${KAFKA_TOOLS_HEAP_OPTS:--Xmx64m -Xms32m}"
# Topic create via kafka-ui API; delete prefers UI but falls back to broker CLI.
KAFKA_UI_NS="${KAFKA_UI_NS:-messaging}"
KAFKA_UI_SVC="${KAFKA_UI_SVC:-kafka-ui}"
KAFKA_UI_CLUSTER_NAME="${KAFKA_UI_CLUSTER_NAME:-dev}"
KAFKA_UI_PF_PID=""
KAFKA_UI_PF_PORT=""
GITOPS_REPO_URL="${GITOPS_REPO_URL:-https://github.com/nusiss-capstone-project/campaign-gitops}"
GITOPS_PATH="${GITOPS_PATH:-argocd/applications}"
# Orphan kinds left in campaign-<env> when Argo root prune is incomplete.
WORKLOAD_ORPHAN_KINDS=(deploy svc ingressroute)

# Business topics to clone (exclude __* internals). Same set for provision + teardown.
ENV_KAFKA_TOPICS=(
  reward.finance_doc.approved
  reward.issue_request.approved
  reward.distribution.execute
  reward.distribution.result
  user.events.registered
  user.events.kyc_complete
  task.events.completed
  payment.payment_method.added
  payment.transaction.updated
  asset.order.payment_result
  deposit.transaction.payment_result
)

assert_safe_env() {
  local env_name="$1"
  if [[ -z "${env_name}" ]]; then
    echo "ERROR: env name is empty." >&2
    exit 1
  fi
  if [[ ! "${env_name}" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
    echo "ERROR: invalid env name '${env_name}'." >&2
    exit 1
  fi
  if [[ "${env_name}" == "${PROTECTED_ENV}" ]]; then
    echo "ERROR: refusing to operate on protected env '${PROTECTED_ENV}'." >&2
    exit 1
  fi
}

root_app_name() {
  local env_name="$1"
  echo "campaign-gitops-root-${env_name}"
}

workload_ns() {
  local env_name="$1"
  echo "campaign-${env_name}"
}

assert_safe_root_app() {
  local name="$1"
  if [[ "${name}" == "${PROTECTED_ROOT_APP}" ]]; then
    echo "ERROR: refusing to touch protected Application ${PROTECTED_ROOT_APP}." >&2
    exit 1
  fi
  if [[ "${name}" != campaign-gitops-root-* ]]; then
    echo "ERROR: refusing Application name '${name}' (must be campaign-gitops-root-<env>)." >&2
    exit 1
  fi
}

assert_safe_workload_ns() {
  local ns="$1"
  if [[ "${ns}" == "${PROTECTED_NS}" ]]; then
    echo "ERROR: refusing to touch protected namespace ${PROTECTED_NS}." >&2
    exit 1
  fi
  if [[ "${ns}" != campaign-* ]]; then
    echo "ERROR: refusing namespace '${ns}' (must be campaign-<env>)." >&2
    exit 1
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: '$1' not found." >&2
    exit 1
  }
}

load_kubeconfig() {
  local cluster_env="$1"
  local path="${KUBECONFIG:-${REPO_ROOT}/kubeconfigs/${cluster_env}.yaml}"
  [[ -f "${path}" ]] || {
    echo "ERROR: Kubeconfig not found: ${path}" >&2
    exit 1
  }
  export KUBECONFIG="${path}"
}

kafka_ui_api_base() {
  echo "http://127.0.0.1:${KAFKA_UI_PF_PORT}/api/clusters/${KAFKA_UI_CLUSTER_NAME}"
}

wait_kube_api() {
  local i
  for i in $(seq 1 30); do
    if kubectl get --raw=/readyz >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "ERROR: Kubernetes API not reachable (TLS/handshake timeouts?). Retry when API is stable." >&2
  return 1
}

kafka_ui_pf_start() {
  require_cmd curl
  require_cmd python3
  wait_kube_api || exit 1

  local attempt port logfile i
  local max_attempts="${KAFKA_UI_PF_RETRIES:-5}"
  trap kafka_ui_pf_stop EXIT INT TERM

  for attempt in $(seq 1 "${max_attempts}"); do
    port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
    logfile="$(mktemp)"
    kubectl -n "${KAFKA_UI_NS}" port-forward --address 127.0.0.1 \
      "svc/${KAFKA_UI_SVC}" "${port}:8080" >"${logfile}" 2>&1 &
    KAFKA_UI_PF_PID=$!
    KAFKA_UI_PF_PORT="${port}"

    for i in $(seq 1 40); do
      if curl -sf --connect-timeout 2 --max-time 5 \
        "http://127.0.0.1:${KAFKA_UI_PF_PORT}/api/clusters" >/dev/null 2>&1; then
        rm -f "${logfile}"
        return 0
      fi
      if ! kill -0 "${KAFKA_UI_PF_PID}" 2>/dev/null; then
        wait "${KAFKA_UI_PF_PID}" 2>/dev/null || true
        KAFKA_UI_PF_PID=""
        echo "WARNING: kafka-ui port-forward died (attempt ${attempt}/${max_attempts}):" >&2
        sed -n '1,20p' "${logfile}" >&2 || true
        rm -f "${logfile}"
        break
      fi
      sleep 0.25
    done

    if [[ -n "${KAFKA_UI_PF_PID}" ]]; then
      kill "${KAFKA_UI_PF_PID}" 2>/dev/null || true
      wait "${KAFKA_UI_PF_PID}" 2>/dev/null || true
      KAFKA_UI_PF_PID=""
      echo "WARNING: kafka-ui API not ready on 127.0.0.1:${port} (attempt ${attempt}/${max_attempts})." >&2
      sed -n '1,20p' "${logfile}" >&2 || true
      rm -f "${logfile}"
    fi
    sleep 2
  done

  echo "ERROR: could not open kafka-ui port-forward after ${max_attempts} attempts." >&2
  echo "  Check: kubectl -n ${KAFKA_UI_NS} get pods,svc -l app.kubernetes.io/name=kafka-ui" >&2
  exit 1
}

kafka_ui_pf_stop() {
  if [[ -n "${KAFKA_UI_PF_PID}" ]] && kill -0 "${KAFKA_UI_PF_PID}" 2>/dev/null; then
    kill "${KAFKA_UI_PF_PID}" 2>/dev/null || true
    wait "${KAFKA_UI_PF_PID}" 2>/dev/null || true
  fi
  KAFKA_UI_PF_PID=""
  # Keep EXIT trap cleared only when intentionally stopping; leave INT/TERM for cleanup during run.
  trap - EXIT INT TERM
}

kafka_ui_create_topic() {
  local topic="$1"
  local tmp code
  tmp="$(mktemp)"
  code="$(curl -sS -o "${tmp}" -w '%{http_code}' -X POST "$(kafka_ui_api_base)/topics" \
    -H 'Content-Type: application/json' \
    -d "{\"name\":\"${topic}\",\"partitions\":1,\"replicationFactor\":1,\"configs\":{}}")"
  if [[ "${code}" == "200" ]]; then
    rm -f "${tmp}"
    return 0
  fi
  if [[ "${code}" == "400" ]] && grep -q "already exists" "${tmp}"; then
    rm -f "${tmp}"
    return 2
  fi
  echo "ERROR: create topic ${topic} failed (HTTP ${code}):" >&2
  cat "${tmp}" >&2 || true
  rm -f "${tmp}"
  return 1
}

# Print existing topic names (one per line) from kafka-ui.
kafka_ui_list_topic_names() {
  curl -sf --connect-timeout 5 --max-time 60 "$(kafka_ui_api_base)/topics" \
    | python3 -c '
import json,sys
data=json.load(sys.stdin)
if isinstance(data, dict):
  data=data.get("topics") or data.get("items") or []
for t in data:
  if isinstance(t, dict):
    name=t.get("name") or t.get("topicName")
    if name:
      print(name)
  elif isinstance(t, str):
    print(t)
'
}

kafka_ui_topic_exists() {
  local topic="$1"
  local code
  code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 30 \
    "$(kafka_ui_api_base)/topics/${topic}")"
  [[ "${code}" == "200" ]]
}

kafka_topics_bin() {
  if kubectl -n "${KAFKA_NS}" exec "${KAFKA_POD}" -c kafka -- \
    test -x /opt/kafka/bin/kafka-topics.sh 2>/dev/null; then
    echo /opt/kafka/bin/kafka-topics.sh
  else
    echo /opt/bitnami/kafka/bin/kafka-topics.sh
  fi
}

kafka_topics_exec() {
  kubectl -n "${KAFKA_NS}" exec "${KAFKA_POD}" -c kafka -- \
    env KAFKA_HEAP_OPTS="${KAFKA_TOOLS_HEAP_OPTS}" "$@"
}

# Delete topic via broker CLI (used when kafka-ui returns "Topic deletion restricted").
kafka_broker_delete_topic() {
  local topic="$1"
  local bin
  bin="$(kafka_topics_bin)"
  kafka_topics_exec "${bin}" \
    --bootstrap-server "${KAFKA_BOOTSTRAP}" \
    --delete \
    --topic "${topic}"
}

# Delete topic if it exists. Skips missing topics (no DELETE call).
# Returns: 0 deleted, 2 skipped missing, 1 error.
kafka_ui_delete_topic() {
  local topic="$1"
  local tmp code

  if ! kafka_ui_topic_exists "${topic}"; then
    return 2
  fi

  tmp="$(mktemp)"
  code="$(curl -sS -o "${tmp}" -w '%{http_code}' -X DELETE "$(kafka_ui_api_base)/topics/${topic}")"
  if [[ "${code}" == "200" ]]; then
    rm -f "${tmp}"
    return 0
  fi
  if [[ "${code}" == "404" || "${code}" == "500" ]] && grep -qiE 'UnknownTopic|does not host|not found|TopicNotFound' "${tmp}"; then
    rm -f "${tmp}"
    return 2
  fi
  # kafka-ui often blocks deletion even when TOPIC_DELETION feature is listed.
  if [[ "${code}" == "400" ]] && grep -qi 'Topic deletion restricted' "${tmp}"; then
    rm -f "${tmp}"
    echo "    kafka-ui restricts deletion; falling back to broker CLI for ${topic}"
    kafka_broker_delete_topic "${topic}"
    return $?
  fi
  echo "ERROR: delete topic ${topic} failed (HTTP ${code}):" >&2
  cat "${tmp}" >&2 || true
  rm -f "${tmp}"
  return 1
}

# Remove Argo orphan workloads left in campaign-<env> after root-app delete.
cleanup_workload_ns_orphans() {
  local ns="$1"
  assert_safe_workload_ns "${ns}"
  if ! kubectl get ns "${ns}" >/dev/null 2>&1; then
    echo "    skip: namespace ${ns} not found"
    return 0
  fi
  local kind
  for kind in "${WORKLOAD_ORPHAN_KINDS[@]}"; do
    if kubectl -n "${ns}" get "${kind}" -o name 2>/dev/null | grep -q .; then
      echo "    delete ${kind} --all in ${ns}"
      kubectl -n "${ns}" delete "${kind}" --all --wait=false
    else
      echo "    skip: no ${kind} in ${ns}"
    fi
  done
}

# Copy a secret from SECRET_SOURCE_NS into workload ns; label managed-by=provision-env.
copy_provision_secret() {
  local secret_name="$1"
  local dest_ns="$2"
  local env_name="$3"

  kubectl get secret -n "${SECRET_SOURCE_NS}" "${secret_name}" >/dev/null
  kubectl get ns "${dest_ns}" >/dev/null 2>&1 || kubectl create ns "${dest_ns}"
  kubectl get secret -n "${dest_ns}" "${secret_name}" >/dev/null 2>&1 && \
    kubectl delete secret -n "${dest_ns}" "${secret_name}"
  kubectl get secret -n "${SECRET_SOURCE_NS}" "${secret_name}" -o json \
    | python3 -c "
import json,sys
d=json.load(sys.stdin)
out={
  'apiVersion':'v1',
  'kind':'Secret',
  'metadata':{
    'name':d['metadata']['name'],
    'namespace':'${dest_ns}',
    'labels':{
      'app.kubernetes.io/managed-by':'provision-env',
      'campaign-center/env':'${env_name}',
    },
  },
  'type':d.get('type','Opaque'),
  'data':d.get('data',{}),
}
json.dump(out,sys.stdout)
" | kubectl apply -f -
}

# Delete secret in workload ns only if labeled managed-by=provision-env.
delete_provision_secret() {
  local secret_name="$1"
  local dest_ns="$2"

  if ! kubectl get ns "${dest_ns}" >/dev/null 2>&1; then
    echo "    skip: namespace ${dest_ns} not found"
    return 0
  fi
  if ! kubectl get secret -n "${dest_ns}" "${secret_name}" >/dev/null 2>&1; then
    echo "    skip: Secret/${secret_name} not found in ${dest_ns}"
    return 0
  fi
  local managed
  managed="$(kubectl get secret -n "${dest_ns}" "${secret_name}" \
    -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}' 2>/dev/null || true)"
  if [[ "${managed}" == "provision-env" ]]; then
    kubectl delete secret -n "${dest_ns}" "${secret_name}"
    echo "    deleted Secret/${secret_name} in ${dest_ns}"
  else
    echo "    skip: Secret/${secret_name} present but managed-by='${managed:-<none>}' (not provision-env)"
  fi
}
