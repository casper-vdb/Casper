import argparse
import os
import struct
import time
from typing import Tuple, Optional, Sequence

import numpy as np
import faiss
from casper_client import CasperClient


faiss.omp_set_num_threads(16)


def read_dump_from_disk(vec_size: int, filename: str) -> Tuple[np.ndarray, list, list, list, int]:
    """
    Read vectors from a Casper-format binary file, same layout as in scripts/recall/recall.py:

      BE u32 dimension, BE u32 count,
      then for each document: BE u32 id + dimension * BE f32

    Returns:
      - xb: np.ndarray shape (count, dimension), dtype=float32
      - placeholders for (nms, subjects, tss, n_unique) to keep the original signature.
    """
    with open(filename, "rb") as f:
        header = f.read(8)
        if len(header) != 8:
            raise ValueError("File too short: missing header (dimension, count)")
        dimension, count = struct.unpack(">II", header)

        if dimension != vec_size:
            raise ValueError(
                f"Vector size mismatch: file dimension={dimension}, expected vec_size={vec_size}"
            )

        xb = np.empty((count, dimension), dtype="float32")

        for i in range(count):
            # Read and ignore document id (BE u32)
            id_bytes = f.read(4)
            if len(id_bytes) != 4:
                raise ValueError(f"Truncated file: cannot read id for i={i}")

            # Read vector as BE f32 and convert to native float32
            vec_bytes = f.read(4 * dimension)
            if len(vec_bytes) != 4 * dimension:
                raise ValueError(f"Truncated file: cannot read vector for i={i}")
            vec = np.frombuffer(vec_bytes, dtype=">f4").astype(np.float32)
            xb[i, :] = vec

    # We don't use nms/subjects/tss/n_unique in downstream code; return empty placeholders.
    return xb, [], [], [], 0


def upload_codebooks_to_casper_and_create_pq(
    *,
    host: str,
    http_port: int,
    grpc_port: int,
    pq_name: str,
    matrix_prefix: str,
    dim: int,
    centroids_all: np.ndarray,  # (M, ksub, dsub)
    overwrite: bool,
    chunk_floats: Optional[int],
) -> Sequence[str]:
    """
    Upload each PQ subspace centroid matrix into Casper Matrix storage (gRPC UploadMatrix),
    then create PQ in Casper referencing those matrices (HTTP PQ service).

    Important: Casper PQ expects `codebooks` to be matrix names (not filenames).
    """
    client = CasperClient(host=host, http_port=int(http_port), grpc_port=int(grpc_port))
    matrix_names: list[str] = []

    try:
        if overwrite:
            try:
                client.delete_pq(pq_name)
                print(f"Deleted existing PQ: {pq_name}")
            except Exception:
                pass

        m, ksub, dsub = centroids_all.shape
        for sub in range(m):
            matrix_name = f"{matrix_prefix}_sub_{sub}"
            matrix_names.append(matrix_name)

            if overwrite:
                try:
                    client.delete_matrix(matrix_name)
                except Exception:
                    pass

            centroids_sub = centroids_all[sub].astype(np.float32)  # (ksub, dsub)
            print(f"Uploading matrix: {matrix_name} (rows={ksub}, dim={dsub})")
            client.upload_matrix(
                name=matrix_name,
                dimension=int(dsub),
                vectors=centroids_sub.tolist(),
                chunk_floats=chunk_floats,
            )

        print(f"Creating PQ: {pq_name} (dim={dim}, codebooks={len(matrix_names)})")
        client.create_pq(pq_name, dim=int(dim), codebooks=matrix_names)
        print("PQ created")
    finally:
        try:
            client.close()
        except Exception:
            pass

    return matrix_names


def export_pq_codebooks_as_clustering_matrices(
    input_path: str,
    vec_size: int,
    m: int,
    nbits: int,
    max_train: int,
    normalize: bool,
    metric: str = "l2",
    *,
    casper_host: str,
    casper_http_port: int,
    casper_grpc_port: int,
    pq_name: str,
    matrix_prefix: str,
    overwrite: bool,
    chunk_floats: Optional[int],
) -> None:
    t0 = time.time()
    xb, _, _, _, _ = read_dump_from_disk(vec_size, input_path)
    nvecs = xb.shape[0]
    print(f"Loaded {nvecs} vectors with dimension {vec_size} from {input_path}")

    if normalize:
        t = time.time()
        for i in range(nvecs):
            norm = np.linalg.norm(xb[i])
            if norm > 0:
                xb[i] = xb[i] / norm
        print(f"Normalized vectors in {int(time.time() - t)} s")

    if vec_size % m != 0:
        raise ValueError(f"vec_size ({vec_size}) must be divisible by M ({m})")

    train_count = min(max_train, nvecs)
    rng = np.random.default_rng(123)
    train_idx = rng.choice(nvecs, size=train_count, replace=False)
    xtrain = xb[train_idx]
    print(f"Training PQ on {xtrain.shape[0]} vectors, M={m}, nbits={nbits}, metric={metric}")

    # Use IndexPQ with appropriate metric
    if metric.lower() == "ip" or metric.lower() == "inner_product":
        index_pq = faiss.IndexPQ(vec_size, m, nbits, faiss.METRIC_INNER_PRODUCT)
        print("Using inner product metric for PQ")
    else:
        index_pq = faiss.IndexPQ(vec_size, m, nbits, faiss.METRIC_L2)
        print("Using L2 metric for PQ")
    
    index_pq.train(xtrain)
    print("PQ training completed")

    # -------------------------------
    # Evaluate reconstruction quality
    # -------------------------------
    # Use a subset of training vectors to estimate distortion
    eval_count = min(100_000, xtrain.shape[0])
    if eval_count > 0:
        rng_eval = np.random.default_rng(321)
        eval_idx = rng_eval.choice(xtrain.shape[0], size=eval_count, replace=False)
        x_eval = xtrain[eval_idx].astype("float32")

        pq = index_pq.pq
        centroids_all = faiss.vector_to_array(pq.centroids).reshape(pq.M, pq.ksub, pq.dsub)

        # Compute PQ codes for evaluation vectors
        codes_bytes = pq.compute_codes(x_eval)
        codes = np.frombuffer(codes_bytes, dtype="uint8").reshape(eval_count, pq.M)

        # Reconstruct vectors from PQ codes
        x_recon = np.empty_like(x_eval)
        for i in range(eval_count):
            for m_idx in range(pq.M):
                code = int(codes[i, m_idx])
                start = m_idx * pq.dsub
                end = start + pq.dsub
                x_recon[i, start:end] = centroids_all[m_idx, code, :]

        # Reconstruction error metrics
        diff = x_eval - x_recon
        sq_err = np.sum(diff * diff, axis=1)  # L2SQ per vector
        norm2 = np.sum(x_eval * x_eval, axis=1)
        rel_err = sq_err / (norm2 + 1e-12)

        # Cosine similarity between original and reconstructed vectors
        dot = np.sum(x_eval * x_recon, axis=1)
        norm_orig = np.linalg.norm(x_eval, axis=1)
        norm_recon = np.linalg.norm(x_recon, axis=1)
        cos = dot / (norm_orig * norm_recon + 1e-12)

        def stats(arr: np.ndarray, name: str) -> None:
            print(
                f"{name}: mean={float(arr.mean()):.6f}, "
                f"p50={float(np.percentile(arr, 50)):.6f}, "
                f"p90={float(np.percentile(arr, 90)):.6f}, "
                f"p99={float(np.percentile(arr, 99)):.6f}"
            )

        print("\nPQ reconstruction quality (on subset of train vectors):")
        stats(sq_err, "L2SQ error")
        stats(rel_err, "Relative L2SQ error")
        stats(cos, "Cosine similarity (orig vs recon)")
        print("")
    else:
        pq = index_pq.pq
        centroids_all = faiss.vector_to_array(pq.centroids).reshape(pq.M, pq.ksub, pq.dsub)

    print("Uploading PQ codebooks into Casper (matrices) and creating PQ...")
    matrices = upload_codebooks_to_casper_and_create_pq(
        host=casper_host,
        http_port=casper_http_port,
        grpc_port=casper_grpc_port,
        pq_name=pq_name,
        matrix_prefix=matrix_prefix,
        dim=vec_size,
        centroids_all=centroids_all,
        overwrite=overwrite,
        chunk_floats=chunk_floats,
    )

    print(f"Done in {int(time.time() - t0)} s")
    print(f"PQ '{pq_name}' codebook matrices:")
    for n in matrices:
        print(f"  - {n}")


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Train FAISS PQ and upload codebooks into Casper (matrices + PQ)")
    p.add_argument("--input", required=True, help="Path to input binary dump file")
    p.add_argument("--vec-size", type=int, default=128, help="Vector dimensionality")
    p.add_argument("--m", type=int, default=8, help="Number of PQ subquantizers (M)")
    p.add_argument("--nbits", type=int, default=8, help="Bits per sub-vector (nbits)")
    p.add_argument("--max-train", type=int, default=1_000_000, help="Max train vectors")
    p.add_argument("--normalize", action="store_true", help="L2-normalize input vectors before PQ")
    p.add_argument("--metric", type=str, default="l2", choices=["l2", "ip", "inner_product"], 
                   help="Distance metric: l2 (default) or ip/inner_product")

    # Casper connection + naming
    p.add_argument("--casper-host", default="http://127.0.0.1", help="Casper host, e.g. http://127.0.0.1")
    p.add_argument("--casper-http-port", type=int, default=8080, help="Casper HTTP port (default: 8080)")
    p.add_argument("--casper-grpc-port", type=int, default=50051, help="Casper gRPC port (default: 50051)")
    p.add_argument("--pq-name", default="", help="PQ name to create in Casper (default: pq_<metric>)")
    p.add_argument("--matrix-prefix", default="", help="Prefix for matrix names (default: pq-name)")
    p.add_argument("--overwrite", action="store_true", help="Delete existing PQ/matrices if they already exist")
    p.add_argument("--chunk-floats", type=int, default=0, help="UploadMatrix chunk size in floats (0 = default)")
    return p.parse_args()


if __name__ == "__main__":
    args = parse_args()
    pq_name = args.pq_name.strip()
    if pq_name == "":
        metric_norm = str(args.metric).lower()
        if metric_norm == "inner_product":
            metric_norm = "ip"
        pq_name = f"pq_{metric_norm}"

    matrix_prefix = args.matrix_prefix.strip() or pq_name
    chunk_floats = int(args.chunk_floats) if int(args.chunk_floats) > 0 else None

    export_pq_codebooks_as_clustering_matrices(
        input_path=args.input,
        vec_size=args.vec_size,
        m=args.m,
        nbits=args.nbits,
        max_train=args.max_train,
        normalize=args.normalize,
        metric=args.metric,
        casper_host=args.casper_host,
        casper_http_port=args.casper_http_port,
        casper_grpc_port=args.casper_grpc_port,
        pq_name=pq_name,
        matrix_prefix=matrix_prefix,
        overwrite=bool(args.overwrite),
        chunk_floats=chunk_floats,
    )



