#!/usr/bin/env bash

set -euo pipefail

BASE=""
OUT_DIR=""
COLLECTION=""
BACKEND="casper"
BASE_URL="http://localhost:8080"
METRIC="ip"
NUM_QUERIES="1000"

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Run recall evaluation for fixed K values and save outputs to files.

Required:
  --base PATH           Path to base vectors file (Casper binary format)
  --out-dir DIR         Directory where results will be saved (files recall@K)
  --collection NAME     Collection name (e.g. alex)

Optional:
  --backend NAME        Backend: casper | qdrant (default: casper)
  --base-url URL        Base URL (default: http://localhost:8080)
  --metric NAME         Metric: ip | l2 (default: ip)
  --num-queries N       Number of queries when sampling from base (default: 1000)
  -h, --help            Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)
      BASE="$2"
      shift 2
      ;;
    --out-dir)
      OUT_DIR="$2"
      shift 2
      ;;
    --collection)
      COLLECTION="$2"
      shift 2
      ;;
    --backend)
      BACKEND="$2"
      shift 2
      ;;
    --base-url)
      BASE_URL="$2"
      shift 2
      ;;
    --metric)
      METRIC="$2"
      shift 2
      ;;
    --num-queries)
      NUM_QUERIES="$2"
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

if [[ -z "${BASE}" ]]; then
  echo "Error: --base is required" >&2
  usage
  exit 1
fi

if [[ -z "${OUT_DIR}" ]]; then
  echo "Error: --out-dir is required" >&2
  usage
  exit 1
fi

if [[ -z "${COLLECTION}" ]]; then
  echo "Error: --collection is required" >&2
  usage
  exit 1
fi

mkdir -p "${OUT_DIR}"

run_recall() {
  local k="$1"
  local out_file="${OUT_DIR}/recall@${k}"
  echo "Running recall evaluation (k=${k}) and saving results to ${out_file}"
  python3 scripts/recall/recall.py \
    --backend "${BACKEND}" \
    --base-url "${BASE_URL}" \
    --base "${BASE}" \
    --collection "${COLLECTION}" \
    --k "${k}" \
    --num-queries "${NUM_QUERIES}" \
    --metric "${METRIC}" \
    > "${out_file}"
}

# Fixed K values to evaluate
run_recall 10
run_recall 100
run_recall 1000
run_recall 10000
run_recall 100000

echo "All recall evaluations completed. Results saved in ${OUT_DIR}"
