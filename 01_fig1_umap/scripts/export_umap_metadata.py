#!/usr/bin/env python3
import argparse
from pathlib import Path

import pandas as pd
import scanpy as sc


def parse_args():
    parser = argparse.ArgumentParser(
        description=(
            "Export UMAP coordinates together with metadata from an h5ad file. "
            "By default, all columns in adata.obs are retained."
        )
    )
    parser.add_argument("--input", required=True, help="Input .h5ad file")
    parser.add_argument("--output", required=True, help="Output CSV file")
    parser.add_argument(
        "--umap-key",
        default="X_umap",
        help="Key in adata.obsm that stores UMAP coordinates (default: X_umap)",
    )
    parser.add_argument(
        "--coord-cols",
        nargs=2,
        default=["UMAP1", "UMAP2"],
        metavar=("XCOL", "YCOL"),
        help="Column names for exported UMAP coordinates (default: UMAP1 UMAP2)",
    )
    parser.add_argument(
        "--cell-id-col",
        default="cell_id",
        help="Column name used for the cell/barcode ID column (default: cell_id)",
    )
    parser.add_argument(
        "--obs-cols",
        default=None,
        help=(
            "Optional comma-separated list of obs columns to export. "
            "If omitted, all adata.obs columns are exported."
        ),
    )
    return parser.parse_args()


def main():
    args = parse_args()

    input_path = Path(args.input)
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    adata = sc.read_h5ad(input_path)

    if args.umap_key not in adata.obsm:
        raise ValueError(
            f"adata.obsm does not contain '{args.umap_key}'. "
            f"Available keys: {list(adata.obsm.keys())}"
        )

    umap = adata.obsm[args.umap_key]
    if umap.shape[1] < 2:
        raise ValueError(
            f"UMAP matrix under '{args.umap_key}' has fewer than 2 dimensions: {umap.shape}"
        )

    umap_df = pd.DataFrame(
        umap[:, :2],
        index=adata.obs_names,
        columns=args.coord_cols,
    )

    if args.obs_cols:
        obs_cols = [x.strip() for x in args.obs_cols.split(",") if x.strip()]
        missing = [c for c in obs_cols if c not in adata.obs.columns]
        if missing:
            raise ValueError(f"These columns are missing in adata.obs: {missing}")
        meta_df = adata.obs.loc[:, obs_cols].copy()
    else:
        meta_df = adata.obs.copy()

    plot_df = pd.concat([umap_df, meta_df], axis=1)
    plot_df.insert(0, args.cell_id_col, plot_df.index.astype(str))

    plot_df.to_csv(output_path, index=False)

    print(f"[OK] Exported: {output_path}")
    print(f"[INFO] Cells: {plot_df.shape[0]}")
    print(f"[INFO] Columns: {plot_df.shape[1]}")
    print(f"[INFO] Metadata columns exported: {meta_df.shape[1]}")
    print(f"[INFO] First columns: {plot_df.columns[:10].tolist()}")


if __name__ == "__main__":
    main()
