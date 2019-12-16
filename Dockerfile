#######################
# Extra builder for healthchecker
#######################
ARG           BUILDER_BASE=dubodubonduponey/base:builder
ARG           RUNTIME_BASE=dubodubonduponey/base:runtime
# hadolint ignore=DL3006
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-healthcheck

ARG           HEALTH_VER=51ebf8ca3d255e0c846307bf72740f731e6210c3

WORKDIR       $GOPATH/src/github.com/dubo-dubon-duponey/healthcheckers
RUN           git clone git://github.com/dubo-dubon-duponey/healthcheckers .
RUN           git checkout $HEALTH_VER
RUN           arch="${TARGETPLATFORM#*/}"; \
              env GOOS=linux GOARCH="${arch%/*}" go build -v -ldflags "-s -w" -o /dist/boot/bin/http-health ./cmd/http

#######################
# Building image
#######################
# hadolint ignore=DL3006
FROM          $BUILDER_BASE                                                                                             AS builder

ENV           ELS_VERSION=7.5.0
ENV           ELS_AMD64_SHA512=4ac4b2d504ed134c2a68ae1ed610c8c224446702fd83371bfd32242a5460751d48298275c46df609b6239006ca1f52a63cb52600957245bbd89741525ac89a53

WORKDIR       /dist/boot

# hadolint ignore=DL4006
RUN           set -eu; \
              curl -k -fsSL -o archive.tgz "https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-${ELS_VERSION}-linux-x86_64.tar.gz"; \
              printf "Downloaded shasum: %s\n" "$(sha512sum archive.tgz)"; \
              printf "%s *archive.tgz" "$ELS_AMD64_SHA512" | sha512sum -c -; \
              tar --strip-components=1 -zxf archive.tgz; \
              rm archive.tgz; \
              mv config ../; \
              rm ../config/log4j2.properties

RUN           grep ES_DISTRIBUTION_TYPE=tar bin/elasticsearch-env     && sed -ie 's/ES_DISTRIBUTION_TYPE=tar/ES_DISTRIBUTION_TYPE=docker/' bin/elasticsearch-env

COPY          --from=builder-healthcheck /dist/boot/bin           /dist/boot/bin

RUN           chmod 555 /dist/boot/bin/*

#######################
# Running image
#######################
# hadolint ignore=DL3006
FROM          $RUNTIME_BASE

COPY          --from=builder --chown=$BUILD_UID:root /dist .

# Set some Kibana configuration defaults.
ENV           cluster.name "docker-cluster"
ENV           network.host 0.0.0.0
ENV           discovery.type single-node
ENV           ELASTIC_CONTAINER true

ENV           HEALTHCHECK_URL="http://127.0.0.1:9200"

# Default volumes for data and certs, since these are expected to be writable
VOLUME        /data

EXPOSE        9200
EXPOSE        9300

HEALTHCHECK --interval=30s --timeout=30s --start-period=10s --retries=1 CMD http-health || exit 1
