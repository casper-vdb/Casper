## Casper HTTP API

This document describes the HTTP endpoints exposed by Casper.

Persistence: collections are disk-backed. All upsert, delete, and batch update operations are durably persisted to disk.

Index requirement: search is unavailable on a collection without an index. To run nearest-neighbor queries, create an index (HNSW) first.

Assumptions:
- Server runs at http://localhost:7222
- Test collection name: demo

---

### Collection service

#### Create collection
- Method: POST
- Path: `/collection/{name}`
- Query: `dim` (usize), `max_size` (u32)
- Body: none

Description: Creates a new collection with the specified dimensionality and capacity.

- **dim**: Vector dimensionality (number of components per vector). All vectors must match this length exactly.
- **max_size**: Maximum number of unique vector IDs stored in the collection. Upsert/batch operations that exceed this limit are rejected.

```bash
curl --location --request POST 'http://localhost:7222/collection/demo?dim=4&max_size=1000000'
```

Response:
- `200 OK`, `application/json`
- JSON example:
```json
{
  "id": "c8c3f16f-0f4e-45af-a4eb-d4969ec74fef"
}
```

---

#### Delete collection
- Method: DELETE
- Path: `/collection/{name}`
- Body: none

Description: Deletes the specified collection and its data.

```bash
curl --location --request DELETE 'http://localhost:7222/collection/demo'
```

Response:
- `200 OK`
- Empty body (no JSON)

---

#### Upsert vectors
- Method: PUT
- Path: `/collection/{name}/vectors`
- Body (`application/json`):
```json
{
  "vectors": [
    { "id": 10, "vector": [0.1, 0.2, 0.3, 0.4] },
    { "id": 11, "vector": [0.2, 0.3, 0.4, 0.5] }
  ]
}
```

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

Response:
- `200 OK`
- Empty body (no JSON)

---

#### Delete vectors
- Method: POST
- Path: `/collection/{name}/vectors/delete`
- Body (`application/json`):
```json
{
  "vectors": [3, 5, 42]
}
```

Description: Deletes the listed vector ids. Rejects duplicate ids and empty lists.

```bash
curl --location --request POST 'http://localhost:7222/collection/demo/vectors/delete' \
  --header 'Content-Type: application/json' \
  --data-raw '{ "vectors": [3, 5, 42] }'
```

Response:
- `200 OK`
- Empty body (no JSON)

---

#### Batch update (upsert + delete)
- Method: POST
- Path: `/collection/{name}/update`
- Body (`application/json`):
```json
{
  "insert": [
    { "id": 10, "vector": [0.1, 0.2, 0.3, 0.4] },
    { "id": 11, "vector": [0.2, 0.3, 0.4, 0.5] }
  ],
  "delete": [3, 5]
}
```

Description: Applies a batch of operations. Inserts are written first, then deletes. Validation: no duplicate ids in `insert`, no duplicate ids in `delete`, no overlap between `insert` and `delete`, and at least one list must be non-empty.

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

Response:
- `200 OK`
- Empty body (no JSON)

---

#### Mute collection
- Method: POST
- Path: `/collection/{name}/mute`
- Body: none

Description: Disables write operations (`upsert`, `delete`, `update`) for the collection until it is unmuted.

```bash
curl --location --request POST 'http://localhost:7222/collection/demo/mute'
```

Response:
- `200 OK`
- Empty body (no JSON)

---

#### Unmute collection
- Method: POST
- Path: `/collection/{name}/unmute`
- Body: none

Description: Re-enables write operations (`upsert`, `delete`, `update`) for the collection.

```bash
curl --location --request POST 'http://localhost:7222/collection/demo/unmute'
```

Response:
- `200 OK`
- Empty body (no JSON)

---

#### Create index (HNSW)
- Method: POST
- Path: `/collection/{name}/index`
- Body (`application/json`):
```json
{
  "hnsw": {
    "metric": "euclidean",
    "quantization": "f32",
    "m": 16,
    "m0": 32,
    "ef_construction": 200
  },
  "normalization": true
}
```

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

Response:
- `202 Accepted` (index build runs in background)
- Empty body (no JSON)

---

#### Delete index
- Method: DELETE
- Path: `/collection/{name}/index`
- Body: none

Description: Deletes the collection index (if present).

```bash
curl --location --request DELETE 'http://localhost:7222/collection/demo/index'
```

Response:
- `200 OK`
- Empty body (no JSON)

---

#### Search
- Method: POST
- Path: `/collection/{name}/search`
- Query:
  - `limit` (usize, required): number of nearest neighbors.
  - `ef_search` (usize, optional): HNSW candidate list size for search.
  - `output` (string, optional): `"json"` (default) or `"bin"`.
- Body (`application/json`):
```json
{
  "vector": [0.1, 0.2, 0.3, 0.4]
}
```

Description: Finds nearest neighbors for the query vector.

```bash
curl --location --request POST 'http://localhost:7222/collection/demo/search?limit=10' \
  --header 'Content-Type: application/json' \
  --data-raw '{ "vector": [0.1, 0.2, 0.3, 0.4] }'
```

Response (`output=json`, default):
- `200 OK`, `application/json`
- JSON example:
```json
{
  "result": [
    { "id": 10, "score": 0.0123 },
    { "id": 11, "score": 0.0456 }
  ]
}
```

```bash
curl --location --request POST 'http://localhost:7222/collection/demo/search?limit=10&ef_search=64&output=bin' \
  --header 'Content-Type: application/json' \
  --output results.bin \
  --data-raw '{ "vector": [0.1, 0.2, 0.3, 0.4] }'
```

Response (`output=bin`):
- `200 OK`, `application/octet-stream`
- Binary payload format: `u32` count (little-endian), then repeated pairs of `id: u32` + `score: f32` (little-endian).

---

#### List collections
- Method: GET
- Path: `/collections`
- Body: none

Description: Returns all collections and their metadata.

```bash
curl --location --request GET 'http://localhost:7222/collections'
```

Response:
- `200 OK`, `application/json`
- JSON example:
```json
{
  "collections": [
    {
      "status": "green",
      "id": "d0d84675-4cb5-4663-9463-bb261848fc36",
      "name": "demo",
      "dimension": 96,
      "max_size": 10000000,
      "size": 9990000,
      "applied_size": 9990000,
      "catalog_seq": 0,
      "current_seq": 52813,
      "applied_seq": 52813,
      "index_seq": 52813,
      "mutable": true,
      "has_index": true,
      "replicated": false,
      "index": {
        "hnsw": {
          "metric": "inner-product",
          "quantization": "f32",
          "m": 16,
          "m0": 32,
          "ef_construction": 200
        },
        "normalization": true
      }
    }
  ]
}
```

---

#### Get collection info
- Method: GET
- Path: `/collection/{name}`
- Body: none

Description: Returns metadata and status for one collection, including applier and replication progress fields (`catalog_seq`, `current_seq`, `applied_seq`, `index_seq`).

```bash
curl --location --request GET 'http://localhost:7222/collection/demo'
```

Response:
- `200 OK`, `application/json`
- JSON example:
```json
{
  "status": "green",
  "id": "d0d84675-4cb5-4663-9463-bb261848fc36",
  "name": "demo",
  "dimension": 96,
  "max_size": 10000000,
  "size": 9990000,
  "applied_size": 9990000,
  "catalog_seq": 0,
  "current_seq": 52813,
  "applied_seq": 52813,
  "index_seq": 52813,
  "mutable": true,
  "has_index": true,
  "replicated": false,
  "index": {
    "hnsw": {
      "metric": "inner-product",
      "quantization": "f32",
      "m": 16,
      "m0": 32,
      "ef_construction": 200
    },
    "normalization": true
  }
}
```

---

#### Get vector by id
- Method: GET
- Path: `/collection/{name}/vector/{id}`
- Body: none

Description: Returns vector by id.

```bash
curl --location --request GET 'http://localhost:7222/collection/demo/vector/42'
```

Response (found):
- `200 OK`, `application/json`
- JSON example:
```json
{
  "id": 42,
  "vector": [0.1, 0.2, 0.3, 0.4]
}
```

Response (not found):
- `404 Not Found`, `application/json`
- JSON example:
```json
{
  "error": "Vector not found",
  "id": 42
}
```

---

### Cluster

#### Get cluster info
- Method: GET
- Path: `/cluster`
- Body: none

Description: Returns node cluster role and progress. Payload shape depends on `role`.

```bash
curl --location --request GET 'http://localhost:7222/cluster'
```

Response:
- `200 OK`, `application/json`
- JSON example (`role=standalone`):
```json
{
  "role": "standalone",
  "node_id": "standalone"
}
```
- JSON example (`role=master`):
```json
{
  "role": "master",
  "node_id": "ea1ae526-cd80-47f6-9ea8-346909637655",
  "global_catalog_seq": 1,
  "collections": [
    {
      "name": "demo",
      "catalog_seq": 1,
      "current_seq": 39024,
      "applied_seq": 39024,
      "index_seq": 39024
    }
  ],
  "replicas": [
    {
      "replica_id": "09a656b1-c95e-46ea-87b2-721b7e6f8ebf",
      "applied_global_catalog_seq": 1,
      "collections": [
        {
          "name": "test_collection",
          "applied_catalog_seq": 0,
          "applied_data_seq": 39024
        }
      ]
    }
  ]
}
```
- JSON example (`role=replica`):
```json
{
  "role": "replica",
  "node_id": "09a656b1-c95e-46ea-87b2-721b7e6f8ebf",
  "applied_global_catalog_seq": 1,
  "master_addr": "127.0.0.1:7223",
  "collections": [
    {
      "name": "demo",
      "applied_catalog_seq": 0,
      "applied_data_seq": 39024
    }
  ]
}
```

---

### Configuration

#### Get runtime configuration
- Method: GET
- Path: `/config`
- Body: none

Description: Returns startup `AppConfig` as JSON. Config is immutable after startup; restart process to change values. See [config.md](config.md) for full reference.

```bash
curl --location --request GET 'http://localhost:7222/config'
```

Response:
- `200 OK`, `application/json`
- JSON example:
```json
{
  "host": "127.0.0.1",
  "http_port": 7222,
  "storage_dir": "./storage",
  "cluster_role": "master",
  "master_addr": null,
  "grpc_port": 7223,
  "snapshot_every_writes": 500000,
  "snapshot_every_seconds": 10000000,
  "snapshot_enabled": true,
  "sync_replicas": 1,
  "write_ack_timeout_ms": 5000
}
```

---

### Health
- Method: GET
- Path: `/health`
- Body: none

Description: Liveness/readiness probe endpoint.

```bash
curl --location --request GET 'http://localhost:7222/health'
```

Response:
- `200 OK`
- Empty body (no JSON)
