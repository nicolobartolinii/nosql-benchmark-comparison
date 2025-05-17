#!/bin/bash
set -euo pipefail

# --- Configurazione ---
CASSANDRA_SETUP_DIR="cassandra"
YCSB_IMAGE_NAME="nosql-benchmark/ycsb"
YCSB_CASSANDRA_SCRIPT_PATH_IN_CONTAINER="./run-cassandra.sh"
DOCKER_NETWORK="shared-net"
<<<<<<< Updated upstream
YCSB_SCRIPT_ARGS="$@"
=======
DB_USER_SUBDIR="andrea" # Your user-specific results subdirectory

# Default YCSB workloads
DEFAULT_WORKLOADS=("workloada" "workloadb" "workloadc" "workloadd" "workloade" "workloadf")
REPETITIONS=3
>>>>>>> Stashed changes
# --- Fine Configurazione ---

function start_cassandra_cluster() {
    echo "INFO: Avvio cluster Cassandra da ${CASSANDRA_SETUP_DIR}..."
    cd "${CASSANDRA_SETUP_DIR}"
    docker compose up -d
    cd ..

    echo "INFO: Attesa di 180 secondi per l'avvio e la stabilizzazione del cluster Cassandra..."
    # sleep 30
    # echo "INFO: Mancano 210 secondi per l'avvio completo del cluster Cassandra..."
    # sleep 30
    # echo "INFO: Mancano 180 secondi per l'avvio completo del cluster Cassandra..."
    sleep 30
    echo "INFO: Mancano 150 secondi per l'avvio completo del cluster Cassandra..."
    sleep 30
    echo "INFO: Mancano 120 secondi per l'avvio completo del cluster Cassandra..."
    sleep 30
    echo "INFO: Mancano 90 secondi per l'avvio completo del cluster Cassandra..."
    sleep 30
    echo "INFO: Mancano 60 secondi per l'avvio completo del cluster Cassandra..."
    sleep 30
    echo "INFO: Mancano 30 secondi per l'avvio completo del cluster Cassandra..."
    sleep 30
    
    MAX_RETRIES=5
    RETRY_COUNT=0
    ALL_NODES_UP=false
    while [ ${RETRY_COUNT} -lt ${MAX_RETRIES} ] && [ "${ALL_NODES_UP}" = "false" ]; do
        echo "INFO: Verifica stato nodi Cassandra (Tentativo $((RETRY_COUNT + 1))).."
        # docker exec cassandra-1 nodetool status | grep "UN " | wc -l
        # Se tutti e 3 i nodi sono UN, allora il conteggio sarà 3
        # Nota: "cassandra-1" è il container_name
        local up_nodes
        up_nodes=$(docker exec cassandra-1 nodetool status 2>/dev/null | grep -E "^UN\s+" | wc -l || true)
        if [ "${up_nodes}" -eq 3 ]; then
            echo "INFO: Tutti e 3 i nodi Cassandra sono UP and NORMAL."
            ALL_NODES_UP=true
        else
            echo "WARN: ${up_nodes} nodi su 3 sono UP. Attendo altri 30 secondi..."
            sleep 30
            RETRY_COUNT=$((RETRY_COUNT + 1))
        fi
    done

    if [ "${ALL_NODES_UP}" = "false" ]; then
        echo "ERROR: Cluster Cassandra non completamente avviato dopo i tentativi. Controllo manuale richiesto."
        docker exec cassandra-1 nodetool status || true
        # exit 1 # Decidi se uscire o tentare comunque
    fi
    echo "INFO: Cluster Cassandra pronto."
}

function stop_cassandra_cluster() {
    echo "INFO: Arresto e pulizia cluster Cassandra da ${CASSANDRA_SETUP_DIR}..."
    cd "${CASSANDRA_SETUP_DIR}"
    docker compose down -v --remove-orphans 2>/dev/null || true
    cd ..
    echo "INFO: Cluster Cassandra arrestato e pulito."
}

function run_ycsb_tests_cassandra() {
    echo "INFO: Esecuzione test YCSB per Cassandra..."
    mkdir -p "$(pwd)/results"

    docker run --rm --name ycsb_cassandra_runner \
        --network "${DOCKER_NETWORK}" \
        -v "$(pwd)/results/andrea:/results" \
        --env-file .env \
        "${YCSB_IMAGE_NAME}" "${YCSB_CASSANDRA_SCRIPT_PATH_IN_CONTAINER}" ${YCSB_SCRIPT_ARGS}
    
    echo "INFO: Test YCSB per Cassandra completati. Controlla la directory 'results'."
}

trap 'echo "WARN: Script interrotto. Tentativo di pulizia finale..."; stop_cassandra_cluster' EXIT SIGINT SIGTERM

echo "INFO: Pulizia preliminare di qualsiasi istanza Cassandra precedente..."
stop_cassandra_cluster
sleep 5

docker network inspect "${DOCKER_NETWORK}" >/dev/null 2>&1 || {
    echo "INFO: Creazione rete Docker '${DOCKER_NETWORK}'..."
    docker network create "${DOCKER_NETWORK}"
}

start_cassandra_cluster
run_ycsb_tests_cassandra
# stop_cassandra_cluster # Gestito dal trap EXIT

echo "INFO: Esecuzione benchmark Cassandra completata."
trap - EXIT
exit 0