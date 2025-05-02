#!/bin/bash
set -euo pipefail
./bin/ycsb load cassandra-cql -s -P workloads/workloada -p hosts=$CASS_HOSTS \
  && ./bin/ycsb run cassandra-cql -s -P workloads/workloada -p hosts=$CASS_HOSTS > /results/cassandra_$(date +%s).txt
