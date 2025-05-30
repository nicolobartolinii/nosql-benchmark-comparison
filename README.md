# Comparazione Prestazioni NoSQL DBMS con YCSB

Il seguente progetto confronta le prestazioni tecniche di tre tipi di DBMS NoSQL:
*   **Key-value store:** Redis (Cluster Mode - 3 nodi)
*   **Document store:** MongoDB (Replica Set - 1 shard primario con 2 secondari, totale 3 nodi)
*   **Column-family store:** Cassandra (Ring - 3 nodi)


Per i test, viene usato il framework di benchmarking Yahoo! Cloud Serving Benchmark (YCSB), versione 0.17.0. Per tenere tutto pulito e replicabile, tutti i test vengono eseguire su container Docker
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
  │    ├─ Dockerfile            # Include Cassandra(cqlsh), Mongo(mongosh), Python3 fix, RedisClient fix
  │    ├─ entrypoint.sh
  │    ├─ run-mongo.sh          # Script interno YCSB per test MongoDB (parametrizzato)
  │    ├─ run-redis.sh          # Script interno YCSB per test Redis Cluster (parametrizzato)
  │    ├─ run-cassandra.sh      # Script interno YCSB per test Cassandra (parametrizzato)
  │    ├─ ycsb_python3.py       # Script bin/ycsb corretto per Python 3
  │    └─ RedisClient.java      # File sorgente RedisClient corretto
  ├─ results/                  ← Output dei test (file .txt), suddivisi per utente
  │    ├─ nick/                 # Risultati per l'utente Nicolò (Apple M2 Pro)
  │    │  ├─ [database]/       # Es. mongo, cassandra, redis
  │    │  │  └─ [workload]/     # Es. workloada, workloadb, ...
  │    │  │     └─ [scenario_rcX_ocY_fcF_flL_rafR_thT]/ # Dettagli scenario e threads
  │    │  │        └─ [phase]_repN_[timestamp].txt      # Es. run_rep1_2024-07-30_10-00-00.txt
  │    ├─ andrea/               # (Potenziali risultati per altri utenti con vecchia struttura)
  │    └─ nicola/               # (Potenziali risultati per altri utenti con vecchia struttura)
  ├─ plots/                    ← Grafici generati dagli script Python
  │    ├─ nick/                 # Grafici dettagliati e di analisi per Nicolò
  │    │  └─ analysis/         # Grafici di analisi specifici per Nicolò
  │    └─ summary/             
  │       ├─ nick/              # Grafici di sommario per Nicolò
  │       │  └─ presentation/   # Grafici per presentazioni (basati sui dati di Nicolò)
  │       └─ (altri utenti se presenti e processati da plot_results.py)
  ├─ .env.example              ← Template per le variabili d'ambiente
  ├─ .gitignore
  ├─ run_mongo_benchmarks.sh   ← Script orchestratore per MongoDB
  ├─ run_cassandra_benchmarks.sh ← Script orchestratore per Cassandra
  ├─ run_redis_benchmarks.sh   ← Script orchestratore per Redis Cluster
  ├─ plot_results.py           ← Script Python per analizzare e plottare i risultati (multi-utente, per archivi storici o future comparazioni)
  ├─ plot_results_single_user.py ← Script Python focalizzato sull'analisi dei risultati di 'nick' (utente principale)
  └─ README.md                 # Questo file
```

## Prerequisiti
AL fine di poter eseguire i test e analizzare i risultati, bisogna avere installato i seguenti strumenti:

*   Docker ([Installazione](https://docs.docker.com/get-docker/))
*   Docker Compose ([Installazione](https://docs.docker.com/compose/install/))
*   `git` (per clonare il repository)
*   Un editor di testo per il file `.env`
*   Python 3.x con `pandas`, `matplotlib`, `seaborn`, `numpy` (per gli script `plot_*.py`)
    ```bash
    pip install pandas matplotlib seaborn numpy
    ```

## Setup Iniziale
Di seguito sono riportati i passaggi per configurare il proprio ambiente di test e preparare i container Docker per i benchmark.
Ovviamente, è necessario aver installato i prerequisiti elencati sopra, ed essere nella root del progetto dopo aver clonato il repository.
1.  **Clonare il Repository:**
    ```bash
    git clone https://github.com/nicolobartolinii/nosql-benchmark-comparison.git
    cd nosql-benchmark-comparison
    ```

2.  **Configurare le Variabili d'Ambiente:**
    Copia il file di esempio `.env.example` in `.env` e personalizzalo se necessario. Per i test locali con Docker, i valori di default che usano i nomi dei servizi Docker dovrebbero andare bene.
    ```bash
    cp .env.example .env
    ```
    Contenuto di `.env` (esempio):
    ```dotenv
    REDIS_NODES=redis-node1:6379,redis-node2:6379,redis-node3:6379
    MONGO_URL=mongodb://mongo-mongos:27017/ycsb?w=1
    CASS_HOSTS=cassandra-1,cassandra-2,cassandra-3
    ```

3.  **Costruire l'Immagine Docker di YCSB:**
    Questo comando compila YCSB 0.17.0 dai sorgenti, applica le patch necessarie per Python 3 e RedisClient, installa i client (`mongosh`, `cqlsh`) e crea l'immagine `nosql-benchmark/ycsb`.
    ```bash
    cd ycsb
    docker build --no-cache -t nosql-benchmark/ycsb .
    cd ..
    ```

4.  **Creare la Rete Docker Condivisa:**
    ```bash
    docker network create shared-net || true
    ```

## Esecuzione dei Benchmark

Gli script orchestratori inseriti nel file (`run_*.sh`) gestiscono l'avvio del cluster,  l'esecuzione dei test YCSB e la pulizia finale. I test sono strutturati per eseguire **7 scenari differenti** per ciascuno dei 6 workload standard YCSB (A-F), inoltre ogni combinazione di scenario e workload viene ripetuta 3 volte.

**Parametri Comuni degli Scenari** (a meno di diversa specificazione):

*   `fieldcount=10`
*   `fieldlength=100`
*   `readallfields=true`

Ovviamente questi parametri possono essere modificati per ogni scenario specifico.

**Definizione degli Scenari di Test:**
Gli scenari che sono stati pensati e creati per coprire una varietà di casi d'uso e configurazioni sono i seguenti:

1.  **S1: Baseline (1 Thread)**
    *   `recordcount=10000`, `operationcount=10000`, `threads=1`
2.  **S2: Dataset Medio (1 Thread)**
    *   `recordcount=100000`, `operationcount=10000`, `threads=1`
3.  **S3: Dataset Grande (1 Thread)**
    *   `recordcount=250000`, `operationcount=10000`, `threads=1`
4.  **S4: Campo Singolo Grande (1 Thread)**
    *   `recordcount=10000`, `operationcount=10000`, `threads=1`
    *   (`fieldcount=1`, `fieldlength=1000`)
5.  **S5: Lettura Selettiva (1 Thread)**
    *   `recordcount=10000`, `operationcount=10000`, `threads=1`
    *   (`readallfields=false`)
6.  **S6: Baseline Alta Concorrenza (8 Threads)**
    *   `recordcount=10000`, `operationcount=10000`, `threads=8`
    *   (Stessi parametri di S1, ma con 8 threads)
7.  **S7: Dataset Grande Alta Concorrenza (8 Threads)**
    *   `recordcount=250000`, `operationcount=10000`, `threads=8`
    *   (Stessi parametri di S3, ma con 8 threads)

**Batch Size Specifici per Database (usati da YCSB):**
*   MongoDB: `mongodb.batchsize=500`
*   Cassandra: `cassandra.batchsize=100` (solo per la fase di `load`)
*   Redis: Non applicabile (YCSB gestisce la pipeline internamente)

**Importante:** Eseguire un solo script di benchmark (`run_*.sh`) alla volta per evitare conflitti di risorse.

### Esempi di Esecuzione dei Test

Assicurati che Docker sia in esecuzione e di essere nella root del progetto.

**Per MongoDB:**
```bash
chmod +x run_mongo_benchmarks.sh
# Esegue tutti e 7 gli scenari:
./run_mongo_benchmarks.sh 
# Esegue scenari specifici (es. S1, S6, S7):
./run_mongo_benchmarks.sh 1 6 7
```

**Per Cassandra:**
```bash
chmod +x run_cassandra_benchmarks.sh
# Esegue tutti e 7 gli scenari:
./run_cassandra_benchmarks.sh
# Esegue scenari specifici:
./run_cassandra_benchmarks.sh 1 6 7
```

**Per Redis Cluster:**
```bash
chmod +x run_redis_benchmarks.sh
# Esegue tutti e 7 gli scenari:
./run_redis_benchmarks.sh
# Esegue scenari specifici:
./run_redis_benchmarks.sh 1 6 7
```

## Flusso di Esecuzione (Per Ogni Database)

1.  **Pulizia Preliminare:** Arresto e rimozione di eventuali container/volumi del database da esecuzioni precedenti.
2.  **Avvio Cluster:** Avvio del cluster del database utilizzando il rispettivo file `[database]/docker-compose.yml`.
3.  **Attesa/Inizializzazione:** Attesa che il cluster sia stabile e pronto (con controlli specifici per MongoDB Replica Set, Cassandra ring, e Redis Cluster).
4.  **Esecuzione YCSB:** Viene lanciato un container Docker dall'immagine `nosql-benchmark/ycsb`.
    *   Questo container esegue lo script `ycsb/run-[database].sh` appropriato.
    *   Allo script interno vengono passati i parametri per lo scenario corrente: nome del workload (es. `workloada`), numero di ripetizione, `recordcount`, `operationcount`, `fieldcount`, `fieldlength`, `readallfields`, `DB_USER_SUBDIR` (es. "nick"), e il numero di `threads`.
5.  **Script Interno YCSB (`ycsb/run-[database].sh`):
    *   **Prima della fase `load`:** Pulisce lo stato precedente del database (es. `db.dropDatabase()` per MongoDB, `DROP KEYSPACE` per Cassandra; Redis viene resettato dal riavvio del cluster gestito dallo script orchestratore).
    *   Esegue la fase `load` di YCSB con i parametri e i `threads` specifici dello scenario.
    *   Esegue la fase `run` (transazioni) di YCSB con i parametri e i `threads` specifici dello scenario.
    *   Salva l'output testuale di `load` e `run` in file separati nella directory `/results` (montata dall'host), seguendo la struttura definita.
6.  **Pulizia Finale:** Arresto e rimozione dei container e volumi del database.

## Risultati

I file di output grezzi di YCSB (formato testo) vengono salvati nella directory `results/[nome_utente_specificato_nello_script_orchestratore]/` sull'host.
La struttura delle directory per i singoli test è ora:
`results/[user]/[database]/[workload]/rc[X]_oc[Y]_fc[F]_fl[L]_raf[R]_th[T]/[phase]_rep[N]_[YYYY-MM-DD_HH-MM-SS].txt`

Dove:
*   `[user]`: Nome dell'utente che ha eseguito il test (es. `nick`).
*   `[database]`: `mongodb`, `cassandra`, `redis`.
*   `[workload]`: `workloada`, `workloadb`, ..., `workloadf`.
*   Parametri scenario:
    *   `rc[X]`: Conteggio record (es. `rc10000`).
    *   `oc[Y]`: Conteggio operazioni (es. `oc10000`).
    *   `fc[F]`: Conteggio campi (es. `fc10`).
    *   `fl[L]`: Lunghezza campo (es. `fl100`).
    *   `raf[R]`: Lettura di tutti i campi (`raftrue` o `raffalse`).
    *   `th[T]`: Numero di thread client YCSB (es. `th1`, `th8`).
*   `[phase]`: `load` o `run`.
*   `rep[N]`: Numero di ripetizione (es. `rep1`).
*   `[YYYY-MM-DD_HH-MM-SS]`: Timestamp della generazione del file (UTC+2).

Esempio aggiornato:
`results/nick/mongodb/workloada/rc10000_oc10000_fc10_fl100_raftrue_th1/load_rep1_2024-07-30_10-00-00.txt`

## Analisi e Visualizzazione dei Risultati
Per facilitare l'analisi dei risultati ottenuti dai test, sono stati sviluppato due script Python che permettono di generare grafici e visualizzazioni basate sui dati raccolti.

1.  **`plot_results.py` (Multi-Utente/Storico):**
    *   Progettato per analizzare i dati di **tutti gli utenti** presenti nella directory `results/` che hanno una struttura di directory compatibile (inclusa la parte `_th[THREADS]`).
    *   Utile per comparazioni storiche o se altri utenti eseguono test con la stessa struttura.
    *   Genera grafici comparativi tra CPU (utenti), oltre a grafici dettagliati e di sommario per ciascun utente.
    *   Salva i grafici in `plots/[user_name]/` e `plots/summary/`.

2.  **`plot_results_single_user.py` (Focus Utente 'nick'):**
    *   Configurato per analizzare specificamente i risultati dell'utente **'nick'** (Nicolò Bartolini - Apple M2 Pro). La variabile `TARGET_USER_NORMALIZED` nello script è impostata su `'nick'`.
    *   Genera un set completo di grafici dettagliati, di analisi e per presentazioni basati esclusivamente sui dati di questo utente.
    *   Omette i grafici di comparazione diretta tra CPU.
    *   Salva i grafici in `plots/nick/`, `plots/nick/analysis/`, e `plots/summary/nick/presentation/`.

**Per utilizzare gli script di plotting:**
1.  Assicurati di avere installato le librerie Python necessarie (vedi sezione Prerequisiti).
2.  Esegui lo script desiderato dalla root del progetto:
    ```bash
    # Per analizzare e plottare solo i risultati di 'nick'
    python plot_results_single_user.py

    # Per un'analisi multi-utente (se applicabile)
    # python plot_results.py 
    ```

Gli script generano una vasta gamma di visualizzazioni, tra cui:
*   Comparazioni di Throughput e Latenza per workload, database e scenario.
*   Grafici di percentili di Latenza (Media, P95, P99).
*   Heatmap di Latenza per operazione e scenario.
*   Grafici Throughput vs. Latenza.
*   Analisi dell'impatto dello scaling dei Thread YCSB.
*   Box plots sulla stabilità della Latenza tra le ripetizioni per scenari chiave.
*   Grafici di sommario e per presentazioni che aggregano le performance.