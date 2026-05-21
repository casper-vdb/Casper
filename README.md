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
- CPU: Intel Core i7-13700HX (16 cores / 24 threads)
- Memory: 32 GB RAM

**Dataset:** deep-image-96-angular.hdf5
- Vectors:   9,990,000
- Dimension: 96
- Metric:    Inner Product (vectors are L2-normalized, IP == cosine)

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
| Casper  | 106.87 k |  30.91 k |  4.363 k |        486 |          53 |
| Qdrant  |  17.02 k |  5.488 k |      730 |         85 |           9 |
| Speedup |     6.3x |     5.6x |     6.0x |       5.7x |        6.1x |

Recall

| Engine  |  Top@10  |  Top@100 |  Top@1k  |  Top@10k   |   Top@100k  |
|---------|---------:|---------:|---------:|-----------:|------------:|
| Casper  |    0.606 |    0.854 |    0.957 |      0.987 |       0.995 |
| Qdrant  |    0.762 |    0.953 |    0.993 |      0.999 |       1.000 |

#### Scalar Quantization (I8)

Requests per second, RPS

| Engine  | Top@10   |  Top@100 |  Top@1k  |  Top@10k   |   Top@100k  |
|:-------:|---------:|---------:|---------:|-----------:|------------:|
| Casper  | 126.63 k |  45.99 k |  6.756 k |        665 |          65 |
| Qdrant  |  12.60 k |  5.698 k |      923 |        100 |          10 |
| Speedup |    10.1x |     8.1x |     7.3x |       6.6x |        6.8x |

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

Casper is currently completely free. You can use the following free API token to run Casper:

```bash
export API_TOKEN=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE3OTMyOTAzNTMsImZyZWUiOnRydWV9.GxqiVw5kPzmPb25vo2CMOEwnBhjTH_GTAHeDg_nhlIQ
```

## Quick Start

### Download and Launch

To quickly get started with Casper, follow these steps:

**1. Download the latest release:**

```bash
wget https://github.com/casper-vdb/casper/releases/download/v0.0.1/casper-x86_64-unknown-linux-gnu.tar.gz
```

**2. Extract the downloaded archive:**

```bash
tar -xzvf casper-x86_64-unknown-linux-gnu.tar.gz
```

**3. Set API token:**

```bash
export API_TOKEN=<YOUR_API_TOKEN>
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

**2. Set API token:**

```bash
export API_TOKEN=<YOUR_API_TOKEN>
```

**3. Run the container:**

```bash
docker run -d --name casper -p 8080:8080 -p 50051:50051 -e API_TOKEN="$API_TOKEN" alexryzhickov/casper:latest
```

**4. Verify health:**

```bash
curl http://localhost:8080/health
```

### Clients

Casper provides client libraries for several programming languages:

- [Python](https://github.com/casper-vdb/python-client)
- [Go](https://github.com/casper-vdb/go-client)
- [Rust](https://github.com/casper-vdb/rust-client)

## API Documentation

Casper exposes an HTTP & GRPC API for managing collections, indexing (HNSW), inserts/updates/deletes, and search. For full endpoint descriptions and curl examples, see the documentation:

- [API Docs](docs/v0.0.1/api.md)

---

## Features

- **Advanced Vector Search**: High-speed retrieval for complex AI-driven applications.
- **Scalability**: Designed to handle large-scale data with ease.
- **Robust and Reliable**: Built in Rust for high performance even under heavy loads.

---
