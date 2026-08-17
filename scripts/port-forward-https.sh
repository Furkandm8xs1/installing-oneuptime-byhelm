#!/usr/bin/env bash

set -euo pipefail

KUBE_CONTEXT="${KUBE_CONTEXT:-oneuptime}"
NAMESPACE="${NAMESPACE:-oneuptime}"
LOCAL_HTTP_PORT="${LOCAL_HTTP_PORT:-80}"
LOCAL_HTTPS_PORT="${LOCAL_HTTPS_PORT:-443}"

for local_port in "${LOCAL_HTTP_PORT}" "${LOCAL_HTTPS_PORT}"; do
  if [[ ! "${local_port}" =~ ^[0-9]+$ ]] || \
    ((local_port < 1 || local_port > 65535)); then
    echo "Gecersiz yerel port: ${local_port}" >&2
    exit 1
  fi
done

KUBECTL_BIN="$(command -v kubectl)"

if ((LOCAL_HTTP_PORT < 1024 || LOCAL_HTTPS_PORT < 1024)) && ((EUID != 0)); then
  KUBE_CONFIG_PATH="${KUBECONFIG:-${HOME}/.kube/config}"
  echo "${LOCAL_HTTP_PORT}/80 ve ${LOCAL_HTTPS_PORT}/443 portlari aciliyor; sudo yetkisi istenecek."
  exec sudo "${KUBECTL_BIN}" \
    --kubeconfig "${KUBE_CONFIG_PATH}" \
    --context "${KUBE_CONTEXT}" \
    --namespace "${NAMESPACE}" \
    port-forward service/oneuptime-local-tls \
    "${LOCAL_HTTP_PORT}:80" \
    "${LOCAL_HTTPS_PORT}:443"
fi

exec "${KUBECTL_BIN}" --context "${KUBE_CONTEXT}" \
  --namespace "${NAMESPACE}" \
  port-forward service/oneuptime-local-tls \
  "${LOCAL_HTTP_PORT}:80" \
  "${LOCAL_HTTPS_PORT}:443"
