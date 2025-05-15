#!/bin/bash
set -euo pipefail

# --- Script Parameters (Passed as arguments) ---
# $1: WORKLOAD_NAME (e.g., workloada)
# $2: REP_NUM (e.g., 1)
# $3: RECORD_COUNT
# $4: OPERATION_COUNT
# $5: FIELD_COUNT
# $6: FIELD_LENGTH
# $7: READ_ALL_FIELDS (true/false)
# $8: DB_USER_SUBDIR (e.g., nicolò)

if [ "$#" -ne 8 ]; then
    echo "ERROR: Illegal number of parameters. Expected 8." >&2
    echo "Usage: $0 WORKLOAD_NAME REP_NUM RECORD_COUNT OPERATION_COUNT FIELD_COUNT FIELD_LENGTH READ_ALL_FIELDS DB_USER_SUBDIR" >&2
    exit 1
fi

WORKLOAD_NAME="$1"
REP_NUM="$2"
RECORD_COUNT="$3"
OPERATION_COUNT="$4"
FIELD_COUNT="$5"
FIELD_LENGTH="$6"
READ_ALL_FIELDS_BOOL="$7" # String 'true' or 'false'
DB_USER_SUBDIR="$8"

# --- Static Config ---
DB_NAME="mongo"
MONGO_BATCH_SIZE=500
YCSB_PATH="./bin/ycsb" # Path to YCSB executable
WORKLOAD_PATH_PREFIX="workloads/" # Path to YCSB workload files

# --- Environment Check ---
[ -z "${MONGO_URL-}" ] && { echo "ERROR: MONGO_URL not set for ${DB_NAME}" >&2; exit 1; }
MONGO_HOST_FOR_CLEANUP=$(echo "${MONGO_URL}" | sed -n 's_mongodb://\([^:]*\):.*_\1_p')
[ -z "${MONGO_HOST_FOR_CLEANUP}" ] && { echo "ERROR: Impossibile estrarre MONGO_HOST_FOR_CLEANUP da MONGO_URL" >&2; exit 1; }

echo "INFO [${DB_NAME}]: Starting test run for ${WORKLOAD_NAME}, Rep ${REP_NUM}"
echo "INFO [${DB_NAME}]: Params: RC=${RECORD_COUNT}, OC=${OPERATION_COUNT}, FC=${FIELD_COUNT}, FL=${FIELD_LENGTH}, RAF=${READ_ALL_FIELDS_BOOL}, UserSubdir=${DB_USER_SUBDIR}"

# --- Timestamp & Output Dir ---
# Generate timestamp (UTC + 2 hours, YYYY-MM-DD_HH-MM-SS format)
# For busybox date (in alpine): date -D '%Y-%m-%dT%H:%M:%SZ' -d "$(date -u -Iseconds)+2 hours" +%Y-%m-%d_%H-%M-%S
# For GNU date:
GENERATED_TIMESTAMP=$(date -u -d "+2 hours" +%Y-%m-%d_%H-%M-%S)

OUTPUT_SUBDIR_PARAMS="rc${RECORD_COUNT}_oc${OPERATION_COUNT}_fc${FIELD_COUNT}_fl${FIELD_LENGTH}_raf${READ_ALL_FIELDS_BOOL}"
OUTPUT_DIR="/results/${DB_USER_SUBDIR}/${DB_NAME}/${WORKLOAD_NAME}/${OUTPUT_SUBDIR_PARAMS}"

echo "INFO [${DB_NAME}]: Creating output directory: ${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"

# --- Database Cleanup ---
echo "INFO [${DB_NAME}]: Pulizia database ycsb (host: ${MONGO_HOST_FOR_CLEANUP})..."
# Use --quiet for mongosh to suppress verbose output, errors will still be shown
mongosh --quiet --host "${MONGO_HOST_FOR_CLEANUP}" --port 27017 --eval 'db.getSiblingDB("ycsb").dropDatabase()' || echo "WARN [${DB_NAME}]: Pulizia DB fallita o DB non esistente (Continuing)."
echo "INFO [${DB_NAME}]: Pulizia database completata."
sleep 2 # Brief pause after drop

# --- YCSB Load Phase ---
LOAD_OUTPUT_FILE="${OUTPUT_DIR}/load_rep${REP_NUM}_${GENERATED_TIMESTAMP}.txt"
echo "INFO [${DB_NAME}]: Esecuzione LOAD. Output: ${LOAD_OUTPUT_FILE}"

"${YCSB_PATH}" load mongodb -s \
    -P "${WORKLOAD_PATH_PREFIX}${WORKLOAD_NAME}" \
    -p recordcount="${RECORD_COUNT}" \
    -p operationcount="${OPERATION_COUNT}" \
    -p fieldcount="${FIELD_COUNT}" \
    -p fieldlength="${FIELD_LENGTH}" \
    -p readallfields="${READ_ALL_FIELDS_BOOL}" \
    -p mongodb.url="${MONGO_URL}" \
    -p mongodb.batchsize=${MONGO_BATCH_SIZE} \
    > "${LOAD_OUTPUT_FILE}" 2>&1 # Redirect stdout and stderr

if ! grep -q "\[OVERALL\], RunTime(ms)" "${LOAD_OUTPUT_FILE}"; then
    echo "ERROR [${DB_NAME}]: LOAD fallito per ${WORKLOAD_NAME}, Rep ${REP_NUM}. Vedi ${LOAD_OUTPUT_FILE}"
    # Consider exiting if load fails, or let the orchestrator decide
    # exit 1 
fi
echo "INFO [${DB_NAME}]: LOAD completato."

# --- YCSB Run Phase ---
RUN_OUTPUT_FILE="${OUTPUT_DIR}/run_rep${REP_NUM}_${GENERATED_TIMESTAMP}.txt"
echo "INFO [${DB_NAME}]: Esecuzione RUN. Output: ${RUN_OUTPUT_FILE}"

"${YCSB_PATH}" run mongodb -s \
    -P "${WORKLOAD_PATH_PREFIX}${WORKLOAD_NAME}" \
    -p recordcount="${RECORD_COUNT}" \
    -p operationcount="${OPERATION_COUNT}" \
    -p fieldcount="${FIELD_COUNT}" \
    -p fieldlength="${FIELD_LENGTH}" \
    -p readallfields="${READ_ALL_FIELDS_BOOL}" \
    -p mongodb.url="${MONGO_URL}" \
    > "${RUN_OUTPUT_FILE}" 2>&1 # Redirect stdout and stderr

if ! grep -q "\[OVERALL\], RunTime(ms)" "${RUN_OUTPUT_FILE}"; then
    echo "ERROR [${DB_NAME}]: RUN fallito per ${WORKLOAD_NAME}, Rep ${REP_NUM}. Vedi ${RUN_OUTPUT_FILE}"
    # exit 1
fi
echo "INFO [${DB_NAME}]: RUN completato."

echo "INFO [${DB_NAME}]: Test run ${WORKLOAD_NAME}, Rep ${REP_NUM} completato."