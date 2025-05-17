#!/bin/bash
set -euo pipefail

# --- Configurazione ---
REDIS_SETUP_DIR="redis"
YCSB_IMAGE_NAME="nosql-benchmark/ycsb"
YCSB_REDIS_SCRIPT_PATH_IN_CONTAINER="./run-redis.sh"
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

function start_redis_cluster() {
    echo "INFO: Avvio cluster Redis da ${REDIS_SETUP_DIR}..."
    cd "${REDIS_SETUP_DIR}"
    docker compose up -d
    cd ..

    echo "INFO: Attesa di 20 secondi per l'avvio dei nodi e la creazione del cluster Redis..."
    sleep 20 # Dare tempo ai nodi e al job redis-cluster-setup

    # Verifica stato cluster
    MAX_RETRIES=3
    RETRY_COUNT=0
    CLUSTER_OK=false
    while [ ${RETRY_COUNT} -lt ${MAX_RETRIES} ] && [ "${CLUSTER_OK}" = "false" ]; do
        echo "INFO: Verifica stato cluster Redis (Tentativo $((RETRY_COUNT + 1))).."
        # Usiamo redis-cli cluster info sul primo nodo. Cerchiamo cluster_state:ok
        local cluster_state
        cluster_state=$(docker exec redis-node1 redis-cli cluster info 2>/dev/null | grep 'cluster_state:ok' || true)
        if [[ -n "${cluster_state}" ]]; then
            echo "INFO: Cluster Redis OK."
            # Potremmo aggiungere un controllo su 'cluster_slots_assigned:16384'
            docker exec redis-node1 redis-cli cluster nodes || true # Stampa nodi per info
            CLUSTER_OK=true
        else
            echo "WARN: Cluster Redis non ancora OK o non raggiungibile. Attendo altri 15 secondi..."
            sleep 15
            RETRY_COUNT=$((RETRY_COUNT + 1))
        fi
    done

    if [ "${CLUSTER_OK}" = "false" ]; then
        echo "ERROR: Cluster Redis non pronto dopo i tentativi. Controllo manuale richiesto."
        docker exec redis-node1 redis-cli cluster info || true
        # exit 1 # Decidi se uscire
    fi
    echo "INFO: Cluster Redis pronto."
}

function stop_redis_cluster() {
    local script_dir
    script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
    echo "INFO: Arresto e pulizia cluster Redis da ${script_dir}/${REDIS_SETUP_DIR}..."
    pushd "${script_dir}/${REDIS_SETUP_DIR}" > /dev/null
    # Usiamo 'docker compose' invece di 'docker-compose' per coerenza se usi v2+
    docker compose down -v --remove-orphans 2>/dev/null || true 
    popd > /dev/null
    echo "INFO: Cluster Redis arrestato e pulito."
}

function run_ycsb_tests_redis() {
    echo "INFO: Esecuzione test YCSB per Redis..."
    mkdir -p "$(pwd)/results"

    docker run --rm --name ycsb_redis_runner \
        --network "${DOCKER_NETWORK}" \
        -v "$(pwd)/results:/results" \
        --env-file .env \
        "${YCSB_IMAGE_NAME}" "${YCSB_REDIS_SCRIPT_PATH_IN_CONTAINER}" ${YCSB_SCRIPT_ARGS}
    
    echo "INFO: Test YCSB per Redis completati. Controlla la directory 'results'."
}

trap 'echo "WARN: Script interrotto. Tentativo di pulizia finale..."; stop_redis_cluster' EXIT SIGINT SIGTERM

echo "INFO: Pulizia preliminare di qualsiasi istanza Redis precedente..."
stop_redis_cluster
sleep 5

docker network inspect "${DOCKER_NETWORK}" >/dev/null 2>&1 || {
    echo "INFO: Creazione rete Docker '${DOCKER_NETWORK}'..."
    docker network create "${DOCKER_NETWORK}"
}

start_redis_cluster
run_ycsb_tests_redis
# stop_redis_cluster # Gestito dal trap EXIT

echo "INFO: Esecuzione benchmark Redis completata."
trap - EXIT
exit 0