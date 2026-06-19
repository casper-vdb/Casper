## Casper Configuration

Casper reads its configuration from command-line flags at startup. The full set is parsed by `clap` in `src/config.rs`; this document mirrors that source.

The running process exposes its configuration as JSON at:

```bash
curl http://localhost:7222/config
```

Configuration is immutable after startup — restart the process to change a value.

---

### Examples

Each example below lists every flag that applies to the role, including those left at their default. This is meant as a complete reference — in practice you only need to pass the flags you want to override.

#### Standalone

Single-node deployment, no replication:

```bash
./casper \
  --host 127.0.0.1 \
  --http-port 7222 \
  --storage-dir ./storage \
  --cluster-role standalone \
  --snapshot-enabled true \
  --snapshot-every-writes 500000 \
  --snapshot-every-seconds 1800
```

#### Master

Accepts writes on `--http-port`, broadcasts to replicas over `--grpc-port`. With `--sync-replicas N` the master waits for `N` replica fsync acks before returning `200` from the endpoints that perform `upsert` and `delete` operations:

```bash
./casper \
  --host 127.0.0.1 \
  --http-port 7222 \
  --storage-dir ./storage-master \
  --cluster-role master \
  --grpc-port 7223 \
  --sync-replicas 1 \
  --write-ack-timeout-ms 5000 \
  --snapshot-enabled true \
  --snapshot-every-writes 500000 \
  --snapshot-every-seconds 1800
```

#### Replica

Connects to a master via `--master-addr` and replays the WAL + catalog stream:

```bash
./casper \
  --host 127.0.0.1 \
  --http-port 7322 \
  --storage-dir ./storage-replica \
  --cluster-role replica \
  --master-addr 127.0.0.1:7223 \
  --snapshot-enabled true \
  --snapshot-every-writes 500000 \
  --snapshot-every-seconds 1800
```

---

### Network

| Flag | Default | Description |
|---|---|---|
| `--host` | `127.0.0.1` | Address the HTTP server binds to. |
| `--http-port` | `7222` | HTTP API port. |

---

### Storage

| Flag | Default | Description |
|---|---|---|
| `--storage-dir` | `./storage` | Root directory for all on-disk state — collections, WAL, catalog. Created at startup if missing. |

Layout under `--storage-dir`:

```
<storage-dir>/
  collection/   # vector data + indices, one subdir per collection
  cluster/      # cluster catalog (master and replica only)
```

---

### Cluster

| Flag | Default | Description |
|---|---|---|
| `--cluster-role` | `standalone` | One of `standalone`, `master`, `replica`. |
| `--master-addr` | — | Master `host:port` the replica connects to. Required when `--cluster-role=replica`. |
| `--grpc-port` | `7223` | gRPC port the master listens on for replica connections. Replicas dial this via `--master-addr`. |

Roles:
- **standalone** — single-node deployment, no replication.
- **master** — accepts writes and broadcasts them to connected replicas over gRPC.
- **replica** — read-only follower; connects to a master, replays the WAL and catalog stream.

---

### Replication

| Flag | Default | Description |
|---|---|---|
| `--sync-replicas` | `0` | Number of replicas (master excluded) that must fsync each write before the endpoints that perform `upsert` and `delete` operations return success. `0` = async (broadcast and don't wait). `N >= 1` = synchronous. Master only. |
| `--write-ack-timeout-ms` | `5000` | Deadline (ms) the master waits for replica acks when `--sync-replicas >= 1`. Ignored when `0`. |

Behaviour with `--sync-replicas N >= 1`:
- fewer than `N` replicas connected → `504 InsufficientReplicas` immediately (pre-flight check, no fsync attempted)
- at least `N` acked within `--write-ack-timeout-ms` → `200`
- fewer than `N` acked within the deadline → `504 ReplicationTimeout`
- once `N` is reached, slower replicas are not waited on — they catch up via the standard reconnect/catchup path

---

### Snapshots

The background applier periodically saves the in-memory HNSW to disk so restart replay length is bounded.

| Flag | Default  | Description |
|---|----------|---|
| `--snapshot-enabled` | `true`   | Enables periodic snapshotting. Pass `--snapshot-enabled=false` to disable (e.g. for benchmarks where `save_index` I/O is unwanted). |
| `--snapshot-every-writes` | `500000` | Snapshot after this many newly applied WAL seqs. |
| `--snapshot-every-seconds` | `1800`   | Snapshot this many seconds after the last one. `0` disables the time trigger (write-count-only). Whichever trigger fires first wins. |

---

### Environment

| Variable | Required | Description |
|---|---|---|
| `API_TOKEN` | yes | JWT used to authenticate HTTP requests. A free development token is in `README.md`. |
| `RUST_LOG` | no | Standard `env_logger` filter. `RUST_LOG=info` is the recommended baseline. |

