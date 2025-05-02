#!/bin/bash
set -euo pipefail

[ -z "${REDIS_NODES-}" ] && { echo "ERROR: REDIS_NODES non definita" >&2; exit 1; }

# launch load
./bin/ycsb load redis -s \
  -P workloads/workloada \
  -p redis.cluster=true \
  -p redis.hosts="$REDIS_NODES"

# launch run
./bin/ycsb run redis -s \
  -P workloads/workloada \
  -p redis.cluster=true \
  -p redis.hosts="$REDIS_NODES" \
  > /results/redis_$(date +%s).txt

