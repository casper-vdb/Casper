#!/usr/bin/env python3
"""
Simple importer for binary vector files (data.bin).

File format:
  - 4 bytes: big-endian u32 dimension
  - 4 bytes: big-endian u32 count
  - then for each document:
      - 4 bytes: big-endian u32 id
      - D * 4 bytes: big-endian f32 values

Backends:
  - casper:
      POST {base_url}/collection/{collection}/update
      body: { "insert": [ {"id": <id>, "vector": [...]}, ... ], "delete": [] }
  - qdrant:
      PUT {base_url}/collections/{collection}/points?wait=true
      body: { "points": [ {"id": <id>, "vector": [...]}, ... ] }
"""

import sys
import struct
import argparse
from typing import Generator, Tuple, List, Dict, Any

import requests


def read_casper_bin(path: str) -> Tuple[int, int, Generator[Tuple[int, List[float]], None, None]]:
    """
    Read a binary file.

    Format:
      - 4 bytes: big-endian u32 dimension
      - 4 bytes: big-endian u32 count
      - then for each document:
          - 4 bytes: big-endian u32 id
          - D * 4 bytes: big-endian f32 values
    """

    def _iter_docs(f, dim: int, count: int) -> Generator[Tuple[int, List[float]], None, None]:
        for i in range(count):
            id_bytes = f.read(4)
            if len(id_bytes) == 0:
                # EOF reached earlier than expected
                break
            if len(id_bytes) != 4:
                raise ValueError(f"Truncated file: cannot read id for document index {i}")
            (doc_id,) = struct.unpack(">I", id_bytes)

            vec_bytes = f.read(4 * dim)
            if len(vec_bytes) != 4 * dim:
                raise ValueError(f"Truncated file: cannot read vector for document id={doc_id}")

            # big-endian floats
            fmt = ">" + "f" * dim
            vector = list(struct.unpack(fmt, vec_bytes))
            yield int(doc_id), vector

    f = open(path, "rb")
    header = f.read(8)
    if len(header) != 8:
        f.close()
        raise ValueError("File too short: missing header (dimension, count)")

    dim, count = struct.unpack(">II", header)
    return dim, count, _iter_docs(f, dim, count)


def send_documents_casper(
    session: requests.Session,
    base_url: str,
    collection: str,
    batch: List[Dict[str, Any]],
    *,
    timeout: float = 120.0,
) -> None:
    """
    Send a batch of documents to Casper:
      POST {base_url}/collection/{collection}/update
      body: { "insert": [ {"id": <id>, "vector": [...]}, ...], "delete": [] }
    """
    url = f"{base_url.rstrip('/')}/collection/{collection}/update"
    payload = {"insert": batch, "delete": []}
    resp = session.post(
        url,
        json=payload,
        headers={"Content-Type": "application/json"},
        timeout=timeout,
    )
    resp.raise_for_status()


def send_documents_qdrant(
    session: requests.Session,
    base_url: str,
    collection: str,
    points: List[Dict[str, Any]],
    *,
    wait: bool = True,
    timeout: float = 120.0,
) -> None:
    """
    Upsert a batch of points into Qdrant.
      PUT {base_url}/collections/{collection}/points?wait=true
      body: { "points": [ {"id": ..., "vector": [...]}, ... ] }
    """
    url = f"{base_url.rstrip('/')}/collections/{collection}/points"
    params = {"wait": "true" if wait else "false"}
    payload = {"points": points}

    resp = session.put(
        url,
        params=params,
        json=payload,
        headers={"Content-Type": "application/json"},
        timeout=timeout,
    )
    resp.raise_for_status()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Import vectors from a Casper binary file into a Casper collection."
    )
    parser.add_argument(
        "path",
        help="Path to Casper-format binary file (e.g., data.bin)",
    )
    parser.add_argument(
        "--base-url",
        default="http://localhost:8080",
        help="Base URL. Defaults to http://localhost:8080.",
    )
    parser.add_argument(
        "--collection",
        required=True,
        help="Collection name (e.g., alex)",
    )
    parser.add_argument(
        "--backend",
        choices=["casper", "qdrant"],
        default="casper",
        help="Backend to import into: casper | qdrant (default: casper)",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=256,
        help="Batch size for Casper batch update / Qdrant upserts (default: 256).",
    )
    parser.add_argument(
        "--wait",
        action="store_true",
        default=True,
        help="(Qdrant) Wait for upsert to be processed before returning (default: true).",
    )
    parser.add_argument(
        "--no-wait",
        action="store_false",
        dest="wait",
        help="(Qdrant) Do not wait for upsert to be processed.",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="Do not print per-document success logs (recommended for large imports).",
    )

    args = parser.parse_args()
    file_path: str = args.path
    base_url: str = args.base_url
    collection: str = args.collection
    backend: str = args.backend
    batch_size: int = int(args.batch_size)
    wait: bool = bool(args.wait)
    quiet: bool = bool(args.quiet)

    print(f"Importing vectors from file: {file_path}")
    print(f"Server URL: {base_url}")
    print(f"Collection: {collection}")
    print(f"Backend: {backend}")
    if backend == "qdrant":
        print(f"Batch size: {batch_size}")
        print(f"Wait: {wait}")
    print()

    try:
        dim, count, docs_iter = read_casper_bin(file_path)
    except Exception as e:
        print(f"Error reading file: {e}", file=sys.stderr)
        return 1

    print("File info:")
    print(f"  Dimension: {dim}")
    print(f"  Documents: {count}")
    print()

    session = requests.Session()
    processed = 0

    def log_batch_progress(processed_now: int, total: int) -> None:
        # Keep progress output consistent across backends.
        if quiet:
            return
        print(f"✓ Imported batch, processed={processed_now}/{total}", flush=True)

    try:
        if backend == "casper":
            if batch_size <= 0:
                raise ValueError("--batch-size must be > 0")

            batch: List[Dict[str, Any]] = []
            for doc_id, vector in docs_iter:
                batch.append({"id": int(doc_id), "vector": vector})
                processed += 1
                if len(batch) >= batch_size:
                    send_documents_casper(session, base_url, collection, batch)
                    log_batch_progress(processed, count)
                    batch = []

            if batch:
                send_documents_casper(session, base_url, collection, batch)
                log_batch_progress(processed, count)
        else:
            if batch_size <= 0:
                raise ValueError("--batch-size must be > 0")

            batch: List[Dict[str, Any]] = []
            for doc_id, vector in docs_iter:
                batch.append({"id": int(doc_id), "vector": vector})
                processed += 1
                if len(batch) >= batch_size:
                    send_documents_qdrant(session, base_url, collection, batch, wait=wait)
                    log_batch_progress(processed, count)
                    batch = []

            if batch:
                send_documents_qdrant(session, base_url, collection, batch, wait=wait)
                log_batch_progress(processed, count)
    except KeyboardInterrupt:
        print("\nImport interrupted by user.", file=sys.stderr)
        return 1
    except Exception as e:
        # Network or parsing error
        print(f"\nError during import: {e}", file=sys.stderr)
        return 1
    finally:
        session.close()

    print()
    print(f"Import finished. Processed documents: {processed}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


