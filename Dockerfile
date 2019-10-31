
#RUN mkdir -p config data logs
#RUN chmod 0775 config data logs
#COPY runtime/config/elasticsearch.yml runtime/config/log4j2.properties config/


#######################
# Building image
#######################
FROM          dubodubonduponey/base:builder                                                                             AS builder

ENV           ELS_VERSION=7.4.0
ENV           ELS_AMD64_SHA512=bfd96df61f8b745dce2e665dfe326f021ffdf080853aa02ca7d4bc2f5e40b949fe566fe6aacc628580b8ca421866b86eeb2f694b14b08f47ebb9e1350d18ecc3

WORKDIR       /build/elastic

RUN           set -eu; \
              curl -k -fsSL -o kbn.tgz "https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-${ELS_VERSION}-linux-x86_64.tar.gz"; \
              printf "%s *kbn.tgz" "$ELS_AMD64_SHA512" | sha512sum -c -; \
              tar --strip-components=1 -zxf kbn.tgz; \
              rm kbn.tgz

RUN           grep ES_DISTRIBUTION_TYPE=tar bin/elasticsearch-env     && sed -ie 's/ES_DISTRIBUTION_TYPE=tar/ES_DISTRIBUTION_TYPE=docker/' bin/elasticsearch-env

#######################
# Extra builder for healthchecker
#######################
FROM          --platform=$BUILDPLATFORM dubodubonduponey/base:builder         AS builder-healthcheck

ARG           HEALTH_VER=51ebf8ca3d255e0c846307bf72740f731e6210c3

WORKDIR       $GOPATH/src/github.com/dubo-dubon-duponey/healthcheckers
RUN           git clone git://github.com/dubo-dubon-duponey/healthcheckers .
RUN           git checkout $HEALTH_VER
RUN           arch="${TARGETPLATFORM#*/}"; \
              env GOOS=linux GOARCH="${arch%/*}" go build -v -ldflags "-s -w" -o /dist/bin/http-health ./cmd/http

RUN           chmod 555 /dist/bin/*

#######################
# Running image
#######################
FROM          dubodubonduponey/base:runtime

USER          root

RUN           apt-get update              > /dev/null && \
              apt-get install -y --no-install-recommends \
                nodejs=10.15.2~dfsg-2 \
                fontconfig=2.13.1-2 \
                libfreetype6=2.9.1-3      > /dev/null && \
              apt-get -y autoremove       > /dev/null && \
              apt-get -y clean            && \
              rm -rf /var/lib/apt/lists/* && \
              rm -rf /tmp/*               && \
              rm -rf /var/tmp/*

USER          dubo-dubon-duponey

COPY          --from=builder --chown=$BUILD_UID:0 /build/elastic /boot
COPY          --from=builder-healthcheck  /dist/bin/http-health ./bin/

# Set some Kibana configuration defaults.
ENV           ELASTIC_CONTAINER true

#ENV           SERVER_NAME elasticsearch
#ENV           SERVER_HOST elasticsearch

ENV           HEALTHCHECK_URL="http://127.0.0.1:9200"
ENV           PATH=/boot/bin:$PATH

VOLUME        /data

# Default volumes for data and certs, since these are expected to be writable
EXPOSE        9200
EXPOSE        9300

HEALTHCHECK --interval=30s --timeout=30s --start-period=10s --retries=1 CMD http-health || exit 1
