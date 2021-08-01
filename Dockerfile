ARG           FROM_REGISTRY=ghcr.io/dubo-dubon-duponey

ARG           FROM_IMAGE_BUILDER=base:builder-bullseye-2021-07-01@sha256:f1c46316c38cc1ca54fd53b54b73797b35ba65ee727beea1a5ed08d0ad7e8ccf
ARG           FROM_IMAGE_RUNTIME=base:runtime-bullseye-2021-07-01@sha256:9f5b20d392e1a1082799b3befddca68cee2636c72c502aa7652d160896f85b36

#######################
# Main builder
#######################
FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_BUILDER                                              AS builder-main

ARG           TARGETARCH
ARG           TARGETOS
ARG           TARGETVARIANT

# Note that this is tied to x86_64 and not a proper multi-arch image
ENV           VERSION=7.13.4
ENV           AMD64_SHA512=510c0ce8af12ccc143b18e73d84047052376cd203f3a913af03baaeb26ffaedfffddd5c4477e5bce84aaf0aaaa436fef4c8012165fc9aa9895518f21cb84c28b
ENV           AARCH64_SHA512=d170517a3ddb47a6113dfe3f2657660782252e98ce799d5b6b6095724edab2fec597c49915fa1f9b8f0888c21fac342441e8d25df10519605523b23b48150985

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
FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_BUILDER                                              AS builder

COPY          --from=builder-main   /dist/boot           /dist/boot

COPY          --from=builder-tools  /boot/bin/goello-server  /dist/boot/bin
COPY          --from=builder-tools  /boot/bin/caddy          /dist/boot/bin
COPY          --from=builder-tools  /boot/bin/http-health    /dist/boot/bin

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

ENV           NICK="elastic"

COPY          --from=builder --chown=$BUILD_UID:root /dist /

### Front server configuration
# Port to use
ENV           PORT=4443
EXPOSE        4443
# Log verbosity for
ENV           LOG_LEVEL="warn"
# Domain name to serve
ENV           DOMAIN="$NICK.local"
# Control wether tls is going to be "internal" (eg: self-signed), or alternatively an email address to enable letsencrypt
ENV           TLS="internal"
# Either require_and_verify or verify_if_given
ENV           MTLS_MODE="verify_if_given"

# Realm in case access is authenticated
ENV           REALM="My Precious Realm"
# Provide username and password here (call the container with the "hash" command to generate a properly encrypted password, otherwise, a random one will be generated)
ENV           USERNAME=""
ENV           PASSWORD=""

### mDNS broadcasting
# Enable/disable mDNS support
ENV           MDNS_ENABLED=false
# Name is used as a short description for the service
ENV           MDNS_NAME="mDNS display name"
# The service will be annonced and reachable at $MDNS_HOST.local
ENV           MDNS_HOST="$NICK"
# Type to advertise
ENV           MDNS_TYPE="_http._tcp"

# Caddy certs will be stored here
VOLUME        /certs

# Caddy uses this
VOLUME        /tmp

# Used by the backend service
VOLUME        /data

ENV           HEALTHCHECK_URL="http://127.0.0.1:10000/?healthcheck"

HEALTHCHECK   --interval=120s --timeout=30s --start-period=10s --retries=1 CMD http-health || exit 1
