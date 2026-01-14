#!/usr/bin/env bash

set -euo pipefail

QDRANT_URL="http://localhost:6333"
DIM="128"
SCENARIO="all" # f32 | i8 | pq | all
COLLECTION=""
COLLECTION_PREFIX=""
QUIET="0"

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Create Qdrant collection(s) with human-readable curl + JSON.

Modes:
  - Single collection:
      --scenario f32|i8|pq --collection NAME
  - All three collections (uses suffixes):
      --scenario all --collection-prefix PREFIX

Options:
  --qdrant-url URL            (default: http://localhost:6333)
  --dim D                     Vector dimension (default: 128)
  --scenario NAME             f32 | i8 | pq | all (default: all)
  --collection NAME           Exact collection name (for f32/i8/pq)
  --collection-prefix PREFIX  Prefix for names (for all):
                              PREFIX_f32_ip, PREFIX_i8_ip, PREFIX_pq_u8
  --quiet                     Do not print response body
  -h, --help                  Show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --qdrant-url)
      QDRANT_URL="$2"
      shift 2
      ;;
    --dim)
      DIM="$2"
      shift 2
      ;;
    --scenario)
      SCENARIO="$2"
      shift 2
      ;;
    --collection)
      COLLECTION="$2"
      shift 2
      ;;
    --collection-prefix)
      COLLECTION_PREFIX="$2"
      shift 2
      ;;
    --quiet)
      QUIET="1"
      shift 1
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

if [[ "${QUIET}" == "1" ]]; then
  CURL_OUT_ARGS=(-o /dev/null)
else
  CURL_OUT_ARGS=()
fi

curl_put() {
  local collection_name="$1"

  # Reads JSON from stdin.
  curl -sS -L -f \
    --request PUT "${QDRANT_URL%/}/collections/${collection_name}" \
    --header 'Content-Type: application/json' \
    --data @- \
    "${CURL_OUT_ARGS[@]}"
}

create_f32() {
  local name="$1"
  curl_put "${name}" <<JSON
{
  "vectors": {
    "size": ${DIM},
    "distance": "Dot"
  },
  "hnsw_config": {
    "m": 16,
    "ef_construct": 200,
    "full_scan_threshold": 10000,
    "max_indexing_threads": 0,
    "on_disk": false
  }
}
JSON
}

create_i8() {
  local name="$1"
  curl_put "${name}" <<JSON
{
  "vectors": {
    "size": ${DIM},
    "distance": "Dot"
  },
  "quantization_config": {
    "scalar": {
      "type": "int8",
      "quantile": 0.99,
      "always_ram": true
    }
  },
  "hnsw_config": {
    "m": 16,
    "ef_construct": 200,
    "full_scan_threshold": 10000,
    "max_indexing_threads": 0,
    "on_disk": false
  }
}
JSON
}

create_pq() {
  local name="$1"
  curl_put "${name}" <<JSON
{
  "vectors": {
    "size": ${DIM},
    "distance": "Dot"
  },
  "quantization_config": {
    "product": {
      "compression": "x16",
      "always_ram": true
    }
  },
  "hnsw_config": {
    "m": 16,
    "ef_construct": 200,
    "full_scan_threshold": 10000,
    "max_indexing_threads": 0,
    "on_disk": false
  }
}
JSON
}

case "${SCENARIO}" in
  f32)
    if [[ -z "${COLLECTION}" ]]; then
      echo "Error: --collection is required for --scenario f32" >&2
      exit 1
    fi
    create_f32 "${COLLECTION}"
    ;;
  i8)
    if [[ -z "${COLLECTION}" ]]; then
      echo "Error: --collection is required for --scenario i8" >&2
      exit 1
    fi
    create_i8 "${COLLECTION}"
    ;;
  pq)
    if [[ -z "${COLLECTION}" ]]; then
      echo "Error: --collection is required for --scenario pq" >&2
      exit 1
    fi
    create_pq "${COLLECTION}"
    ;;
  all)
    if [[ -z "${COLLECTION_PREFIX}" ]]; then
      echo "Error: --collection-prefix is required for --scenario all" >&2
      exit 1
    fi
    create_f32 "${COLLECTION_PREFIX}_f32_ip"
    create_i8 "${COLLECTION_PREFIX}_i8_ip"
    create_pq "${COLLECTION_PREFIX}_pq_u8"
    ;;
  *)
    echo "Error: unknown --scenario: ${SCENARIO} (expected f32|i8|pq|all)" >&2
    exit 1
    ;;
esac
