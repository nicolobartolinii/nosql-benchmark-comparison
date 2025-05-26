#!/bin/bash
set -euo pipefail

# --- Configurazione ---
MONGO_SETUP_DIR="mongo"
YCSB_IMAGE_NAME="nosql-benchmark/ycsb"
YCSB_MONGO_SCRIPT_PATH_IN_CONTAINER="./run-mongo.sh"
DOCKER_NETWORK="shared-net"
DB_USER_SUBDIR="nick" # Your user-specific results subdirectory

# Default YCSB workloads
DEFAULT_WORKLOADS=("workloada" "workloadb" "workloadc" "workloadd" "workloade" "workloadf")
REPETITIONS=3

# --- Fine Configurazione ---

function start_mongo_cluster() {
    echo "INFO: Avvio cluster MongoDB da ${MONGO_SETUP_DIR}..."
    cd "${MONGO_SETUP_DIR}"
    docker compose up -d
    cd ..

    echo "INFO: Attesa di 35 secondi per la stabilizzazione e l'avvio del cluster MongoDB..."
    sleep 35 # Aumenta se necessario

    # Tentativi di inizializzazione, più tolleranti agli errori "already initialized"
    echo "INFO: Tentativo di inizializzazione Config Server Replica Set (cfgRS)..."
    docker exec -it mongo-cfg1 mongosh --quiet --port 27019 --eval 'try { rs.initiate({_id:"cfgRS",configsvr:true,members:[{_id:0,host:"mongo-cfg1:27019"},{_id:1,host:"mongo-cfg2:27019"},{_id:2,host:"mongo-cfg3:27019"}]}) } catch (e) { if (e.codeName && e.codeName.toLowerCase().includes("alreadyinitialized")) { print("INFO: cfgRS già inizializzato."); } else { throw e; } }'
    sleep 10

    echo "INFO: Tentativo di inizializzazione Shard Replica Set (shard1RS)..."
    docker exec -it mongo-shard1a mongosh --quiet --port 27018 --eval 'try { rs.initiate({_id:"shard1RS",members:[{_id:0,host:"mongo-shard1a:27018"},{_id:1,host:"mongo-shard1b:27018"}]}) } catch (e) { if (e.codeName && e.codeName.toLowerCase().includes("alreadyinitialized")) { print("INFO: shard1RS già inizializzato."); } else { throw e; } }'
    sleep 10

    echo "INFO: Tentativo di inizializzazione Shard Replica Set (shard2RS)..."
    docker exec -it mongo-shard2a mongosh --quiet --port 27020 --eval 'try { rs.initiate({_id:"shard2RS",members:[{_id:0,host:"mongo-shard2a:27020"},{_id:1,host:"mongo-shard2b:27020"}]}) } catch (e) { if (e.codeName && e.codeName.toLowerCase().includes("alreadyinitialized")) { print("INFO: shard2RS già inizializzato."); } else { throw e; } }'
    sleep 10

    echo "INFO: Tentativo di aggiunta dello shard1RS al router mongos..."
    if ! docker exec -it mongo-mongos mongosh --port 27017 --eval 'sh.addShard("shard1RS/mongo-shard1a:27018,mongo-shard1b:27018")'; then
        echo "WARN: sh.addShard è fallito. Controllo sh.status()..."
        sleep 2
        docker exec -it mongo-mongos mongosh --port 27017 --eval 'sh.status()' || echo "ERROR: Impossibile ottenere sh.status()"
        echo "WARN: Proseguo comunque, ma lo sharding potrebbe non essere configurato correttamente."
    fi
    
    echo "INFO: Tentativo di aggiunta dello shard2RS al router mongos..."
    if ! docker exec -it mongo-mongos mongosh --port 27017 --eval 'sh.addShard("shard2RS/mongo-shard2a:27020,mongo-shard2b:27020")'; then
        echo "WARN: sh.addShard per shard2RS è fallito. Controllo sh.status()..."
        sleep 2
        docker exec -it mongo-mongos mongosh --port 27017 --eval 'sh.status()' || echo "ERROR: Impossibile ottenere sh.status()"
        echo "WARN: Proseguo comunque, ma lo sharding potrebbe non essere configurato correttamente per shard2RS."
    fi
    
    sleep 5
    
    echo "INFO: Cluster MongoDB pronto e inizializzato (o già inizializzato)."
}

function stop_mongo_cluster() {
    echo "INFO: Arresto e pulizia cluster MongoDB da ${MONGO_SETUP_DIR}..."
    cd "${MONGO_SETUP_DIR}"
    docker compose down -v --remove-orphans 2>/dev/null || true 
    cd ..
    echo "INFO: Cluster MongoDB arrestato e pulito."
}

function run_ycsb_tests() {
    echo "INFO: Esecuzione test YCSB per MongoDB..."
    mkdir -p "$(pwd)/results/${DB_USER_SUBDIR}"

    declare -a SCENARIOS_DEF
    SCENARIOS_DEF[0]="10000 10000 10 100 true"
    SCENARIOS_DEF[1]="100000 10000 10 100 true"
    SCENARIOS_DEF[2]="250000 10000 10 100 true"
    SCENARIOS_DEF[3]="10000 10000 1 1000 true"
    SCENARIOS_DEF[4]="10000 10000 10 100 false"

    declare -a scenario_indices_to_run
    if [ "$#" -eq 0 ]; then
        scenario_indices_to_run=("${!SCENARIOS_DEF[@]}")
        echo "INFO: Nessuno scenario specificato, esecuzione di tutti gli scenari (1-${#SCENARIOS_DEF[@]})."
    else
        for user_scenario_num_arg in "$@"; do
            if ! [[ "${user_scenario_num_arg}" =~ ^[1-5]$ ]]; then
                echo "WARN: Numero di scenario '${user_scenario_num_arg}' non valido (deve essere tra 1 e ${#SCENARIOS_DEF[@]}). Verrà ignorato."
                continue
            fi
            local target_index=$((user_scenario_num_arg - 1))
            if [ -n "${SCENARIOS_DEF[${target_index}]-}" ]; then
                local already_added=0
                # C-style loop for duplicate check
                local len_check_dup=${#scenario_indices_to_run[@]}
                for ((d_idx = 0; d_idx < len_check_dup; d_idx++)); do
                    if [ "${scenario_indices_to_run[d_idx]}" -eq "${target_index}" ]; then
                        already_added=1
                        break
                    fi
                done
                if [ "${already_added}" -eq 0 ]; then scenario_indices_to_run+=("${target_index}"); fi
            else
                echo "WARN: Scenario '${user_scenario_num_arg}' (indice ${target_index}) non definito internamente. Verrà ignorato."
            fi
        done
        if [ ${#scenario_indices_to_run[@]} -eq 0 ]; then
            echo "ERROR: Nessuno scenario valido specificato. Uscita."; exit 1;
        fi
        
        local n_sort=${#scenario_indices_to_run[@]}
        if [ "${n_sort}" -gt 1 ]; then
            for ((i_sort = 0; i_sort < n_sort; i_sort++)); do
                for ((j_sort = 0; j_sort < n_sort - i_sort - 1; j_sort++)); do
                    if ((${scenario_indices_to_run[j_sort]} > ${scenario_indices_to_run[j_sort+1]})); then
                        local temp_sort=${scenario_indices_to_run[j_sort]}
                        scenario_indices_to_run[j_sort]=${scenario_indices_to_run[j_sort+1]}
                        scenario_indices_to_run[j_sort+1]=$temp_sort
                    fi
                done
            done
        fi

        local user_friendly_scenarios_selected_str=""
        local num_to_print=${#scenario_indices_to_run[@]}
        if [ "$num_to_print" -gt 0 ]; then
            for ((p_idx = 0; p_idx < num_to_print; p_idx++)); do
                user_friendly_scenarios_selected_str+="$((scenario_indices_to_run[p_idx] + 1)) "
            done
            # Trim trailing space for neatness
            user_friendly_scenarios_selected_str=${user_friendly_scenarios_selected_str%% }
        fi
        echo "INFO: Esecuzione scenari specificati: ${user_friendly_scenarios_selected_str}"
    fi

    local num_selected_indices=${#scenario_indices_to_run[@]}
    if [ "$num_selected_indices" -eq 0 ] && [ "$#" -ne 0 ]; then
         # This case should be caught by the earlier exit, but as a safeguard:
        echo "ERROR: Logica interna ha portato a nessun scenario selezionato nonostante gli argomenti. Uscita."
        exit 1
    elif [ "$num_selected_indices" -eq 0 ] && [ "$#" -eq 0 ]; then
        # If running all and SCENARIOS_DEF was empty (it's not, but defensive)
        echo "INFO: Nessuno scenario definito per l'esecuzione (caso 'tutti gli scenari')."
        # Allow script to complete without error if it means running zero YCSB tests.
        # Or, could exit 1 if this is considered an error state.
    fi

    for (( k=0; k < num_selected_indices; k++ )); do
        local scenario_idx=${scenario_indices_to_run[k]}
        local current_user_scenario_num=$((scenario_idx + 1))
        read -r RC OC FC FL RAF <<< "${SCENARIOS_DEF[${scenario_idx}]}"
        echo "INFO: Starting Scenario ${current_user_scenario_num}: RC=${RC}, OC=${OC}, FC=${FC}, FL=${FL}, RAF=${RAF}"

        for workload_name in "${DEFAULT_WORKLOADS[@]}"; do
            echo "INFO: Processing Workload: ${workload_name} for Scenario ${current_user_scenario_num}"
            for (( rep_num=1; rep_num<=${REPETITIONS}; rep_num++ )); do
                echo "INFO: Repetition ${rep_num}/${REPETITIONS} for Workload ${workload_name}, Scenario ${current_user_scenario_num}"
                
                CONTAINER_NAME="ycsb_mongo_runner_scen${current_user_scenario_num}_wl${workload_name}_rep${rep_num}"
                echo "DEBUG: YCSB_IMAGE_NAME is '${YCSB_IMAGE_NAME}'"
                echo "DEBUG: Attempting to run container with name: '${CONTAINER_NAME}'"
                echo "DEBUG: Full command (approximate, quoting may vary slightly in actual execution by shell):
                docker run --rm --name \"${CONTAINER_NAME}\" --network \"${DOCKER_NETWORK}\" -v \"$(pwd)/results:/results\" --env-file .env \"${YCSB_IMAGE_NAME}\" \"${YCSB_MONGO_SCRIPT_PATH_IN_CONTAINER}\" \"${workload_name}\" \"${rep_num}\" \"${RC}\" \"${OC}\" \"${FC}\" \"${FL}\" \"${RAF}\" \"${DB_USER_SUBDIR}\""

                docker run --rm --name "${CONTAINER_NAME}" --network "${DOCKER_NETWORK}" -v "$(pwd)/results:/results" --env-file .env "${YCSB_IMAGE_NAME}" "${YCSB_MONGO_SCRIPT_PATH_IN_CONTAINER}" "${workload_name}" "${rep_num}" "${RC}" "${OC}" "${FC}" "${FL}" "${RAF}" "${DB_USER_SUBDIR}"
                
                echo "INFO: Completed Repetition ${rep_num} for Workload ${workload_name}, Scenario ${current_user_scenario_num}"
                sleep 5 
            done 
            echo "INFO: Completed all repetitions for Workload ${workload_name}, Scenario ${current_user_scenario_num}"
        done 
        echo "INFO: Completed Scenario ${current_user_scenario_num}"
        sleep 10 
    done 
    
    echo "INFO: Tutti i test YCSB per MongoDB completati. Controlla la directory 'results/${DB_USER_SUBDIR}'."
}

# Trap per assicurare la pulizia anche in caso di errore o interruzione
trap 'echo "WARN: Script interrotto. Tentativo di pulizia finale..."; stop_mongo_cluster' EXIT SIGINT SIGTERM

# --- Flusso Principale ---
echo "INFO: Pulizia preliminare di qualsiasi istanza MongoDB precedente..."
stop_mongo_cluster 
sleep 5

docker network inspect "${DOCKER_NETWORK}" >/dev/null 2>&1 || {
    echo "INFO: Creazione rete Docker '${DOCKER_NETWORK}'..."
    docker network create "${DOCKER_NETWORK}"
}

start_mongo_cluster
# Pass script arguments ($@) to the test function to select scenarios
run_ycsb_tests "$@"

echo "INFO: Esecuzione benchmark MongoDB completata."
trap - EXIT
exit 0