ARG           FROM_REGISTRY=ghcr.io/dubo-dubon-duponey

ARG           FROM_IMAGE_BUILDER=base:builder-bullseye-2022-04-01@sha256:d73bb6ea84152c42e314bc9bff6388d0df6d01e277bd238ee0e6f8ade721856d
ARG           FROM_IMAGE_AUDITOR=base:auditor-bullseye-2022-04-01@sha256:ca513bf0219f654afeb2d24aae233fef99cbcb01991aea64060f3414ac792b3f
ARG           FROM_IMAGE_RUNTIME=base:runtime-bullseye-2022-04-01@sha256:6456b76dd2eedf34b4c5c997f9ad92901220dfdd405ec63419d0b54b6d85a777

ARG           FROM_IMAGE_TOOLS=tools:linux-bullseye-2022-04-01@sha256:323f3e36da17d8638a07a656e2f17d5ee4dc2b17dfea7e2da36e1b2174cc5f18

FROM          $FROM_REGISTRY/$FROM_IMAGE_TOOLS                                                                          AS builder-tools
#######################
# Main builder
#######################
FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_BUILDER                                              AS builder-main

ARG           TARGETARCH
ARG           TARGETOS
ARG           TARGETVARIANT
ARG           TARGETPLATFORM

# Note that this is tied to x86_64 and not a proper multi-arch image
#ENV           VERSION=7.14.0
#ENV           AMD64_SHA512=30764d5838009dc36d8f5c6c7249e65f323b5bd843027b47b37b91566d28cac95c4b5e6db1decce748f9ccd404a7ca4ba4fa9632bcd8b43fb27b0d93cc7b8f27
#ENV           AARCH64_SHA512=1b7193adb5bfa67963e972a6ad2e65df2281f970a48f416637014e78affe087f668ca4860fb0b267c8c64f2f084cf48471eae5a14919eee4706ebd8370a0562f
ENV           VERSION=7.17.2
ENV           AMD64_SHA512=c03ed71e3ec0855781e685dc523c4a9e53839a2cb08f7b2df6338a56df036ddcdc0871935dde64605bca96d0d140aaaaa19a6a3eafdf77114da264f7f89c8e46
ENV           AARCH64_SHA512=1529c5f63b33748497977d29ab0961afcb845f18c317480871c4a55a9db4d4ba6abcd6bd46e8c2a04ac62f1e37c105ad66974d7a20f8d00d95af675c6c9dd749

WORKDIR       /dist/boot

RUN           --mount=type=secret,id=CA \
              --mount=type=secret,id=CERTIFICATE \
              --mount=type=secret,id=KEY \
              --mount=type=secret,id=NETRC \
              --mount=type=secret,id=.curlrc \
              case "$TARGETPLATFORM" in \
                "linux/amd64")    arch=x86_64;      checksum=$AMD64_SHA512;      ;; \
                "linux/arm64")    arch=aarch64;     checksum=$AARCH64_SHA512;     ;; \
              esac; \
              curl -sSfL -o archive.tgz "https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-${VERSION}-linux-${arch}.tar.gz"; \
              printf "Downloaded shasum: %s\n" "$(sha512sum archive.tgz)"; \
              printf "%s *archive.tgz" "$checksum" | sha512sum -c -; \
              tar --strip-components=1 -zxf archive.tgz; \
              rm archive.tgz; \
              mv config ../; \
              rmdir logs; \
              rm LICENSE.txt; \
              rm NOTICE.txt; \
              rm README.asciidoc; \
              rm ../config/elasticsearch.yml; \
              rm ../config/log4j2.properties

RUN           grep ES_DISTRIBUTION_TYPE=tar bin/elasticsearch-env     && sed -ie 's/ES_DISTRIBUTION_TYPE=tar/ES_DISTRIBUTION_TYPE=docker/' bin/elasticsearch-env

# XXX kind of dirty, given ${ES_PATH_DATA} is only defined in the entrypoint script
RUN           sed -i'' -e 's|-XX:HeapDumpPath=data|-XX:HeapDumpPath=/tmp/|' ../config/jvm.options
RUN           sed -i'' -e 's|-XX:ErrorFile=logs/hs_err_pid%p.log|-XX:ErrorFile=/tmp/hs_err_pid%p.log|' ../config/jvm.options
RUN           sed -i'' -e 's|9-:-Xlog:gc\*,gc+age=trace,safepoint:file=logs/gc.log:utctime,pid,tags:filecount=32,filesize=64m|9-:-Xlog:gc*,gc+age=trace,safepoint:file=/tmp/gc.log:utctime,pid,tags:filecount=32,filesize=64m|' ../config/jvm.options

#######################
# Builder assembly, XXX should be auditor
#######################
FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_AUDITOR                                              AS assembly

COPY          --from=builder-main   /dist/boot           /dist/boot

COPY          --from=builder-tools  /boot/bin/goello-server-ng  /dist/boot/bin
COPY          --from=builder-tools  /boot/bin/caddy          /dist/boot/bin
COPY          --from=builder-tools  /boot/bin/http-health    /dist/boot/bin

RUN           setcap 'cap_net_bind_service+ep' /dist/boot/bin/caddy

RUN           RUNNING=true \
              STATIC=true \
                dubo-check validate /dist/boot/bin/*

RUN           RO_RELOCATIONS=true \
                dubo-check validate /dist/boot/bin/caddy

RUN           chmod 555 /dist/boot/bin/*; \
              epoch="$(date --date "$BUILD_CREATED" +%s)"; \
              find /dist/boot -newermt "@$epoch" -exec touch --no-dereference --date="@$epoch" '{}' +;

# XXX latest elastic distribution does not seem to include transform-log4j-config anymore - temporarily, log4j2.properties has been updated manually and this is commented out
#RUN           chmod u+w /config/elastic; \
#              /boot/jdk/bin/java -jar bin/transform-log4j-config-*.jar /config/elastic/log4j2.file.properties > /config/elastic/log4j2.properties; \
#              chmod u-w /config/elastic

#######################
# Running image
#######################
FROM          $FROM_REGISTRY/$FROM_IMAGE_RUNTIME

# Elastic: bring in the config as well
COPY          --from=builder-main --chown=$BUILD_UID:root /dist/config /config/elastic

ENV           _SERVICE_NICK="elastic"
ENV           _SERVICE_TYPE="http"

COPY          --from=assembly --chown=$BUILD_UID:root /dist /

### Front server configuration
## Advanced settings that usually should not be changed
# Ports for http and https - recent changes in docker make it no longer necessary to have caps, plus we have our NET_BIND_SERVICE cap set anyhow - it's 2021, there is no reason to keep on venerating privileged ports
ENV           ADVANCED_PORT_HTTPS=443
ENV           ADVANCED_PORT_HTTP=80
EXPOSE        443
EXPOSE        80
# By default, tls should be restricted to 1.3 - you may downgrade to 1.2+ for compatibility with older clients (webdav client on macos, older browsers)
ENV           ADVANCED_TLS_MIN=1.3
# Name advertised by Caddy in the server http header
ENV           ADVANCED_SERVER_NAME="DuboDubonDuponey/1.0 (Caddy/2) [$_SERVICE_NICK]"
# Root certificate to trust for mTLS - this is not used if MTLS is disabled
ENV           ADVANCED_MTLS_TRUST="/certs/mtls_ca.crt"
# Log verbosity for
ENV           LOG_LEVEL="warn"
# Whether to start caddy at all or not
ENV           PROXY_HTTPS_ENABLED=true
# Domain name to serve
ENV           DOMAIN="$_SERVICE_NICK.local"
ENV           ADDITIONAL_DOMAINS=""
# Control wether tls is going to be "internal" (eg: self-signed), or alternatively an email address to enable letsencrypt - use "" to disable TLS entirely
ENV           TLS="internal"
# Issuer name to appear in certificates
#ENV           TLS_ISSUER="Dubo Dubon Duponey"
# Either disable_redirects or ignore_loaded_certs if one wants the redirects
ENV           TLS_AUTO=disable_redirects
# Staging
# https://acme-staging-v02.api.letsencrypt.org/directory
# Plain
# https://acme-v02.api.letsencrypt.org/directory
# PKI
# https://pki.local
ENV           TLS_SERVER="https://acme-v02.api.letsencrypt.org/directory"
# Either require_and_verify or verify_if_given, or "" to disable mTLS altogether
ENV           MTLS="require_and_verify"
# Realm for authentication - set to "" to disable authentication entirely
ENV           AUTH="My Precious Realm"
# Provide username and password here (call the container with the "hash" command to generate a properly encrypted password, otherwise, a random one will be generated)
ENV           AUTH_USERNAME="dubo-dubon-duponey"
ENV           AUTH_PASSWORD="cmVwbGFjZV9tZV93aXRoX3NvbWV0aGluZwo="
### mDNS broadcasting
# Whether to enable MDNS broadcasting or not
ENV           MDNS_ENABLED=true
# Type to advertise
ENV           MDNS_TYPE="_$_SERVICE_TYPE._tcp"
# Name is used as a short description for the service
ENV           MDNS_NAME="$_SERVICE_NICK mDNS display name"
# The service will be annonced and reachable at $MDNS_HOST.local (set to empty string to disable mDNS announces entirely)
ENV           MDNS_HOST="$_SERVICE_NICK"
# Also announce the service as a workstation (for example for the benefit of coreDNS mDNS)
ENV           MDNS_STATION=true
# Caddy certs will be stored here
VOLUME        /certs
# Caddy uses this
VOLUME        /tmp
# Used by the backend service
VOLUME        /data
ENV           HEALTHCHECK_URL="http://127.0.0.1:10000/?healthcheck"

HEALTHCHECK   --interval=120s --timeout=30s --start-period=10s --retries=1 CMD http-health || exit 1
