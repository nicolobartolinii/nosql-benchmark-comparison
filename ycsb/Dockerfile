# ycsb/Dockerfile
FROM eclipse-temurin:17-jdk-jammy
ARG YCSB_TAG=0.17.0
ARG CASSANDRA_VERSION=4.1.8

WORKDIR /opt

# Installazione dipendenze
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    git \
    maven \
    python3.10 \
    python-is-python3 \
    gnupg \
    wget \
    lsb-release \
 && rm -rf /var/lib/apt/lists/*

# Installazione di mongodb-mongosh
RUN wget -qO- https://www.mongodb.org/static/pgp/server-7.0.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/mongodb-org-7.0.gpg > /dev/null \
 && UBUNTU_CODENAME=$(lsb_release -cs) \
 && echo "deb [ arch=$(dpkg --print-architecture) signed-by=/etc/apt/trusted.gpg.d/mongodb-org-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu ${UBUNTU_CODENAME}/mongodb-org/7.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-7.0.list \
 && apt-get update \
 && apt-get install -y mongodb-mongosh \
 && rm -rf /var/lib/apt/lists/*

# --- Installazione di Cassandra ${CASSANDRA_VERSION} per cqlsh ---
    RUN echo "INFO: Downloading Cassandra ${CASSANDRA_VERSION} for cqlsh..." \
    && CASSANDRA_DOWNLOAD_URL="https://dlcdn.apache.org/cassandra/${CASSANDRA_VERSION}/apache-cassandra-${CASSANDRA_VERSION}-bin.tar.gz" \
    && wget -q "${CASSANDRA_DOWNLOAD_URL}" -O /tmp/cassandra.tar.gz \
    && echo "INFO: Extracting Cassandra..." \
    && tar -xzf /tmp/cassandra.tar.gz -C /opt \
    && mv /opt/apache-cassandra-${CASSANDRA_VERSION} /opt/cassandra \
    && rm /tmp/cassandra.tar.gz
   # Aggiungi Cassandra bin alla PATH per usare cqlsh direttamente
   ENV PATH="${PATH}:/opt/cassandra/bin"
   # --- Fine Installazione Cassandra ---

# 1. Clone YCSB
RUN set -e; \
    echo "INFO: WORKDIR corrente prima del clone: $(pwd)"; \
    echo "INFO: Cloning YCSB tag: ${YCSB_TAG} in /opt/YCSB_PROJECT_ROOT"; \
    git clone --depth 1 --branch ${YCSB_TAG} https://github.com/brianfrankcooper/YCSB.git YCSB_PROJECT_ROOT; \
    echo "INFO: Clone completato con codice di uscita $?"; \
    echo "--- Contenuto di /opt DOPO clone YCSB ---"; \
    ls -la /opt; \
    echo "--- Contenuto di /opt/YCSB_PROJECT_ROOT (ROOT DEL PROGETTO YCSB) DOPO clone ---"; \
    ls -la /opt/YCSB_PROJECT_ROOT; \
    echo "--- Verifica presenza pom.xml in /opt/YCSB_PROJECT_ROOT ---"; \
    if [ -f /opt/YCSB_PROJECT_ROOT/pom.xml ]; then echo "pom.xml TROVATO in /opt/YCSB_PROJECT_ROOT"; else echo "ERRORE: pom.xml NON TROVATO in /opt/YCSB_PROJECT_ROOT"; exit 1; fi

# 2. Sovrascrivi lo script bin/ycsb con la versione Python 3 corretta
COPY ycsb_python3.py /opt/YCSB_PROJECT_ROOT/bin/ycsb
RUN chmod +x /opt/YCSB_PROJECT_ROOT/bin/ycsb

# 3. Pulisci la cache Maven, poi COMPILA YCSB
RUN set -e; \
    rm -rf /root/.m2/repository; \
    echo "INFO: Building YCSB core and specific bindings (mongodb, redis, cassandra)..."; \
    cd /opt/YCSB_PROJECT_ROOT && mvn -q -DskipTests clean package -pl core,mongodb,redis,cassandra

# 4. Crea il link simbolico e la directory results
RUN set -e; \
    ln -s /opt/YCSB_PROJECT_ROOT /ycsb; \
    mkdir /ycsb/results

VOLUME /ycsb/results
WORKDIR /ycsb

COPY entrypoint.sh /entrypoint.sh
COPY run-*.sh ./
RUN chmod +x /entrypoint.sh
RUN chmod +x ./run-*.sh
ENTRYPOINT ["/entrypoint.sh"]