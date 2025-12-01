## Benchmarks and Metrics Guide

This document describes how to run the **public benchmarks and metrics** for Casper.
It is intended for external users who want to verify performance and quality,
without needing to know internal implementation details.

---

### 1. Prerequisites

#### 1.1 Install Apache Bench (ab)

Apache Bench is used for HTTP load testing of the Casper HTTP API.

- **Ubuntu / Debian**
  ```bash
  sudo apt-get update
  sudo apt-get install -y apache2-utils
  ```

- **Fedora / CentOS / RHEL**

  ```bash
  sudo dnf install -y httpd-tools
  ```


- **Arch Linux**

  ```bash
  sudo pacman -S --noconfirm apache
  ```


- **macOS (Homebrew)**
  ```bash
  brew install httpd
  ```

Verify installation:

```bash
ab -V
```

#### 1.2 Python environment for recall evaluation

Recall evaluation relies on FAISS, NumPy and Requests.
We recommend preparing a dedicated Conda environment:

```bash
conda create -n casper python=3.10 -y
conda activate casper
pip install faiss-cpu requests numpy
```

This environment is used by:

- `scripts/import/import.py`
- `scripts/recall/recall.py`
- `scripts/recall.sh`

#### 1.3 Download and prepare benchmark data

Before running the load tests and recall evaluation, download and prepare the public benchmark dataset.

1. **Download the archive from GitHub Releases**

   ```bash
   wget https://github.com/casper-vdb/casper/releases/download/benchmark-data-v0/casper-bench-data-v0.zip
   ```

2. **Unpack the archive**

   ```bash
   unzip casper-bench-data-v0.zip
   ```

   After unpacking, you should have at least:

   - `casper-bench-data/data/data.bin` – vectors in Casper binary format  
   - `casper-bench-data/json/casper/req.json` – example HTTP request body for load testing

   The `data.bin` file contains:

   - **Vectors:** 572,940
   - **Dimension:** 128
   - **Preprocessing:** all vectors are L2-normalized and contain no duplicates

3. **Create the collection in Casper**

   Assuming dimension \(128\) and a max size of \(600000\) documents:

   ```bash
   curl -X POST "http://localhost:8080/collection/demo?dim=128&max_size=600000"
   ```

4. **Import the vectors using the Python import script (via Makefile target)**

   ```bash
   make import
   ```

   After this step, the `demo` collection is populated and ready for load testing and recall evaluation.

5. **Create an HNSW index for the `demo` collection**

   To run benchmarks on top of an index, create an HNSW index for the `demo` collection:

   ```bash
   curl --location --request POST 'http://localhost:8080/collection/demo/index' \
     --header 'Content-Type: application/json' \
     --data-raw '{
       "index": "hnsw",
       "config": {
           "metric": "inner-product",
           "quantization": "i8",
           "m": 16,
           "m0": 32,
           "ef_construction": 200,
           "normalization": true
       }
     }'
   ```

   This configuration matches the benchmark setup used in our published results (normalized vectors, inner-product metric, i8 quantization).
   You are free to use any other supported index configuration (different metrics, quantizations, or HNSW parameters) that better matches your own use case.

---

### 2. Load testing Casper (Apache Bench)

Load tests exercise the Casper HTTP search API and record latency
and throughput under different query limits.

All commands below assume that a Casper server is already running
and listening on `http://localhost:8080`.

#### 2.1 Single load test

To run a simple load test against Casper HNSW:

```bash
make load-test
```

This will send many search requests with a fixed `limit` and report
aggregate statistics such as requests per second and latency distribution.

#### 2.2 Load test with saved results

To run a series of load tests for different `limit` values and save
the detailed `ab` output to disk:

```bash
make load-test-save
```

This target internally uses the helper script:

- `scripts/ab.sh`

The script runs Apache Bench several times (for multiple `limit` values)
and writes outputs into a metrics directory (configured in the `Makefile`,
commonly `metrics/`).

You can also call it directly (equivalent to `make load-test-save`):

```bash
./scripts/ab.sh \
  --base-url http://localhost:8080 \
  --collection demo \
  --body casper-bench-data/json/casper/req.json \
  --out-dir metrics
```

The result will be a set of files like:

```text
metrics/ab@10
metrics/ab@100
metrics/ab@1000
metrics/ab@10000
metrics/ab@100000
```

These can be archived or compared across versions of Casper.

---

### 3. Recall evaluation (Casper vs FAISS)

Recall benchmarks compare the top‑K results returned by Casper
against a FAISS Flat index built over the same base vectors.
This provides a quality metric (recall@K) independent of latency.

All recall commands assume:

- A Casper server running at `http://localhost:8080`.
- A base vector file in Casper binary format located at:
  - `casper-bench-data/data/data.bin`

#### 3.1 Single recall run

To perform a single recall evaluation for Casper:

```bash
make recall
```

This internally calls `scripts/recall/recall.py`, which:

- Builds a FAISS Flat index on the base vectors.
- Queries Casper for top‑K neighbors.
- Computes recall@K for the given number of queries.

#### 3.2 Recall with saved results (multiple K)

To run recall for several fixed values of K and save the detailed output:

```bash
make recall-save
```

This target uses the helper:

- `scripts/recall.sh`

and writes resulting logs into a metrics directory (commonly `metrics/`), e.g.:

```text
metrics/recall@10
metrics/recall@100
metrics/recall@1000
metrics/recall@10000
metrics/recall@100000
```

You can also invoke the script directly (equivalent to `make recall-save`):

```bash
./scripts/recall.sh \
  --backend casper \
  --base-url http://localhost:8080 \
  --base casper-bench-data/data/data.bin \
  --collection demo \
  --num-queries 1000 \
  --metric ip \
  --out-dir metrics
```

---

### 4. Collecting Casper metrics in one command

For convenience, there is a combined target that runs both the
load test (with saved results) and the recall evaluation
(with saved results) for Casper:

```bash
make metrics
```

Conceptually, this:

- Runs `load-test-save` to collect latency/throughput metrics
  via Apache Bench.
- Runs `recall-save` to collect recall@K metrics against
  a FAISS Flat ground truth.
- Writes all outputs into a shared metrics directory (commonly `metrics/`).

---

### 5. Summary

- **Load tests** (Apache Bench) measure throughput and latency
  of the Casper HTTP search API under different query limits.
- **Recall tests** compare Casper search results against a FAISS Flat index
  to quantify retrieval quality (recall@K).

Taken together, these tools allow external users to:

- Validate Casper performance on their hardware.
- Compare versions or configurations.
- Track regressions in both speed and quality over time.


