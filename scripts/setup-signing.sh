#!/bin/zsh
# Одноразово створює самопідписаний сертифікат «Screent Local Signing» у login keychain.
# Завдяки йому підпис застосунку не змінюється між збірками, і macOS пам'ятає дозвіл «Запис екрана».
set -euo pipefail
NAME="Screent Local Signing"
if security find-identity -p codesigning | grep -q "$NAME"; then
  echo "Certificate \"$NAME\" already exists."; exit 0
fi
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cfg.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -days 3650 -config "$TMP/cfg.cnf"
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/id.p12" -passout pass:screent -name "$NAME"
security import "$TMP/id.p12" -k ~/Library/Keychains/login.keychain-db -P screent -T /usr/bin/codesign
echo "Done: \"$NAME\". Now run: ./scripts/build-app.sh --install --run"
