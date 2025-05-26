# Comparazione Prestazioni NoSQL DBMS con YCSB

Questo progetto confronta le prestazioni tecniche di tre tipi di DBMS NoSQL:
*   **Key-value store:** Redis (Cluster Mode)
*   **Document store:** MongoDB (Sharded Cluster)
*   **Column-family store:** Cassandra (Ring)

Il framework di benchmarking utilizzato è Yahoo! Cloud Serving Benchmark (YCSB), versione 0.17.0. Tutti i test vengono eseguiti in container Docker, sia in modalità cluster distribuito sia su hardware standardizzato (tramite limiti di risorse Docker), per normalizzare i risultati.

## Struttura del Progetto

```
nosql-benchmark-comparison/
  ├─ redis/                    ← Configurazione cluster Redis
  │    └─ docker-compose.yml
  ├─ mongo/                    ← Configurazione cluster MongoDB
  │    └─ docker-compose.yml
  ├─ cassandra/                ← Configurazione ring Cassandra
  │    └─ docker-compose.yml
  ├─ ycsb/                     ← Sorgenti YCSB, Dockerfile per build, script di esecuzione
  │    ├─ Dockerfile            # Include Cassandra(cqlsh), Mongo(mongosh), Python3 fix, RedisClient fix
  │    ├─ entrypoint.sh
  │    ├─ run-mongo.sh          # Script interno YCSB per test MongoDB
  │    ├─ run-redis.sh          # Script interno YCSB per test Redis Cluster
  │    ├─ run-cassandra.sh      # Script interno YCSB per test Cassandra
  │    ├─ ycsb_python3.py       # Script bin/ycsb corretto per Python 3 (usato nel Dockerfile)
  │    └─ RedisClient.java      # File sorgente RedisClient corretto (usato nel Dockerfile)
  ├─ results/                  ← Output dei test (file .txt e grafici futuri)
  ├─ .env.example              ← Template per le variabili d'ambiente
  ├─ .gitignore
  ├─ run_mongo_benchmarks.sh   ← Script orchestratore per MongoDB
  ├─ run_cassandra_benchmarks.sh ← Script orchestratore per Cassandra
  ├─ run_redis_benchmarks.sh   ← Script orchestratore per Redis Cluster
  └─ README.md                 # Questo file
```

## Prerequisiti

*   Docker ([Installazione](https://docs.docker.com/get-docker/))
*   Docker Compose ([Installazione](https://docs.docker.com/compose/install/))
*   `git` (per clonare il repository)
*   Un editor di testo per il file `.env`

## Setup Iniziale

1.  **Clonare il Repository:**
    ```bash
    git clone <URL_DEL_TUO_REPOSITORY>
    cd nosql-benchmark-comparison
    ```

2.  **Configurare le Variabili d'Ambiente:**
    Copia il file di esempio `.env.example` in `.env` e personalizzalo se necessario. Per i test locali con Docker, i valori di default che usano i nomi dei servizi Docker dovrebbero andare bene.
    ```bash
    cp .env.example .env
    ```
    Contenuto di `.env`:
    ```dotenv
    # Redis cluster nodes (usato da ycsb/run-redis.sh)
    REDIS_NODES=redis-node1:6379,redis-node2:6379,redis-node3:6379

    # MongoDB router URL (usato da ycsb/run-mongo.sh)
    MONGO_URL=mongodb://mongo-mongos:27017/ycsb?w=1

    # Cassandra hosts CSV (usato da ycsb/run-cassandra.sh)
    CASS_HOSTS=cassandra-1,cassandra-2,cassandra-3
    ```

3.  **Costruire l'Immagine Docker di YCSB:**
    Questo comando compila YCSB 0.17.0 dai sorgenti, applica le patch necessarie per Python 3 e RedisClient, installa i client necessari (`mongosh`, `cqlsh` da Cassandra 4.1) e crea l'immagine Docker (`nosql-benchmark/ycsb`) che verrà usata per eseguire i benchmark.
    ```bash
    # Potrebbe essere necessario eseguirlo con --no-cache se si modificano i file sorgente o script
    cd ycsb
    docker build --no-cache -t nosql-benchmark/ycsb .
    cd ..
    ```

4.  **Creare la Rete Docker Condivisa (se non già presente):**
    Gli script di orchestrazione e i `docker-compose.yml` si aspettano una rete condivisa per la comunicazione tra il container YCSB e i cluster dei database.
    ```bash
    docker network create shared-net || true
    ```
    Assicurati che i file `docker-compose.yml` dei database siano configurati per connettersi a questa rete (`shared-net`).

## Esecuzione dei Benchmark

Sono forniti script orchestratori per ogni database. Questi script gestiscono l'avvio del cluster del database, l'esecuzione dei test YCSB e la pulizia finale.

I test sono strutturati per eseguire 5 scenari differenti per ciascuno dei 6 workload standard YCSB (A-F). Ogni scenario viene ripetuto 3 volte.

**Scenari di Test (per ogni workload e ripetizione):**
1.  **Scenario 1 (Baseline):**
    *   `recordcount=10000`, `operationcount=10000`
    *   `fieldcount=10`, `fieldlength=100`, `readallfields=true` (Default YCSB)
2.  **Scenario 2 (Dataset Medio):**
    *   `recordcount=100000`, `operationcount=10000`
    *   `fieldcount=10`, `fieldlength=100`, `readallfields=true`
3.  **Scenario 3 (Dataset Grande):**
    *   `recordcount=250000`, `operationcount=10000`
    *   `fieldcount=10`, `fieldlength=100`, `readallfields=true`
4.  **Scenario 4 (Campo Singolo Grande):**
    *   `recordcount=10000`, `operationcount=10000`
    *   `fieldcount=1`, `fieldlength=1000`, `readallfields=true`
5.  **Scenario 5 (Lettura Selettiva Campi):**
    *   `recordcount=10000`, `operationcount=10000`
    *   `fieldcount=10`, `fieldlength=100`, `readallfields=false`

Batch size specifici per database:
*   MongoDB: 500
*   Cassandra: 100 (per `load`)
*   Redis: Non applicabile

**Importante:** Eseguire un solo script di benchmark alla volta, poiché avviano e fermano i rispettivi cluster di database.

### 1. Esecuzione Benchmark per MongoDB

```bash
# Assicurati che Docker sia in esecuzione.
# Dalla root del progetto:

# Rendi lo script eseguibile (solo la prima volta)
chmod +x run_mongo_benchmarks.sh

# Avvia i benchmark per MongoDB (tutti e 5 gli scenari, tutti i workload A-F, 3 ripetizioni)
./run_mongo_benchmarks.sh

# Per eseguire solo scenari specifici (es. scenario 1, 4 e 5):
# ./run_mongo_benchmarks.sh 1 4 5

# NOTA: Attualmente non è possibile selezionare workload specifici tramite argomenti
# quando si specificano gli scenari. Tutti i workload A-F verranno eseguiti per gli scenari scelti.
```

### 2. Esecuzione Benchmark per Cassandra

```bash
# Assicurati che Docker sia in esecuzione.
# Dalla root del progetto:

# Rendi lo script eseguibile (solo la prima volta)
chmod +x run_cassandra_benchmarks.sh

# Avvia i benchmark per Cassandra (tutti e 5 gli scenari, tutti i workload A-F, 3 ripetizioni)
./run_cassandra_benchmarks.sh

# Per eseguire solo scenari specifici (es. scenario 2 e 3):
# ./run_cassandra_benchmarks.sh 2 3
```

### 3. Esecuzione Benchmark per Redis (Cluster Mode)

```bash
# Assicurati che Docker sia in esecuzione.
# Dalla root del progetto:

# Rendi lo script eseguibile (solo la prima volta)
chmod +x run_redis_benchmarks.sh

# Avvia i benchmark per Redis Cluster (tutti e 5 gli scenari, tutti i workload A-F, 3 ripetizioni)
./run_redis_benchmarks.sh

# Per eseguire solo scenari specifici (es. scenario 1 e 5):
# ./run_redis_benchmarks.sh 1 5
```

## Flusso di Esecuzione (Per Ogni Database)

Gli script orchestratori (`run_*.sh` nella root) eseguono i seguenti passi:
1.  **Pulizia Preliminare:** Ferma e rimuove eventuali container/volumi del database da esecuzioni precedenti (`docker compose down -v`).
2.  **Avvio Cluster:** Avvia il cluster del database usando il rispettivo file `[database]/docker-compose.yml`.
3.  **Attesa/Inizializzazione:** Attende che il cluster sia stabile e pronto. Per MongoDB, inizializza i replica set per i due shard e li aggiunge al router.
4.  **Esecuzione YCSB:** Lancia un container Docker dall'immagine `nosql-benchmark/ycsb`.
    *   Questo container esegue lo script `ycsb/run-[database].sh` appropriato, passandogli i parametri per lo scenario corrente (workload, ripetizione, recordcount, operationcount, fieldcount, fieldlength, readallfields) e il nome della sottodirectory utente per i risultati (es. "nicolò").
5.  **Script Interno YCSB (`ycsb/run-*.sh`):
    *   **Prima di ogni fase `load`:** Pulisce lo stato precedente del database (es. `db.dropDatabase()` per Mongo).
    *   Esegue la fase `load` di YCSB con i parametri dello scenario corrente.
    *   Esegue la fase `run` (transazioni) di YCSB con i parametri dello scenario corrente.
    *   Salva l'output di `load` e `run` in file separati nella directory `/results` (montata dall'host), seguendo la struttura definita.
6.  **Pulizia Finale:** Ferma e rimuove i container e i volumi del database (`docker compose down -v`).

## Risultati

I file di output grezzi di YCSB (formato testo) vengono salvati nella directory `results/[nome_utente_specificato_nello_script_orchestratore]/` sull'host.
Ad esempio, per l'utente "nicolò", la struttura sarà:
`results/nicolò/[database]/[workload]/rc[X]_oc[Y]_fc[F]_fl[L]_raf[R]/[phase]_rep[N]_[YYYY-MM-DD_HH-MM-SS].txt`

Dove:
*   `[database]`: `mongodb`, `cassandra`, `redis`
*   `[workload]`: `workloada`, `workloadb`, ecc.
*   `rc[X]`: Conteggio record (es. `rc10000`)
*   `oc[Y]`: Conteggio operazioni (es. `oc10000`)
*   `fc[F]`: Conteggio campi (es. `fc10`)
*   `fl[L]`: Lunghezza campo (es. `fl100`)
*   `raf[R]`: Lettura di tutti i campi (es. `raftrue` o `raffalse`)
*   `[phase]`: `load` o `run`
*   `rep[N]`: Numero di ripetizione (es. `rep1`)
*   `[YYYY-MM-DD_HH-MM-SS]`: Timestamp della generazione del file (UTC+2)

Esempio:
`results/nicolò/mongodb/workloada/rc10000_oc10000_fc1_fl100_raftrue/load_rep1_2023-10-27_16-30-00.txt`

L'analisi e la visualizzazione di questi risultati (grafici, tabelle comparative) sono fasi successive del progetto.

## TODO / Prossimi Passi

*   Eseguire i cicli completi di benchmark per tutti e tre i database.
*   Concordare e applicare i limiti di risorse Docker nei `docker-compose.yml`.
*   **Rieseguire tutti i benchmark** con i limiti di risorse applicati.
*   Sviluppare script/metodi per estrarre i dati chiave (Throughput, Latenze) dai file di risultati.
*   Generare grafici comparativi e analizzare i risultati.
*   Redigere il report finale del progetto.