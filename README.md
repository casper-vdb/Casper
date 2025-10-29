<p align="center">
  <img height="100" alt="Casper" src="docs/logo.png">
</p>

<p align="center">
    <b>⚡ World’s Fastest Vector Database for AI & RAG</b>
</p>

# Casper

**Casper** is a high-performance Vector Search Database, perfectly suited for high-load search systems and AI applications (RAG). It provides a robust and scalable solution to store, search, and manage vectors efficiently.

Casper is built using Rust 🦀 for performance and reliability.

---

## Why Casper ?

**Casper** is the fastest vector database in our internal benchmarks. It consistently outperforms Qdrant across Top@K workloads and both f32 and i8 quantizations. Notably, Qdrant is widely recognized as the leading open‑source engine and demonstrates state‑of‑the‑art throughput versus other databases (e.g., Weaviate, Milvus), as shown in their published results: [Qdrant benchmarks](https://qdrant.tech/benchmarks/). Surpassing Qdrant therefore places Casper ahead of the current open‑source performance leader.

In practice, Casper delivers up to an order‑of‑magnitude higher RPS compared to Qdrant on our datasets, which translates directly into substantial infrastructure savings: fewer CPU cores and instances to achieve the same SLA, lower memory pressure, and reduced total cost of ownership due to more efficient use of compute resources. **Casper** is the ideal solution for high-load systems, real-time search, and AI & RAG.

**Conclusion**: Casper achieves performance unattainable for other databases under comparable conditions, requires fewer compute resources at the same load, and materially reduces infrastructure costs through more efficient CPU and memory utilization.

### Casper vs Qdrant

#### Benchmark

**Hardware:**
- CPU: Intel Core i7-13700HX (16 cores / 24 threads)
- Memory: 32 GB RAM

**Dataset:**
- Vectors:   572,940
- Dimension: 128
- Metric:    Inner Product

Qdrant configured with quantile 0.99 (for int8), always ram enabled.

#### f32

Requests per second, RPS

| Engine  |  Top@100 | Top@1000 | Top@10.000 | Top@100.000 |
|---------|---------:|---------:|-----------:|------------:|
| Casper  | 123.98 k |  26.47 k |    2.427 k |         168 |
| Qdrant  |  14.57 k |   4.25 k |        517 |          17 |
| Speedup |     8.5x |     6.2x |       4.7x |        9.8x |

#### i8

Requests per second, RPS

| Engine  |  Top@100 | Top@1000 | Top@10.000 | Top@100.000 |
|---------|---------:|---------:|-----------:|------------:|
| Casper  | 193.28 k |  34.12 k |    3.633 k |         244 |
| Qdrant  |  15.81 k |   5.94 k |        606 |          18 |
| Speedup |    12.2x |     5.7x |         6x |       13.5x |

---

## HNSW

Casper features a highly efficient **HNSW (Hierarchical Navigable Small World)** index, providing fast and accurate similarity search. 

### Metrics

Casper supports multiple distance metrics:

- **Euclidean**
- **Cosine**
- **Inner-Product**

### Quantizations

Quantizations: f32 (full precision), i8 scalar quantization (compressed). Reduces memory footprint and improves search performance.

- **f32**
- **i8**

---

## Quick Start

### Download and Launch

To quickly get started with Casper, follow these steps:

**1. Download the latest release:**

```bash
wget https://github.com/casper-vdb/casper/releases/download/v0.0.0/casper-x86_64-unknown-linux-gnu.tar.gz
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
docker run -d --name casper -p 8080:8080 -e API_TOKEN="$API_TOKEN" alexryzhickov/casper:latest
```

**4. Verify health:**

```bash
curl http://localhost:8080/health
```

## Free Access

Casper is currently completely free. You can use the following free API token to run Casper:

```bash
export API_TOKEN=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE3OTMyOTAzNTMsImZyZWUiOnRydWV9.GxqiVw5kPzmPb25vo2CMOEwnBhjTH_GTAHeDg_nhlIQ
```

## API Documentation

Casper exposes an HTTP API for managing collections, indexing (HNSW), inserts/updates/deletes, and search. For full endpoint descriptions and curl examples, see the documentation:

- [HTTP API Docs](docs/docs.md)

---

## Features

- **Advanced Vector Search**: High-speed retrieval for complex AI-driven applications.
- **Scalability**: Designed to handle large-scale data with ease.
- **Robust and Reliable**: Built in Rust for high performance even under heavy loads.

---
