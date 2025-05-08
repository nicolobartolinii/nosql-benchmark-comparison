#!/bin/bash
# Usiamo set -x per stampare ogni comando prima di eseguirlo (molto verboso!)
# Usiamo set -e per uscire all'errore, -u per variabili non definite, -o pipefail per pipeline
set -xeuo pipefail

# --- Configurazione Test ---
DB_NAME="cassandra"
REPETITIONS=3
RECORD_COUNT=10000
OPERATION_COUNT=10000
CASSANDRA_BATCH_SIZE=100
REPLICATION_FACTOR=3
READ_CONSISTENCY="QUORUM"
WRITE_CONSISTENCY="QUORUM"
KEYSPACE_NAME="ycsb"
TABLE_NAME="usertable"

DEFAULT_WORKLOADS=("workloada" "workloadb" "workloadc" "workloadd" "workloade" "workloadf")
# --- Fine Configurazione ---

# --- Funzione robusta per cqlsh ---
execute_cql_or_exit() {
    local host="$1"
    local cql_command="$2"
    local description="$3"
    local ignore_failure="${4:-false}" # Argomento opzionale per non uscire in caso di fallimento

    echo "INFO [${DB_NAME}]: Tentativo CQL (${description}) su host ${host}..."
    echo "DEBUG [${DB_NAME}]: Comando: cqlsh \"${host}\" -e \"${cql_command}\""

    local output
    local exit_code=0
    # Esegui e cattura output+errore
    output=$(cqlsh "${host}" -e "${cql_command}" 2>&1) || exit_code=$?

    echo "--- Inizio Output cqlsh (${description}) ---"
    echo "${output}"
    echo "--- Fine Output cqlsh (${description}) ---"
    echo "DEBUG [${DB_NAME}]: Codice uscita cqlsh: ${exit_code}"

    if [ ${exit_code} -ne 0 ]; then
        echo "ERROR [${DB_NAME}]: Esecuzione CQL (${description}) fallita con codice ${exit_code}!"
        if [ "$ignore_failure" = "false" ]; then
            echo "ERROR [${DB_NAME}]: Script interrotto a causa del fallimento CQL."
            exit 1
        else
            echo "WARN [${DB_NAME}]: Fallimento ignorato come richiesto."
        fi
    else
        echo "INFO [${DB_NAME}]: Esecuzione CQL (${description}) completata."
    fi
    # Restituisci il codice di uscita per usi successivi se necessario
    return ${exit_code} 
}
# --- Fine funzione ---

[ -z "${CASS_HOSTS-}" ] && { echo "ERROR: CASS_HOSTS not set for ${DB_NAME}" >&2; exit 1; }
CQLSH_HOST=$(echo "${CASS_HOSTS}" | cut -d, -f1)

declare -a workloads_to_run
if [ "$#" -ge 1 ]; then
    workloads_to_run=("$@")
    echo "INFO [${DB_NAME}]: Esecuzione workload specifici: ${workloads_to_run[*]}"
else
    workloads_to_run=("${DEFAULT_WORKLOADS[@]}")
    echo "INFO [${DB_NAME}]: Esecuzione workload di default: ${workloads_to_run[*]}"
fi

# --- Preparazione Schema Cassandra (Keyspace e Tabella) ---
echo "INFO [${DB_NAME}]: Preparazione Schema Cassandra (Host: ${CQLSH_HOST})..."

# 0. Verifica cqlsh
echo "INFO [${DB_NAME}]: Verifica comando cqlsh..."
if ! command -v cqlsh &> /dev/null; then
    echo "ERROR [${DB_NAME}]: Comando 'cqlsh' non trovato nel PATH!"
    exit 1
fi
cqlsh --version # Stampa la versione per debug

# 1. Drop Keyspace (Ignora fallimento qui, perché IF EXISTS gestisce il caso non esistente)
execute_cql_or_exit "${CQLSH_HOST}" "DROP KEYSPACE IF EXISTS ${KEYSPACE_NAME};" "Drop Keyspace" true # Il quarto argomento 'true' ignora il fallimento
echo "INFO [${DB_NAME}]: Attesa dopo DROP..."
sleep 20

# 2. Crea Keyspace (Fallimento è fatale qui)
CREATE_KEYSPACE_CQL="CREATE KEYSPACE IF NOT EXISTS ${KEYSPACE_NAME} WITH replication = {'class': 'SimpleStrategy', 'replication_factor': '${REPLICATION_FACTOR}'};"
execute_cql_or_exit "${CQLSH_HOST}" "${CREATE_KEYSPACE_CQL}" "Crea Keyspace"
echo "INFO [${DB_NAME}]: Attesa dopo CREATE KEYSPACE..."
sleep 15

# 3. Verifica ESPLICITA che il Keyspace esista (Fallimento è fatale dopo i tentativi)
echo "INFO [${DB_NAME}]: Verifica esistenza KEYSPACE ${KEYSPACE_NAME}..."
CHECK_KEYSPACE_CQL="DESCRIBE KEYSPACE ${KEYSPACE_NAME};"
MAX_CHECKS=4 # Aumentato tentativi
CHECK_COUNT=0
KEYSPACE_FOUND=false
while [ ${CHECK_COUNT} -lt ${MAX_CHECKS} ] && [ "${KEYSPACE_FOUND}" = "false" ]; do
    echo "DEBUG [${DB_NAME}]: Tentativo verifica keyspace $((CHECK_COUNT + 1))/${MAX_CHECKS}..."
    # Esegui cqlsh direttamente per il controllo, ma non uscire con set -e
    set +e # Disabilita temporaneamente l'uscita all'errore
    cqlsh "${CQLSH_HOST}" -e "${CHECK_KEYSPACE_CQL}" > /dev/null 2>&1
    check_exit_code=$?
    set -e # Riabilita l'uscita all'errore
    
    if [ ${check_exit_code} -eq 0 ]; then
        echo "INFO [${DB_NAME}]: Keyspace ${KEYSPACE_NAME} TROVATO!"
        KEYSPACE_FOUND=true
    else
        echo "WARN [${DB_NAME}]: Keyspace ${KEYSPACE_NAME} non ancora trovato/propagato (Tentativo $((CHECK_COUNT + 1))/${MAX_CHECKS}, Exit Code: ${check_exit_code}). Attendo 15 secondi..."
        sleep 15 # Aumentato attesa verifica
        CHECK_COUNT=$((CHECK_COUNT + 1))
    fi
done
if [ "${KEYSPACE_FOUND}" = "false" ]; then
    echo "ERROR [${DB_NAME}]: Keyspace ${KEYSPACE_NAME} non trovato dopo la creazione e i controlli! Script interrotto."
    exit 1
fi

# 4. Crea Tabella (Fallimento è fatale qui)
echo "INFO [${DB_NAME}]: Creazione TABLE ${TABLE_NAME} nel keyspace ${KEYSPACE_NAME}..."
CREATE_TABLE_CQL="CREATE TABLE IF NOT EXISTS ${KEYSPACE_NAME}.${TABLE_NAME} (y_id varchar PRIMARY KEY, field0 varchar, field1 varchar, field2 varchar, field3 varchar, field4 varchar, field5 varchar, field6 varchar, field7 varchar, field8 varchar, field9 varchar) WITH default_time_to_live = 0;"
execute_cql_or_exit "${CQLSH_HOST}" "${CREATE_TABLE_CQL}" "Crea Tabella"
echo "INFO [${DB_NAME}]: Attesa dopo CREATE TABLE..."
sleep 10
# --- Fine Preparazione ---

# --- INIZIO WORKLOAD YCSB ---
echo "INFO [${DB_NAME}]: Preparazione schema completata. Inizio esecuzione benchmark YCSB..."
# ... (resto dello script con il ciclo for per workload e ripetizioni rimane uguale) ...

for workload_file in "${workloads_to_run[@]}"; do
    echo "INFO [${DB_NAME}]: Inizio workload ${workload_file}"
    for (( rep=1; rep<=${REPETITIONS}; rep++ )); do
        echo "INFO [${DB_NAME}]: Workload ${workload_file}, Ripetizione ${rep}/${REPETITIONS}"

        LOAD_OUTPUT_FILE="/results/${DB_NAME}_${workload_file}_load_rep${rep}_$(date +%Y%m%d%H%M%S).txt"
        echo "INFO [${DB_NAME}]: Esecuzione LOAD (${workload_file}, Rep ${rep}). Output: ${LOAD_OUTPUT_FILE}"
        ./bin/ycsb load cassandra-cql -s \
            -P "workloads/${workload_file}" \
            -p hosts="${CASS_HOSTS}" \
            -p recordcount=${RECORD_COUNT} \
            -p operationcount=${OPERATION_COUNT} \
            -p cassandra.batchsize=${CASSANDRA_BATCH_SIZE} \
            -p cassandra.keyspace=${KEYSPACE_NAME} \
            -p cassandra.table=${TABLE_NAME} \
            -p cassandra.readconsistencylevel=${READ_CONSISTENCY} \
            -p cassandra.writeconsistencylevel=${WRITE_CONSISTENCY} \
            > "${LOAD_OUTPUT_FILE}" 2>&1

        if ! grep -q "\[OVERALL\], RunTime(ms)" "${LOAD_OUTPUT_FILE}"; then
            echo "ERROR [${DB_NAME}]: LOAD fallito per ${workload_file}, Rep ${rep}. Vedi ${LOAD_OUTPUT_FILE}"
            tail -n 20 "${LOAD_OUTPUT_FILE}"
            continue
        fi
        echo "INFO [${DB_NAME}]: LOAD completato."

        RUN_OUTPUT_FILE="/results/${DB_NAME}_${workload_file}_run_rep${rep}_$(date +%Y%m%d%H%M%S).txt"
        echo "INFO [${DB_NAME}]: Esecuzione RUN (${workload_file}, Rep ${rep}). Output: ${RUN_OUTPUT_FILE}"
        ./bin/ycsb run cassandra-cql -s \
            -P "workloads/${workload_file}" \
            -p hosts="${CASS_HOSTS}" \
            -p recordcount=${RECORD_COUNT} \
            -p operationcount=${OPERATION_COUNT} \
            -p cassandra.keyspace=${KEYSPACE_NAME} \
            -p cassandra.table=${TABLE_NAME} \
            -p cassandra.readconsistencylevel=${READ_CONSISTENCY} \
            -p cassandra.writeconsistencylevel=${WRITE_CONSISTENCY} \
            > "${RUN_OUTPUT_FILE}" 2>&1

        if ! grep -q "\[OVERALL\], RunTime(ms)" "${RUN_OUTPUT_FILE}"; then
            echo "ERROR [${DB_NAME}]: RUN fallito per ${workload_file}, Rep ${rep}. Vedi ${RUN_OUTPUT_FILE}"
            tail -n 20 "${RUN_OUTPUT_FILE}"
        fi
        echo "INFO [${DB_NAME}]: RUN completato."

        echo "INFO [${DB_NAME}]: Ripetizione ${rep}/${REPETITIONS} per ${workload_file} completata."
        sleep 10
    done
    echo "INFO [${DB_NAME}]: Workload ${workload_file} completato."
done
echo "INFO [${DB_NAME}]: Tutti i test completati."