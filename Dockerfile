ARG           BUILDER_BASE=dubodubonduponey/base:builder
ARG           RUNTIME_BASE=dubodubonduponey/base:runtime

#######################
# Extra builder for healthchecker
#######################
# hadolint ignore=DL3006,DL3029
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-healthcheck

ARG           GIT_REPO=github.com/dubo-dubon-duponey/healthcheckers
ARG           GIT_VERSION=51ebf8ca3d255e0c846307bf72740f731e6210c3

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone git://$GIT_REPO .
RUN           git checkout $GIT_VERSION
# hadolint ignore=DL4006
RUN           env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" go build -v -ldflags "-s -w" \
                -o /dist/boot/bin/http-health ./cmd/http

#######################
# Building image
#######################
# hadolint ignore=DL3006
FROM          $BUILDER_BASE                                                                                             AS builder

#ENV           ELS_VERSION=7.5.0
#ENV           ELS_AMD64_SHA512=4ac4b2d504ed134c2a68ae1ed610c8c224446702fd83371bfd32242a5460751d48298275c46df609b6239006ca1f52a63cb52600957245bbd89741525ac89a53
#ENV           ELS_VERSION=7.5.2
#ENV           ELS_AMD64_SHA512=a9dfc062f010a73a8774745730465e768d58cf418579f0aef0b0032e6be49285a9077be3d08b729679d1895b97ced3a1b061b075c167c15e6faf08267a179e52
#ENV           ELS_VERSION=7.7.1
#ENV           ELS_AMD64_SHA512=f228f0a8bd60fe10d5959d01934008f205b5567a392ae73602549dcefeedb0918a4607b05c59d6168b232cd0a5225ca461ef4bb0f47097c96ba27df7c12fed97
#ENV           ELS_VERSION=7.8.1
#ENV           ELS_AMD64_SHA512=11c5b8b9e3727bba33141771e12dfb29687e01508c06f087691d284a5de6c543247394a102778b8afb25cab3530340608f2a797524ff1439386241ef4e4d0978
ENV           ELS_VERSION=7.10.0
ENV           ELS_AMD64_SHA512=5c159bdf0d6e140a2bee5fbb1c379fbe23b0ea39b01d715564f02e4674b444b065a8abfda86440229c4b70defa175722c479b60009b7eef7b3de66e2339aacea

RUN           apt-get update -qq \
              && apt-get install -qq --no-install-recommends \
                curl=7.64.0-4+deb10u1

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

# XXX kind of dirty, given ${ES_PATH_DATA} is only defined in the entrypoint script
RUN           sed -i'' -e 's|-XX:HeapDumpPath=data|-XX:HeapDumpPath=/tmp/|' ../config/jvm.options
RUN           sed -i'' -e 's|-XX:ErrorFile=logs/hs_err_pid%p.log|-XX:ErrorFile=/tmp/hs_err_pid%p.log|' ../config/jvm.options
RUN           sed -i'' -e 's|9-:-Xlog:gc\*,gc+age=trace,safepoint:file=logs/gc.log:utctime,pid,tags:filecount=32,filesize=64m|9-:-Xlog:gc*,gc+age=trace,safepoint:file=/tmp/gc.log:utctime,pid,tags:filecount=32,filesize=64m|' ../config/jvm.options

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

# Default volumes for data and tmp, since these are expected to be writable
VOLUME        /config
VOLUME        /data
VOLUME        /tmp

EXPOSE        9200
EXPOSE        9300

HEALTHCHECK --interval=30s --timeout=30s --start-period=10s --retries=1 CMD http-health || exit 1
