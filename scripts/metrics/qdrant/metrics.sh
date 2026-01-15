#!/usr/bin/env bash

set -euo pipefail

QDRANT_URL="http://localhost:6333"
QDRANT_VERSION="1.16.0"
COLLECTION_PREFIX="test_collection"
BASE_BIN=""
NUM_QUERIES="1000"
METRIC="ip"
IMPORT_BATCH_SIZE="256"
AB_BODY=""

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Create Qdrant collections (f32, i8 scalar, pq), import vectors, run load-test and recall,
save results into metrics/qdrant@<version>/<scenario>/, then delete collections.

Required:
  --base PATH                 Path to Casper-format base vectors file (data.bin)

Optional:
  --qdrant-url URL            Qdrant base URL (default: http://localhost:6333)
  --qdrant-version VER        Used in output path (default: 1.16.0)
  --collection-prefix PREFIX  Prefix for collection names (default: test_collection)
  --num-queries N             Recall: number of queries (default: 1000)
  --metric NAME               Recall metric: ip | l2 (default: ip)
  --import-batch-size N       Qdrant upsert batch size (default: 256)
  --ab-body PATH              Path to AB request body JSON (required)

Notes:
  - Requires running Qdrant at --qdrant-url
  - Saves results into: metrics/qdrant@<qdrant-version>/{f32_ip,i8_ip,pq_u8}/
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --qdrant-url)
      QDRANT_URL="$2"
      shift 2
      ;;
    --qdrant-version)
      QDRANT_VERSION="$2"
      shift 2
      ;;
    --collection-prefix)
      COLLECTION_PREFIX="$2"
      shift 2
      ;;
    --base)
      BASE_BIN="$2"
      shift 2
      ;;
    --num-queries)
      NUM_QUERIES="$2"
      shift 2
      ;;
    --metric)
      METRIC="$2"
      shift 2
      ;;
    --import-batch-size)
      IMPORT_BATCH_SIZE="$2"
      shift 2
      ;;
    --ab-body)
      AB_BODY="$2"
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

if [[ -z "${BASE_BIN}" ]]; then
  echo "Error: --base is required" >&2
  usage
  exit 1
fi

if [[ -z "${AB_BODY}" ]]; then
  echo "Error: --ab-body is required (path to request JSON)" >&2
  usage
  exit 1
fi

if [[ ! -f "${BASE_BIN}" ]]; then
  echo "Error: base file not found: ${BASE_BIN}" >&2
  exit 1
fi

# Ensure we cleanup even on failure / Ctrl+C.
trap 'cleanup_all_collections' EXIT

DIM="$(python3 - "${BASE_BIN}" <<'PY'
import struct
import sys
path = sys.argv[1]
with open(path, "rb") as f:
    header = f.read(8)
dim, count = struct.unpack(">II", header)
print(dim)
PY
)"

METRICS_ROOT="metrics/qdrant@${QDRANT_VERSION}"
mkdir -p "${METRICS_ROOT}"

create_collection() {
  local scenario="$1"      # f32 | i8 | pq
  local collection="$2"

  echo "Creating collection: ${collection}"
  ./scripts/metrics/qdrant/create_collections.sh \
    --qdrant-url "${QDRANT_URL}" \
    --dim "${DIM}" \
    --scenario "${scenario}" \
    --collection "${collection}" \
    --quiet
}

delete_collection() {
  local collection="$1"
  echo "Deleting collection: ${collection}"
  curl -sS --request DELETE "${QDRANT_URL%/}/collections/${collection}" >/dev/null || true
}

cleanup_all_collections() {
  # Best-effort cleanup for all scenario collections (safe to call multiple times).
  delete_collection "${COLLECTION_PREFIX}_f32_ip"
  delete_collection "${COLLECTION_PREFIX}_i8_ip"
  delete_collection "${COLLECTION_PREFIX}_pq_u8"
}

import_data() {
  local collection="$1"
  echo "Importing vectors into Qdrant collection: ${collection}"
  python3 scripts/import/import.py "${BASE_BIN}" \
    --backend qdrant \
    --base-url "${QDRANT_URL}" \
    --collection "${collection}" \
    --batch-size "${IMPORT_BATCH_SIZE}" \
    --wait
}

run_load_test() {
  local collection="$1"
  local out_dir="$2"
  ./scripts/ab/qdrant/ab.sh \
    --base-url "${QDRANT_URL}" \
    --collection "${collection}" \
    --body "${AB_BODY}" \
    --out-dir "${out_dir}"
}

run_recall() {
  local collection="$1"
  local out_dir="$2"
  ./scripts/recall.sh \
    --backend qdrant \
    --base-url "${QDRANT_URL}" \
    --base "${BASE_BIN}" \
    --collection "${collection}" \
    --num-queries "${NUM_QUERIES}" \
    --metric "${METRIC}" \
    --out-dir "${out_dir}"
}

run_scenario() {
  local scenario="$1"     # f32_ip | i8_ip | pq_u8
  local collection="$2"

  local out_dir="${METRICS_ROOT}/${scenario}"
  mkdir -p "${out_dir}"

  echo "============================================================"
  echo "Scenario: ${scenario}"
  echo "Collection: ${collection}"
  echo "Output: ${out_dir}"
  echo "============================================================"

  # Best-effort cleanup if something is left from previous run
  delete_collection "${collection}"

  case "${scenario}" in
    f32_ip) create_collection "f32" "${collection}" ;;
    i8_ip)  create_collection "i8"  "${collection}" ;;
    pq_u8)  create_collection "pq"  "${collection}" ;;
    *) echo "Unknown scenario: ${scenario}" >&2; exit 1 ;;
  esac
  import_data "${collection}"
  run_load_test "${collection}" "${out_dir}"
  run_recall "${collection}" "${out_dir}"
  delete_collection "${collection}"
}

run_scenario "f32_ip" "${COLLECTION_PREFIX}_f32_ip"
run_scenario "i8_ip" "${COLLECTION_PREFIX}_i8_ip"
run_scenario "pq_u8" "${COLLECTION_PREFIX}_pq_u8"

echo "Done. Results saved in ${METRICS_ROOT}"


