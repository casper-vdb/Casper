## Casper Configuration

Casper is configured by YAML files, environment variables and command-line flags. Every setting has a key in the file; most also have a flag. The tables below list every key Casper reads, with its default.

The running process exposes its configuration as JSON at:

```bash
curl http://localhost:7222/config
```

Configuration is immutable after startup — restart the process to change a value. The one exception is `PUT /cluster/transfer-limit`, which moves `cluster.replication.max_transfer_mb_per_sec` until the next restart (see [api.md](api.md)).

---

### Layers

Each layer overrides the ones before it key by key, so a file only needs the keys it changes:

1. The defaults compiled into the binary (`config/config.yaml` in the repository).
2. `./config/config.yaml`, if it exists.
3. `./config/{RUN_MODE}.yaml`, if it exists. `RUN_MODE` defaults to `development`; the Docker image sets `production`.
4. The file given with `--config-path <PATH>`. Unlike the two above, it must exist, or the node refuses to start.
5. Environment variables `CASPER__<SECTION>__<KEY>`, with a double underscore between levels: `CASPER__SERVICE__HTTP_PORT=7333` is `service.http_port`.
6. Command-line flags.

A layer may be spelled `.yaml` or `.yml`, but not both: two files for one layer is a startup error. The startup log names the layers that contributed (`config sources=embedded,config/config.yaml,...`).

A key Casper does not know is refused at startup, every such key at once, each with the file it came from and a sentence on what Casper does instead. This covers misspellings and the Qdrant keys Casper does not implement (`service.grpc_port`, `storage.hnsw_index.*`, `storage.optimizers`, `cluster.consensus.*` and others). A node with an invalid configuration exits with code `2`.

---

### Default configuration

The defaults compiled into the binary. A file of your own needs only the keys it changes. Keys with no default — `service.uri`, `cluster.bootstrap`, `cluster.p2p.uri`, `cluster.replication.uri`, the API keys and the `tls` section — are not in it; they are described in the tables below.

```yaml
log_level: INFO

storage:
  storage_path: ./storage
  min_free_disk_mb: 8192
  wal:
    max_batch_size_mb: 1
    log_tail_mb: 1024
    snapshot_every_mb: 256
    snapshot_every_entries: 5000
  index:
    snapshot:
      enabled: true
    compaction:
      enabled: true

search:
  max_search_limit: 100000
  max_scores_ids: 100000

service:
  host: 127.0.0.1
  http_port: 7222
  metrics_prefix: casper_
  enable_tls: false
  verify_https_client_certificate: false
  shutdown_timeout_sec: 25
  jwt_rbac: false

cluster:
  enabled: false
  p2p:
    port: 7224
    enable_tls: false
  replication:
    port: 7223
    max_transfer_mb_per_sec: 50
  write_ack_timeout_ms: 5000
  max_inflight_entries: 16
  max_apply_lag_mb: 1024
  write_queue_mb: 128
```

---

### Examples

#### Standalone

Single node, no replication — the default mode:

```bash
./casper \
  --host 127.0.0.1 \
  --http-port 7222 \
  --storage-dir ./storage
```

#### Cluster

Every node is a full replica, and any node may lead. Writes go to the leader, through the Raft log, and are durable on a majority. The first node starts without `--bootstrap` and creates the cluster; every other node names the Raft address of a node already in it:

```bash
./casper \
  --cluster-role cluster \
  --host 10.0.0.2 \
  --http-port 7222 \
  --raft-port 7224 \
  --replication-port 7223 \
  --storage-dir ./storage \
  --bootstrap 10.0.0.1:7224
```

The same node as a file, passed with `--config-path`:

```yaml
storage:
  storage_path: ./storage
service:
  host: 10.0.0.2
  http_port: 7222
cluster:
  enabled: true
  bootstrap: 10.0.0.1:7224
  p2p:
    port: 7224
  replication:
    port: 7223
```

`--bootstrap` is read only on a node's first start: a node that already has Raft state resumes its membership. `GET /cluster` lists every member with the addresses it published, which is where to find a `--bootstrap` address for a new node.

#### Docker

The image runs with `WORKDIR /`, `RUN_MODE=production` and `RUST_LOG=info`, keeps its data in `/storage`, binds `0.0.0.0` (from `/config/config.yaml` in the image) and exposes `7222`, `7223` and `7224`. Mount your own settings at `/config/production.yaml`; a partial file there does not undo the wildcard bind.

---

### Service

| Key | Flag | Default | Description |
|---|---|---|---|
| `service.host` | `--host` | `127.0.0.1` | Address the HTTP server binds to. In a cluster it must be an IP address (`0.0.0.0` binds every interface), because the peer transports bind on it too; a host name belongs in the `uri` keys below. |
| `service.http_port` | `--http-port` | `7222` | HTTP API port. `/metrics` is served on it too. |
| `service.uri` | `--http-uri` | host of `cluster.p2p.uri` with `service.http_port` | The address clients reach this node's REST API at. Published in the cluster's membership: a follower names the leader's when it refuses a write (`leader_addr`). Set it when a port is remapped between clients and the node. |
| `service.metrics_prefix` | `--metrics-prefix` | `casper_` | Prepended to every metric name at `/metrics`. Must match `[a-zA-Z_:][a-zA-Z0-9_:]*`; `""` means bare names. |
| `service.shutdown_timeout_sec` | `--shutdown-timeout-sec` | `25` | How long a stop on SIGTERM or SIGINT may take, in seconds, from 1 to 86400 (a day). At the deadline the node logs the step it is in and exits `1`; a second signal exits at once. In a cluster it must be at least `cluster.write_ack_timeout_ms` plus 7 s, or the node refuses to start. Give the orchestrator a grace period at least 5 s longer. |
| `log_level` | none | `INFO` | Logger filter. `RUST_LOG` overrides it when set. |

---

### Storage

| Key | Flag | Default | Description |
|---|---|---|---|
| `storage.storage_path` | `--storage-dir` | `./storage` | Root directory for all on-disk state: collections, WAL, index sets, the Raft log and the catalog. Created at startup if missing. |
| `storage.min_free_disk_mb` | none | `8192` | Free disk a write leaves, or it gets `507`. Below half of this a node stops applying and appending until there is room. In a cluster a node refuses to start on a filesystem smaller than this. |

A collection belongs to the mode that created it. A node in `standalone` does not load collections created in a cluster, and a cluster node does not load collections created in `standalone`: they stay on disk, the API answers as for an unknown collection, and the node logs each one at startup. They return when the node runs in their mode again. There is no conversion between modes: to move a standalone collection into a cluster, insert its data again through the API. To remove one, delete its directory by hand.

---

### Batch size

| Key | Flag | Default | Description |
|---|---|---|---|
| `storage.wal.max_batch_size_mb` | `--max-batch-size-mb` | `1` | The largest batch a write may carry, measured as the WAL record it becomes, from 1 to 8. A node refuses to start outside that range. A larger batch gets `413`, and the client splits it. |

In a cluster the limit in force is the lower of this value and 8 MiB divided by the followers, learners included, and never below 1 MiB. It moves with membership. The body limit of `POST /collection/{name}/update` is eight times this value.

---

### Cluster

| Key | Flag | Default | Description |
|---|---|---|---|
| `cluster.enabled` | `--cluster-role` | `false` / `standalone` | `--cluster-role cluster` (or `cluster.enabled: true`) makes the node a member of a Raft cluster. |
| `cluster.bootstrap` | `--bootstrap` | — | The Raft address of a node already in the cluster, to join through. Omitted on the node that creates the cluster. Must not be this node's own address. |
| `cluster.p2p.port` | `--raft-port` | `7224` | Consensus transport: the log, votes and WAL snapshots. |
| `cluster.p2p.uri` | `--raft-uri` | `<service.host>:<cluster.p2p.port>` | The address other nodes dial to reach this node's Raft transport. Required when `service.host` is a wildcard (`0.0.0.0`, `::`). |
| `cluster.replication.port` | `--replication-port` | `7223` | Data transport: `FetchIndex` and `FetchWal`, which copy an index set and a WAL behind the purged log between nodes. |
| `cluster.replication.uri` | `--replication-uri` | `<service.host>:<cluster.replication.port>` | The address other nodes dial to reach this node's data transport. Required when `service.host` is a wildcard. Nodes need not use the same ports as each other. |

The HTTP, Raft and replication ports must all differ, and the three advertised addresses must name three different listeners; a node refuses to start otherwise.

A member leaves the cluster only through `DELETE /cluster/peer/{node_id}` (see [api.md](api.md)). Nothing evicts a node automatically.

---

### Writes in a cluster

| Key | Flag | Default | Description |
|---|---|---|---|
| `cluster.write_ack_timeout_ms` | `--write-ack-timeout-ms` | `5000` | How long a request waits for the log, at least 1. After it the client gets `504` and the outcome is unknown: the entry may still commit. A retry is safe, a write being an upsert by id. |

A write is acknowledged once it is applied on the leader and committed on a majority. A cluster without a majority takes no writes. There is no `--sync-replicas` and no `storage.collection.write_consistency_factor`; a config that sets the key is refused at startup.

### The queue in front of the log

Config file only.

| Key | Default | Description |
|---|---|---|
| `cluster.max_inflight_entries` | `16` | Entries a leader has on their way through the log at once, at least 1. |
| `cluster.write_queue_mb` | `128` | Payload queued behind them, half of it at most from one collection. A batch that does not fit, or whose estimated wait is above half of `cluster.write_ack_timeout_ms`, gets `429` with `Retry-After`. At least twice `storage.wal.max_batch_size_mb`. |
| `cluster.max_apply_lag_mb` | `1024` | Committed and unapplied payload past which a node does not stand for election. At twice this it stops taking writes from the log and falls behind. At least 1. |
| `storage.wal.log_tail_mb` | `1024` | Payload a node keeps in its log behind a WAL snapshot. A node further behind fetches the WAL from a peer. |
| `storage.wal.snapshot_every_mb`, `storage.wal.snapshot_every_entries` | `256`, `5000` | Applied payload and entries after which a node takes a WAL snapshot, whichever comes first. Each at least 1. |
| `cluster.replication.max_transfer_mb_per_sec` | `50` | What a node sends by `FetchWal` and `FetchIndex` together, in MiB/s. `0` turns the limit off. `PUT /cluster/transfer-limit` moves it until a restart. |

---

### Search limits

Config file only.

| Key | Default | Description |
|---|---|---|
| `search.max_search_limit` | `100000` | The largest `limit` of `POST /collection/{name}/search`, at least 1. A larger one gets `400`. |
| `search.max_scores_ids` | `100000` | The most ids one `POST /collection/{name}/scores` may name, at least 1. More gets `400`. |

Both are checked before the collection is looked up. A key no layer sets takes `100000`, even when the `search` section is missing from every file. A node refuses to start with either at `0`.

---

### Snapshots and compaction

The background applier periodically saves the in-memory HNSW to disk so that a restart replays a bounded part of the WAL, and fold passes rewrite the payload chains snapshots leave. Every node snapshots and folds on its own.

When either happens is each index's own policy, set under `index.storage` in `POST /collection/{name}` and changed with `PATCH /collection/{name}/index`: see [api.md](api.md). The node only says whether the mechanism may run at all; it runs when this switch and the index's `enabled` are both on.

| Key | Flag | Default | Description |
|---|---|---|---|
| `storage.index.snapshot.enabled` | `--snapshot-enabled` | `true` | Allows snapshots on this node. `false` turns them off for every index (e.g. for benchmarks where the I/O is unwanted). While off, the WAL is not trimmed. |
| `storage.index.compaction.enabled` | none | `true` | Allows fold passes on this node. `false` turns them off for every index. |

`changes`, `wal_ops`, `range_size_bytes`, `max_chain_depth` and `max_tail_ratio` belong to the index, not to the node: a config file that sets them under `storage.index` is refused at startup with a message saying where they went, as is the old `storage.index_snapshot` section.

---

### TLS

| Key | Flag | Default | Description |
|---|---|---|---|
| `service.enable_tls` | `--enable-tls` | `false` | HTTPS on the REST API. Requires `tls.cert` and `tls.key`. |
| `service.verify_https_client_certificate` | `--verify-https-client-certificate` | `false` | Also require REST callers to present a certificate signed by `tls.ca_cert`. Requires `--enable-tls` and `tls.ca_cert`. |
| `cluster.p2p.enable_tls` | `--p2p-enable-tls` | `false` | Mutual TLS on both peer transports, Raft and replication, in both directions: a peer without a certificate signed by `tls.ca_cert` cannot connect. Cluster mode only. Requires `tls.cert`, `tls.key` and `tls.ca_cert`. |
| `tls.cert` | `--tls-cert` | — | PEM certificate chain this node presents, to peers and (with `--enable-tls`) to REST clients. Its SAN must contain the host of both `cluster.p2p.uri` and `cluster.replication.uri`, and with `--enable-tls` the name REST clients use. |
| `tls.key` | `--tls-key` | — | PEM private key matching `tls.cert`. |
| `tls.ca_cert` | `--tls-ca-cert` | — | PEM certificate authority that peer certificates, and REST client certificates when required, are verified against. The system root store is never consulted, so this should be an internal CA. |
| `tls.cert_ttl` | `--tls-cert-ttl` | `3600` | Seconds between re-reads of `tls.cert` and `tls.key`, so a renewed REST certificate is picked up without a restart. `0` turns reloading off. REST only: rotating the peer certificates is a rolling restart. A value other than `0` without `--enable-tls` is refused. |

The two switches are independent: either contour can be encrypted on its own. Every file is read at startup, and a missing or unparsable one stops the node. Certificate material given without either switch is refused rather than ignored. The paths are never shown by `GET /config`.

---

### Authentication

With no key configured the REST API authenticates nobody. Once any key is set, every route except `/health` and `/readyz` requires a credential, sent in the `api-key` header or as `Authorization: Bearer <value>`. See [api.md](api.md) for what each level allows.

| Key | Flag / environment | Default | Description |
|---|---|---|---|
| `service.api_key` | `--api-key` / `CASPER_API_KEY` | — | Grants read and write on every route. With `--jwt-rbac` it is also the HS256 secret tokens are signed with. |
| `service.alt_api_key` | `--alt-api-key` / `CASPER_ALT_API_KEY` | — | A second key with the same rights, and a second signing key, so a rotation has no window in which neither works. |
| `service.read_only_api_key` | `--read-only-api-key` / `CASPER_READ_ONLY_API_KEY` | — | Grants read only: `403` on any route that writes. Must differ from the other two. |
| `service.jwt_rbac` | `--jwt-rbac` | `false` | Also accept JWTs in the same header, signed with `api_key` or `alt_api_key`. Requires `api_key`. |

A key must be at least 8 bytes, and with `--jwt-rbac` the two signing keys at least 32; an empty key is refused rather than treated as unset. Prefer the environment variables to the flags: a flag is visible to every process on the host through `ps`. The keys are never logged and never shown by `GET /config`.

A JWT carries `exp` (required, 30 s of clock-skew leeway) and `access`: `"r"` or `"rw"` for every collection and the global routes, or a list such as `[{"collection": "test_collection", "access": "rw"}]` for those collections only. A scoped token gets `404` for a collection outside its scope and `403` on the global routes.

The node warns at startup when a key is configured while `--enable-tls` is off (the key travels in cleartext), and, in a cluster, while `--p2p-enable-tls` is off (the peer ports authenticate nobody).

---

### Environment

| Variable | Required | Description |
|---|---|---|
| `LICENSE_TOKEN` | yes | JWT licence token, checked once at startup; it does not authenticate HTTP requests. A free token is in `README.md`. |
| `RUST_LOG` | no | Standard `env_logger` filter; overrides `log_level`. `RUST_LOG=info` is the recommended baseline. |
| `RUN_MODE` | no | Selects the `./config/{RUN_MODE}.yaml` layer. Default `development`. |
| `CASPER__<SECTION>__<KEY>` | no | Any configuration key, e.g. `CASPER__STORAGE__MIN_FREE_DISK_MB=16384`. |
| `CASPER_API_KEY`, `CASPER_ALT_API_KEY`, `CASPER_READ_ONLY_API_KEY` | no | The three API keys, as `--api-key`, `--alt-api-key` and `--read-only-api-key`. |
