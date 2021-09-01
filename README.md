# What

This is a Docker image for ElasticSearch, with strong opinions (TLS, authentication, mDNS support).

This is based on [Elastic](https://github.com/elastic/elasticsearch).

## Image features

* multi-architecture:
  * [x] linux/amd64
  * [x] linux/386
  * [x] linux/arm64
  * [x] linux/arm/v7
  * [x] linux/arm/v6
  * [x] linux/ppc64le
  * [x] linux/s390x
* hardened:
  * [x] image runs read-only
  * [x] image runs with no capabilities but NET_BIND_SERVICE
  * [x] process runs as a non-root user, disabled login, no shell
* lightweight
  * [x] based on our slim [Debian Bullseye](https://github.com/dubo-dubon-duponey/docker-debian)
  * [x] simple entrypoint script
  * [x] multi-stage build with no installed dependencies for the runtime image
* observable
  * [x] healthcheck
  * [x] log to stdout
  * [ ] ~~prometheus endpoint~~


    * [ ] ~~linux/arm/v7~~ unsupported by Elastic
    * [ ] ~~linux/arm/v6~~ unsupported by Elastic

## Run

See [example script](example/example.sh) for a complete stack including Kibana.

For Elastic specifically:

```bash
# Domain name for your Elastic server (will be used to generate self-signed certificates, and also as a container name)
ES_DOMAIN=myelastic.local
# Port to expose for Elastic
ES_PORT=5000

# Username and password
USERNAME=my_elastic_username
PASSWORD=secret_password

# Generate the salted password hash
SALTED_PASSWORD="$(docker run --rm ghcr.io/dubo-dubon-duponey/elastic hash -plaintext "$PASSWORD" 2>/dev/null)"
# If you prefer *not* to pass the plaintext password, you can provide it interactively and manually copy the output into SALTED_PASSWORD
# docker run -ti ghcr.io/dubo-dubon-duponey/elastic hash-interactive

######################################
# Elastic
######################################

mkdir -p certificates

# Create a bridge network (add both Elastic and Kibana to it so they can communicate together)
# If you want to use mDNS, you have to switch to host or mac/ip-vlan network instead.

docker network create dubo-bridge 2>/dev/null || true
docker rm -f "$ES_DOMAIN" 2>/dev/null || true

docker run -d --cap-drop ALL --read-only \
  -v "$(pwd)"/certificates:/certs \
  --user $(id -u) \
  --net dubo-bridge \
  --name "$ES_DOMAIN" \
  --publish "$ES_PORT:$ES_PORT" \
  --env DOMAIN="$ES_DOMAIN" \
  --env PORT="$ES_PORT" \
  --env USERNAME="$USERNAME" \
  --env PASSWORD="$SALTED_PASSWORD" \
  ghcr.io/dubo-dubon-duponey/elastic
```

## Notes

### Prometheus

Not applicable.

## Moar?

See [DEVELOP.md](DEVELOP.md)
