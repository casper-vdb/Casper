## Casper HTTP API

This document describes the HTTP endpoints exposed by Casper.

Persistence: collections are disk-backed. Every write (`POST /collection/{name}/update`) is durably persisted to disk before it is acknowledged.

Index requirement: search, scores and get-by-id are unavailable on a collection without an index. The index schema is given when the collection is created; to run nearest-neighbor queries, start indexing with `POST /collection/{name}/index/start`.

Assumptions:
- Server runs at http://localhost:7222
- Test collection name: test_collection, `dim` 4

In a cluster, writes go to the leader; with authentication on, every request carries a key. Both are described at the end: [Writes in a cluster](#writes-in-a-cluster), [Errors](#errors) and [Authentication](#authentication).

---

### Collection service

#### Create collection
- Method: POST
- Path: `/collection/{name}`
- Body (`application/json`):
```json
{
    "dim": 4,
    "max_size": 10000000,
    "index": {
        "hnsw": {
            "metric": "inner-product",
            "quantization": "f32",
            "m": 16,
            "m0": 32,
            "ef_construction": 200
        },
        "normalization": true,
        "storage": {
            "range_size_bytes": 134217728,
            "snapshot": {
                "enabled": true,
                "changes": 1000000,
                "wal_ops": 2000000
            },
            "compaction": {
                "enabled": true,
                "max_chain_depth": 8,
                "max_tail_ratio": 0.25
            }
        }
    }
}
```

Description: Creates a new collection with its dimensionality, its capacity, and the schema and policy of its index. The schema never changes; the policy can be changed with `PATCH /collection/{name}/index`, before indexing starts as well. Creating a collection builds no index: writes go into its WAL, and `POST /collection/{name}/index/start` starts indexing. `index` is required. `normalization`, `storage` and every key of `storage` are optional; an omitted value takes the default shown above and is recorded explicitly. The exceptions are `normalization`, which defaults to `false` (the example turns it on), `storage.snapshot.changes`, which defaults to 1/10 of `max_size`, and `storage.snapshot.wal_ops`, which defaults to 2/10, each at least 1. If the request names one of the two, the default of the other gives way so that the pair stays legal. `state`, `snapshot_active` and `compaction_active` are refused as unknown keys: a node computes them.

- **dim**: Vector dimensionality (number of components per vector). All vectors must match this length exactly.
- **max_size**: Maximum number of unique vector IDs stored in the collection. A batch that would exceed it is refused with `400 Bad Request` (`collection capacity exceeded`).
- **index.hnsw.metric**: Distance function used for similarity search. Supported values: `"euclidean"`, `"l2sq"`, `"cosine"`, `"inner-product"`.
- **index.hnsw.quantization**: Vector storage precision. `"f32"` for full precision; `"i8"` for scalar quantization to reduce memory footprint and improve throughput at the cost of approximation.
- **index.hnsw.m**: Target number of connections per node on upper layers. Higher values increase recall and memory usage; lower values reduce both.
- **index.hnsw.m0**: Number of connections per node on the bottom layer (level 0). Typically set higher than `m`; increases recall and memory usage.
- **index.hnsw.ef_construction**: Candidate list size during index build. Larger values improve recall but increase build time and memory.
- **index.normalization**: If true, the index L2-normalizes every vector it stores, and every query of a search or scores before comparing it. A `cosine` index always normalizes, whatever this says. Useful for `inner-product` over vectors the client does not normalize itself. Defaults to `false`.
- **index.storage.range_size_bytes**: Target payload bytes per range of the index set. A snapshot appends only the ranges that changed, so this is the granularity of an incremental save: smaller ranges write less per snapshot but leave more files to read at load. Between 128 MiB and 8 GiB. Cannot be changed after creation.
- **index.storage.snapshot.enabled**: Periodic snapshots of this index. Runs only if `storage.index.snapshot.enabled` is on for the node too. While off, this index's WAL is not trimmed and a restart replays everything since the last snapshot.
- **index.storage.snapshot.changes**: Snapshot once this many internal ids changed their payload since the last snapshot. Bounds what a restart replays. Every snapshot rewrites the whole graph (about 148 bytes per element), so raise it on large collections. At least `1`.
- **index.storage.snapshot.wal_ops**: Backstop: snapshot once this many WAL ops (inserts + deletes) were applied since the last snapshot. Covers hot keys and deletes, which do not grow the changed ids. At least `index.storage.snapshot.changes`. Whichever trigger fires first wins.
- **index.storage.compaction.enabled**: Fold passes for this index. Runs only if `storage.index.compaction.enabled` is on for the node too.
- **index.storage.compaction.max_chain_depth**: A range whose chain has this many files is folded: bounds the file count and the load time. At least `3`, or `null` to turn the rule off.
- **index.storage.compaction.max_tail_ratio**: A range whose files after the oldest hold this share of the range's capacity is folded: bounds the superseded vectors on disk. Also chooses between a tail fold and a full one. In `(0, 1)`.

```bash
curl --location --request POST 'http://localhost:7222/collection/test_collection' \
  --header 'Content-Type: application/json' \
  --data-raw '{
      "dim": 4,
      "max_size": 10000000,
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
  }'
```

Response:
- `200 OK`, `application/json`
- JSON example:
```json
{
  "id": "a9a30dfc-70d4-4dd1-93ad-10934c3cadd0"
}
```
- `400 Bad Request`: an unknown key, or a schema or policy that is not valid; the message names the key under `index.hnsw` or `index.storage`
- `405 Method Not Allowed`: the collection already exists, or in a cluster this node is not the leader

---

#### Delete collection
- Method: DELETE
- Path: `/collection/{name}`
- Body: none

Description: Deletes the specified collection and its data, index included.

```bash
curl --location --request DELETE 'http://localhost:7222/collection/test_collection'
```

Response:
- `200 OK`
- Empty body (no JSON)
- `404 Not Found`: no such collection
- `405 Method Not Allowed`: its index is being built, or in a cluster this node is not the leader

---

#### Batch limit

`POST /collection/{name}/update` refuses a batch whose WAL record would exceed the limit, 1 MiB by default, with `413 Payload Too Large`, naming both sizes. A body over eight times the configured limit gets `413` too. The client splits the batch. See [config.md](config.md).

In cluster mode a write can also get:

- `405` with `leader_addr`: this node does not lead. Retry there. One that lost the lead after taking the write gives no answer about it either: the entry may still commit, as for `504`, and the retry is just as safe.
- `429` with `Retry-After`: the queue in front of the log is full, or the estimated wait too long.
- `503` with `Retry-After`: this leader has no quorum, has not applied its term's first entry, or the collection has not reached this node.
- `504`: the outcome is unknown, and the entry may still commit. A retry is safe, a write being an upsert by id.
- `507`: no room for the record on top of `storage.min_free_disk_mb`.
- `500`: this node's consensus has stopped. Nothing was written, and the node is on its way down.

#### Reads in a cluster

Every node answers reads from what it has applied, so nothing uncommitted is ever read.

- On the leader, a vector read by id sees a write once the write has answered `200`. A search sees it once the index has applied it, which happens in the background on every node.
- A follower serves what it has applied, which can be behind the leader. Just after a collection is dropped and created again under the same name, a follower can serve the old one for a moment.
- After the leader changes, the new leader can miss an acknowledged write until it has applied it.

#### Batch update (upsert + delete)
- Method: POST
- Path: `/collection/{name}/update`
- Body (`application/json`):
```json
{
  "upserts": [
    { "id": 10, "vector": [0.1, 0.2, 0.3, 0.4] },
    { "id": 11, "vector": [0.2, 0.3, 0.4, 0.5] }
  ],
  "delete": [3, 5]
}
```

Description: The one write of vectors. Upserts insert or replace vectors by id, then deletes remove ids; the batch is one WAL record. Both lists are required, either may be empty: an upsert alone is `"delete": []`, a delete alone is `"upserts": []`. Validation: dimensionality, no duplicate ids in `upserts`, no duplicate ids in `delete`, no overlap between `upserts` and `delete`, and at least one list must be non-empty.

```bash
curl --location --request POST 'http://localhost:7222/collection/test_collection/update' \
  --header 'Content-Type: application/json' \
  --data-raw '{
    "upserts": [
      { "id": 10, "vector": [0.1, 0.2, 0.3, 0.4] },
      { "id": 11, "vector": [0.2, 0.3, 0.4, 0.5] }
    ],
    "delete": [3, 5]
  }'
```

Response:
- `200 OK`
- Empty body (no JSON)
- `400 Bad Request`: the batch fails validation, or it would take the collection past `max_size` (`collection capacity exceeded`)
- `404 Not Found`: no such collection
- `413 Payload Too Large`: the batch is over the limit, see [Batch limit](#batch-limit)

In a cluster, also the codes listed under [Batch limit](#batch-limit).

---

#### Start indexing
- Method: POST
- Path: `/collection/{name}/index/start`
- Body: none

Description: Starts indexing the collection on the schema it was created with. In a cluster the leader proposes it to the catalog and builds the index; every other node fetches the leader's set. In `Standalone` the node builds it, under a new index id, unless an index is attached or being built. A repeated call changes nothing, and after a failed build in `Standalone` it starts one again. In `Standalone` the start is not durable until the index is published: after a restart during the build, call it again. `GET /collections/{name}` shows the progress in `index.state`.

```bash
curl --location --request POST 'http://localhost:7222/collection/test_collection/index/start'
```

Response:
- `202 Accepted` (the build runs in the background), empty body
- `404 Not Found`: no such collection
- `405 Method Not Allowed`: in a cluster, this node is not the leader
- `503 Service Unavailable`: this node is stopping

---

#### Trigger a snapshot
- Method: POST
- Path: `/collection/{name}/index/snapshot/trigger`
- Body: none

Description: Asks this node for a snapshot of the index, whatever `storage.snapshot.changes` and `storage.snapshot.wal_ops` say, covering everything written before the call: with a backlog, it is taken once the backlog is applied. Only this node: every node snapshots on its own, so this can be called on a follower, and to snapshot the whole cluster call every node. The call does not wait: `wal.snapshotted_count` in `GET /collections/{name}` shows when the snapshot is done: it reaches `wal.write_count` as of the call. A request that fails is retried after the usual cooldown.

```bash
curl --location --request POST 'http://localhost:7222/collection/test_collection/index/snapshot/trigger'
```

Response:
- `202 Accepted`: the request is recorded; with nothing to write, no snapshot follows
- `404 Not Found`: no such collection
- `409 Conflict`: the collection has no index, or snapshots are off on this node or in the index's policy

---

#### Trigger compaction
- Method: POST
- Path: `/collection/{name}/index/compaction/trigger`
- Body: none

Description: Starts a fold pass on this node now, without waiting for a snapshot. The pass folds the ranges `storage.compaction.max_chain_depth` or `storage.compaction.max_tail_ratio` hold for and no others, so a chain under both thresholds stays as it is: lower them with `PATCH` first to fold more. The call does not wait for the pass.

```bash
curl --location --request POST 'http://localhost:7222/collection/test_collection/index/compaction/trigger'
```

Response:
- `202 Accepted`: a pass is running or will run
- `404 Not Found`: no such collection
- `409 Conflict`: the collection has no index, or compaction is off on this node or in the index's policy

---

#### Change index policy
- Method: PATCH
- Path: `/collection/{name}/index`
- Body (`application/json`): `storage` with `snapshot` and `compaction`, as in `index.storage` of the create request.

Description: Changes the snapshot and compaction policy of the collection's index, before indexing starts as well. Only the keys present under `storage` change; `max_chain_depth: null` turns the depth rule off. The merged policy is validated as a whole. The change takes effect at the next check: after the next applied WAL file under load, within 30 seconds when idle. It starts no fold pass of its own. In a cluster every other node takes it at its next catalog sync.

```bash
curl --location --request PATCH 'http://localhost:7222/collection/test_collection/index' \
  --header 'Content-Type: application/json' \
  --data-raw '{
      "storage": {
          "snapshot": {
              "enabled": false
          }
      }
  }'
```

Response:
- `200 OK`, empty body
- `400 Bad Request`: an unknown key, `range_size_bytes` among them, or a merged policy that is not valid
- `404 Not Found`: no such collection
- `405 Method Not Allowed`: in a cluster, this node is not the leader
- `409 Conflict`: the change lost a race with another one

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
curl --location --request POST 'http://localhost:7222/collection/test_collection/search?limit=10' \
  --header 'Content-Type: application/json' \
  --data-raw '{ "vector": [0.1, 0.2, 0.3, 0.4] }'
```

Response (`output=json`, default):
- `200 OK`, `application/json`
- JSON example:
```json
{
  "result": [
    { "id": 10, "score": 1.0 },
    { "id": 11, "score": 0.993808 }
  ]
}
```

```bash
curl --location --request POST 'http://localhost:7222/collection/test_collection/search?limit=10&ef_search=64&output=bin' \
  --header 'Content-Type: application/json' \
  --output results.bin \
  --data-raw '{ "vector": [0.1, 0.2, 0.3, 0.4] }'
```

Response (`output=bin`):
- `200 OK`, `application/octet-stream`
- Binary payload format: `u32` count (little-endian), then repeated pairs of `id: u64` + `score: f32` (little-endian).

The query is compared as the index stores its vectors. If the index normalizes (every `cosine`
index does, and any index created with `normalization: true`), the query is normalized first, so
only its direction counts and a `cosine` score is the cosine distance whatever the query's length.
An index that does not normalize takes the query as it is.

What a score is depends on the metric, and the results come best first:

| Metric | Score | Best |
|---|---|---|
| `euclidean` | L2 distance | lowest |
| `l2sq` | squared L2 distance | lowest |
| `cosine` | cosine distance, `1 - cos` | lowest |
| `inner-product` | dot product | highest |

A JSON score is printed as the `f32` it is (`0.1`), not widened to `f64`.

Refused queries:
- `400 Bad Request`: `limit` is above `search.max_search_limit` (default `100000`, see [config.md](config.md))
- `400 Bad Request`: the query's length is not the collection's `dim`
- `400 Bad Request`: the query is all zeros and the index normalizes; it has no direction
- `400 Bad Request`: the index is `i8` and a component of the query, normalized if the index
  normalizes, is outside `[-1, 1]`, the range it quantizes; the error names the component

Before an index is attached a search answers by `index.state`:
- `400 Bad Request`: `not_started`, indexing has not been started
- `405 Method Not Allowed`: `building`, the index is being built here or, in a cluster, not fetched yet

`500 Internal Server Error` is a failure of the index on a query it accepted.

---

#### Scores
- Method: POST
- Path: `/collection/{name}/scores`
- Query:
  - `output` (string, optional): `"json"` (default) or `"bin"`.
- Body (`application/json`):
```json
{
  "vector": [0.1, 0.2, 0.3, 0.4],
  "ids": [10, 11, 42]
}
```

Description: Scores the query vector against the vector each of `ids` holds in the collection's
in-memory index, as a search scores a match: the same metric, the same quantization and
normalization of the query, and the same number a search would answer for that id. The answer is
in the order of `ids`. An id the index does not hold, never written or deleted, is left out and
is no error; an id given twice is answered twice. An empty `ids` is an empty answer.

The scores see what a search sees: writes the index has applied. A write that has been
acknowledged but not yet applied is not visible to them yet.

```bash
curl --location --request POST 'http://localhost:7222/collection/test_collection/scores' \
  --header 'Content-Type: application/json' \
  --data-raw '{ "vector": [0.1, 0.2, 0.3, 0.4], "ids": [10, 11, 42] }'
```

Response (`output=json`, default):
- `200 OK`, `application/json`
- JSON example, id 42 not in the index:
```json
{
  "result": [
    { "id": 10, "score": 1.0 },
    { "id": 11, "score": 0.993808 }
  ]
}
```

```bash
curl --location --request POST 'http://localhost:7222/collection/test_collection/scores?output=bin' \
  --header 'Content-Type: application/json' \
  --output scores.bin \
  --data-raw '{ "vector": [0.1, 0.2, 0.3, 0.4], "ids": [10, 11, 42] }'
```

Response (`output=bin`):
- `200 OK`, `application/octet-stream`
- Binary payload format: as a search's, `u32` count (little-endian), then repeated pairs of
  `id: u64` + `score: f32` (little-endian).

`ids` may name at most `search.max_scores_ids` ids (default `100000`, see [config.md](config.md)); more is
`400 Bad Request`.

The query is refused as a search refuses it, with the same `400`s, and before an index is
attached the answer is a search's: `400` for `not_started`, `405` for `building`. A collection
that does not exist is `404 Not Found`. `500 Internal Server Error` is a failure of the index on
a query it accepted.

---

#### List collections
- Method: GET
- Path: `/collections`
- Body: none

Description: Returns the names of all collections, as Qdrant lists them. A collection's metadata is `GET /collections/{name}`.

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
      "name": "test_collection"
    }
  ]
}
```

---

#### Get collection info
- Method: GET
- Path: `/collections/{name}`
- Body: none

Description: Returns metadata and status for one collection, including applier and replication progress. `status` is `yellow` while the index is being built and `green` otherwise. `size` is the number of ids the collection holds, `applied_size` the number the in-memory index holds. `wal` counts writes, one WAL record each, from the collection's creation: `write_count` is how many are durably in the WAL, `applied_count` how many of them the in-memory index has applied, so are visible to search, and `snapshotted_count` how many the index on disk covers. All three are always there; while no index is attached `applied_count` and `snapshotted_count` are 0, so only with an index is `write_count - applied_count` the applier's backlog and `write_count - snapshotted_count` what a restart replays. `snapshot` holds the snapshot trigger's counters as of the request — `changes`, the internal ids changed, and `wal_ops`, the WAL ops applied since the last snapshot — compared against `index.storage.snapshot.changes` and `index.storage.snapshot.wal_ops`; it is absent while no index is attached. `index` is always there: the schema and the policy the collection was given, and `index.state`, which is `not_started` before indexing starts, `building` until an index is attached (in a cluster, while the record names an index this node does not hold yet) and `ready` once one is. After a failed build in `Standalone` it is `not_started` again; the failure is in the log and in `casper_index_builds_total{outcome="failure"}`. `index.storage` is what this node runs, which in a cluster can lag the catalog by one sync pass. `index.storage.snapshot_active` and `index.storage.compaction_active` say whether this node runs each mechanism for the index: the node's flag and the policy's together.

```bash
curl --location --request GET 'http://localhost:7222/collections/test_collection'
```

Response:
- `200 OK`, `application/json`
- JSON example:
```json
{
    "status": "green",
    "id": "a9a30dfc-70d4-4dd1-93ad-10934c3cadd0",
    "name": "test_collection",
    "dimension": 4,
    "max_size": 10000000,
    "size": 461824,
    "applied_size": 461824,
    "has_index": true,
    "replicated": true,
    "wal": {
        "write_count": 1804,
        "applied_count": 1804,
        "snapshotted_count": 1804
    },
    "index": {
        "state": "ready",
        "hnsw": {
            "metric": "inner-product",
            "quantization": "f32",
            "m": 16,
            "m0": 32,
            "ef_construction": 200
        },
        "normalization": true,
        "storage": {
            "range_size_bytes": 134217728,
            "snapshot": {
                "enabled": true,
                "changes": 1000000,
                "wal_ops": 2000000
            },
            "compaction": {
                "enabled": true,
                "max_chain_depth": 8,
                "max_tail_ratio": 0.25
            },
            "snapshot_active": true,
            "compaction_active": true
        }
    },
    "snapshot": {
        "changes": 0,
        "wal_ops": 0
    }
}
```

---

#### Get vector by id
- Method: GET
- Path: `/collection/{name}/vector/{id}`
- Body: none

Description: Returns the vector stored for `id` in the collection's in-memory index, exactly as the
index holds it, with no conversion:

- an `f32` index returns its components as numbers. If the index normalizes (every `cosine` index
  does, and any index created with `normalization: true`), that is the normalized vector, not the
  one written;
- an `i8` index returns its components as integers in `[-100, 100]`, the quantized values
  (`round(x · 100)`). They are not dequantized.

The index's `quantization` and `metric` are in `GET /collections/{name}`.

The lookup sees what a search sees: writes the index has applied. A write that has been
acknowledged but not yet applied is not visible to it yet. A new id answers `404` and an upsert
the previous vector until the index catches up.

```bash
curl --location --request GET 'http://localhost:7222/collection/test_collection/vector/10'
```

Response (found):
- `200 OK`, `application/json`
- JSON example, `f32` index:
```json
{
  "id": 42,
  "vector": [0.1, 0.2, 0.3, 0.4]
}
```
- JSON example, `i8` index:
```json
{
  "id": 42,
  "vector": [10, 20, 30, 40]
}
```

An `f32` component is printed as the `f32` it is (`0.1`), not widened to `f64`.

Response (no index on the collection):
- `400 Bad Request`, the same error a search on it gets. This is the answering node's state: in a
  cluster, a follower answers `400` from the moment the leader has an index until the follower has
  fetched it (`FetchIndex`), as a search there does. Retry on another node, or later.

Response (index being built):
- `405 Method Not Allowed`

Response (the index could not be read):
- `500 Internal Server Error`, for a failure of the index other than a missing id

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

Description: Returns node cluster role and progress. Payload shape depends on `role`. In a cluster, `raft_state` is one of `leader`, `follower`, `candidate`, `learner` or `shutdown`; `leader_id` is absent while no leader is known; `members` lists every node with the addresses it published, `raft_addr` (what `--bootstrap` takes) and `replication_addr`; `last_log_index` and `last_applied_index` are this node's Raft progress, absent while its log is empty.

```bash
curl --location --request GET 'http://localhost:7222/cluster'
```

Response:
- `200 OK`, `application/json`
- JSON example (`role=standalone`):
```json
{
    "role": "standalone"
}
```
- JSON example (a cluster):
```json
{
    "role": "cluster",
    "node_id": "14ccfafb-af27-449f-b93c-caec45ddcb46",
    "raft_state": "leader",
    "current_term": 1,
    "leader_id": "14ccfafb-af27-449f-b93c-caec45ddcb46",
    "voters": [
        "14ccfafb-af27-449f-b93c-caec45ddcb46",
        "3ab444f3-36b2-40ad-b841-8c1ef73d9ec9",
        "9f5654e6-a905-4ad4-ad58-930947c0c5f9"
    ],
    "learners": [],
    "members": [
        {
            "node_id": "14ccfafb-af27-449f-b93c-caec45ddcb46",
            "raft_addr": "127.0.0.1:7224",
            "replication_addr": "127.0.0.1:7223",
            "voter": true
        },
        {
            "node_id": "3ab444f3-36b2-40ad-b841-8c1ef73d9ec9",
            "raft_addr": "127.0.0.1:7244",
            "replication_addr": "127.0.0.1:7243",
            "voter": true
        },
        {
            "node_id": "9f5654e6-a905-4ad4-ad58-930947c0c5f9",
            "raft_addr": "127.0.0.1:7234",
            "replication_addr": "127.0.0.1:7233",
            "voter": true
        }
    ],
    "last_log_index": 1813,
    "last_applied_index": 1813
}
```

---

#### Remove a node
- Method: DELETE
- Path: `/cluster/peer/{node_id}`
- Body: none

Description: Removes a node from the cluster's membership, a voter or a learner, through the Raft log; every other node converges on the new membership. It is the only way a node leaves: nothing evicts one automatically. Stop the node first: one still running and joining asks to be added again. The leader can remove itself; it steps down.

```bash
curl --location --request DELETE 'http://localhost:7222/cluster/peer/9f5654e6-a905-4ad4-ad58-930947c0c5f9'
```

Response:
- `200 OK`, `{ "removed": "<node_id>" }`
- `400 Bad Request`: the node runs standalone, or the id is not a uuid
- `404 Not Found`: the id is not a member
- `405 Method Not Allowed`: this node is not the leader, with `leader_addr`
- `409 Conflict`: it is the only voter
- `503 Service Unavailable`: the change failed
- `504 Gateway Timeout`: not committed within 30 s; the change goes on, and `GET /cluster` shows when it is done

#### Transfer limit
- Method: PUT
- Path: `/cluster/transfer-limit`
- Body (`application/json`): `{ "mb_per_sec": 200 }`, and `0` turns the limit off

Description: Sets what this node sends by `FetchWal` and `FetchIndex` together, usually on the leader, for a fetch that has to outrun the writes. Held in memory: a restart returns to `cluster.replication.max_transfer_mb_per_sec`, and a new sender has its own.

```bash
curl --location --request PUT 'http://localhost:7222/cluster/transfer-limit' \
  --header 'Content-Type: application/json' \
  --data-raw '{
      "mb_per_sec": 200
  }'
```

Response:
- `200 OK`, empty body

---

### Configuration

#### Get runtime configuration
- Method: GET
- Path: `/config`
- Body: none

Description: Returns the configuration the node started with, as JSON. API keys and the paths of TLS material are never included. Config is immutable after startup; restart process to change values. See [config.md](config.md) for full reference.

```bash
curl --location --request GET 'http://localhost:7222/config'
```

Response:
- `200 OK`, `application/json`
- JSON example:
```json
{
    "service": {
        "host": "127.0.0.1",
        "http_port": 7222,
        "uri": null,
        "shutdown_timeout_sec": 25
    },
    "cluster": {
        "role": "cluster",
        "bootstrap": null,
        "write_ack_timeout_ms": 5000,
        "max_inflight_entries": 16,
        "max_apply_lag_mb": 1024,
        "write_queue_mb": 128,
        "raft": {
            "port": 7224,
            "enable_tls": false,
            "uri": "127.0.0.1:7224"
        },
        "replication": {
            "port": 7223,
            "uri": null,
            "max_transfer_mb_per_sec": 50
        }
    },
    "storage": {
        "storage_dir": "./storage",
        "min_free_disk_mb": 8192,
        "wal": {
            "max_batch_size_mb": 1,
            "log_tail_mb": 1024,
            "snapshot_every_mb": 256,
            "snapshot_every_entries": 5000
        },
        "index": {
            "snapshot": {
                "enabled": true
            },
            "compaction": {
                "enabled": true
            }
        }
    },
    "search": {
        "max_search_limit": 100000,
        "max_scores_ids": 100000
    },
    "tls": {
        "enable": false,
        "verify_https_client_certificate": false,
        "tls_cert_ttl": null
    },
    "auth": {
        "jwt_rbac": false
    },
    "metrics": {
        "prefix": "casper_"
    }
}
```

---

### Health
- Method: GET
- Path: `/health`
- Body: none

Description: Liveness probe endpoint. Needs no credential.

```bash
curl --location --request GET 'http://localhost:7222/health'
```

Response:
- `200 OK`
- Empty body (no JSON)

---

### Readiness
- Method: GET
- Path: `/readyz`
- Body: none

Description: What a load balancer polls. Needs no credential, like `/health`. In cluster mode a node starts serving REST while it joins, and holds nothing until it is a voter.

```bash
curl --location --request GET 'http://localhost:7222/readyz'
```

Before restarting the next node of a rolling restart:

```bash
curl --location --request GET 'http://localhost:7222/readyz?quorum=true'
```

Response:
- `200 OK` when the node should get reads
- `503 Service Unavailable` while it is not a voter, or once it has known no leader for 10 s: partitioned, a leader cut off from its quorum or a follower cut off with one, or removed from the cluster, which a removed node never learns. Collection routes answer `503` with `Retry-After` while it is not a voter.
- `503 Service Unavailable` with `{ "reason": "stopping" }` once the node has begun to stop (SIGTERM or SIGINT)

A standalone node is always ready until it stops.

`/readyz` answers for reads and not for the quorum, so a voter fetching for hours reports ready. A rolling restart waits on `/readyz?quorum=true`, which also answers `503` while this node is behind the purged log, while it takes no new log entries (low disk, or far behind on apply), and, on a follower, unless in the last 10 s it has acknowledged a leader's append that left it holding everything the leader had committed.

---

### Metrics
- Method: GET
- Path: `/metrics`
- Body: none

Description: Prometheus metrics, in the text exposition format, on the REST port. Every name starts with `service.metrics_prefix` (`casper_` by default). Requires a read credential when authentication is on: the labels carry collection names.

```bash
curl --location --request GET 'http://localhost:7222/metrics'
```

Response:
- `200 OK`, `text/plain`

---

### Writes in a cluster

Only the leader accepts `POST` and `DELETE /collection/{name}`, the vector writes, `POST /collection/{name}/index/start`, `PATCH /collection/{name}/index`, and `DELETE /cluster/peer/{node_id}`. Any other node answers `405 Method Not Allowed` with a JSON body naming the leader's REST address, published by that node as `--http-uri` / `service.uri`:

```json
{
    "error": "Method not allowed: mutating operations require the Raft leader",
    "leader_addr": "10.0.0.7:7222"
}
```

`leader_addr` is absent while no leader is known: wait and retry. `DELETE /cluster/peer/{node_id}` checks the id against the node's own membership first, so a follower can answer `400`, `404` or `409` instead. Stop a node before removing it: one still joining asks to be added again. Other `405` responses have a plain text body.

While a cluster node is joining, every `/collection/...` and `/collections...` route answers `503` with `Retry-After`.

### Errors

An error is a plain text body naming its kind and the reason, e.g. `Bad request: ...` or `Resource not found: collection not found`. The exceptions are the `405` from a follower above, the `404` of `GET /collection/{name}/vector/{id}` and the answers of `DELETE /cluster/peer/{node_id}`, which are JSON. A `500` says only `Internal server error`; the cause is in the node's log. A `429`, and a `503` from a collection route, carry `Retry-After`.

### Authentication

With no API key configured, nothing is authenticated. Once `service.api_key`, `service.alt_api_key` or `service.read_only_api_key` is set (see [config.md](config.md)), every route except `/health` and `/readyz` needs a credential, in the `api-key` header or as `Authorization: Bearer <value>`:

```bash
curl --header 'api-key: <YOUR_API_KEY>' 'http://localhost:7222/collections'
```

- `api_key` and `alt_api_key` grant read and write on every route.
- `read_only_api_key` grants the reads: `GET /collections`, `GET /collections/{name}`, `GET /collection/{name}/vector/{id}`, `POST /collection/{name}/search`, `POST /collection/{name}/scores`, `GET /cluster`, `GET /config` and `GET /metrics`. Any other route answers `403`.
- With `service.jwt_rbac` on, the same header also takes a JWT signed (HS256) with `api_key` or `alt_api_key`. It carries `exp` and `access`: `"r"` or `"rw"` for everything, or a list `[{"collection": "test_collection", "access": "rw"}]` for those collections only. A scoped token gets `404` for a collection outside its scope, as for one that does not exist, `403` on the global routes (`/cluster`, `/config`, `/metrics`), and `GET /collections` lists only the collections it may see.

A missing, unknown or expired credential is `401`.
