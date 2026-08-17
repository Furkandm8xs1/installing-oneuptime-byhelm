#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TLS_DIR="${PROJECT_DIR}/k8s/local-tls"
CERT_DIR="${TLS_DIR}/certs"

KUBE_CONTEXT="${KUBE_CONTEXT:-oneuptime}"
NAMESPACE="${NAMESPACE:-oneuptime}"
RELEASE="${RELEASE:-oneuptime}"
LOCAL_HOST="${LOCAL_HOST:-oneuptime.furkan.test}"
LOCAL_HTTPS_PORT="${LOCAL_HTTPS_PORT:-443}"
TRUST_CA=false

if [[ "${1:-}" == "--trust" ]]; then
  TRUST_CA=true
elif [[ -n "${1:-}" ]]; then
  echo "Kullanim: $0 [--trust]" >&2
  exit 2
fi

for command_name in kubectl helm openssl; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Gerekli komut bulunamadi: ${command_name}" >&2
    exit 1
  fi
done

if [[ ! "${LOCAL_HOST}" =~ ^[A-Za-z0-9.-]+$ ]]; then
  echo "Gecersiz LOCAL_HOST: ${LOCAL_HOST}" >&2
  exit 1
fi

if [[ ! "${LOCAL_HTTPS_PORT}" =~ ^[0-9]+$ ]] || \
  ((LOCAL_HTTPS_PORT < 1 || LOCAL_HTTPS_PORT > 65535)); then
  echo "Gecersiz LOCAL_HTTPS_PORT: ${LOCAL_HTTPS_PORT}" >&2
  exit 1
fi

if [[ "${LOCAL_HTTPS_PORT}" == "443" ]]; then
  PUBLIC_HOST="${LOCAL_HOST}"
else
  PUBLIC_HOST="${LOCAL_HOST}:${LOCAL_HTTPS_PORT}"
fi

if [[ "$(uname -s)" == "Darwin" ]]; then
  HOSTS_IP="$(awk -v host_name="${LOCAL_HOST}" '
    $1 !~ /^#/ {
      for (field = 2; field <= NF; field++) {
        if ($field == host_name) {
          print $1
          exit
        }
      }
    }
  ' /etc/hosts)"

  if [[ -z "${HOSTS_IP}" ]]; then
    echo "${LOCAL_HOST}, /etc/hosts dosyasina ekleniyor..."
    printf '127.0.0.1\t%s\n' "${LOCAL_HOST}" | \
      sudo tee -a /etc/hosts >/dev/null
    sudo dscacheutil -flushcache
    sudo killall -HUP mDNSResponder 2>/dev/null || true
  elif [[ "${HOSTS_IP}" != "127.0.0.1" ]]; then
    echo "${LOCAL_HOST}, /etc/hosts icinde ${HOSTS_IP} adresine bagli." >&2
    echo "Devam etmeden once bu kaydi 127.0.0.1 olarak duzeltin." >&2
    exit 1
  fi
fi

kubectl --context "${KUBE_CONTEXT}" get namespace "${NAMESPACE}" >/dev/null
kubectl --context "${KUBE_CONTEXT}" --namespace "${NAMESPACE}" \
  get service "${RELEASE}-nginx" >/dev/null

umask 077
mkdir -p "${CERT_DIR}"

CA_KEY="${CERT_DIR}/local-ca.key"
CA_CERT="${CERT_DIR}/local-ca.crt"
SERVER_KEY="${CERT_DIR}/localhost.key"
SERVER_CSR="${CERT_DIR}/localhost.csr"
SERVER_CERT="${CERT_DIR}/localhost.crt"
SERVER_EXT="${CERT_DIR}/localhost.ext"
CA_NAME="OneUptime Local Development CA"
SERVER_CERT_TEXT=""

if [[ -s "${SERVER_CERT}" ]]; then
  SERVER_CERT_TEXT="$(
    openssl x509 -in "${SERVER_CERT}" -noout -text 2>/dev/null || true
  )"
fi

if [[ ! -s "${CA_KEY}" || ! -s "${CA_CERT}" ]]; then
  echo "Yerel sertifika otoritesi olusturuluyor..."
  openssl req -x509 -newkey rsa:3072 -sha256 -nodes \
    -days 3650 \
    -keyout "${CA_KEY}" \
    -out "${CA_CERT}" \
    -subj "/CN=${CA_NAME}" \
    -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" \
    -addext "subjectKeyIdentifier=hash"
fi

if [[ ! -s "${SERVER_CERT}" ]] || \
  ! openssl x509 -checkend 2592000 -noout -in "${SERVER_CERT}" >/dev/null 2>&1 || \
  [[ "${SERVER_CERT_TEXT}" != *"DNS:${LOCAL_HOST}"* ]]; then
  echo "${LOCAL_HOST} sunucu sertifikasi olusturuluyor..."
  openssl req -new -newkey rsa:2048 -sha256 -nodes \
    -keyout "${SERVER_KEY}" \
    -out "${SERVER_CSR}" \
    -subj "/CN=${LOCAL_HOST}"

  printf '%s\n' \
    'authorityKeyIdentifier=keyid,issuer' \
    'basicConstraints=critical,CA:FALSE' \
    'keyUsage=critical,digitalSignature,keyEncipherment' \
    'extendedKeyUsage=serverAuth' \
    "subjectAltName=DNS:${LOCAL_HOST},DNS:localhost,IP:127.0.0.1,IP:::1" \
    > "${SERVER_EXT}"

  openssl x509 -req \
    -in "${SERVER_CSR}" \
    -CA "${CA_CERT}" \
    -CAkey "${CA_KEY}" \
    -CAcreateserial \
    -out "${SERVER_CERT}" \
    -days 825 \
    -sha256 \
    -extfile "${SERVER_EXT}"
fi

chmod 600 "${CA_KEY}" "${SERVER_KEY}"
chmod 644 "${CA_CERT}" "${SERVER_CERT}"

if [[ "${TRUST_CA}" == true ]]; then
  if ! command -v security >/dev/null 2>&1; then
    echo "--trust yalnizca macOS security komutu ile destekleniyor." >&2
    exit 1
  fi

  LOGIN_KEYCHAIN="$(security default-keychain -d user | tr -d '"')"
  echo "Yerel CA, macOS kullanici anahtar zincirine guvenilir olarak ekleniyor..."
  security add-trusted-cert -r trustRoot -k "${LOGIN_KEYCHAIN}" "${CA_CERT}"
fi

echo "TLS proxy Kubernetes'e uygulaniyor..."
kubectl --context "${KUBE_CONTEXT}" apply -k "${TLS_DIR}"
kubectl --context "${KUBE_CONTEXT}" --namespace "${NAMESPACE}" \
  rollout restart deployment/oneuptime-local-tls
kubectl --context "${KUBE_CONTEXT}" --namespace "${NAMESPACE}" \
  rollout status deployment/oneuptime-local-tls --timeout=180s

echo "OneUptime ana URL'si HTTPS olarak guncelleniyor..."
helm upgrade "${RELEASE}" "${PROJECT_DIR}/oneuptime" \
  --kube-context "${KUBE_CONTEXT}" \
  --namespace "${NAMESPACE}" \
  --reuse-values \
  --set-string host="${PUBLIC_HOST}" \
  --set-string httpProtocol=https \
  --wait \
  --timeout 15m

echo
echo "Kurulum tamamlandi. HTTPS port-forward icin:"
echo "  ${SCRIPT_DIR}/port-forward-https.sh"
echo
echo "Ardindan su adresi acin: https://${PUBLIC_HOST}"
if [[ "${TRUST_CA}" != true ]]; then
  echo "Tarayici uyarisi olmamasi icin kurulumu bir kez --trust ile calistirin."
fi
