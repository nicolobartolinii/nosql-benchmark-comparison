#!/bin/bash
set -euo pipefail

# --- Configurazione Test ---
DB_NAME="mongo"
REPETITIONS=3
RECORD_COUNT=10000
OPERATION_COUNT=10000
MONGO_BATCH_SIZE=500
DEFAULT_WORKLOADS=("workloada" "workloadb" "workloadc" "workloadd" "workloade" "workloadf")
# --- Fine Configurazione ---

[ -z "${MONGO_URL-}" ] && { echo "ERROR: MONGO_URL not set for ${DB_NAME}" >&2; exit 1; }
# MONGO_HOST_FOR_CLEANUP dovrebbe essere il nome del servizio mongos, es: mongo-mongos
MONGO_HOST_FOR_CLEANUP=$(echo "${MONGO_URL}" | sed -n 's_mongodb://\([^:]*\):.*_\1_p')
[ -z "${MONGO_HOST_FOR_CLEANUP}" ] && { echo "ERROR: Impossibile estrarre MONGO_HOST_FOR_CLEANUP da MONGO_URL" >&2; exit 1; }


declare -a workloads_to_run
if [ "$#" -ge 1 ]; then
    workloads_to_run=("$@") # Esegui workload specificati come argomenti
    echo "INFO [${DB_NAME}]: Esecuzione workload specifici: ${workloads_to_run[*]}"
else
    workloads_to_run=("${DEFAULT_WORKLOADS[@]}")
    echo "INFO [${DB_NAME}]: Esecuzione workload di default: ${workloads_to_run[*]}"
fi

for workload_file in "${workloads_to_run[@]}"; do
    echo "INFO [${DB_NAME}]: Inizio workload ${workload_file}"
    for (( rep=1; rep<=${REPETITIONS}; rep++ )); do
        echo "INFO [${DB_NAME}]: Workload ${workload_file}, Ripetizione ${rep}/${REPETITIONS}"

        echo "INFO [${DB_NAME}]: Pulizia database ycsb (host: ${MONGO_HOST_FOR_CLEANUP})..."
        mongosh --quiet --host "${MONGO_HOST_FOR_CLEANUP}" --port 27017 --eval 'db.getSiblingDB("ycsb").dropDatabase()' || echo "WARN [${DB_NAME}]: Pulizia DB fallita o DB non esistente."
        echo "INFO [${DB_NAME}]: Pulizia database completata."
        sleep 2 # Breve pausa dopo il drop

        LOAD_OUTPUT_FILE="/results/${DB_NAME}_${workload_file}_load_rep${rep}_$(date +%Y%m%d%H%M%S).txt"
        echo "INFO [${DB_NAME}]: Esecuzione LOAD (${workload_file}, Rep ${rep}). Output: ${LOAD_OUTPUT_FILE}"
        ./bin/ycsb load mongodb -s \
            -P "workloads/${workload_file}" \
            -p recordcount=${RECORD_COUNT} \
            -p operationcount=${OPERATION_COUNT} \
            -p mongodb.url="${MONGO_URL}" \
            -p mongodb.batchsize=${MONGO_BATCH_SIZE} \
            > "${LOAD_OUTPUT_FILE}"
        
        if ! grep -q "\[OVERALL\], RunTime(ms)" "${LOAD_OUTPUT_FILE}"; then
            echo "ERROR [${DB_NAME}]: LOAD fallito per ${workload_file}, Rep ${rep}. Vedi ${LOAD_OUTPUT_FILE}"
            continue
        fi
        echo "INFO [${DB_NAME}]: LOAD completato."

        RUN_OUTPUT_FILE="/results/${DB_NAME}_${workload_file}_run_rep${rep}_$(date +%Y%m%d%H%M%S).txt"
        echo "INFO [${DB_NAME}]: Esecuzione RUN (${workload_file}, Rep ${rep}). Output: ${RUN_OUTPUT_FILE}"
        ./bin/ycsb run mongodb -s \
            -P "workloads/${workload_file}" \
            -p recordcount=${RECORD_COUNT} \
            -p operationcount=${OPERATION_COUNT} \
            -p mongodb.url="${MONGO_URL}" \
            > "${RUN_OUTPUT_FILE}" 2>&1

        if ! grep -q "\[OVERALL\], RunTime(ms)" "${RUN_OUTPUT_FILE}"; then
            echo "ERROR [${DB_NAME}]: RUN fallito per ${workload_file}, Rep ${rep}. Vedi ${RUN_OUTPUT_FILE}"
        fi
        echo "INFO [${DB_NAME}]: RUN completato."

        echo "INFO [${DB_NAME}]: Ripetizione ${rep}/${REPETITIONS} per ${workload_file} completata."
        sleep 10 
    done
    echo "INFO [${DB_NAME}]: Workload ${workload_file} completato."
done
echo "INFO [${DB_NAME}]: Tutti i test completati."