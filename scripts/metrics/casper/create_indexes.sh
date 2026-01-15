#!/usr/bin/env bash

set -euo pipefail

BASE_URL="http://localhost:8080"
COLLECTION=""
SCENARIO="all" # f32 | i8 | pq | all
PQ_NAME="pq_test"

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Create Casper HNSW indexes with human-readable curl + JSON.

Modes:
  --scenario f32|i8|pq --collection NAME
  --scenario all       --collection NAME  (runs f32 then i8 then pq, each requires deleting index between runs)

Options:
  --base-url URL        Casper base URL (default: http://localhost:8080)
  --collection NAME     Collection name (required)
  --scenario NAME       f32 | i8 | pq | all (default: all)
  --pq-name NAME        PQ name for pq8 scenario (default: pq_test)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url)
      BASE_URL="$2"
      shift 2
      ;;
    --collection)
      COLLECTION="$2"
      shift 2
      ;;
    --scenario)
      SCENARIO="$2"
      shift 2
      ;;
    --pq-name)
      PQ_NAME="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "${COLLECTION}" ]]; then
  echo "Error: --collection is required" >&2
  usage
  exit 1
fi

create_f32() {
  curl --location --request POST "${BASE_URL%/}/collection/${COLLECTION}/index" \
    --header 'Content-Type: application/json' \
    --data '{
      "hnsw": {
        "metric": "inner-product",
        "quantization": "f32",
        "m": 16,
        "m0": 32,
        "ef_construction": 200
      },
      "normalization": true
    }'
}

create_i8() {
  curl --location --request POST "${BASE_URL%/}/collection/${COLLECTION}/index" \
    --header 'Content-Type: application/json' \
    --data '{
      "hnsw": {
        "metric": "inner-product",
        "quantization": "i8",
        "m": 16,
        "m0": 32,
        "ef_construction": 200
      },
      "normalization": true
    }'
}

create_pq() {
  curl --location --request POST "${BASE_URL%/}/collection/${COLLECTION}/index" \
    --header 'Content-Type: application/json' \
    --data "{
      \"hnsw\": {
        \"metric\": \"inner-product\",
        \"quantization\": \"pq8\",
        \"m\": 16,
        \"m0\": 32,
        \"ef_construction\": 200,
        \"pq_name\": \"${PQ_NAME}\"
      },
      \"normalization\": false
    }"
}

case "${SCENARIO}" in
  f32) create_f32 ;;
  i8)  create_i8 ;;
  pq)  create_pq ;;
  all)
    echo "Error: scenario 'all' is not supported by this script alone." >&2
    echo "Use scripts/metrics/casper/metrics.sh which handles delete-index between runs." >&2
    exit 2
    ;;
  *)
    echo "Error: unknown --scenario: ${SCENARIO} (expected f32|i8|pq)" >&2
    exit 1
    ;;
esac


