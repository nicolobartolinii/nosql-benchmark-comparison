#!/bin/bash
set -euo pipefail

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

DB_NAME="mongo"
MONGO_BATCH_SIZE=500
YCSB_PATH="./bin/ycsb"
WORKLOAD_PATH_PREFIX="workloads/"

[ -z "${MONGO_URL-}" ] && { echo "ERROR: MONGO_URL not set for ${DB_NAME}" >&2; exit 1; }
MONGO_HOST_FOR_CLEANUP=$(echo "${MONGO_URL}" | sed -n 's_mongodb://\([^:]*\):.*_\1_p')
[ -z "${MONGO_HOST_FOR_CLEANUP}" ] && { echo "ERROR: Impossibile estrarre MONGO_HOST_FOR_CLEANUP da MONGO_URL" >&2; exit 1; }

echo "INFO [${DB_NAME}]: Starting test run for ${WORKLOAD_NAME}, Rep ${REP_NUM}, Threads ${THREADS}"
echo "INFO [${DB_NAME}]: Params: RC=${RECORD_COUNT}, OC=${OPERATION_COUNT}, FC=${FIELD_COUNT}, FL=${FIELD_LENGTH}, RAF=${READ_ALL_FIELDS_BOOL}, Threads=${THREADS}, UserSubdir=${DB_USER_SUBDIR}"

GENERATED_TIMESTAMP=$(date -u -d "+2 hours" +%Y-%m-%d_%H-%M-%S)

OUTPUT_SUBDIR_PARAMS="rc${RECORD_COUNT}_oc${OPERATION_COUNT}_fc${FIELD_COUNT}_fl${FIELD_LENGTH}_raf${READ_ALL_FIELDS_BOOL}_th${THREADS}"
OUTPUT_DIR="/results/${DB_USER_SUBDIR}/${DB_NAME}/${WORKLOAD_NAME}/${OUTPUT_SUBDIR_PARAMS}"

echo "INFO [${DB_NAME}]: Creating output directory: ${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"

echo "INFO [${DB_NAME}]: Pulizia database ycsb (host: ${MONGO_HOST_FOR_CLEANUP})..."
mongosh --quiet --host "${MONGO_HOST_FOR_CLEANUP}" --port 27017 --eval 'db.getSiblingDB("ycsb").dropDatabase()' || echo "WARN [${DB_NAME}]: Pulizia DB fallita o DB non esistente (Continuing)."
echo "INFO [${DB_NAME}]: Pulizia database completata."
sleep 2

LOAD_OUTPUT_FILE="${OUTPUT_DIR}/load_rep${REP_NUM}_${GENERATED_TIMESTAMP}.txt"
echo "INFO [${DB_NAME}]: Esecuzione LOAD. Output: ${LOAD_OUTPUT_FILE}"

"${YCSB_PATH}" load mongodb -s -threads "${THREADS}" \
    -P "${WORKLOAD_PATH_PREFIX}${WORKLOAD_NAME}" \
    -p recordcount="${RECORD_COUNT}" \
    -p operationcount="${OPERATION_COUNT}" \
    -p fieldcount="${FIELD_COUNT}" \
    -p fieldlength="${FIELD_LENGTH}" \
    -p readallfields="${READ_ALL_FIELDS_BOOL}" \
    -p mongodb.url="${MONGO_URL}" \
    -p mongodb.batchsize=${MONGO_BATCH_SIZE} \
    > "${LOAD_OUTPUT_FILE}" 2>&1
        
if ! grep -q "\[OVERALL\], RunTime(ms)" "${LOAD_OUTPUT_FILE}"; then
    echo "ERROR [${DB_NAME}]: LOAD fallito per ${WORKLOAD_NAME}, Rep ${REP_NUM}, Threads ${THREADS}. Vedi ${LOAD_OUTPUT_FILE}"
fi
echo "INFO [${DB_NAME}]: LOAD completato."

RUN_OUTPUT_FILE="${OUTPUT_DIR}/run_rep${REP_NUM}_${GENERATED_TIMESTAMP}.txt"
echo "INFO [${DB_NAME}]: Esecuzione RUN. Output: ${RUN_OUTPUT_FILE}"

"${YCSB_PATH}" run mongodb -s -threads "${THREADS}" \
    -P "${WORKLOAD_PATH_PREFIX}${WORKLOAD_NAME}" \
    -p recordcount="${RECORD_COUNT}" \
    -p operationcount="${OPERATION_COUNT}" \
    -p fieldcount="${FIELD_COUNT}" \
    -p fieldlength="${FIELD_LENGTH}" \
    -p readallfields="${READ_ALL_FIELDS_BOOL}" \
    -p mongodb.url="${MONGO_URL}" \
    > "${RUN_OUTPUT_FILE}" 2>&1

if ! grep -q "\[OVERALL\], RunTime(ms)" "${RUN_OUTPUT_FILE}"; then
    echo "ERROR [${DB_NAME}]: RUN fallito per ${WORKLOAD_NAME}, Rep ${REP_NUM}, Threads ${THREADS}. Vedi ${RUN_OUTPUT_FILE}"
fi
echo "INFO [${DB_NAME}]: RUN completato."

echo "INFO [${DB_NAME}]: Test run ${WORKLOAD_NAME}, Rep ${REP_NUM}, Threads ${THREADS} completato."