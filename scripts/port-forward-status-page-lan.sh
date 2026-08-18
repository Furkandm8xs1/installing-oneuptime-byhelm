#!/usr/bin/env bash

set -euo pipefail

KUBE_CONTEXT="${KUBE_CONTEXT:-oneuptime}"
NAMESPACE="${NAMESPACE:-oneuptime}"
WIFI_INTERFACE="${WIFI_INTERFACE:-en0}"
LOCAL_HTTP_PORT="${LOCAL_HTTP_PORT:-80}"
LAN_ADDRESS="${LAN_ADDRESS:-}"
DNS_NAME="${DNS_NAME:-furkanstatus.test}"

if [[ ! "${LOCAL_HTTP_PORT}" =~ ^[0-9]+$ ]] || \
  ((LOCAL_HTTP_PORT < 1 || LOCAL_HTTP_PORT > 65535)); then
  echo "Gecersiz yerel port: ${LOCAL_HTTP_PORT}" >&2
  exit 1
fi

if [[ -z "${LAN_ADDRESS}" ]] && [[ "$(uname -s)" == "Darwin" ]]; then
  LAN_ADDRESS="$(ipconfig getifaddr "${WIFI_INTERFACE}" 2>/dev/null || true)"
fi

if [[ -z "${LAN_ADDRESS}" ]]; then
  echo "Wi-Fi IPv4 adresi bulunamadi." >&2
  echo "LAN_ADDRESS=192.168.x.x ile adresi acikca belirtin." >&2
  exit 1
fi

if [[ ! "${LAN_ADDRESS}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
  echo "Gecersiz LAN_ADDRESS: ${LAN_ADDRESS}" >&2
  exit 1
fi

KUBECTL_BIN="$(command -v kubectl)"

"${KUBECTL_BIN}" --context "${KUBE_CONTEXT}" --namespace "${NAMESPACE}" \
  get service oneuptime-lan-status >/dev/null

if [[ "${LOCAL_HTTP_PORT}" == "80" ]]; then
  LAN_URL="http://${LAN_ADDRESS}"
  DNS_URL="http://${DNS_NAME}"
else
  LAN_URL="http://${LAN_ADDRESS}:${LOCAL_HTTP_PORT}"
  DNS_URL="http://${DNS_NAME}:${LOCAL_HTTP_PORT}"
fi

echo "Status page LAN erisimi: ${LAN_URL}"
echo "Router DNS kaydi: ${DNS_NAME} -> ${LAN_ADDRESS}"
echo "DNS hazir oldugunda: ${DNS_URL}"
echo "Yalnizca Wi-Fi adresi dinlenecek; localhost HTTPS erisimi degismeyecek."

if ((LOCAL_HTTP_PORT < 1024)) && ((EUID != 0)); then
  KUBE_CONFIG_PATH="${KUBECONFIG:-${HOME}/.kube/config}"
  exec sudo "${KUBECTL_BIN}" \
    --kubeconfig "${KUBE_CONFIG_PATH}" \
    --context "${KUBE_CONTEXT}" \
    --namespace "${NAMESPACE}" \
    port-forward --address "${LAN_ADDRESS}" \
    service/oneuptime-lan-status "${LOCAL_HTTP_PORT}:80"
else
  exec "${KUBECTL_BIN}" --context "${KUBE_CONTEXT}" \
    --namespace "${NAMESPACE}" \
    port-forward --address "${LAN_ADDRESS}" \
    service/oneuptime-lan-status "${LOCAL_HTTP_PORT}:80"
fi
