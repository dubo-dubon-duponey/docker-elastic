#!/usr/bin/env bash
set -o errexit -o errtrace -o functrace -o nounset -o pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]:-$PWD}")" 2>/dev/null 1>&2 && pwd)"
readonly root
# shellcheck source=/dev/null
source "$root/helpers.sh"
# shellcheck source=/dev/null
source "$root/mdns.sh"

helpers::dir::writable "/certs"
helpers::dir::writable "$XDG_DATA_HOME" create
helpers::dir::writable "$XDG_DATA_DIRS" create
helpers::dir::writable "$XDG_RUNTIME_DIR" create
helpers::dir::writable "$XDG_STATE_HOME" create
helpers::dir::writable "$XDG_CACHE_HOME" create

# mDNS blast if asked to
[ ! "${MDNS_HOST:-}" ] || {
  _mdns_port="$([ "$TLS" != "" ] && printf "%s" "${PORT_HTTPS:-443}" || printf "%s" "${PORT_HTTP:-80}")"
  [ ! "${MDNS_STATION:-}" ] || mdns::add "_workstation._tcp" "$MDNS_HOST" "${MDNS_NAME:-}" "$_mdns_port"
  mdns::add "${MDNS_TYPE:-_http._tcp}" "$MDNS_HOST" "${MDNS_NAME:-}" "$_mdns_port"
  mdns::start &
}

# Start the sidecar
start::sidecar &

# This is in the official dockerfile, so...
export ELASTIC_CONTAINER=true

export ES_HOME=/data
export ES_PATH_DATA=/data/data
export ES_PATH_LOGS=/tmp/logs
helpers::dir::writable "$ES_PATH_DATA" create
helpers::dir::writable "$ES_PATH_LOGS" create
helpers::dir::writable "/data/tmp-java" create

# XXX ARRRRR ELASTIC - mutable config???? WHY?
export ES_PATH_CONF=/data/xxx-elastic
rm -Rf "$ES_PATH_CONF"
cp -R /config/elastic "$ES_PATH_CONF"
chmod u+w "$ES_PATH_CONF"

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
export ES_JAVA_OPTS="-Djava.io.tmpdir=/data/tmp-java -Des.cgroups.hierarchy.override=/ ${ES_JAVA_OPTS:-}"

# es_opts+=("-Escript.max_compilations_rate=2048/1m")
elasticsearch "-Epath.data=$ES_PATH_DATA" "-Epath.logs=$ES_PATH_LOGS" "$@"
