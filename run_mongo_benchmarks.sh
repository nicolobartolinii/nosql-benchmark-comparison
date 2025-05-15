#!/bin/bash
set -euo pipefail

# --- Configurazione ---
MONGO_SETUP_DIR="mongo"
YCSB_IMAGE_NAME="nosql-benchmark/ycsb"
YCSB_MONGO_SCRIPT_PATH_IN_CONTAINER="./run-mongo.sh"
DOCKER_NETWORK="shared-net"

YCSB_SCRIPT_ARGS="$@"
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
    # L'opzione --quiet per mongosh sopprime l'output di successo, ma gli errori verranno mostrati.
    docker exec -it mongo-cfg1 mongosh --quiet --port 27019 --eval 'try { rs.initiate({_id:"cfgRS",configsvr:true,members:[{_id:0,host:"mongo-cfg1:27019"},{_id:1,host:"mongo-cfg2:27019"},{_id:2,host:"mongo-cfg3:27019"}]}) } catch (e) { if (e.codeName && e.codeName.toLowerCase().includes("alreadyinitialized")) { print("INFO: cfgRS già inizializzato."); } else { throw e; } }'
    sleep 10

    echo "INFO: Tentativo di inizializzazione Shard Replica Set (shard1RS)..."
    docker exec -it mongo-shard1a mongosh --quiet --port 27018 --eval 'try { rs.initiate({_id:"shard1RS",members:[{_id:0,host:"mongo-shard1a:27018"},{_id:1,host:"mongo-shard1b:27018"}]}) } catch (e) { if (e.codeName && e.codeName.toLowerCase().includes("alreadyinitialized")) { print("INFO: shard1RS già inizializzato."); } else { throw e; } }'
    sleep 10

    echo "INFO: Tentativo di inizializzazione Shard Replica Set (shard2RS)..."
    docker exec -it mongo-shard2a mongosh --quiet --port 27020 --eval 'try { rs.initiate({_id:"shard2RS",members:[{_id:0,host:"mongo-shard2a:27020"},{_id:1,host:"mongo-shard2b:27020"}]}) } catch (e) { if (e.codeName && e.codeName.toLowerCase().includes("alreadyinitialized")) { print("INFO: shard2RS già inizializzato."); } else { throw e; } }'
    sleep 10

    echo "INFO: Tentativo di aggiunta dello shard1RS al router mongos..."
    # Per sh.addShard(), l'idempotenza è più difficile da gestire con un semplice try-catch perché
    # potrebbe fallire per vari motivi se lo shard è già aggiunto o in uno stato intermedio.
    # Un modo è controllare prima sh.status(). Per ora, proviamo a eseguirlo.
    # Se fallisce perché lo shard esiste, potrebbe non essere un problema bloccante se lo stato è corretto.
    # Potremmo aggiungere un controllo sullo status per vedere se lo shard è già presente.
    # Esempio di controllo (più avanzato):
    # SHARD_EXISTS=$(docker exec -it mongo-mongos mongosh --quiet --eval 'sh.status().shards.some(shard => shard._id === "shard1RS")')
    # if [ "$SHARD_EXISTS" = "false" ]; then
    #    docker exec -it mongo-mongos mongosh --quiet --eval 'sh.addShard("shard1RS/mongo-shard1a:27018,mongo-shard1b:27018")'
    # else
    #    echo "INFO: Shard shard1RS già aggiunto."
    # fi
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
    # Ignora errori se i container non esistono (utile per la prima esecuzione o pulizia manuale)
    docker compose down -v --remove-orphans 2>/dev/null || true 
    cd ..
    echo "INFO: Cluster MongoDB arrestato e pulito."
}

function run_ycsb_tests() {
    echo "INFO: Esecuzione test YCSB per MongoDB..."
    mkdir -p "$(pwd)/results"

    docker run --rm --name ycsb_mongo_runner \
        --network "${DOCKER_NETWORK}" \
        -v "$(pwd)/results:/results" \
        --env-file .env \
        "${YCSB_IMAGE_NAME}" "${YCSB_MONGO_SCRIPT_PATH_IN_CONTAINER}" ${YCSB_SCRIPT_ARGS}
    
    echo "INFO: Test YCSB per MongoDB completati. Controlla la directory 'results'."
}

# Trap per assicurare la pulizia anche in caso di errore o interruzione
trap 'echo "WARN: Script interrotto. Tentativo di pulizia finale..."; stop_mongo_cluster' EXIT SIGINT SIGTERM

# --- Flusso Principale ---

# 0. Pulisci qualsiasi istanza precedente per partire da uno stato completamente vergine
echo "INFO: Pulizia preliminare di qualsiasi istanza MongoDB precedente..."
stop_mongo_cluster 
sleep 5 # Pausa per assicurarsi che le porte siano liberate ecc.

# 1. Crea la rete Docker se non esiste
docker network inspect "${DOCKER_NETWORK}" >/dev/null 2>&1 || {
    echo "INFO: Creazione rete Docker '${DOCKER_NETWORK}'..."
    docker network create "${DOCKER_NETWORK}"
}

# 2. Avvia e inizializza il cluster MongoDB
start_mongo_cluster

# 3. Esegui i test YCSB
run_ycsb_tests

# 4. Arresta e pulisci il cluster MongoDB (gestito principalmente dal trap EXIT)
# stop_mongo_cluster # Chiamato dal trap EXIT

echo "INFO: Esecuzione benchmark MongoDB completata."
trap - EXIT # Rimuove il trap per un'uscita pulita
exit 0