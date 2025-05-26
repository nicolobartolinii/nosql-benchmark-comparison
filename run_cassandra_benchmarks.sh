#!/bin/bash
set -euo pipefail

# --- Configurazione ---
CASSANDRA_SETUP_DIR="cassandra"
YCSB_IMAGE_NAME="nosql-benchmark/ycsb"
YCSB_CASSANDRA_SCRIPT_PATH_IN_CONTAINER="./run-cassandra.sh"
DOCKER_NETWORK="shared-net"
DB_USER_SUBDIR="nick" # Your user-specific results subdirectory

# Default YCSB workloads
DEFAULT_WORKLOADS=("workloada" "workloadb" "workloadc" "workloadd" "workloade" "workloadf")
REPETITIONS=3
# --- Fine Configurazione ---

function start_cassandra_cluster() {
    echo "INFO: Avvio cluster Cassandra da ${CASSANDRA_SETUP_DIR}..."
    cd "${CASSANDRA_SETUP_DIR}"
    docker compose up -d --remove-orphans # Ensure clean start
    cd ..

    echo "INFO: Attesa iniziale di 60 secondi per l'avvio dei container Cassandra..."
    sleep 60
    
    MAX_RETRIES=10 # Aumentato a 10 tentativi (10 * 30s = 5 minuti max)
    RETRY_COUNT=0
    ALL_NODES_UP=false
    EXPECTED_NODES=3 # Numero di nodi Cassandra nel cluster

    echo "INFO: Inizio verifica stato nodi Cassandra (fino a ${MAX_RETRIES} tentativi)..."
    while [ ${RETRY_COUNT} -lt ${MAX_RETRIES} ] && [ "${ALL_NODES_UP}" = "false" ]; do
        RETRY_COUNT=$((RETRY_COUNT + 1))
        echo "INFO: Verifica stato nodi Cassandra (Tentativo ${RETRY_COUNT}/${MAX_RETRIES})..."
        
        local up_nodes
        # Esegui nodetool status solo se il container cassandra-1 è in esecuzione
        if docker ps --filter "name=cassandra-1" --filter "status=running" --format "{{.Names}}" | grep -q "cassandra-1"; then
            # L'output di nodetool status può variare, assicurati che il grep sia robusto
            # grep -E "^UN\s+" cerca righe che iniziano con UN (Up Normal) seguito da spazi
            up_nodes=$(docker exec cassandra-1 nodetool status 2>/dev/null | grep -E "^UN\s+" | wc -l || echo "0")
        else
            echo "WARN: Container cassandra-1 non è (ancora) in esecuzione. Impossibile eseguire nodetool status."
            up_nodes=0
        fi
        
        if [ "${up_nodes}" -eq ${EXPECTED_NODES} ]; then
            echo "INFO: Tutti e ${EXPECTED_NODES} i nodi Cassandra sono UP and NORMAL."
            ALL_NODES_UP=true
        else
            echo "WARN: ${up_nodes}/${EXPECTED_NODES} nodi Cassandra sono UP. Attendo altri 30 secondi..."
            sleep 30
        fi
    done

    if [ "${ALL_NODES_UP}" = "false" ]; then
        echo "ERROR: Cluster Cassandra non completamente avviato dopo ${MAX_RETRIES} tentativi. Controllo manuale richiesto."
        # Mostra lo status corrente se possibile
        if docker ps --filter "name=cassandra-1" --filter "status=running" --format "{{.Names}}" | grep -q "cassandra-1"; then
        docker exec cassandra-1 nodetool status || true
        else
            echo "ERROR: Container cassandra-1 non raggiungibile per status finale."
        fi
        echo "WARN: Lo script continuerà, ma i benchmark potrebbero fallire o essere inaccurati."
        # exit 1 # Togli commento se preferisci uscire in caso di fallimento avvio cluster
    else
        echo "INFO: Cluster Cassandra pronto e stabile."
    fi
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
    mkdir -p "$(pwd)/results/${DB_USER_SUBDIR}"

    declare -a SCENARIOS_DEF
    # Params: RC OC FC FL RAF THREADS
    SCENARIOS_DEF[0]="10000 10000 10 100 true 1"    # S1
    SCENARIOS_DEF[1]="100000 10000 10 100 true 1"   # S2
    SCENARIOS_DEF[2]="250000 10000 10 100 true 1"   # S3
    SCENARIOS_DEF[3]="10000 10000 1 1000 true 1"   # S4
    SCENARIOS_DEF[4]="10000 10000 10 100 false 1"  # S5
    SCENARIOS_DEF[5]="10000 10000 10 100 true 8"    # S6 (S1 @ 8 Threads)
    SCENARIOS_DEF[6]="250000 10000 10 100 true 8"   # S7 (S3 @ 8 Threads)

    declare -a scenario_indices_to_run
    if [ "$#" -eq 0 ]; then
        scenario_indices_to_run=("${!SCENARIOS_DEF[@]}")
        echo "INFO: Nessuno scenario specificato, esecuzione di tutti gli scenari Cassandra (1-${#SCENARIOS_DEF[@]})."
    else
        for user_scenario_num_arg in "$@"; do
            if ! [[ "${user_scenario_num_arg}" =~ ^[1-7]$ ]]; then
                echo "WARN: Numero di scenario Cassandra '${user_scenario_num_arg}' non valido. Verrà ignorato."
                continue
            fi
            local target_index=$((user_scenario_num_arg - 1))
            if [ -n "${SCENARIOS_DEF[${target_index}]-}" ]; then
                local already_added=0
                local len_check_dup=${#scenario_indices_to_run[@]}
                for ((d_idx = 0; d_idx < len_check_dup; d_idx++)); do
                    if [ "${scenario_indices_to_run[d_idx]}" -eq "${target_index}" ]; then already_added=1; break; fi
                done
                if [ "${already_added}" -eq 0 ]; then scenario_indices_to_run+=("${target_index}"); fi
            else
                echo "WARN: Scenario Cassandra '${user_scenario_num_arg}' (indice ${target_index}) non definito. Verrà ignorato."
            fi
        done
        if [ ${#scenario_indices_to_run[@]} -eq 0 ]; then echo "ERROR: Nessuno scenario Cassandra valido. Uscita."; exit 1; fi
        local n_sort=${#scenario_indices_to_run[@]}
        if [ "${n_sort}" -gt 1 ]; then
            for ((i_sort = 0; i_sort < n_sort; i_sort++)); do
                for ((j_sort = 0; j_sort < n_sort - i_sort - 1; j_sort++)); do
                    if ((${scenario_indices_to_run[j_sort]} > ${scenario_indices_to_run[j_sort+1]})); then
                        local temp_sort=${scenario_indices_to_run[j_sort]}; scenario_indices_to_run[j_sort]=${scenario_indices_to_run[j_sort+1]}; scenario_indices_to_run[j_sort+1]=$temp_sort; fi
                done; done; fi
        local user_friendly_scenarios_selected_str=""; local num_to_print=${#scenario_indices_to_run[@]}
        if [ "$num_to_print" -gt 0 ]; then for ((p_idx = 0; p_idx < num_to_print; p_idx++)); do user_friendly_scenarios_selected_str+="$((scenario_indices_to_run[p_idx] + 1)) "; done; user_friendly_scenarios_selected_str=${user_friendly_scenarios_selected_str%% }; fi
        echo "INFO: Esecuzione scenari Cassandra specificati: ${user_friendly_scenarios_selected_str}"
    fi

    local num_selected_indices=${#scenario_indices_to_run[@]}
    if [ "$num_selected_indices" -eq 0 ] && [ "$#" -ne 0 ]; then echo "ERROR: Logica interna errore. Uscita."; exit 1;
    elif [ "$num_selected_indices" -eq 0 ] && [ "$#" -eq 0 ]; then echo "INFO: Nessuno scenario definito."; fi

    for (( k=0; k < num_selected_indices; k++ )); do
        local scenario_idx=${scenario_indices_to_run[k]}
        local current_user_scenario_num=$((scenario_idx + 1))
        read -r RC OC FC FL RAF THREADS <<< "${SCENARIOS_DEF[${scenario_idx}]}"
        echo "INFO: Starting Scenario ${current_user_scenario_num} for Cassandra: RC=${RC}, OC=${OC}, FC=${FC}, FL=${FL}, RAF=${RAF}, Threads=${THREADS}"

        for workload_name in "${DEFAULT_WORKLOADS[@]}"; do
            echo "INFO: Processing Workload: ${workload_name} for Scenario ${current_user_scenario_num}"
            for (( rep_num=1; rep_num<=${REPETITIONS}; rep_num++ )); do
                echo "INFO: Repetition ${rep_num}/${REPETITIONS} for Workload ${workload_name}, Scenario ${current_user_scenario_num}"
                CONTAINER_NAME="ycsb_cassandra_runner_scen${current_user_scenario_num}_wl${workload_name}_rep${rep_num}"
                CMD_IN_CONTAINER="set -xeuo pipefail && ${YCSB_CASSANDRA_SCRIPT_PATH_IN_CONTAINER} '${workload_name}' '${rep_num}' '${RC}' '${OC}' '${FC}' '${FL}' '${RAF}' '${DB_USER_SUBDIR}' '${THREADS}'"
                docker run --rm --name "${CONTAINER_NAME}" --network "${DOCKER_NETWORK}" -v "$(pwd)/results:/results" --env-file .env "${YCSB_IMAGE_NAME}" bash -c "${CMD_IN_CONTAINER}"
                echo "INFO: Completed Repetition ${rep_num} for Workload ${workload_name}, Scenario ${current_user_scenario_num}"
                sleep 5
            done
            echo "INFO: Completed all repetitions for Workload ${workload_name}, Scenario ${current_user_scenario_num}"
        done
        echo "INFO: Completed Scenario ${current_user_scenario_num} for Cassandra"
        sleep 10
    done
    echo "INFO: Tutti i test YCSB per Cassandra completati. Controlla 'results/${DB_USER_SUBDIR}'."
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
run_ycsb_tests_cassandra "$@"

echo "INFO: Esecuzione benchmark Cassandra completata."
trap - EXIT
exit 0