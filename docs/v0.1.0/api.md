## Casper HTTP API

This document describes the HTTP endpoints exposed by Casper. Each endpoint includes a short description, parameters, and curl examples.

Persistence: Collections are disk-backed. All upsert, delete, and batch update operations are durably persisted to disk.

Index requirement: Search is unavailable on a collection without an index. To perform nearest‑neighbor queries, create an index (HNSW) for the target collection first.

Assumptions:
- Server runs at http://localhost:7222
- Test collection name: demo

---

### Collection service

#### Create collection
- Method: POST
- Path: /collection/{name}
- Query: dim (usize), max_size (u32)
- Body: none
- Response: 200 OK, `{ "id": <u32> }`

Description: Creates a new collection with the specified dimensionality and capacity.

- **dim**: Vector dimensionality (number of components per vector). All vectors must match this length exactly.
- **max_size**: Maximum number of unique vector IDs stored in the collection. Upsert/batch operations that exceed this limit are rejected.

```bash
curl --location --request POST 'http://localhost:7222/collection/demo?dim=4&max_size=1000000'
```

---

#### Delete collection
- Method: DELETE
- Path: /collection/{name}
- Body: none

Description: Deletes the specified collection and its data.

```bash
curl --location --request DELETE 'http://localhost:7222/collection/demo'
```

---

#### Upsert vectors
- Method: PUT
- Path: /collection/{name}/vectors
- Body (application/json): `{ "vectors": [{ "id": u32, "vector": number[] }, ...] }`

Description: Inserts or replaces a batch of vectors by id. Validates dimensionality and rejects duplicate ids inside `vectors`.

```bash
curl --location --request PUT 'http://localhost:7222/collection/demo/vectors' \
  --header 'Content-Type: application/json' \
  --data-raw '{
    "vectors": [
      { "id": 10, "vector": [0.1, 0.2, 0.3, 0.4] },
      { "id": 11, "vector": [0.2, 0.3, 0.4, 0.5] }
    ]
  }'
```

---

#### Delete vectors
- Method: POST
- Path: /collection/{name}/vectors/delete
- Body (application/json): `{ "vectors": [u32, ...] }`

Description: Deletes the listed vector ids. Rejects duplicate ids and empty lists.

```bash
curl --location --request POST 'http://localhost:7222/collection/demo/vectors/delete' \
  --header 'Content-Type: application/json' \
  --data-raw '{ "vectors": [3, 5, 42] }'
```

---

#### Batch update (upsert + delete)
- Method: POST
- Path: /collection/{name}/update
- Body (application/json):
  ```json
  {
    "insert": [{ "id": <u32>, "vector": <number[]> }, ...],
    "delete": [<u32>, ...]
  }
  ```

Description: Applies a batch of operations. Inserts are written first, then deletes. Validation: no duplicate ids in insert; no duplicate ids in delete; no overlap between insert and delete; at least one of the lists must be non-empty.

```bash
curl --location --request POST 'http://localhost:7222/collection/demo/update' \
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

#### Mute collection
- Method: POST
- Path: /collection/{name}/mute
- Body: none

Description: Disables write operations (upsert, delete, and update) for the collection until it is unmuted.

```bash
curl --location --request POST 'http://localhost:7222/collection/demo/mute'
```

---

#### Unmute collection
- Method: POST
- Path: /collection/{name}/unmute
- Body: none

Description: Re-enables write operations (upsert, delete, and update) for the collection.

```bash
curl --location --request POST 'http://localhost:7222/collection/demo/unmute'
```

---

#### Create index (HNSW)
- Method: POST
- Path: /collection/{name}/index
- Body (application/json):
  ```json
  {
    "hnsw": {
      "metric": "<string>",
      "quantization": "<string>",
      "m": <number>,
      "m0": <number>,
      "ef_construction": <number>
    },
    "normalization": <bool, optional>
  }
  ```
- Response: 202 Accepted (build runs in the background)

Description: Creates an HNSW index with provided parameters. Validates metric/quantization and HNSW parameters.

- **metric**: Distance function used for similarity search. Supported values: `"euclidean"`, `"l2sq"`, `"cosine"`, `"inner-product"`.
- **quantization**: Vector storage precision. `"f32"` for full precision; `"i8"` for scalar quantization to reduce memory footprint and improve throughput at the cost of approximation.
- **m**: Target number of connections per node on upper layers. Higher values increase recall and memory usage; lower values reduce both.
- **m0**: Number of connections per node on the bottom layer (level 0). Typically set higher than `m`; increases recall and memory usage.
- **ef_construction**: Candidate list size during index build. Larger values improve recall but increase build time and memory.
- **normalization**: If true, vectors are L2-normalized on upsert and update only; query vectors are not normalized by the index. Enable for cosine similarity or inner-product with pre-normalized (unit-length) vectors supplied by the client.

Full precision (F32) + Euclidean:
```bash
curl --location --request POST 'http://localhost:7222/collection/demo/index' \
  --header 'Content-Type: application/json' \
  --data-raw '{
    "hnsw": {
        "metric": "euclidean",
        "quantization": "f32",
        "m": 16,
        "m0": 32,
        "ef_construction": 200
    },
    "normalization": true
  }'
```

Scalar quantization (I8) + Inner-Product:
```bash
curl --location --request POST 'http://localhost:7222/collection/demo/index' \
  --header 'Content-Type: application/json' \
  --data-raw '{
    "hnsw": {
        "metric": "inner-product",
        "quantization": "i8",
        "m": 16,
        "m0": 32,
        "ef_construction": 200
    },
    "normalization": true
  }'
```

---

#### Delete index
- Method: DELETE
- Path: /collection/{name}/index
- Body: none

Description: Deletes the index for the collection (if present).

```bash
curl --location --request DELETE 'http://localhost:7222/collection/demo/index'
```

---

#### Search
- Method: POST
- Path: /collection/{name}/search
- Query:
  - **limit** (usize, required) — number of nearest neighbors to return.
  - **ef_search** (usize, optional) — HNSW candidate list size at query time. Larger ⇒ higher recall, lower RPS. Defaults to the index's runtime default when omitted.
  - **output** (string, optional) — `"json"` (default) or `"bin"`.
- Body (application/json): `{ "vector": number[] }`

Description: Searches nearest neighbors for the provided query vector.

- `output=json` (default) → JSON: `{ "result": [ { "id": <u32>, "score": <f32> }, ... ] }`
- `output=bin` → `application/octet-stream`: `u32` little-endian count, then `count` pairs of `id: u32` and `dist: f32`, all little-endian.

JSON response (default):
```bash
curl --location --request POST 'http://localhost:7222/collection/demo/search?limit=10' \
  --header 'Content-Type: application/json' \
  --data-raw '{ "vector": [0.1, 0.2, 0.3, 0.4] }'
```

Binary response with explicit `ef_search`:
```bash
curl --location --request POST 'http://localhost:7222/collection/demo/search?limit=10&ef_search=64&output=bin' \
  --header 'Content-Type: application/json' \
  --output results.bin \
  --data-raw '{ "vector": [0.1, 0.2, 0.3, 0.4] }'
```

---

#### List collections
- Method: GET
- Path: /collections
- Body: none

Description: Returns a list of existing collections and their metadata.

```bash
curl --location --request GET 'http://localhost:7222/collections'
```

---

#### Get collection info
- Method: GET
- Path: /collection/{name}
- Body: none

Description: Returns metadata and status of the specified collection, including replication / applier progress (`current_seq`, `applied_seq`, `index_seq`, `catalog_seq`).

```bash
curl --location --request GET 'http://localhost:7222/collection/demo'
```

---

#### Get vector by id
- Method: GET
- Path: /collection/{name}/vector/{id}
- Body: none

Description: Returns the vector by id. 404 if not found.

```bash
curl --location --request GET 'http://localhost:7222/collection/demo/vector/42'
```

---

### Cluster

#### Get cluster info
- Method: GET
- Path: /cluster
- Body: none

Description: Returns the node's cluster role and progress. The response shape depends on the role and is tagged by `"role"`:

- `"role": "standalone"` — `{ node_id }`
- `"role": "master"` — `{ node_id, global_catalog_seq, collections, replicas }`. `collections` lists every local collection's `catalog_seq`, WAL head `current_seq`, `applied_seq` (HNSW applier head) and `index_seq` (WAL seq covered by the on-disk snapshot). `replicas` lists each connected replica's last-known cursors.
- `"role": "replica"` — `{ node_id, applied_global_catalog_seq, master_addr, collections }`. `collections` lists this replica's `applied_catalog_seq` and `applied_data_seq` per collection.

```bash
curl --location --request GET 'http://localhost:7222/cluster'
```

---

### Configuration

#### Get runtime configuration
- Method: GET
- Path: /config
- Body: none

Description: Returns the `AppConfig` the process started with as JSON. Configuration is immutable after startup — restart the process to change a value. See [config.md](config.md) for the full flag reference.

```bash
curl --location --request GET 'http://localhost:7222/config'
```

---

### Health
- Method: GET
- Path: /health
- Body: none

Description: Liveness and readiness probe endpoint. Returns HTTP 200 OK when the service process is up. Suitable for container orchestrators (e.g., Kubernetes) as both liveness and readiness probes.

```bash
curl --location --request GET 'http://localhost:7222/health'
```
