#!/usr/bin/env bash

set -euo pipefail

BASE_URL=""
OUT_DIR=""
COLLECTION=""
BODY_FILE="req.json"

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Run a series of Apache Bench load tests for Casper HNSW and save results.

Required:
  --base-url URL        Full base URL, e.g. http://localhost:8080
  --out-dir DIR         Directory where result files (ab@10, ab@100, ...) will be saved
  --collection NAME     Collection name (e.g. alex)

Other:
  --body FILE           Path to JSON request body (default: req.json)
  -h, --help            Show this help

EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url)
      BASE_URL="$2"
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
    --body)
      BODY_FILE="$2"
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

if [[ -z "${BASE_URL}" ]]; then
  echo "Error: --base-url is required" >&2
  usage
  exit 1
fi

mkdir -p "${OUT_DIR}"

run_ab() {
  local limit="$1"
  local requests="$2"
  local out_file="${OUT_DIR}/ab@${limit}"

  echo "Running Apache Bench load test for HNSW and saving results to ${out_file}"
  ab -p "${BODY_FILE}" -c 32 -n "${requests}" -k -T 'application/json' "${BASE_URL}/collection/${COLLECTION}/search?limit=${limit}&output=bin" > "${out_file}"
}

# Corresponds to existing Makefile configuration
run_ab 10 3000000
sleep 15
run_ab 100 3000000
sleep 15
run_ab 1000 300000
sleep 15
run_ab 10000 300000
sleep 15
run_ab 100000 10000

echo "All load tests completed. Results saved in ${OUT_DIR}"


