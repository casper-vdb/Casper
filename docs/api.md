## Casper HTTP API

This document describes the HTTP endpoints exposed by Casper's HTTP services. Endpoints are grouped into **Collection service**, **Matrix service**, and **PQ service** sections. Each endpoint includes a short description, parameters, and curl examples.

Persistence: Collections are disk-backed. All insert, delete, and batch update operations are durably persisted to disk.

Index requirement: Search is unavailable on a collection without an index. To perform nearest‑neighbor queries, create an index (HNSW) for the target collection first.

Assumptions:
- Server runs at http://localhost:8080
- Test collection name: demo

---

### Collection service

#### Create collection
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

#### Delete collection
- Method: DELETE
- Path: /collection/{name}
- Body: none

Description: Deletes the specified collection and its data.

```bash
curl --location --request DELETE 'http://localhost:8080/collection/demo'
```

---

#### Insert vector
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

#### Delete vector by id
- Method: DELETE
- Path: /collection/{name}/delete
- Query: id (u32)

Description: Deletes the vector with the specified id from the collection.

```bash
curl --location --request DELETE 'http://localhost:8080/collection/demo/delete?id=42'
```

---

#### Batch update (insert + delete)
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

#### Mute collection
- Method: POST
- Path: /collection/{name}/mute
- Body: none

Description: Disables write operations (insert, delete, and update) for the collection until it is unmuted.

```bash
curl --location --request POST 'http://localhost:8080/collection/demo/mute'
```

---

#### Unmute collection
- Method: POST
- Path: /collection/{name}/unmute
- Body: none

Description: Re-enables write operations (insert, delete, and update) for the collection.

```bash
curl --location --request POST 'http://localhost:8080/collection/demo/unmute'
```

---

#### Create index (HNSW)
- Method: POST
- Path: /collection/{name}/index
- Body (application/json): { "index": "hnsw", "config": { "metric": string, "quantization": string, "m": number, "m0": number, "ef_construction": number, "normalization": bool (optional) } }

Description: Creates an HNSW index with provided parameters. Validates metric/quantization and HNSW parameters.

- **metric**: Distance function used for similarity search. Supported values: "euclidean", "l2sq", "cosine", "inner-product".
- **quantization**: Vector storage precision. "f32" for full precision; "i8" for scalar quantization to reduce memory footprint and improve throughput at the cost of approximation. Product quantization (PQ, e.g. "pq8") is configured separately via PQ service and **does not support** the "cosine" metric (only "euclidean", "l2sq", and "inner-product" are allowed).
- **m**: Target number of connections per node on upper layers. Higher values increase recall and memory usage; lower values reduce both.
- **m0**: Number of connections per node on the bottom layer (level 0). Typically set higher than m; increases recall and memory usage.
- **ef_construction**: Candidate list size during index build. Larger values improve recall but increase build time and memory.
- **normalization**: If true, vectors are L2-normalized on insert and update only; query vectors are not normalized by the index. Enable for cosine similarity or inner-product with pre-normalized (unit-length) vectors supplied by the client.

Full precision (F32) + Euclidean:
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
        "normalization": true
    }
  }'
```

Scalar quantization (I8) + Inner-Product:
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

Example with PQ quantization (`pq8`) and a preconfigured PQ named `pq_ip`:
```bash
curl --location --request POST 'http://localhost:8080/collection/demo/index' \
  --header 'Content-Type: application/json' \
  --data-raw '{
    "index": "hnsw",
    "config": {
        "metric": "inner-product",
        "quantization": "pq8",
        "m": 16,
        "m0": 32,
        "ef_construction": 200,
        "pq_name": "pq_ip",
        "normalization": false
    }
  }'
```

---

#### Delete index
- Method: DELETE
- Path: /collection/{name}/index
- Body: none

Description: Deletes the index for the collection (if present).

```bash
curl --location --request DELETE 'http://localhost:8080/collection/demo/index'
```

---

#### Search
- Method: POST
- Path: /collection/{name}/search
- Query: **limit** (usize), **output** (optional, string, e.g. "json" or "bin", default: "bin")
- Body (application/json): { "vector": number[] }

Description: Searches nearest neighbors for the provided query vector. If output=json is set, returns JSON array of [id, score]. Otherwise (or if output is omitted) returns application/octet-stream with binary-encoded results (u32 count, then id u32 and dist f32 pairs).

JSON request example (returns JSON response):
```bash
curl --location --request POST 'http://localhost:8080/collection/demo/search?limit=10&output=json' \
  --header 'Content-Type: application/json' \
  --data-raw '{ "vector": [0.1, 0.2, 0.3, 0.4] }'
```

Binary request example (returns binary response):
```bash
curl --location --request POST 'http://localhost:8080/collection/demo/search?limit=10' \
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
curl --location --request GET 'http://localhost:8080/collections'
```

---

#### Get collection info
- Method: GET
- Path: /collection/{name}
- Body: none

Description: Returns metadata and status of the specified collection.

```bash
curl --location --request GET 'http://localhost:8080/collection/demo'
```

---

#### Get vector by id
- Method: GET
- Path: /collection/{name}/vector/{id}
- Body: none

Description: Returns the vector by id. 404 if not found.

```bash
curl --location --request GET 'http://localhost:8080/collection/demo/vector/42'
```

---

### Matrix service

#### Create matrix (gRPC UploadMatrix)

Matrix creation via HTTP JSON body has been removed, because large matrices do not fit well into a single HTTP request body. The only supported way to create or replace a matrix is the gRPC streaming method `matrix_service.MatrixService/UploadMatrix`.

- Transport: gRPC (tonic)
- Service: `matrix_service.MatrixService`
- Method: `UploadMatrix(stream UploadMatrixRequest) returns (UploadMatrixResponse)`

Upload flow:
- Client opens a streaming RPC and first sends exactly **one** `MatrixHeader`.
- Then it sends **`total_chunks`** `MatrixData` messages with the matrix data.
- Server validates the stream and saves the matrix under `header.name` if everything is consistent.

`MatrixHeader` fields:
- **name** (`string`): Logical matrix name. This name is used later in HTTP Matrix/PQ APIs (e.g., `/matrix/{name}`).
- **dimension** (`uint32`): Vector dimensionality (number of `float` components per row). Must be > 0. All matrix rows must have this length.
- **total_chunks** (`uint32`): Number of `MatrixData` chunks the client will send. The server checks that the actual number of received chunks matches this value.
- **max_vectors_per_chunk** (`uint32`): Upper bound on the number of vectors in a single data chunk. For each chunk the server enforces that `len(vector) / dimension <= max_vectors_per_chunk`.

`MatrixData` fields:
- **chunk_index** (`uint32`): Position of this data chunk in the stream (client should send them in order from 1 to `total_chunks`). Currently used for client-side bookkeeping; the server validates only the total number of chunks.
- **vector** (`repeated float`): Flattened buffer of vector components for this chunk. Its length must be divisible by `dimension`. The number of vectors in this chunk is `vector.len() / dimension`.

`UploadMatrixResponse` fields:
- **total_vectors** (`uint32`): Total number of vectors (rows) saved in the matrix.
- **total_chunks** (`uint32`): Number of data chunks actually received and accepted by the server (must equal `header.total_chunks`).

Proto definition:

```proto
syntax = "proto3";

package matrix_service;

service MatrixService {
  rpc UploadMatrix(stream UploadMatrixRequest) returns (UploadMatrixResponse);
}

message UploadMatrixRequest {
  oneof payload {
    MatrixHeader header = 1;
    MatrixData data = 2;
  }
}

message MatrixHeader {
  string name = 1;
  uint32 dimension = 2;
  uint32 total_chunks = 3;
  uint32 max_vectors_per_chunk = 4;
}

message MatrixData {
  uint32 chunk_index = 1;
  repeated float vector = 2;
}

message UploadMatrixResponse {
  uint32 total_vectors = 1;
  uint32 total_chunks  = 2;
}
```

---

#### Delete matrix
- Method: DELETE
- Path: /matrix/{name}
- Body: none

Description: Deletes the specified matrix and its metadata.

```bash
curl --location --request DELETE 'http://localhost:8080/matrix/demo_matrix'
```

---

#### List matrices
- Method: GET
- Path: /matrix/list
- Body: none

Description: Returns a list of saved matrices with basic metadata.

Response JSON (array of objects):
- **name**: Matrix name (string)
- **dim**: Vector dimensionality (usize)
- **len**: Number of rows (usize)
- **enabled**: Whether the matrix is currently enabled for use (bool)

```bash
curl --location --request GET 'http://localhost:8080/matrix/list'
```

---

#### Get matrix info
- Method: GET
- Path: /matrix/{name}
- Body: none

Description: Returns metadata for the specified matrix (same shape as items from /matrix/list).

```bash
curl --location --request GET 'http://localhost:8080/matrix/demo_matrix'
```

---

### PQ service

#### Create PQ
- Method: POST
- Path: /pq/{name}
- Body (application/json): { "dim": number, "codebooks": string[] }

Description: Creates a PQ configuration with the given name. `dim` is the vector dimensionality; `codebooks` is a list of codebook filenames to use.

```bash
curl --location --request POST 'http://localhost:8080/pq/my_pq' \
  --header 'Content-Type: application/json' \
  --data-raw '{
    "dim": 128,
    "codebooks": ["pq_sub_0.bin", "pq_sub_1.bin"]
  }'
```

---

#### Delete PQ
- Method: DELETE
- Path: /pq/{name}
- Body: none

Description: Deletes the specified PQ configuration.

```bash
curl --location --request DELETE 'http://localhost:8080/pq/my_pq'
```

---

#### List PQ configurations
- Method: GET
- Path: /pq/list
- Body: none

Description: Returns a list of configured PQ entries.

Response JSON (array of objects):
- **name**: PQ name (string)
- **dim**: Vector dimensionality (usize)
- **codebooks**: List of codebook filenames (string[])
- **enabled**: Whether the PQ configuration is enabled (bool)

```bash
curl --location --request GET 'http://localhost:8080/pq/list'
```

---

#### Get PQ info
- Method: GET
- Path: /pq/{name}
- Body: none

Description: Returns metadata for the specified PQ configuration (same shape as items from /pq/list).

```bash
curl --location --request GET 'http://localhost:8080/pq/my_pq'
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

