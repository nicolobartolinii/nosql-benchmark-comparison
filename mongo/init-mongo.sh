#!/bin/bash
# mongo/init-mongo.sh

echo "Starting initialization script..."
MAX_RETRIES=30
RETRY_INTERVAL=5

wait_for_mongo() {
  HOST=$1
  PORT=$2
  echo "Waiting for MongoDB to be ready at ${HOST}:${PORT}..."
  retries=0
  until mongo --host "${HOST}" --port "${PORT}" --eval "db.adminCommand('ping')" &>/dev/null; do
    retries=$((retries + 1))
    if [ $retries -ge $MAX_RETRIES ]; then
      echo "MongoDB at ${HOST}:${PORT} did not become ready after ${MAX_RETRIES} retries."
      exit 1
    fi
    echo "Retrying connection to ${HOST}:${PORT} (${retries}/${MAX_RETRIES})..."
    sleep $RETRY_INTERVAL
  done
  echo "MongoDB at ${HOST}:${PORT} is ready."
}

echo "All MongoDB instances seem to be running based on docker-compose healthchecks/depends_on."
sleep 10

echo "Attempting to initiate Config Server Replica Set 'cfgRS'..."
mongo --host cfg1 --port 27019 <<EOF
rs.initiate(
  {
    _id: "cfgRS",
    configsvr: true,
    members: [
      { _id : 0, host : "cfg1:27019" },
      { _id : 1, host : "cfg2:27019" },
      { _id : 2, host : "cfg3:27019" }
    ]
  }
)
EOF
echo "Config Server initialization command sent."
sleep 5

echo "Attempting to initiate Shard Replica Set 'shard1RS'..."
mongo --host shard1a --port 27018 <<EOF
rs.initiate(
  {
    _id: "shard1RS",
    members: [
      { _id : 0, host : "shard1a:27018" },
      { _id : 1, host : "shard1b:27018" },
      { _id : 2, host : "shard1c:27018" }
    ]
  }
)
EOF
echo "Shard initialization command sent."
sleep 5

echo "Waiting for mongos router to be fully ready..."
retries=0
until mongo --host mongos --port 27017 --eval "sh.getBalancerState()" &>/dev/null; do
 retries=$((retries + 1))
 if [ $retries -ge $MAX_RETRIES ]; then
   echo "Mongos router did not become ready after ${MAX_RETRIES} retries."
   break
 fi
 echo "Retrying connection to mongos (${retries}/${MAX_RETRIES})..."
 sleep $RETRY_INTERVAL
done
if [ $retries -lt $MAX_RETRIES ]; then
  echo "Mongos router is ready."
else
  echo "WARNING: Mongos router may not be fully ready, proceeding with addShard anyway..."
fi
sleep 5

echo "Attempting to add shard 'shard1RS' to the cluster via mongos..."
SHARD_ALREADY_ADDED=$(mongo --host mongos --port 27017 --quiet --eval 'sh.status().shards.some(shard => shard._id === "shard1RS")')

if [ "$SHARD_ALREADY_ADDED" = "true" ]; then
  echo "Shard 'shard1RS' is already part of the cluster. Skipping addShard."
else
  mongo --host mongos --port 27017 <<EOF
sh.addShard("shard1RS/shard1a:27018,shard1b:27018,shard1c:27018")
EOF
  ADD_SHARD_STATUS=$?
  if [ $ADD_SHARD_STATUS -eq 0 ]; then
    echo "Shard 'shard1RS' added successfully."
  else
    echo "Failed to add shard 'shard1RS'. Exit code: $ADD_SHARD_STATUS. Check mongos logs."
  fi
fi

echo "Initialization script finished."
exit 0
