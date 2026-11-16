<p align="center">
  <img height="100" alt="Casper" src="docs/logo.png">
</p>

<p align="center">
    <b>⚡ World’s Fastest Vector Database for AI & RAG</b>
</p>

# Casper

**Casper** is a high-performance Vector Search Database, perfectly suited for high-load search systems and AI applications (RAG). It provides a robust and scalable solution to store, search, and manage vectors efficiently.

Casper is built using Rust 🦀 for performance and reliability. Casper clients [Python](https://github.com/casper-vdb/python-client) • [Go](https://github.com/casper-vdb/go-client) • [Rust](https://github.com/casper-vdb/rust-client)

---

## Why Casper ?

**Casper** is the fastest vector database in our internal benchmarks. It consistently outperforms Qdrant across Top@K workloads and both f32 and i8 quantizations. Notably, Qdrant is widely recognized as the leading open‑source engine and demonstrates state‑of‑the‑art throughput versus other databases (e.g., Weaviate, Milvus), as shown in their published results: [Qdrant benchmarks](https://qdrant.tech/benchmarks/). Surpassing Qdrant therefore places Casper ahead of the current open‑source performance leader.

In practice, Casper delivers up to an order‑of‑magnitude higher RPS compared to Qdrant on our datasets, which translates directly into substantial infrastructure savings: fewer CPU cores and instances to achieve the same SLA, lower memory pressure, and reduced total cost of ownership due to more efficient use of compute resources. **Casper** is the ideal solution for high-load systems, real-time search, and AI & RAG.

**Conclusion**: Casper achieves performance unattainable for other databases under comparable conditions, requires fewer compute resources at the same load, and materially reduces infrastructure costs through more efficient CPU and memory utilization.

### Casper vs Qdrant

#### Benchmarks RPS & Recall

**Hardware:**
- CPU: 2 × AMD EPYC 9474F (2 × 48 cores 96 threads L3 Cache 256 MB)
- Memory: 256 GB RAM

**Dataset:** deep-image-96-angular.hdf5
- Vectors:   9,990,000
- Dimension: 96
- Metric:    Inner Product (vectors are L2-normalized)

**HNSW**
- m: 16
- ef construct: 200

Qdrant configured with quantile 0.99 (for int8), always ram enabled.

**Search-time parameter.** For every measurement in the tables below we explicitly set `ef_search = limit` on both engines (for Qdrant via `params.hnsw_ef`, overriding its server-side default of `max(limit, 128)`). This is the smallest valid HNSW `ef` and the most apples-to-apples comparison: both engines do the minimum amount of graph exploration the algorithm allows.

**Index granularity (why Qdrant recall is higher).** Casper builds a **single monolithic HNSW index** per collection. Qdrant splits the collection across multiple segments (`segments_count: 8` in this benchmark) and runs HNSW search **independently in every segment**, then merges the per-segment top‑K on the coordinator. With per-segment `hnsw_ef = limit`, Qdrant effectively examines `segments_count × limit = 8 × limit` candidates per query — eight times more than Casper for the same nominal `ef`. The higher recall Qdrant shows at every K in the tables therefore reflects this storage organization, not better HNSW graph quality; the same effect is the reason its RPS is correspondingly lower (more work per request).

#### Full Precision (F32)

Requests per second, RPS

| Engine  | Top@10   |  Top@100 |  Top@1k  |  Top@10k   |   Top@100k  |
|:-------:|---------:|---------:|---------:|-----------:|------------:|
| Casper  | 248.86 k |  93.55 k |  12.02 k |     1.43 k |         163 |
| Qdrant  |  13.25 k |  15.65 k |   2.48 k |       285  |          28 |
| Speedup |    18.8x |     6.0x |     4.8x |       5.0x |        5.8x |

Recall

| Engine  |  Top@10  |  Top@100 |  Top@1k  |  Top@10k   |   Top@100k  |
|---------|---------:|---------:|---------:|-----------:|------------:|
| Casper  |    0.606 |    0.854 |    0.957 |      0.987 |       0.995 |
| Qdrant  |    0.762 |    0.953 |    0.993 |      0.999 |       1.000 |

#### Scalar Quantization (I8)

Requests per second, RPS

| Engine  | Top@10   |  Top@100 |  Top@1k  |  Top@10k   |   Top@100k  |
|:-------:|---------:|---------:|---------:|-----------:|------------:|
| Casper  | 248.79 k | 145.53 k | 22.47 k  |     2.36 k |         221 |
| Qdrant  |  26.90 k |  19.43 k |  3.29 k  |       345  |          28 |
| Speedup |     9.2x |     7.5x |     6.8x |       6.8x |        7.9x |

Recall

| Engine  |  Top@10  |  Top@100 |  Top@1k  |  Top@10k   |   Top@100k  |
|:-------:|---------:|---------:|---------:|-----------:|------------:|
| Casper  |    0.578 |    0.820 |    0.921 |      0.957 |       0.975 |
| Qdrant  |    0.729 |    0.914 |    0.959 |      0.975 |       0.985 |

## HNSW

Casper features a highly efficient **HNSW (Hierarchical Navigable Small World)** index, providing fast and accurate similarity search. 

### Metrics

Casper supports multiple distance metrics:

- **Euclidean**
- **L2SQ**
- **Cosine**
- **Inner-Product**

### Quantizations

Quantizations: f32 (full precision), i8 scalar quantization — reducing memory footprint and improving search performance.

- **F32**
- **I8**

---

## Free Access

Casper is currently completely free. You can use the following free licence token to run Casper:

```bash
export LICENSE_TOKEN=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE4MjU1ODE2NzIsImZyZWUiOnRydWV9.1RW9Q3JyAtc_DiwtAnZA0gfRYWfHTIRusQ57XR3TV_U
```

## Quick Start

### Download and Launch

To quickly get started with Casper, follow these steps:

**1. Download the latest release:**

```bash
wget https://github.com/casper-vdb/casper/releases/download/v0.2.0/casper-x86_64-unknown-linux-gnu.tar.gz
```

**2. Extract the downloaded archive:**

```bash
tar -xzvf casper-x86_64-unknown-linux-gnu.tar.gz
```

**3. Set licence token:**

```bash
export LICENSE_TOKEN=<YOUR_LICENSE_TOKEN>
```

**4. Run Casper:**

```bash
./casper
```

Now you're ready to use Casper and explore its features!

### Docker: Download and Launch

**1. Pull the image:**

```bash
docker pull alexryzhickov/casper:latest
```

**2. Set licence token:**

```bash
export LICENSE_TOKEN=<YOUR_LICENSE_TOKEN>
```

**3. Run the container:**

```bash
docker run -d --name casper \
  -p 7222:7222 -p 7223:7223 -p 7224:7224 \
  -v casper-storage:/storage \
  -e LICENSE_TOKEN="$LICENSE_TOKEN" \
  alexryzhickov/casper:latest
```

`7222` is the REST API, `7223` carries fetched indexes and WALs and `7224` the
Raft log — a standalone node uses only the first, a node started
with `--cluster-role cluster` needs all three reachable from its peers. The
volume holds `/storage`: collections, WAL and Raft state. Without it they live
in the container's writable layer and `docker rm` takes them with it.

To override configuration, mount a YAML file at `/config/production.yaml` —
the image sets `RUN_MODE=production`, so that layer is read at startup, and it
merges key by key onto the defaults, so it may contain only the keys you
change:

```bash
docker run -d --name casper -p 7222:7222 \
  -v ./my-config.yaml:/config/production.yaml \
  -v casper-storage:/storage \
  -e LICENSE_TOKEN="$LICENSE_TOKEN" \
  alexryzhickov/casper:latest
```

**4. Verify health:**

```bash
curl http://localhost:7222/health
```

### Clients

Casper provides client libraries for several programming languages:

- [Python](https://github.com/casper-vdb/python-client)
- [Go](https://github.com/casper-vdb/go-client)
- [Rust](https://github.com/casper-vdb/rust-client)

## API Documentation

Casper exposes an HTTP API for managing collections, indexing (HNSW), inserts/updates/deletes, and search. For full endpoint descriptions and curl examples, see the documentation:

- [API Docs](docs/v0.2.0/api.md)
- [Configuration Docs](docs/v0.2.0/config.md)

## Cluster Mode

Casper runs as a cluster of full replicas under one Raft group. Every write goes through the Raft log and is durable on a majority; any node may lead, and followers serve reads.

By default the server runs in `standalone` mode. To enable clustering, pass `--cluster-role` and configure replication. The full set of flags is documented in [docs/config.md](docs/v0.2.0/config.md).

### Run standalone

A single-node deployment with no replication — the default mode:

```bash
./casper \
  --host 127.0.0.1 \
  --http-port 7222 \
  --storage-dir ./storage
```

### Run a cluster

Every node is a full replica, and any node may lead. A write goes through the Raft log and is durable on a majority, so a cluster without one takes no writes. The first node starts alone:

```bash
./casper \
  --host 10.0.0.1 \
  --cluster-role cluster \
  --storage-dir ./storage
```

The others name it:

```bash
./casper \
  --host 10.0.0.2 \
  --cluster-role cluster \
  --storage-dir ./storage \
  --bootstrap 10.0.0.1:7224
```

A write that reaches a follower is refused with `405` and the leader's address.

## Features

- **Advanced Vector Search**: High-speed retrieval for complex AI-driven applications.
- **Scalability**: Designed to handle large-scale data with ease.
- **Robust and Reliable**: Built in Rust for high performance even under heavy loads.

---
