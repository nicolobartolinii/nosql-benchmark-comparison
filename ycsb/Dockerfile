# Base JDK 17 multi‑arch (arm64+amd64) – Temurin è già cross‑compiled
FROM eclipse-temurin:17-jdk-jammy

ARG YCSB_COMMIT=master   # prendi l’ultimo commit; cambia se vuoi un tag
WORKDIR /opt

# Pacchetti minimi per clonare e compilare
RUN apt-get update && \
    apt-get install -y --no-install-recommends git maven python3.10 python-is-python3 && \
    rm -rf /var/lib/apt/lists/*

# Clona YCSB (shallow) e compila solo i binding che ci servono
RUN git clone --depth 1 --branch ${YCSB_COMMIT} https://github.com/brianfrankcooper/YCSB.git && \
    cd YCSB && \
    mvn -q -DskipTests \
    -pl site.ycsb:redis-binding,site.ycsb:mongodb-binding,site.ycsb:cassandra-binding \
    -am clean package && \
    ln -s /opt/YCSB /ycsb   # percorsi più comodi

# Directory dove buttiamo i risultati
RUN mkdir /results
VOLUME /results
WORKDIR /opt/YCSB

COPY run-redis.sh ./run-redis.sh
RUN chmod +x ./run-redis.sh
COPY run-cassandra.sh ./run-cassandra.sh
RUN chmod +x ./run-cassandra.sh
COPY run-mongo.sh ./run-mongo.sh
RUN chmod +x ./run-mongo.sh
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
