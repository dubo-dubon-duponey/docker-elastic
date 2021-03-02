#!/usr/bin/env bash
set -o errexit -o errtrace -o functrace -o nounset -o pipefail

[ -w "/certs" ] || {
  printf >&2 "/certs is not writable. Check your mount permissions.\n"
  exit 1
}

[ -w "/tmp" ] || {
  printf >&2 "/tmp is not writable. Check your mount permissions.\n"
  exit 1
}

[ -w "/data" ] || {
  printf >&2 "/data is not writable. Check your mount permissions.\n"
  exit 1
}

# Helpers
case "${1:-}" in
  # Short hand helper to generate password hash
  "hash")
    shift
    printf >&2 "Generating password hash\n"
    caddy hash-password -algorithm bcrypt "$@"
    exit
  ;;
  # Helper to get the ca.crt out (once initialized)
  "cert")
    if [ "$TLS" == "" ]; then
      echo "Your container is not configured for TLS termination - there is no local CA in that case."
      exit 1
    fi
    if [ "$TLS" != internal ]; then
      echo "Your container uses letsencrypt - there is no local CA in that case."
      exit 1
    fi
    if [ ! -e "/certs/pki/authorities/local/root.crt" ]; then
      echo "No root certificate installed or generated. Run the container so that a cert is generated, or provide one at runtime."
      exit 1
    fi
    cat /certs/pki/authorities/local/root.crt
    exit
  ;;
esac

# Bonjour the container if asked to. While the PORT is no guaranteed to be mapped on the host in bridge, this does not matter since mDNS will not work at all in bridge mode.
if [ "${MDNS_ENABLED:-}" == true ]; then
  goello-server -name "$MDNS_NAME" -host "$MDNS_HOST" -port "$PORT" -type "$MDNS_TYPE" &
fi

# Given how the caddy conf is set right now, we cannot have these be not set, so, stuff in randomized shit in there in case there is nothing
readonly USERNAME="${USERNAME:-"$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 64)"}"
readonly PASSWORD="${PASSWORD:-$(caddy hash-password -algorithm bcrypt -plaintext "$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 64)")}"

# If we want TLS and authentication, start caddy in the background
if [ "$TLS" ]; then
  HOME=/tmp/caddy-home exec caddy run -config /config/caddy/main.conf --adapter caddyfile &
fi

# This is in the official dockerfile, so...
export ELASTIC_CONTAINER=true

# Parse Docker env vars to customize Elasticsearch
#
# e.g. Setting the env var cluster.name=testcluster
#
# will cause Elasticsearch to be invoked with -Ecluster.name=testcluster
#
# see https://www.elastic.co/guide/en/elasticsearch/reference/current/settings.html#_setting_default_settings

export ES_HOME=/data
# XXX ARRRRR ELASTIC - mutable config???? WHY?
export ES_PATH_CONF=/data/xxx-elastic
export ES_PATH_DATA=/data/data
export ES_PATH_LOGS=/tmp/logs

mkdir -p "$ES_PATH_DATA"
mkdir -p "$ES_PATH_LOGS"
mkdir -p /tmp/java

rm -Rf "$ES_PATH_CONF"
cp -R /config/elastic "$ES_PATH_CONF"
chmod u+w "$ES_PATH_CONF"

es_opts+=("-Epath.data=/data/data")
es_opts+=("-Epath.logs=/tmp/logs")
# es_opts+=("-Escript.max_compilations_rate=2048/1m")

# The virtual file /proc/self/cgroup should list the current cgroup
# membership. For each hierarchy, you can follow the cgroup path from
# this file to the cgroup filesystem (usually /sys/fs/cgroup/) and
# introspect the statistics for the cgroup for the given
# hierarchy. Alas, Docker breaks this by mounting the container
# statistics at the root while leaving the cgroup paths as the actual
# paths. Therefore, Elasticsearch provides a mechanism to override
# reading the cgroup path from /proc/self/cgroup and instead uses the
# cgroup path defined the JVM system property
# es.cgroups.hierarchy.override. Therefore, we set this value here so
# that cgroup statistics are available for the container this process
# will run in.
# -Djava.io.tmpdir=/tmp
export ES_JAVA_OPTS="-Djava.io.tmpdir=/tmp/java -Des.cgroups.hierarchy.override=/ ${ES_JAVA_OPTS:-}"

elasticsearch "${es_opts[@]}" "$@"
