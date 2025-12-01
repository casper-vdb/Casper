#!/usr/bin/env python3
"""
Simple importer for Casper binary vector files (data.bin):
  - reads a Casper-format binary file (dimension, count, then id + vector)
  - sends each document as a JSON payload to
      POST http://localhost:8080/collection/alex/insert?id=<id>
    with body: { "vector": [ ... ] }
"""

import sys
import struct
import argparse
from typing import Generator, Tuple, List

import requests


def read_casper_bin(path: str) -> Tuple[int, int, Generator[Tuple[int, List[float]], None, None]]:
    """
    Read a Casper-format binary file.

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


def send_document(
    session: requests.Session,
    base_url: str,
    collection: str,
    doc_id: int,
    vector: List[float],
) -> None:
    """
    Send a single document to Casper:
      POST {base_url}/collection/{collection}/insert?id=<doc_id>
      body: { "vector": [ ... ] }

    Mirrors the behavior of `send_document` in import.rs:
      - prints ✓ on success
      - prints ✗ and status code on HTTP error status
      - raises on network errors
    """
    url = f"{base_url.rstrip('/')}/collection/{collection}/insert"
    params = {"id": str(doc_id)}
    payload = {"vector": vector}

    resp = session.post(url, params=params, json=payload, headers={"Content-Type": "application/json"})

    if 200 <= resp.status_code < 300:
        print(f"✓ Document {doc_id} imported successfully")
    else:
        # Keep behavior similar to Rust version: log but do not raise on HTTP status errors
        print(f"✗ Failed to import document {doc_id}: HTTP {resp.status_code}", file=sys.stderr)


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

    args = parser.parse_args()
    file_path: str = args.path
    base_url: str = args.base_url
    collection: str = args.collection

    print(f"Importing vectors from file: {file_path}")
    print(f"Server URL: {base_url}")
    print(f"Collection: {collection}")
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

    try:
        for doc_id, vector in docs_iter:
            send_document(session, base_url, collection, doc_id, vector)
            processed += 1
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
