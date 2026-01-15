#!/usr/bin/env bash

set -euo pipefail

BASE_URL="http://localhost:8080"
CASPER_VERSION="v0.0.0"
COLLECTION="test_collection"
BASE_BIN=""
MAX_SIZE=""
PQ_NAME="pq_test"
MATRIX_PREFIX=""
CASPER_HOST="http://127.0.0.1"
CASPER_HTTP_PORT="8080"
CASPER_GRPC_PORT="50051"
PQ_M="16"
PQ_NBITS="8"
PQ_MAX_TRAIN="1000000"
NUM_QUERIES="1000"
METRIC="ip"
IMPORT_BATCH_SIZE="256"
AB_BODY=""

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Full Casper metrics scenario:
  - delete+create collection
  - import vectors
  - for each index (f32, i8, pq8):
      - create index (waits for completion)
      - run load-test (ab) + recall and save results
      - delete index
  - delete collection

Required:
  --base PATH           Path to Casper-format base vectors file (data.bin)

Optional:
  --base-url URL        Casper base URL (default: http://localhost:8080)
  --casper-version VER  Used in output path (default: v0.0.0)
  --collection NAME     Collection name (default: beh)
  --max-size N          Collection max_size (default: auto from base file count)
  --pq-name NAME        PQ name for pq8 scenario (default: pq_ip)
  --matrix-prefix NAME  Prefix for PQ codebook matrix names (default: pq-name)
  --casper-host URL     Casper host for python-client (default: http://127.0.0.1)
  --casper-http-port N  Casper HTTP port for python-client (default: 8080)
  --casper-grpc-port N  Casper gRPC port for python-client (default: 50051)
  --pq-m N              PQ subquantizers M (default: 16)
  --pq-nbits N          PQ bits per subvector (default: 8)
  --pq-max-train N      PQ max train vectors (default: 1000000)
  --ab-body PATH        Path to AB request body JSON (required)
  --num-queries N       Recall: number of queries (default: 1000)
  --metric NAME         Recall metric: ip | l2 (default: ip)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url)
      BASE_URL="$2"
      shift 2
      ;;
    --casper-version)
      CASPER_VERSION="$2"
      shift 2
      ;;
    --collection)
      COLLECTION="$2"
      shift 2
      ;;
    --base)
      BASE_BIN="$2"
      shift 2
      ;;
    --max-size)
      MAX_SIZE="$2"
      shift 2
      ;;
    --pq-name)
      PQ_NAME="$2"
      shift 2
      ;;
    --matrix-prefix)
      MATRIX_PREFIX="$2"
      shift 2
      ;;
    --casper-host)
      CASPER_HOST="$2"
      shift 2
      ;;
    --casper-http-port)
      CASPER_HTTP_PORT="$2"
      shift 2
      ;;
    --casper-grpc-port)
      CASPER_GRPC_PORT="$2"
      shift 2
      ;;
    --pq-m)
      PQ_M="$2"
      shift 2
      ;;
    --pq-nbits)
      PQ_NBITS="$2"
      shift 2
      ;;
    --pq-max-train)
      PQ_MAX_TRAIN="$2"
      shift 2
      ;;
    --ab-body)
      AB_BODY="$2"
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

read_dim_and_count() {
  python3 - "${BASE_BIN}" <<'PY'
import struct
import sys
path = sys.argv[1]
with open(path, "rb") as f:
    header = f.read(8)
dim, count = struct.unpack(">II", header)
print(dim)
print(count)
PY
}

DIM_AND_COUNT="$(read_dim_and_count)"
DIM="$(echo "${DIM_AND_COUNT}" | sed -n '1p')"
COUNT="$(echo "${DIM_AND_COUNT}" | sed -n '2p')"

if [[ -z "${MAX_SIZE}" ]]; then
  MAX_SIZE="${COUNT}"
fi
if [[ -z "${MATRIX_PREFIX}" ]]; then
  MATRIX_PREFIX="${PQ_NAME}"
fi

METRICS_ROOT="metrics/casper@${CASPER_VERSION}"
mkdir -p "${METRICS_ROOT}"

get_has_index() {
  # Returns: true | false | unknown
  # Must be robust: on transient network/HTTP errors Casper may return empty/non-JSON.
  resp="$(curl -sSf --max-time 5 "${BASE_URL%/}/collection/${COLLECTION}" 2>/dev/null || true)"
  python3 - <<'PY' "${resp}"
import json
import sys

raw = sys.argv[1]
if not raw:
    print("unknown")
    raise SystemExit(0)

try:
    data = json.loads(raw)
except Exception:
    print("unknown")
    raise SystemExit(0)

print("true" if data.get("has_index") else "false")
PY
}

wait_has_index() {
  local want="$1"     # true|false
  local timeout="$2"  # seconds
  local start
  start="$(date +%s)"
  while true; do
    cur="$(get_has_index)"
    if [[ "${cur}" == "unknown" ]]; then
      cur="false"
    fi
    if [[ "${cur}" == "${want}" ]]; then
      return 0
    fi
    now="$(date +%s)"
    if (( now - start > timeout )); then
      echo "Timeout waiting for has_index=${want} (last=${cur})" >&2
      return 1
    fi
    sleep 2
  done
}

delete_collection() {
  echo "Deleting collection (best-effort): ${COLLECTION}"
  curl -sS -X DELETE "${BASE_URL%/}/collection/${COLLECTION}" >/dev/null || true
}

create_collection() {
  echo "Creating collection: ${COLLECTION} (dim=${DIM}, max_size=${MAX_SIZE})"
  curl -sS -X POST "${BASE_URL%/}/collection/${COLLECTION}?dim=${DIM}&max_size=${MAX_SIZE}" >/dev/null
}

import_data() {
  echo "Importing vectors into Casper collection: ${COLLECTION}"
  python3 scripts/import/import.py "${BASE_BIN}" \
    --backend casper \
    --base-url "${BASE_URL}" \
    --collection "${COLLECTION}" \
    --batch-size "${IMPORT_BATCH_SIZE}"
}

import_pq() {
  echo "Importing PQ into Casper (pq=${PQ_NAME}, matrix_prefix=${MATRIX_PREFIX})"
  python3 scripts/pq/pq.py \
    --input "${BASE_BIN}" \
    --vec-size "${DIM}" \
    --m "${PQ_M}" \
    --nbits "${PQ_NBITS}" \
    --max-train "${PQ_MAX_TRAIN}" \
    --metric "${METRIC}" \
    --casper-host "${CASPER_HOST}" \
    --casper-http-port "${CASPER_HTTP_PORT}" \
    --casper-grpc-port "${CASPER_GRPC_PORT}" \
    --pq-name "${PQ_NAME}" \
    --matrix-prefix "${MATRIX_PREFIX}" \
    --overwrite
}

delete_pq_and_matrices() {
  echo "Deleting PQ and matrices (best-effort): ${PQ_NAME}"
  python3 - "${CASPER_HOST}" "${CASPER_HTTP_PORT}" "${CASPER_GRPC_PORT}" "${PQ_NAME}" <<'PY' || true
import sys

host = sys.argv[1]
http_port = int(sys.argv[2])
grpc_port = int(sys.argv[3])
pq_name = sys.argv[4]

from casper_client import CasperClient

client = CasperClient(host=host, http_port=http_port, grpc_port=grpc_port)
try:
    codebooks = []
    try:
        info = client.get_pq_info(pq_name)
        codebooks = list(getattr(info, "codebooks", []) or [])
    except Exception:
        pass

    try:
        client.delete_pq(pq_name)
    except Exception:
        pass

    for m in codebooks:
        try:
            client.delete_matrix(m)
        except Exception:
            pass
finally:
    try:
        client.close()
    except Exception:
        pass
PY
}

delete_index() {
  echo "Deleting index (best-effort): ${COLLECTION}"
  curl -sS -X DELETE "${BASE_URL%/}/collection/${COLLECTION}/index" >/dev/null || true
  wait_has_index "false" 600 || true
}

create_index() {
  local scenario="$1" # f32_ip | i8_ip | pq_u8
  echo "Creating index: ${scenario}"
  case "${scenario}" in
    f32_ip)
      ./scripts/metrics/casper/create_indexes.sh --base-url "${BASE_URL}" --collection "${COLLECTION}" --scenario f32 >/dev/null
      ;;
    i8_ip)
      ./scripts/metrics/casper/create_indexes.sh --base-url "${BASE_URL}" --collection "${COLLECTION}" --scenario i8 >/dev/null
      ;;
    pq_u8)
      ./scripts/metrics/casper/create_indexes.sh --base-url "${BASE_URL}" --collection "${COLLECTION}" --scenario pq --pq-name "${PQ_NAME}" >/dev/null
      ;;
    *)
      echo "Unknown scenario: ${scenario}" >&2
      exit 1
      ;;
  esac
  wait_has_index "true" 7200
}

run_load_test() {
  local out_dir="$1"
  ./scripts/ab/casper/ab.sh \
    --base-url "${BASE_URL}" \
    --collection "${COLLECTION}" \
    --body "${AB_BODY}" \
    --out-dir "${out_dir}"
}

run_recall() {
  local out_dir="$1"
  ./scripts/recall.sh \
    --backend casper \
    --base-url "${BASE_URL}" \
    --base "${BASE_BIN}" \
    --collection "${COLLECTION}" \
    --num-queries "${NUM_QUERIES}" \
    --metric "${METRIC}" \
    --out-dir "${out_dir}"
}

run_scenario() {
  local scenario="$1" # f32_ip | i8_ip | pq_u8
  local out_dir="${METRICS_ROOT}/${scenario}"
  mkdir -p "${out_dir}"

  echo "============================================================"
  echo "Scenario: ${scenario}"
  echo "Collection: ${COLLECTION}"
  echo "Output: ${out_dir}"
  echo "============================================================"

  delete_index
  create_index "${scenario}"
  run_load_test "${out_dir}"
  run_recall "${out_dir}"
  delete_index
}

delete_collection
create_collection
import_data
import_pq

trap 'delete_index; delete_pq_and_matrices; delete_collection' EXIT

run_scenario "f32_ip"
run_scenario "i8_ip"
run_scenario "pq_u8"

delete_pq_and_matrices
delete_collection

echo "Done. Results saved in ${METRICS_ROOT}"


