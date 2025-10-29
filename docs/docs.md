## Casper HTTP API

This document describes the HTTP endpoints exposed by Casper's collection service. Each section includes a short description, parameters, and curl examples.

Persistence: Collections are disk-backed. All insert, delete, and batch update operations are durably persisted to disk.

Index requirement: Search is unavailable on a collection without an index. To perform nearest‑neighbor queries, create an index (HNSW) for the target collection first.

Assumptions:
- Server runs at http://localhost:8080
- Test collection name: demo

---

### Create collection
- Method: POST
- Path: /collection/{name}
- Query: dim (usize), max_size (usize)
- Body: none

Description: Creates a new collection with the specified dimensionality and capacity.

- **dim**: Vector dimensionality (number of components per vector). All vectors must match this length exactly.
- **max_size**: Maximum number of unique vector IDs stored in the collection. Insert/batch operations that exceed this limit are rejected.

```bash
curl --location --request POST 'http://localhost:8080/collection/demo?dim=4&max_size=1000000'
```

---

### Delete collection
- Method: DELETE
- Path: /collection/{name}
- Body: none

Description: Deletes the specified collection and its data.

```bash
curl --location --request DELETE 'http://localhost:8080/collection/demo'
```

---

### Insert vector
- Method: POST
- Path: /collection/{name}/insert
- Query: id (u32)
- Body (application/json): { "vector": number[] }

Description: Inserts or replaces a vector under the given id. Validates vector dimensionality.

```bash
curl --location --request POST 'http://localhost:8080/collection/demo/insert?id=42' \
  --header 'Content-Type: application/json' \
  --data-raw '{
    "vector": [0.1, 0.2, 0.3, 0.4]
  }'
```

---

### Delete vector by id
- Method: DELETE
- Path: /collection/{name}/delete
- Query: id (u32)

Description: Deletes the vector with the specified id from the collection.

```bash
curl --location --request DELETE 'http://localhost:8080/collection/demo/delete?id=42'
```

---

### Batch update (insert + delete)
- Method: POST
- Path: /collection/{name}/update
- Body (application/json):
  {
    "insert": [{ "id": u32, "vector": number[] }, ...],
    "delete": [u32, ...]
  }

Description: Applies a batch of operations. Inserts are written first, then deletes. Validation: no duplicate ids in insert; no duplicate ids in delete; no overlap between insert and delete; at least one of the lists must be non-empty.

```bash
curl --location --request POST 'http://localhost:8080/collection/demo/update' \
  --header 'Content-Type: application/json' \
  --data-raw '{
    "insert": [
      { "id": 10, "vector": [0.1, 0.2, 0.3, 0.4] },
      { "id": 11, "vector": [0.2, 0.3, 0.4, 0.5] }
    ],
    "delete": [3, 5]
  }'
```

---

### Mute collection
- Method: POST
- Path: /collection/{name}/mute
- Body: none

Description: Disables write operations (insert, delete, and update) for the collection until it is unmuted.

```bash
curl --location --request POST 'http://localhost:8080/collection/demo/mute'
```

---

### Unmute collection
- Method: POST
- Path: /collection/{name}/unmute
- Body: none

Description: Re-enables write operations (insert, delete, and update) for the collection.

```bash
curl --location --request POST 'http://localhost:8080/collection/demo/unmute'
```

---

### Create index (HNSW)
- Method: POST
- Path: /collection/{name}/index
- Body (application/json): { "index": "hnsw", "config": { "metric": string, "quantization": string, "m": number, "m0": number, "ef_construction": number, "ef": number, "normalization"?: bool } }

Description: Creates an HNSW index with provided parameters. Validates metric/quantization and HNSW parameters.

- **metric**: Distance function used for similarity search. Supported values: "euclidean", "cosine", "inner-product".
- **quantization**: Vector storage precision. "f32" for full precision; "i8" (scalar quantization) to reduce memory footprint and improve throughput at the cost of approximation.
- **m**: Target number of connections per node on upper layers. Higher values increase recall and memory usage; lower values reduce both.
- **m0**: Number of connections per node on the bottom layer (level 0). Typically set higher than m; increases recall and memory usage.
- **ef_construction**: Candidate list size during index build. Larger values improve build-time recall but increase build time and memory.
- **ef**: Candidate list size during search. Larger values improve recall but increase query latency and CPU usage.
- **normalization**: If true, vectors are L2-normalized on insert and update only; query vectors are not normalized by the index. Enable for cosine similarity or inner-product with pre-normalized (unit-length) vectors supplied by the client.

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
        "ef": 50,
        "normalization": true
    }
  }'
```

Alternative (Euclidean + f32):
```bash
curl --location --request POST 'http://localhost:8080/collection/demo/index' \
  --header 'Content-Type: application/json' \
  --data-raw '{
    "index": "hnsw",
    "config": {
        "metric": "euclidean",
        "quantization": "f32",
        "m": 16,
        "m0": 32,
        "ef_construction": 200,
        "ef": 50,
        "normalization": true
    }
  }'
```

---

### Delete index
- Method: DELETE
- Path: /collection/{name}/index
- Body: none

Description: Deletes the index for the collection (if present).

```bash
curl --location --request DELETE 'http://localhost:8080/collection/demo/index'
```

---

### Search
- Method: POST
- Path: /collection/{name}/search
- Query: n_neighbors (usize), output_type? ("json")
- Body (application/json): { "vector": number[] }

Description: Searches nearest neighbors for the provided query vector. If output_type=json is set, returns JSON array of [id, score]. Otherwise returns application/octet-stream with binary-encoded results (u32 count, then id u32 and dist f32 pairs).

JSON response example:
```bash
curl --location --request POST 'http://localhost:8080/collection/demo/search?n_neighbors=10&output_type=json' \
  --header 'Content-Type: application/json' \
  --data-raw '{ "vector": [0.1, 0.2, 0.3, 0.4] }'
```

Binary response example:
```bash
curl --location --request POST 'http://localhost:8080/collection/demo/search?n_neighbors=10' \
  --header 'Content-Type: application/json' \
  --output results.bin \
  --data-raw '{ "vector": [0.1, 0.2, 0.3, 0.4] }'
```

---

### List collections
- Method: GET
- Path: /collections
- Body: none

Description: Returns a list of existing collections and their metadata.

```bash
curl --location --request GET 'http://localhost:8080/collections'
```

---

### Get collection info
- Method: GET
- Path: /collection/{name}
- Body: none

Description: Returns metadata and status of the specified collection.

```bash
curl --location --request GET 'http://localhost:8080/collection/demo'
```

---

### Get vector by id
- Method: GET
- Path: /collection/{name}/vector/{id}
- Body: none

Description: Returns the vector by id. 404 if not found.

```bash
curl --location --request GET 'http://localhost:8080/collection/demo/vector/42'
```

---

### Health
- Method: GET
- Path: /health
- Body: none

Description: Liveness and readiness probe endpoint. Returns HTTP 200 OK when the service process is up. Suitable for container orchestrators (e.g., Kubernetes) as both liveness and readiness probes.

```bash
curl --location --request GET 'http://localhost:8080/health'
```

