#!/usr/bin/env bash

set -euo pipefail

BASE_URL=""
OUT_DIR=""
COLLECTION=""
BODY_FILE=""

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Run a series of Apache Bench load tests for Qdrant and save results.

Required:
  --base-url URL        Qdrant base URL, e.g. http://localhost:6333
  --out-dir DIR         Directory where result files (ab@10, ab@100, ...) will be saved
  --collection NAME     Collection name (e.g. test_collection_f32_ip)

Other:
  --body FILE           Path to JSON request body template (required)
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

if [[ -z "${BODY_FILE}" ]]; then
  echo "Error: request body JSON is required: pass --body FILE" >&2
  usage
  exit 1
fi

mkdir -p "${OUT_DIR}"

tmp_body="$(mktemp)"
trap 'rm -f "${tmp_body}"' EXIT

make_body_with_limit() {
  local limit="$1"
  python3 - "${BODY_FILE}" "${limit}" > "${tmp_body}" <<'PY'
import json
import sys

path = sys.argv[1]
limit = int(sys.argv[2])

with open(path, "r", encoding="utf-8") as f:
    body = json.load(f)

body["limit"] = limit

json.dump(body, sys.stdout, ensure_ascii=False)
PY
}

run_ab() {
  local limit="$1"
  local requests="$2"
  local out_file="${OUT_DIR}/ab@${limit}"

  make_body_with_limit "${limit}"
  echo "Running Apache Bench load test for Qdrant (limit=${limit}) and saving results to ${out_file}"

  ab -l -p "${tmp_body}" -c 32 -n "${requests}" -k -T 'application/json' \
    "${BASE_URL%/}/collections/${COLLECTION}/points/search" \
    > "${out_file}"
}

# Qdrant request profile (per K)
run_ab 10 300000
sleep 15
run_ab 100 300000
sleep 15
run_ab 1000 300000
sleep 15
run_ab 10000 30000
sleep 15
run_ab 100000 1000

echo "All load tests completed. Results saved in ${OUT_DIR}"


