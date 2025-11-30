#!/usr/bin/env python3
import argparse
import json
import os
import struct
import sys
from typing import List, Tuple

import numpy as np
import requests

try:
    import faiss  # pip install faiss-cpu
except Exception as e:
    print("Error: package 'faiss' is required (e.g., pip install faiss-cpu).", file=sys.stderr)
    raise


def read_casper_bin(path: str) -> Tuple[np.ndarray, np.ndarray]:
    """
    Read a Casper-format binary file.
    Returns:
      - ids: np.ndarray shape (N,), dtype=np.int64
      - vectors: np.ndarray shape (N, D), dtype=np.float32
    Format:
      BE u32 dimension, BE u32 count,
      then for each document: BE u32 id + D * BE f32
    """
    with open(path, "rb") as f:
        header = f.read(8)
        if len(header) != 8:
            raise ValueError("File too short: missing header (dimension, count)")
        dimension, count = struct.unpack(">II", header)

        ids = np.empty(count, dtype=np.int64)
        vectors = np.empty((count, dimension), dtype=np.float32)

        for i in range(count):
            id_bytes = f.read(4)
            if len(id_bytes) != 4:
                raise ValueError(f"Truncated file: cannot read id for i={i}")
            doc_id = struct.unpack(">I", id_bytes)[0]
            vec_bytes = f.read(4 * dimension)
            if len(vec_bytes) != 4 * dimension:
                raise ValueError(f"Truncated file: cannot read vector for i={i}")
            vec = np.frombuffer(vec_bytes, dtype=">f4").astype(np.float32)  # BE f32 -> native float32
            ids[i] = int(doc_id)
            vectors[i, :] = vec
    return ids, vectors


def build_faiss_index(vectors: np.ndarray, metric: str):
    d = vectors.shape[1]
    if metric == "ip":
        index = faiss.IndexFlatIP(d)
    elif metric == "l2":
        index = faiss.IndexFlatL2(d)
    else:
        raise ValueError("metric must be 'ip' or 'l2'")
    index.add(vectors)
    return index


def faiss_gt(index, queries: np.ndarray, k: int) -> np.ndarray:
    """
    Return indices (0..N-1) of top-k for each query: shape (Q, k), dtype=int64
    """
    distances, indices = index.search(queries, k)
    return indices.astype(np.int64)


def fetch_casper_topk(session: requests.Session, base_url: str, collection: str, vector: np.ndarray, k: int, timeout: float = 30.0) -> List[int]:
    """
    POST a query to Casper:
      POST {base_url}/collection/{collection}/search?limit=k&output=json
      body: { "vector": [..] }
    Expects response as a list of pairs [id, score] or a list of dicts with 'id'.
    Returns a list of ids with length <= k.
    """
    url = f"{base_url.rstrip('/')}/collection/{collection}/search"
    params = {"limit": str(k), "output": "json"}
    payload = {"vector": vector.astype(float).tolist()}

    resp = session.post(url, params=params, json=payload, headers={"Content-Type": "application/json"}, timeout=timeout)
    resp.raise_for_status()
    data = resp.json()
    return parse_casper_ids(data, k)


def fetch_qdrant_topk(session: requests.Session, base_url: str, collection: str, vector: np.ndarray, k: int, timeout: float = 30.0) -> List[int]:
    """
    POST a query to Qdrant:
      POST {base_url}/collections/{collection}/points/search
      body: { "vector": [..], "limit": k }
    Expects response:
      {
        "result": [{"id": id, "version": ..., "score": ...}, ...],
        "status": "ok",
        "time": ...
      }
    Returns a list of ids with length <= k.
    """
    url = f"{base_url.rstrip('/')}/collections/{collection}/points/search"
    payload = {
        "vector": vector.astype(float).tolist(),
        "limit": k,
        "with_payload": False
    }

    resp = session.post(url, json=payload, headers={"Content-Type": "application/json"}, timeout=timeout)
    resp.raise_for_status()
    data = resp.json()
    return parse_qdrant_ids(data, k)

def parse_casper_ids(data, k: int) -> List[int]:
    """
    Handle several response formats:
      - [[id, score], ...]
      - [{"id": id, "score": ...}, ...]
      - {"results": [...]} or {"neighbors": [...]} — pick the first found
    """
    payload = data
    if isinstance(payload, dict):
        for key in ("results", "neighbors", "data", "items"):
            if key in payload and isinstance(payload[key], list):
                payload = payload[key]
                break

    ids: List[int] = []
    if isinstance(payload, list):
        for item in payload:
            if isinstance(item, list) and len(item) >= 1:
                ids.append(int(item[0]))
            elif isinstance(item, dict):
                if "id" in item:
                    ids.append(int(item["id"]))
                elif "doc_id" in item:
                    ids.append(int(item["doc_id"]))
            if len(ids) >= k:
                break
    return ids


def parse_qdrant_ids(data, k: int) -> List[int]:
    """
    Parse Qdrant response format:
      {
        "result": [
          {"id": id, "version": ..., "score": ...},
          ...
        ],
        "status": "ok",
        "time": ...
      }
    Returns list of ids from the "result" array.
    """
    ids: List[int] = []
    if isinstance(data, dict) and "result" in data:
        result = data["result"]
        if isinstance(result, list):
            for item in result:
                if isinstance(item, dict) and "id" in item:
                    ids.append(int(item["id"]))
                if len(ids) >= k:
                    break
    return ids


def compute_recall_at_k(gt_ids_row: List[int], approx_ids_row: List[int], k: int) -> float:
    """
    gt_ids_row: list of ids of length k (ground truth)
    approx_ids_row: list of ids of length <= k (Casper result)
    recall@k = |intersection| / k
    """
    gt_set = set(gt_ids_row[:k])
    inter = gt_set.intersection(approx_ids_row[:k])
    return len(inter) / float(k)


def main():
    parser = argparse.ArgumentParser(description="Compute recall@k between Casper/Qdrant and FAISS Flat (GT).")
    parser.add_argument("--base", required=True, help="Base binary file (Casper format) to build FAISS GT")
    parser.add_argument("--queries", required=False, help="Queries binary file (Casper format). If omitted, queries are sampled from base.")
    parser.add_argument("--k", type=int, default=10, help="Top-k for evaluation (default: 10)")
    parser.add_argument("--metric", choices=["ip", "l2"], default="ip", help="FAISS Flat metric (ip or l2), default ip")
    parser.add_argument("--limit-queries", type=int, default=0, help="Limit number of queries (0 = all)")
    parser.add_argument("--backend", choices=["casper", "qdrant"], default="casper", help="Backend to query: 'casper' or 'qdrant' (default: casper)")
    parser.add_argument("--base-url", default="http://localhost:8080", help="Base URL. Defaults to Casper at http://localhost:8080 (use e.g. http://localhost:6333 for Qdrant).")
    parser.add_argument("--collection", required=True, help="Collection name (e.g., demo)")
    parser.add_argument("--num-queries", type=int, default=0, help="If --queries is omitted, take N random queries from base (0 = all)")
    parser.add_argument("--query-seed", type=int, default=42, help="Seed for sampling random queries from base")
    args = parser.parse_args()

    if not os.path.isfile(args.base):
        print(f"File not found: {args.base}", file=sys.stderr)
        sys.exit(1)
    if args.queries is not None and not os.path.isfile(args.queries):
        print(f"File not found: {args.queries}", file=sys.stderr)
        sys.exit(1)
    if args.k <= 0:
        print("k must be > 0", file=sys.stderr)
        sys.exit(1)

    print("Loading base...")
    base_ids, base_vecs = read_casper_bin(args.base)
    print(f"  Base: {base_vecs.shape[0]} vectors, D={base_vecs.shape[1]}")

    print("Building FAISS Flat GT...")
    index = build_faiss_index(base_vecs, args.metric)

    # Prepare queries
    if args.queries:
        print("Loading queries from separate file...")
        query_ids, query_vecs = read_casper_bin(args.queries)
        print(f"  Queries: {query_vecs.shape[0]} vectors, D={query_vecs.shape[1]}")
    else:
        print("Using queries sampled from base...")
        total = base_vecs.shape[0]
        if args.num_queries and args.num_queries > 0:
            n_q = min(args.num_queries, total)
        else:
            n_q = total
        rng = np.random.RandomState(args.query_seed)
        chosen = rng.choice(total, size=n_q, replace=False)
        query_vecs = base_vecs[chosen]
        query_ids = base_ids[chosen]
        print(f"  Selected queries: {n_q} out of {total}")

    if query_vecs.shape[1] != base_vecs.shape[1]:
        raise ValueError(f"Query dimension ({query_vecs.shape[1]}) != base dimension ({base_vecs.shape[1]})")

    num_queries = query_vecs.shape[0]
    if args.limit_queries and args.limit_queries > 0:
        num_queries = min(num_queries, args.limit_queries)
        query_vecs = query_vecs[:num_queries]
        query_ids = query_ids[:num_queries]

    # GT: indices -> ids (use k directly)
    gt_indices = faiss_gt(index, query_vecs, args.k)  # shape (Q, k)
    base_ids_arr = np.asarray(base_ids, dtype=np.int64)

    session = requests.Session()

    recalls: List[float] = []
    for i in range(num_queries):
        gt_ids_row = base_ids_arr[gt_indices[i]].tolist()
        if args.backend == "casper":
            approx_ids = fetch_casper_topk(session, args.base_url, args.collection, query_vecs[i], args.k)
        else:
            approx_ids = fetch_qdrant_topk(session, args.base_url, args.collection, query_vecs[i], args.k)
        approx_ids = approx_ids[:args.k]

        r_at_k = compute_recall_at_k(gt_ids_row, approx_ids, args.k)
        recalls.append(r_at_k)

        if (i + 1) % 50 == 0 or i == num_queries - 1:
            print(f"  Processed {i+1}/{num_queries}, current mean recall@{args.k}: {np.mean(recalls):.4f}")

    mean_recall = float(np.mean(recalls)) if recalls else 0.0
    print(f"\nFinal recall@{args.k}: {mean_recall:.6f} over {num_queries} queries")


if __name__ == "__main__":
    main()
