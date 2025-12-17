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

#### Benchmarks RPS & Recall

**Hardware:**
- CPU: Intel Core i7-13700HX (16 cores / 24 threads)
- Memory: 32 GB RAM

**Dataset:**
- Vectors:   572,940
- Dimension: 128
- Metric:    Inner Product

**HNSW**
- m: 16
- ef construct: 200

Qdrant configured with quantile 0.99 (for int8), always ram enabled.

#### Full Precision (F32)

Requests per second, RPS

| Engine  | Top@10   |  Top@100 |  Top@1k  |  Top@10k   |   Top@100k  |
|:-------:|---------:|---------:|---------:|-----------:|------------:|
| Casper  | 253.19 k | 121.80 k |  26.03 k |    2.600 k |         157 |
| Qdrant  |   8.78 k |   7.79 k |   2.80 k |        168 |          18 |
| Speedup |    28.8x |    15.6x |     9.3x |      15.5x |        8.6x |

Recall

| Engine  |  Top@10  |  Top@100 |  Top@1k  |  Top@10k   |   Top@100k  |
|---------|---------:|---------:|---------:|-----------:|------------:|
| Casper  |    0.970 |    0.951 |    0.940 |      0.926 |       0.965 |
| Qdrant  |    0.996 |    0.985 |    0.978 |      0.982 |       0.991 |

#### Scalar Quantization (I8)

Requests per second, RPS

| Engine  | Top@10   |  Top@100 |  Top@1k  |  Top@10k   |   Top@100k  |
|:-------:|---------:|---------:|---------:|-----------:|------------:|
| Casper  | 264.20 k | 251.80 k |  30.81 k |    3.747 k |         210 |
| Qdrant  |  11.01 k |   7.97 k |   3.25 k |        189 |          19 |
| Speedup |    23.9x |    31.6x |     9.5x |      19.8x |       11.1x |

Recall

| Engine  |  Top@10  |  Top@100 |  Top@1k  |  Top@10k   |   Top@100k  |
|:-------:|---------:|---------:|---------:|-----------:|------------:|
| Casper  |    0.842 |    0.910 |    0.927 |      0.932 |       0.964 |
| Qdrant  |    0.892 |    0.945 |    0.960 |      0.974 |       0.982 |

#### Product Quantization (PQ)

16 subspaces and 2⁸ = 256 codewords per subspace

Requests per second, RPS

| Engine  | Top@10   |  Top@100 |  Top@1k  |  Top@10k   |   Top@100k  |
|:-------:|---------:|---------:|---------:|-----------:|------------:|
| Casper  | 204.91 k | 123.16 k |  25.81 k |    3.205 k |         224 |
| Qdrant  |   8.12 k |   6.53 k |   2.75 k |        190 |          18 |
| Speedup |    25.2x |    18.9x |     9.4x |      16.8x |       12.3x |

Recall

| Engine  |  Top@10  |  Top@100 |  Top@1k  |  Top@10k   |   Top@100k  |
|:-------:|---------:|---------:|---------:|-----------:|------------:|
| Casper  |    0.630 |    0.697 |    0.742 |      0.800 |       0.766 |
| Qdrant  |    0.639 |    0.764 |    0.834 |      0.899 |       0.899 |

- [Benchmarks Guide](docs/benchmarks.md) — For details on how to reproduce these benchmarks yourself (rps and recall).

## HNSW

Casper features a highly efficient **HNSW (Hierarchical Navigable Small World)** index, providing fast and accurate similarity search. 

### Metrics

Casper supports multiple distance metrics:

- **Euclidean**
- **L2SQ**
- **Cosine**
- **Inner-Product**

### Quantizations

Quantizations: f32 (full precision), i8 scalar quantization, and product quantization — reducing memory footprint and improving search performance.

- **F32**
- **I8**
- **PQ**

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
docker run -d --name casper -p 8080:8080 -p 50051:50051 -e API_TOKEN="$API_TOKEN" alexryzhickov/casper:latest
```

**4. Verify health:**

```bash
curl http://localhost:8080/health
```

### Clients

Casper provides client libraries for several programming languages:

- [Go](https://github.com/casper-vdb/go-client)
- [Rust](https://github.com/casper-vdb/rust-client)

## API Documentation

Casper exposes an HTTP & GRPC API for managing collections, indexing (HNSW), inserts/updates/deletes, and search. For full endpoint descriptions and curl examples, see the documentation:

- [API Docs](docs/api.md)

---

## Features

- **Advanced Vector Search**: High-speed retrieval for complex AI-driven applications.
- **Scalability**: Designed to handle large-scale data with ease.
- **Robust and Reliable**: Built in Rust for high performance even under heavy loads.

---
