#!/usr/bin/env bash
set -o errexit -o errtrace -o functrace -o nounset -o pipefail

ELASTIC_PASSWORD="${ELASTIC_PASSWORD:-}"

# Files created by Elasticsearch should always be group writable too
umask 0002

# Parse Docker env vars to customize Elasticsearch
#
# e.g. Setting the env var cluster.name=testcluster
#
# will cause Elasticsearch to be invoked with -Ecluster.name=testcluster
#
# see https://www.elastic.co/guide/en/elasticsearch/reference/current/settings.html#_setting_default_settings

es_opts=()

while IFS='=' read -r envvar_key envvar_value
do
  # Elasticsearch settings need to have at least two dot separated lowercase
  # words, e.g. `cluster.name`, except for `processors` which we handle
  # specially
  if [[ "$envvar_key" =~ ^[a-z0-9_]+\.[a-z0-9_]+ || "$envvar_key" == "processors" ]]; then
    if [[ ! -z $envvar_value ]]; then
      es_opt="-E${envvar_key}=${envvar_value}"
      es_opts+=("${es_opt}")
    fi
  fi
done < <(env)

# ES_HOME=...
export ES_PATH_CONF=/config
export ES_PATH_DATA=/data/data
export ES_PATH_LOGS=/data/logs
mkdir -p /data/data
mkdir -p /data/logs

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
export ES_JAVA_OPTS="-Des.cgroups.hierarchy.override=/ $ES_JAVA_OPTS"

if [[ -f bin/elasticsearch-users ]]; then
  # Check for the ELASTIC_PASSWORD environment variable to set the
  # bootstrap password for Security.
  #
  # This is only required for the first node in a cluster with Security
  # enabled, but we have no way of knowing which node we are yet. We'll just
  # honor the variable if it's present.
  if [[ -n "$ELASTIC_PASSWORD" ]]; then
    [[ -f /config/elasticsearch.keystore ]] || (exec elasticsearch-keystore create)
    if ! (exec elasticsearch-keystore list | grep -q '^bootstrap.password$'); then
      (exec echo "$ELASTIC_PASSWORD" | elasticsearch-keystore add -x 'bootstrap.password')
    fi
  fi
fi

exec elasticsearch "${es_opts[@]}"
