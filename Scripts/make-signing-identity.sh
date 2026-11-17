#!/bin/zsh
# Creates a self-signed code-signing identity, "Harbor Local Signing", in its own keychain.
#
# Ad-hoc signatures change with every build, so macOS treats each build as a new app and the
# Accessibility and Screen Recording grants stop applying. Signing with a fixed certificate gives
# every build the same designated requirement, so grants survive rebuilds.
#
# The login keychain and the keychain search list are left alone; `make app` passes this keychain
# to codesign directly. Safe to run again: it does nothing when the identity already exists.
set -euo pipefail

NAME="Harbor Local Signing"
KEYCHAIN="$HOME/Library/Keychains/harbor-signing.keychain-db"
# Only guards a keychain holding a local, self-signed signing key; not a secret.
PASSWORD="harbor-local-signing"

if [[ -f "$KEYCHAIN" ]] && security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$NAME"; then
    echo "\"$NAME\" already exists in $KEYCHAIN"
    exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$WORK/cert.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
# macOS's importer only reads PKCS#12 files made with the older SHA1/3DES algorithms.
openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$NAME" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
    -passout pass:"$PASSWORD" -out "$WORK/identity.p12"

[[ -f "$KEYCHAIN" ]] || security create-keychain -p "$PASSWORD" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"
security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign
# Lets codesign use the key without a confirmation dialog.
security set-key-partition-list -S apple-tool:,apple: -s -k "$PASSWORD" "$KEYCHAIN" >/dev/null

security find-identity -p codesigning "$KEYCHAIN"
echo "Created \"$NAME\" in $KEYCHAIN"
