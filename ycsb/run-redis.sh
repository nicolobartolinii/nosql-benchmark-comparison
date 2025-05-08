#!/bin/bash
set -euo pipefail # Aggiunto -x per debug se necessario

# --- Configurazione Test ---
DB_NAME="redis"
REPETITIONS=3
RECORD_COUNT=10000
OPERATION_COUNT=10000
# Redis non ha un batch size configurabile via YCSB nello stesso modo
# Usa pipeline internamente, ma non c'è un parametro -p per il batch

DEFAULT_WORKLOADS=("workloada" "workloadb" "workloadc" "workloadd" "workloade" "workloadf")
# --- Fine Configurazione ---

# In ycsb/run-redis.sh
[ -z "${REDIS_NODES-}" ] && { echo "ERROR: REDIS_NODES not set for ${DB_NAME}" >&2; exit 1; }
echo "DEBUG [${DB_NAME}]: Valore ricevuto per REDIS_NODES='${REDIS_NODES}'"

declare -a workloads_to_run
if [ "$#" -ge 1 ]; then
    workloads_to_run=("$@")
    echo "INFO [${DB_NAME}]: Esecuzione workload specifici: ${workloads_to_run[*]}"
else
    workloads_to_run=("${DEFAULT_WORKLOADS[@]}")
    echo "INFO [${DB_NAME}]: Esecuzione workload di default: ${workloads_to_run[*]}"
fi

# --- Pulizia (Assumiamo che venga fatta esternamente con docker-compose down/up) ---
# Se servisse pulire un cluster attivo, useremmo FLUSHALL su ogni nodo
# echo "INFO [${DB_NAME}]: Pulizia Redis Cluster..."
# IFS=',' read -ra HOST_PORTS <<< "$REDIS_NODES"
# for hp in "${HOST_PORTS[@]}"; do
#   host=$(echo "$hp" | cut -d: -f1)
#   port=$(echo "$hp" | cut -d: -f2)
#   echo "INFO [${DB_NAME}]: Eseguo FLUSHALL su ${host}:${port}..."
#   redis-cli -h "$host" -p "$port" -c FLUSHALL || echo "WARN: FLUSHALL fallito su ${host}:${port}"
# done
# echo "INFO [${DB_NAME}]: Pulizia Redis Cluster completata."
# sleep 5
# --- Fine Pulizia ---

for workload_file in "${workloads_to_run[@]}"; do
    echo "INFO [${DB_NAME}]: Inizio workload ${workload_file}"
    for (( rep=1; rep<=${REPETITIONS}; rep++ )); do
        echo "INFO [${DB_NAME}]: Workload ${workload_file}, Ripetizione ${rep}/${REPETITIONS}"

        LOAD_OUTPUT_FILE="/results/${DB_NAME}_${workload_file}_load_rep${rep}_$(date +%Y%m%d%H%M%S).txt"
        echo "INFO [${DB_NAME}]: Esecuzione LOAD (${workload_file}, Rep ${rep}). Output: ${LOAD_OUTPUT_FILE}"
        ./bin/ycsb load redis -s \
            -P "workloads/${workload_file}" \
            -p redis.hosts="${REDIS_NODES}" \
            -p redis.cluster=true \
            -p recordcount=${RECORD_COUNT} \
            -p operationcount=${OPERATION_COUNT} \
            > "${LOAD_OUTPUT_FILE}" 2>&1

        if ! grep -q "\[OVERALL\], RunTime(ms)" "${LOAD_OUTPUT_FILE}"; then
            echo "ERROR [${DB_NAME}]: LOAD fallito per ${workload_file}, Rep ${rep}. Vedi ${LOAD_OUTPUT_FILE}"
            tail -n 20 "${LOAD_OUTPUT_FILE}"
            # Per Redis, potremmo voler continuare anche se il load fallisce parzialmente
            # perché il run potrebbe funzionare sui dati caricati.
            # Ma per ora, continuiamo al prossimo ciclo.
            continue
        fi
        echo "INFO [${DB_NAME}]: LOAD completato."

        RUN_OUTPUT_FILE="/results/${DB_NAME}_${workload_file}_run_rep${rep}_$(date +%Y%m%d%H%M%S).txt"
        echo "INFO [${DB_NAME}]: Esecuzione RUN (${workload_file}, Rep ${rep}). Output: ${RUN_OUTPUT_FILE}"
        ./bin/ycsb run redis -s \
            -P "workloads/${workload_file}" \
            -p redis.hosts="${REDIS_NODES}" \
            -p redis.cluster=true \
            -p recordcount=${RECORD_COUNT} \
            -p operationcount=${OPERATION_COUNT} \
            > "${RUN_OUTPUT_FILE}" 2>&1

        if ! grep -q "\[OVERALL\], RunTime(ms)" "${RUN_OUTPUT_FILE}"; then
            echo "ERROR [${DB_NAME}]: RUN fallito per ${workload_file}, Rep ${rep}. Vedi ${RUN_OUTPUT_FILE}"
            tail -n 20 "${RUN_OUTPUT_FILE}"
        fi
        echo "INFO [${DB_NAME}]: RUN completato."

        echo "INFO [${DB_NAME}]: Ripetizione ${rep}/${REPETITIONS} per ${workload_file} completata."
        sleep 5 # Breve pausa tra ripetizioni
    done
    echo "INFO [${DB_NAME}]: Workload ${workload_file} completato."
    sleep 10 # Pausa tra workload
done
echo "INFO [${DB_NAME}]: Tutti i test completati."