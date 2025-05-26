# Comparazione Prestazioni NoSQL DBMS con YCSB

Questo progetto confronta le prestazioni tecniche di tre tipi di DBMS NoSQL:
*   **Key-value store:** Redis (Cluster Mode - 3 nodi)
*   **Document store:** MongoDB (Replica Set - 1 shard con 3 nodi)
*   **Column-family store:** Cassandra (Ring - 3 nodi)

Il framework di benchmarking utilizzato è Yahoo! Cloud Serving Benchmark (YCSB), versione 0.17.0. Tutti i test vengono eseguiti in container Docker.

## Struttura del Progetto

```
nosql-benchmark-comparison/
  ├─ redis/                    ← Configurazione cluster Redis
  │    └─ docker-compose.yml
  ├─ mongo/                    ← Configurazione cluster MongoDB (Replica Set)
  │    └─ docker-compose.yml
  ├─ cassandra/                ← Configurazione ring Cassandra
  │    └─ docker-compose.yml
  ├─ ycsb/                     ← Sorgenti YCSB, Dockerfile, script di esecuzione YCSB per DB
  ├─ results/                  ← Output dei test (file .txt)
  ├─ plots/                    ← Grafici generati da plot_results.py
  │    ├─ [user_name]/         # Grafici dettagliati per utente
  │    └─ summary/             # Grafici di sommario e per presentazioni
  │         └─ presentation/
  ├─ .env.example
  ├─ run_mongo_benchmarks.sh   ← Script orchestratore per MongoDB
  ├─ run_cassandra_benchmarks.sh ← Script orchestratore per Cassandra
  ├─ run_redis_benchmarks.sh   ← Script orchestratore per Redis Cluster
  ├─ plot_results.py           ← Script Python per analizzare e plottare i risultati
  └─ README.md
```

## Prerequisiti
*   Docker, Docker Compose, `git`
*   Python 3.x con `pandas`, `matplotlib`, `seaborn` (per `plot_results.py`)

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

Gli script orchestratori gestiscono l'avvio del cluster, l'esecuzione dei test YCSB e la pulizia.
I test sono strutturati per eseguire **7 scenari differenti** per ciascuno dei 6 workload standard YCSB (A-F). Ogni scenario viene ripetuto 3 volte.

**Parametri di Scenario Comuni:**
*   **fieldcount**: 10 (tranne S4)
*   **fieldlength**: 100 (tranne S4)
*   **readallfields**: true (tranne S5)

**Scenari di Test (per ogni workload e ripetizione):**
1.  **S1: Baseline (1 Thread)**
    *   `recordcount=10000`, `operationcount=10000`, `threads=1`
    *   `fc=10, fl=100, raf=true`
2.  **S2: Dataset Medio (1 Thread)**
    *   `recordcount=100000`, `operationcount=10000`, `threads=1`
    *   `fc=10, fl=100, raf=true`
3.  **S3: Dataset Grande (1 Thread)**
    *   `recordcount=250000`, `operationcount=10000`, `threads=1`
    *   `fc=10, fl=100, raf=true`
4.  **S4: Campo Singolo Grande (1 Thread)**
    *   `recordcount=10000`, `operationcount=10000`, `threads=1`
    *   `fc=1, fl=1000, raf=true`
5.  **S5: Lettura Selettiva (1 Thread)**
    *   `recordcount=10000`, `operationcount=10000`, `threads=1`
    *   `fc=10, fl=100, raf=false`
6.  **S6: Baseline Alta Concorrenza (8 Threads)**
    *   `recordcount=10000`, `operationcount=10000`, `threads=8`
    *   `fc=10, fl=100, raf=true` (Parametri di S1 con più threads)
7.  **S7: Dataset Grande Alta Concorrenza (8 Threads)**
    *   `recordcount=250000`, `operationcount=10000`, `threads=8`
    *   `fc=10, fl=100, raf=true` (Parametri di S3 con più threads)

Batch size specifici per database:
*   MongoDB: 500
*   Cassandra: 100 (per `load`)
*   Redis: Non applicabile (YCSB gestisce la pipeline)

**Importante:** Eseguire un solo script di benchmark alla volta.

### 1. Esecuzione Benchmark per MongoDB
```bash
chmod +x run_mongo_benchmarks.sh
# Esegue tutti e 7 gli scenari:
./run_mongo_benchmarks.sh 
# Esegue scenari specifici (es. 1, 6 e 7):
./run_mongo_benchmarks.sh 1 6 7
```

### 2. Esecuzione Benchmark per Cassandra
```bash
chmod +x run_cassandra_benchmarks.sh
# Esegue tutti e 7 gli scenari:
./run_cassandra_benchmarks.sh
# Esegue scenari specifici:
./run_cassandra_benchmarks.sh 1 6 7
```

### 3. Esecuzione Benchmark per Redis (Cluster Mode)
```bash
chmod +x run_redis_benchmarks.sh
# Esegue tutti e 7 gli scenari:
./run_redis_benchmarks.sh
# Esegue scenari specifici:
./run_redis_benchmarks.sh 1 6 7
```

## Flusso di Esecuzione (Per Ogni Database)
1.  Pulizia Preliminare.
2.  Avvio Cluster del DB.
3.  Attesa/Inizializzazione (per MongoDB, inizializza il Replica Set).
4.  **Esecuzione YCSB:** Lancia container `nosql-benchmark/ycsb`.
    *   Il container esegue `ycsb/run-[database].sh` passando i parametri dello scenario corrente (workload, ripetizione, counts vari, field params, **threads**) e la sottodirectory utente (es. "nicolò").
5.  **Script Interno YCSB (`ycsb/run-*.sh`):
    *   Pulisce DB (se necessario, es. dropDatabase per Mongo, Keyspace per Cassandra).
    *   Esegue `load` YCSB con i parametri e **threads** dello scenario.
    *   Esegue `run` YCSB con i parametri e **threads** dello scenario.
    *   Salva output in `/results` secondo la nuova struttura.
6.  Pulizia Finale.

## Risultati

Output grezzi YCSB salvati in `results/[nome_utente_specificato_nello_script_orchestratore]/`.
La struttura delle directory per i singoli test è ora:
`results/[user]/[db]/[workload]/rc[X]_oc[Y]_fc[F]_fl[L]_raf[R]_th[T]/[phase]_rep[N]_[YYYY-MM-DD_HH-MM-SS].txt`

Dove `_th[T]` indica il numero di threads usati (es. `_th1` o `_th8`).

Esempio aggiornato:
`results/nicolò/mongodb/workloada/rc10000_oc10000_fc10_fl100_raftrue_th1/load_rep1_2024-07-30_10-00-00.txt`

## Analisi e Visualizzazione dei Risultati
Lo script `plot_results.py` è stato fornito per automatizzare l'analisi dei file di output e la generazione di grafici.

**Per usarlo:**
1.  Assicurati di avere installato le librerie Python necessarie:
    ```bash
    pip install pandas matplotlib seaborn
    ```
2.  Esegui lo script dalla root del progetto:
    ```bash
    python plot_results.py
    ```
Lo script:
*   Analizza tutti i file di risultato nella directory `results/` (per tutti gli utenti).
*   Genera grafici dettagliati per utente, workload e database in `plots/[nome_utente]/`.
*   Genera grafici di sommario e per presentazioni in `plots/summary/` e `plots/summary/presentation/`.
    *   Questi includono comparazioni di CPU, profili di workload, performance aggregate dei DB, e impatto degli scenari.

## TODO / Prossimi Passi
*   Completare i cicli di benchmark con la nuova configurazione a 7 scenari.
*   Applicare limiti di risorse Docker consistenti (se non già fatto) e rieseguire i test.
*   Analizzare i grafici generati da `plot_results.py`.
*   Redigere il report finale del progetto.