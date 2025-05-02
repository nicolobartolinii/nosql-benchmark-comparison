#!/bin/bash
set -euo pipefail # Mantiene le opzioni di sicurezza

# Controlla se la variabile MONGO_URL è impostata
[ -z "${MONGO_URL-}" ] && { echo "ERROR: MONGO_URL not set" >&2; exit 1; }

# --- NUOVA LINEA DI DEBUG ---
echo "DEBUG: Tentativo di connessione a MONGO_URL=${MONGO_URL}"
# -------------------------

# Esegui il load di YCSB
./bin/ycsb load mongodb -s -P workloads/workloada -p mongodb.url="${MONGO_URL}"

# Esegui il run di YCSB e salva i risultati
./bin/ycsb run   mongodb -s -P workloads/workloada -p mongodb.url="${MONGO_URL}" > /results/mongo_$(date +%s).txt

echo "INFO: Test MongoDB completato. Risultati salvati in /results/"
