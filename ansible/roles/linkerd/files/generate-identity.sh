#!/usr/bin/env bash
# Generate Linkerd trust-anchor + issuer (ECDSA P-256) into a directory.
# Idempotent: skips when ca.crt, issuer.crt, and issuer.key already exist.
set -euo pipefail

DIR="${1:?usage: generate-identity.sh <output-dir> [trust-days] [issuer-days]}"
TRUST_DAYS="${2:-3650}"
ISSUER_DAYS="${3:-365}"

mkdir -p "${DIR}"
cd "${DIR}"

if [[ -f ca.crt && -f issuer.crt && -f issuer.key ]]; then
  echo "Linkerd identity materials already present in ${DIR}"
  exit 0
fi

echo "Generating Linkerd identity certificates in ${DIR}"

openssl ecparam -name prime256v1 -genkey -noout -out ca.key
openssl req -new -x509 -key ca.key -out ca.crt -days "${TRUST_DAYS}" \
  -subj "/CN=root.linkerd.cluster.local" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,digitalSignature,keyCertSign,cRLSign"

openssl ecparam -name prime256v1 -genkey -noout -out issuer.key
openssl req -new -key issuer.key -out issuer.csr \
  -subj "/CN=identity.linkerd.cluster.local"

cat > issuer.ext <<'EOF'
basicConstraints=critical,CA:TRUE,pathlen:0
keyUsage=critical,digitalSignature,keyCertSign,cRLSign
EOF

openssl x509 -req -in issuer.csr \
  -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out issuer.crt -days "${ISSUER_DAYS}" \
  -extfile issuer.ext

rm -f issuer.csr issuer.ext ca.srl
chmod 600 ca.key issuer.key
echo "Wrote ca.crt ca.key issuer.crt issuer.key"
