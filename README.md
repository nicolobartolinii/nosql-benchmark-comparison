# Comparazione Prestazioni NoSQL DBMS con YCSB

Questo progetto confronta le prestazioni tecniche di tre tipi di DBMS NoSQL:
*   **Key-value store:** Redis
*   **Document store:** MongoDB (Sharded Cluster)
*   **Column-family store:** Cassandra (Ring)

Il framework di benchmarking utilizzato è Yahoo! Cloud Serving Benchmark (YCSB). Tutti i test vengono eseguiti in container Docker, sia in modalità cluster distribuito sia su hardware standardizzato (tramite limiti di risorse Docker), per normalizzare i risultati.

## Struttura del Progetto

```
nosql-benchmark-comparison/
  ├─ redis/                    ← Configurazione cluster Redis
  │    └─ docker-compose.yml
  ├─ mongo/                    ← Configurazione cluster MongoDB sharded
  │    └─ docker-compose.yml
  ├─ cassandra/                ← Configurazione ring Cassandra
  │    └─ docker-compose.yml
  ├─ ycsb/                     ← Sorgenti YCSB, Dockerfile per build, script di esecuzione
  │    ├─ Dockerfile
  │    ├─ entrypoint.sh
  │    ├─ run-mongo.sh
  │    ├─ run-redis.sh
  │    ├─ run-cassandra.sh
  │    └─ ycsb_python3.py       # Script bin/ycsb corretto per Python 3
  ├─ results/                  ← Output dei test (file .txt e grafici futuri)
  ├─ .env.example              ← Template per le variabili d'ambiente
  ├─ .gitignore
  ├─ run_mongo_benchmarks.sh   ← Script orchestratore per MongoDB
  └─ README.md
```

## Prerequisiti

*   Docker ([Installazione](https://docs.docker.com/get-docker/))
*   Docker Compose ([Installazione](https://docs.docker.com/compose/install/)) (solitamente incluso con Docker Desktop)
*   `git` (per clonare il repository)
*   Un editor di testo per il file `.env`

## Setup Iniziale

1.  **Clonare il Repository:**
    ```bash
    git clone https://github.com/nicolobartolinii/nosql-benchmark-comparison
    cd nosql-benchmark-comparison
    ```

2.  **Configurare le Variabili d'Ambiente:**
    Copia il file di esempio `.env.example` in `.env` e personalizzalo se necessario. Per i test locali con Docker, i valori di default che usano i nomi dei servizi Docker dovrebbero andare bene.
    ```bash
    cp .env.example .env
    ```
    Esempio di contenuto per `.env`:
    ```dotenv
    # Redis cluster nodes (usato da ycsb/run-redis.sh)
    REDIS_NODES=redis-node1:6379,redis-node2:6379,redis-node3:6379

    # MongoDB router URL (usato da ycsb/run-mongo.sh)
    MONGO_URL=mongodb://mongo-mongos:27017/ycsb?w=1

    # Cassandra hosts CSV (usato da ycsb/run-cassandra.sh)
    CASS_HOSTS=cassandra-1,cassandra-2,cassandra-3
    ```

3.  **Costruire l'Immagine Docker di YCSB:**
    Questo comando compila YCSB dai sorgenti (con le patch necessarie) e crea l'immagine Docker che verrà usata per eseguire i benchmark.
    ```bash
    cd ycsb
    docker build -t nosql-benchmark/ycsb .
    cd ..
    ```

4.  **Creare la Rete Docker Condivisa (se non già presente):**
    Gli script di orchestrazione e i `docker-compose.yml` potrebbero aspettarsi una rete condivisa per la comunicazione tra il container YCSB e i cluster dei database.
    ```bash
    docker network create shared-net || true
    ```
    Assicurati che i file `docker-compose.yml` dei database siano configurati per connettersi a questa rete (es. `shared-net`).

## Esecuzione dei Benchmark

Verranno forniti script orchestratori per ogni database (es. `run_mongo_benchmarks.sh`). Questi script gestiscono l'avvio del cluster del database, l'esecuzione dei test YCSB (tutti i workload rilevanti, con ripetizioni) e la pulizia finale.

### Esempio: Esecuzione Benchmark per MongoDB

Lo script `run_mongo_benchmarks.sh` automatizza l'intero processo per MongoDB.

1.  **Assicurati che Docker sia in esecuzione.**
2.  **Dalla root del progetto, rendi lo script eseguibile (solo la prima volta):**
    ```bash
    chmod +x run_mongo_benchmarks.sh
    ```
3.  **Avvia i benchmark per MongoDB:**
    *   Per eseguire tutti i workload YCSB di default (A-F), con 3 ripetizioni ciascuno e 10.000 record:
        ```bash
        ./run_mongo_benchmarks.sh
        ```
    *   Per eseguire solo workload specifici (es. `workloada` e `workloadc`):
        ```bash
        ./run_mongo_benchmarks.sh workloada workloadc
        ```

Lo script si occuperà di:
*   Pulire eventuali istanze precedenti del cluster MongoDB.
*   Avviare il cluster MongoDB sharded usando `mongo/docker-compose.yml`.
*   Inizializzare i replica set e lo sharding.
*   Lanciare il container YCSB (`nosql-benchmark/ycsb`) che eseguirà lo script `ycsb/run-mongo.sh`.
    *   `ycsb/run-mongo.sh` ciclerà attraverso i workload, pulirà il DB YCSB prima di ogni `load`, ed eseguirà le fasi `load` e `run`.
*   Salvare i risultati nella directory `results/`.
*   Arrestare e pulire il cluster MongoDB al termine.

*(Sezioni simili verranno aggiunte per Redis e Cassandra una volta implementati i rispettivi script orchestratori).*

## Risultati

I file di output grezzi di YCSB (formato testo) verranno salvati nella directory `results/`.
I nomi dei file seguiranno un pattern simile a: `[database]_[workload]_[fase]_[ripetizione]_[timestamp].txt`.

Esempio: `mongo_workloada_run_rep1_20230508103000.txt`

L'analisi e la visualizzazione di questi risultati (grafici, tabelle comparative) sono fasi successive del progetto.

## TODO / Prossimi Passi

*   Implementare gli script orchestratori `run_redis_benchmarks.sh` e `run_cassandra_benchmarks.sh`.
*   Configurare e testare i cluster per Redis e Cassandra.
*   Adattare gli script `ycsb/run-redis.sh` e `ycsb/run-cassandra.sh` per l'automazione (cicli, parametri, pulizia).
*   Implementare la limitazione delle risorse Docker nei file `docker-compose.yml` per standardizzare l'hardware.
*   Sviluppare script per l'estrazione dei dati chiave e la generazione di grafici comparativi.
*   Redigere il report finale del progetto.