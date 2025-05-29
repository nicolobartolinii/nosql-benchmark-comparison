#!/bin/bash
set -xeuo pipefail

if [ "$#" -ne 9 ]; then
    echo "ERROR: Illegal number of parameters. Expected 9." >&2
    echo "Usage: $0 WORKLOAD_NAME REP_NUM RECORD_COUNT OPERATION_COUNT FIELD_COUNT FIELD_LENGTH READ_ALL_FIELDS DB_USER_SUBDIR THREADS" >&2
    exit 1
fi

WORKLOAD_NAME="$1"
REP_NUM="$2"
RECORD_COUNT="$3"
OPERATION_COUNT="$4"
FIELD_COUNT="$5"
FIELD_LENGTH="$6"
READ_ALL_FIELDS_BOOL="$7"
DB_USER_SUBDIR="$8"
THREADS="$9"

DB_NAME="cassandra"
CASSANDRA_BATCH_SIZE=100
REPLICATION_FACTOR=3 
READ_CONSISTENCY="QUORUM"
WRITE_CONSISTENCY="QUORUM"
KEYSPACE_NAME="ycsb"
TABLE_NAME="usertable"
YCSB_PATH="./bin/ycsb"
WORKLOAD_PATH_PREFIX="workloads/"

[ -z "${CASS_HOSTS-}" ] && { echo "ERROR: CASS_HOSTS not set for ${DB_NAME}" >&2; exit 1; }
CQLSH_HOST=$(echo "${CASS_HOSTS}" | cut -d, -f1)

echo "INFO [${DB_NAME}]: Starting test run for ${WORKLOAD_NAME}, Rep ${REP_NUM}, Threads ${THREADS}"
echo "INFO [${DB_NAME}]: Params: RC=${RECORD_COUNT}, OC=${OPERATION_COUNT}, FC=${FIELD_COUNT}, FL=${FIELD_LENGTH}, RAF=${READ_ALL_FIELDS_BOOL}, Threads=${THREADS}, UserSubdir=${DB_USER_SUBDIR}"

GENERATED_TIMESTAMP=$(date -u -d "+2 hours" +%Y-%m-%d_%H-%M-%S)
OUTPUT_SUBDIR_PARAMS="rc${RECORD_COUNT}_oc${OPERATION_COUNT}_fc${FIELD_COUNT}_fl${FIELD_LENGTH}_raf${READ_ALL_FIELDS_BOOL}_th${THREADS}"
OUTPUT_DIR="/results/${DB_USER_SUBDIR}/${DB_NAME}/${WORKLOAD_NAME}/${OUTPUT_SUBDIR_PARAMS}"

echo "INFO [${DB_NAME}]: Creating output directory: ${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"

execute_cql_or_exit() {
    local host="$1"
    local cql_command="$2"
    local description="$3"
    local ignore_failure="${4:-false}"
    local output
    local exit_code=0
    echo "INFO [${DB_NAME}]: Attempting CQL (${description}) on host ${host}: ${cql_command}"
    output=$(cqlsh "${host}" -e "${cql_command}" 2>&1) || exit_code=$?
    echo "--- CQL Output (${description}) ---"
    echo "${output}"
    echo "--- End CQL Output (${description}) --- (Exit code: ${exit_code})"
    if [ ${exit_code} -ne 0 ]; then
        echo "ERROR [${DB_NAME}]: CQL command (${description}) failed with exit code ${exit_code}!"
        if [ "$ignore_failure" = "false" ]; then
            echo "ERROR [${DB_NAME}]: Script terminating due to CQL failure."
            exit 1
        else
            echo "WARN [${DB_NAME}]: Failure ignored as requested for ${description}."
        fi
    fi
    return ${exit_code} 
}

echo "INFO [${DB_NAME}]: Preparing Cassandra Schema (Host: ${CQLSH_HOST})..."
if ! command -v cqlsh &> /dev/null; then echo "ERROR [${DB_NAME}]: 'cqlsh' not found!" >&2; exit 1; fi
cqlsh --version

execute_cql_or_exit "${CQLSH_HOST}" "DROP KEYSPACE IF EXISTS ${KEYSPACE_NAME};" "Drop Keyspace" true
echo "INFO [${DB_NAME}]: Waiting after DROP KEYSPACE (allow propagation across nodes if any)..."
sleep 20

CREATE_KEYSPACE_CQL="CREATE KEYSPACE IF NOT EXISTS ${KEYSPACE_NAME} WITH replication = {'class': 'SimpleStrategy', 'replication_factor': '${REPLICATION_FACTOR}'};"
execute_cql_or_exit "${CQLSH_HOST}" "${CREATE_KEYSPACE_CQL}" "Create Keyspace"
echo "INFO [${DB_NAME}]: Waiting after CREATE KEYSPACE..."
sleep 15

MAX_CHECKS=5; CHECK_COUNT=0; KEYSPACE_FOUND=false
while [ "${KEYSPACE_FOUND}" = "false" ] && [ ${CHECK_COUNT} -lt ${MAX_CHECKS} ]; do
    echo "INFO [${DB_NAME}]: Verifying keyspace ${KEYSPACE_NAME} (Attempt $((CHECK_COUNT+1))/${MAX_CHECKS})..."
    set +e; cqlsh "${CQLSH_HOST}" -e "DESCRIBE KEYSPACE ${KEYSPACE_NAME};" >/dev/null 2>&1; check_exit_code=$?; set -e
    if [ ${check_exit_code} -eq 0 ]; then KEYSPACE_FOUND=true; echo "INFO [${DB_NAME}]: Keyspace ${KEYSPACE_NAME} confirmed."; else
        echo "WARN [${DB_NAME}]: Keyspace not yet confirmed. Waiting 15s..."; sleep 15; CHECK_COUNT=$((CHECK_COUNT+1)); fi
done
if [ "${KEYSPACE_FOUND}" = "false" ]; then echo "ERROR [${DB_NAME}]: Keyspace ${KEYSPACE_NAME} not found after multiple checks!" >&2; exit 1; fi

CREATE_TABLE_CQL="CREATE TABLE IF NOT EXISTS ${KEYSPACE_NAME}.${TABLE_NAME} (y_id varchar PRIMARY KEY, field0 varchar, field1 varchar, field2 varchar, field3 varchar, field4 varchar, field5 varchar, field6 varchar, field7 varchar, field8 varchar, field9 varchar) WITH default_time_to_live = 0;"
execute_cql_or_exit "${CQLSH_HOST}" "${CREATE_TABLE_CQL}" "Create Table"
echo "INFO [${DB_NAME}]: Waiting after CREATE TABLE..."
sleep 10
echo "INFO [${DB_NAME}]: Cassandra schema preparation completed."

LOAD_OUTPUT_FILE="${OUTPUT_DIR}/load_rep${REP_NUM}_${GENERATED_TIMESTAMP}.txt"
echo "INFO [${DB_NAME}]: Esecuzione LOAD. Output: ${LOAD_OUTPUT_FILE}"
"${YCSB_PATH}" load cassandra-cql -s -threads "${THREADS}" \
    -P "${WORKLOAD_PATH_PREFIX}${WORKLOAD_NAME}" \
            -p hosts="${CASS_HOSTS}" \
    -p recordcount="${RECORD_COUNT}" \
    -p operationcount="${OPERATION_COUNT}" \
    -p fieldcount="${FIELD_COUNT}" \
    -p fieldlength="${FIELD_LENGTH}" \
    -p readallfields="${READ_ALL_FIELDS_BOOL}" \
            -p cassandra.batchsize=${CASSANDRA_BATCH_SIZE} \
    -p cassandra.keyspace="${KEYSPACE_NAME}" \
    -p cassandra.table="${TABLE_NAME}" \
    -p cassandra.readconsistencylevel="${READ_CONSISTENCY}" \
    -p cassandra.writeconsistencylevel="${WRITE_CONSISTENCY}" \
            > "${LOAD_OUTPUT_FILE}" 2>&1

        if ! grep -q "\[OVERALL\], RunTime(ms)" "${LOAD_OUTPUT_FILE}"; then
    echo "ERROR [${DB_NAME}]: LOAD fallito per ${WORKLOAD_NAME}, Rep ${REP_NUM}, Threads ${THREADS}. Vedi ${LOAD_OUTPUT_FILE}"
    tail -n 30 "${LOAD_OUTPUT_FILE}" 
        fi
        echo "INFO [${DB_NAME}]: LOAD completato."

RUN_OUTPUT_FILE="${OUTPUT_DIR}/run_rep${REP_NUM}_${GENERATED_TIMESTAMP}.txt"
echo "INFO [${DB_NAME}]: Esecuzione RUN. Output: ${RUN_OUTPUT_FILE}"
"${YCSB_PATH}" run cassandra-cql -s -threads "${THREADS}" \
    -P "${WORKLOAD_PATH_PREFIX}${WORKLOAD_NAME}" \
            -p hosts="${CASS_HOSTS}" \
    -p recordcount="${RECORD_COUNT}" \
    -p operationcount="${OPERATION_COUNT}" \
    -p fieldcount="${FIELD_COUNT}" \
    -p fieldlength="${FIELD_LENGTH}" \
    -p readallfields="${READ_ALL_FIELDS_BOOL}" \
    -p cassandra.keyspace="${KEYSPACE_NAME}" \
    -p cassandra.table="${TABLE_NAME}" \
    -p cassandra.readconsistencylevel="${READ_CONSISTENCY}" \
    -p cassandra.writeconsistencylevel="${WRITE_CONSISTENCY}" \
            > "${RUN_OUTPUT_FILE}" 2>&1

        if ! grep -q "\[OVERALL\], RunTime(ms)" "${RUN_OUTPUT_FILE}"; then
    echo "ERROR [${DB_NAME}]: RUN fallito per ${WORKLOAD_NAME}, Rep ${REP_NUM}, Threads ${THREADS}. Vedi ${RUN_OUTPUT_FILE}"
        fi
        echo "INFO [${DB_NAME}]: RUN completato."

echo "INFO [${DB_NAME}]: Test run ${WORKLOAD_NAME}, Rep ${REP_NUM}, Threads ${THREADS} completato."