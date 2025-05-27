#!/bin/bash
set -euo pipefail

# --- Script Parameters (Passed as arguments) ---
# $1: WORKLOAD_NAME
# $2: REP_NUM
# $3: RECORD_COUNT
# $4: OPERATION_COUNT
# $5: FIELD_COUNT
# $6: FIELD_LENGTH
# $7: READ_ALL_FIELDS (true/false)
# $8: DB_USER_SUBDIR
# $9: THREADS

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

# --- Static Redis Config ---
DB_NAME="redis"
YCSB_PATH="./bin/ycsb"
WORKLOAD_PATH_PREFIX="workloads/"

# --- Environment Check ---
[ -z "${REDIS_NODES-}" ] && { echo "ERROR: REDIS_NODES not set for ${DB_NAME}" >&2; exit 1; }
echo "DEBUG [${DB_NAME}]: Received REDIS_NODES='${REDIS_NODES}'"

echo "INFO [${DB_NAME}]: Starting test run for ${WORKLOAD_NAME}, Rep ${REP_NUM}, Threads ${THREADS}"
echo "INFO [${DB_NAME}]: Params: RC=${RECORD_COUNT}, OC=${OPERATION_COUNT}, FC=${FIELD_COUNT}, FL=${FIELD_LENGTH}, RAF=${READ_ALL_FIELDS_BOOL}, Threads=${THREADS}, UserSubdir=${DB_USER_SUBDIR}"

# --- Timestamp & Output Dir ---
GENERATED_TIMESTAMP=$(date -u -d "+2 hours" +%Y-%m-%d_%H-%M-%S)
OUTPUT_SUBDIR_PARAMS="rc${RECORD_COUNT}_oc${OPERATION_COUNT}_fc${FIELD_COUNT}_fl${FIELD_LENGTH}_raf${READ_ALL_FIELDS_BOOL}_th${THREADS}"
OUTPUT_DIR="/results/${DB_USER_SUBDIR}/${DB_NAME}/${WORKLOAD_NAME}/${OUTPUT_SUBDIR_PARAMS}"

echo "INFO [${DB_NAME}]: Creating output directory: ${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"

# Note: Redis data is flushed by tearing down and restarting the cluster in the orchestrator script.
# No explicit FLUSHALL needed here if orchestrator handles docker compose down -v / up.

# --- YCSB Load Phase ---
LOAD_OUTPUT_FILE="${OUTPUT_DIR}/load_rep${REP_NUM}_${GENERATED_TIMESTAMP}.txt"
echo "INFO [${DB_NAME}]: Esecuzione LOAD. Output: ${LOAD_OUTPUT_FILE}"
"${YCSB_PATH}" load redis -s -threads "${THREADS}" \
    -P "${WORKLOAD_PATH_PREFIX}${WORKLOAD_NAME}" \
            -p redis.hosts="${REDIS_NODES}" \
            -p redis.cluster=true \
    -p recordcount="${RECORD_COUNT}" \
    -p operationcount="${OPERATION_COUNT}" \
    -p fieldcount="${FIELD_COUNT}" \
    -p fieldlength="${FIELD_LENGTH}" \
    -p readallfields="${READ_ALL_FIELDS_BOOL}" \
            > "${LOAD_OUTPUT_FILE}" 2>&1

        if ! grep -q "\[OVERALL\], RunTime(ms)" "${LOAD_OUTPUT_FILE}"; then
    echo "ERROR [${DB_NAME}]: LOAD fallito per ${WORKLOAD_NAME}, Rep ${REP_NUM}, Threads ${THREADS}. Vedi ${LOAD_OUTPUT_FILE}"
            tail -n 20 "${LOAD_OUTPUT_FILE}"
        fi
        echo "INFO [${DB_NAME}]: LOAD completato."

# --- YCSB Run Phase ---
RUN_OUTPUT_FILE="${OUTPUT_DIR}/run_rep${REP_NUM}_${GENERATED_TIMESTAMP}.txt"
echo "INFO [${DB_NAME}]: Esecuzione RUN. Output: ${RUN_OUTPUT_FILE}"
"${YCSB_PATH}" run redis -s -threads "${THREADS}" \
    -P "${WORKLOAD_PATH_PREFIX}${WORKLOAD_NAME}" \
            -p redis.hosts="${REDIS_NODES}" \
            -p redis.cluster=true \
    -p recordcount="${RECORD_COUNT}" \
    -p operationcount="${OPERATION_COUNT}" \
    -p fieldcount="${FIELD_COUNT}" \
    -p fieldlength="${FIELD_LENGTH}" \
    -p readallfields="${READ_ALL_FIELDS_BOOL}" \
            > "${RUN_OUTPUT_FILE}" 2>&1

        if ! grep -q "\[OVERALL\], RunTime(ms)" "${RUN_OUTPUT_FILE}"; then
    echo "ERROR [${DB_NAME}]: RUN fallito per ${WORKLOAD_NAME}, Rep ${REP_NUM}, Threads ${THREADS}. Vedi ${RUN_OUTPUT_FILE}"
            tail -n 20 "${RUN_OUTPUT_FILE}"
        fi
        echo "INFO [${DB_NAME}]: RUN completato."

echo "INFO [${DB_NAME}]: Test run ${WORKLOAD_NAME}, Rep ${REP_NUM}, Threads ${THREADS} completato."