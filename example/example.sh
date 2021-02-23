#!/usr/bin/env bash
set -o errexit -o errtrace -o functrace -o nounset -o pipefail

######################################
# Your configuration
######################################

# The salt that is going to be used for storing passwords
SALT=lalalalala

# Domain name for your Elastic server (will be used to generate self-signed certificates, and also as a container name)
ES_DOMAIN=myelastic.local
# Same, for kibana
KBN_DOMAIN=mykibana.local
# Port to expose for Elastic
ES_PORT=5000
# Port to expose for Kibana
KBN_PORT=5001

# Username and password (same for Elastic & Kibana for simplicity, but you may (should!) use different credentials for both services)
USERNAME=my_elastic_username
PASSWORD=secret_password

######################################
# Salt encoding and password salting
######################################

# Generate the salted password hash
SALTED_PASSWORD="$(docker run --rm --env SALT="$SALT" dubodubonduponey/elastic hash -plaintext "$PASSWORD" 2>/dev/null)"
# If you prefer *not* to pass the plaintext password, you can provide it interactively and manually copy the output into SALTED_PASSWORD
# docker run -ti --env SALT="$ES_SALT" dubodubonduponey/elastic hash-interactive

B64_SALT="$(printf "%s" "$SALT" | base64)"

mkdir -p certificates

######################################
# Elastic
######################################

docker network create dubo-bridge 2>/dev/null || true
docker rm -f "$ES_DOMAIN" 2>/dev/null || true

docker run -d --cap-drop ALL --read-only \
  -v "$(pwd)"/certificates:/certs \
  --user $(id -u) \
  --net dubo-bridge \
  --name "$ES_DOMAIN" \
  --publish "$ES_PORT:$ES_PORT" \
  --env DOMAIN="$ES_DOMAIN" \
  --env SALT="$B64_SALT" \
  --env PORT="$ES_PORT" \
  --env USERNAME="$USERNAME" \
  --env PASSWORD="$SALTED_PASSWORD" \
  dubodubonduponey/elastic

######################################
# Kibana
######################################
docker rm -f "$KBN_DOMAIN" 2>/dev/null || true

# --cap-drop ALL --read-only \
docker run -d \
  -v $(pwd)/certificates:/certs \
  --user $(id -u) \
  --net dubo-bridge \
  --name "$KBN_DOMAIN" \
  --publish "$KBN_PORT:$KBN_PORT" \
  --env DOMAIN="$KBN_DOMAIN" \
  --env SALT="$B64_SALT" \
  --env PORT="$KBN_PORT" \
  --env USERNAME="$USERNAME" \
  --env PASSWORD="$SALTED_PASSWORD" \
  --env ELASTICSEARCH_HOSTS="https://$ES_DOMAIN:$ES_PORT" \
  --env ELASTICSEARCH_SSL_CERTIFICATEAUTHORITIES=/certs/pki/authorities/local/root.crt \
  --env ELASTICSEARCH_USERNAME="$USERNAME" \
  --env ELASTICSEARCH_PASSWORD="$PASSWORD" \
  dubodubonduponey/kibana


######################################
# Verification
######################################

# Verify that TLS is working from the host
echo "curl -iv --cacert certificates/pki/authorities/local/root.crt -s --resolve "$ES_DOMAIN:$ES_PORT:127.0.0.1" "https://$ES_DOMAIN:$ES_PORT""
while true; do
  if curl -iv --cacert certificates/pki/authorities/local/root.crt -s --resolve "$ES_DOMAIN:$ES_PORT:127.0.0.1" "https://$ES_DOMAIN:$ES_PORT" 2>/dev/null | grep HTTP; then
    break
  fi
  echo "Waiting for Caddy to come up..."
  sleep 1
done

# Verify that authentication is working, and wait for elastic to be alive
echo "curl -iv --cacert certificates/pki/authorities/local/root.crt -u "$USERNAME:$PASSWORD" -s --resolve "$ES_DOMAIN:$ES_PORT:127.0.0.1" "https://$ES_DOMAIN:$ES_PORT""
while true; do
  if curl -iv --cacert certificates/pki/authorities/local/root.crt -u "$USERNAME:$PASSWORD" -s --resolve "$ES_DOMAIN:$ES_PORT:127.0.0.1" "https://$ES_DOMAIN:$ES_PORT" 2>/dev/null | grep HTTP | grep 200; then
    break
  fi
  echo "Waiting for Elastic to come up..."
  sleep 1
done

echo "curl -iv --cacert certificates/pki/authorities/local/root.crt -s --resolve "$KBN_DOMAIN:$KBN_PORT:127.0.0.1" "https://$KBN_DOMAIN:$KBN_PORT""
while true; do
  if curl -iv --cacert certificates/pki/authorities/local/root.crt -s --resolve "$KBN_DOMAIN:$KBN_PORT:127.0.0.1" "https://$KBN_DOMAIN:$KBN_PORT" 2>/dev/null | grep HTTP; then
    break
  fi
  echo "Waiting for Caddy to come up..."
  sleep 1
done

# Verify that authentication is working, and wait for elastic to be alive
echo "curl -iv --cacert certificates/pki/authorities/local/root.crt -u "$USERNAME:$PASSWORD" -s --resolve "$KBN_DOMAIN:$KBN_PORT:127.0.0.1" "https://$KBN_DOMAIN:$KBN_PORT/app/home#/""
while true; do
  if curl -iv --cacert certificates/pki/authorities/local/root.crt -u "$USERNAME:$PASSWORD" -s --resolve "$KBN_DOMAIN:$KBN_PORT:127.0.0.1" "https://$KBN_DOMAIN:$KBN_PORT/app/home#/" 2>/dev/null | grep HTTP | grep 200; then
    break
  fi
  echo "Waiting for Kibana to come up..."
  sleep 1
done


######################################
# Trust your certificate so that you can access from your browser
######################################

# macOS

# security add-trusted-cert -d -r trustRoot -k ~/Library/Keychains/login.keychain registry.local.ca.crt
