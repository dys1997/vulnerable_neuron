#!/usr/bin/env python

import argparse
import os
import numpy as np
import pandas as pd
import scanpy as sc


def merge_subtypes(x, mode):
    x = x.astype(str).copy()

    if mode == "In":
        x = x.replace({
            "In.5HT3aR.CDH4_CCK": "In.5HT3aR.CDH4",
            "In.5HT3aR.CDH4_SCGN": "In.5HT3aR.CDH4",
        })

    elif mode == "Ex":
        x = x.replace({
            "Ex.L5.VAT1L_EYA4": "Ex.L5.VAT1L",
            "Ex.L5.VAT1L_THSD4": "Ex.L5.VAT1L",
        })

    return x


def main():
    parser = argparse.ArgumentParser()

    parser.add_argument("--input-h5ad", required=True)
    parser.add_argument("--mode", choices=["In", "Ex"], required=True)
    parser.add_argument("--region", required=True)
    parser.add_argument("--output-csv", required=True)

    parser.add_argument("--celltype-col", default="Org_celltype")
    parser.add_argument("--score-col", default="scdrs_ppr")

    args = parser.parse_args()

    adata = sc.read_h5ad(args.input_h5ad)

    if "X_umap" not in adata.obsm:
        raise ValueError("X_umap not found in adata.obsm")

    if args.celltype_col not in adata.obs.columns:
        raise ValueError(f"{args.celltype_col} not found in adata.obs")

    if args.score_col not in adata.obs.columns:
        raise ValueError(f"{args.score_col} not found in adata.obs")

    org = adata.obs[args.celltype_col].astype(str)

    if args.mode == "In":
        mask_keep = (
            org.str.contains("PV", case=False, na=False) |
            org.str.contains("5HT3aR", case=False, na=False)
        )
    else:
        mask_keep = org.str.startswith("Ex.", na=False)

    ad = adata[mask_keep].copy()

    if ad.n_obs == 0:
        raise ValueError(f"No cells left for {args.region} {args.mode}")

    plot_group = merge_subtypes(
        ad.obs[args.celltype_col].astype(str),
        mode=args.mode,
    )

    score = ad.obs[args.score_col].astype(float).replace([np.inf, -np.inf], np.nan)

    sd = score.std(skipna=True)
    if sd == 0 or np.isnan(sd):
        sd = 1.0

    score_z = (score - score.mean(skipna=True)) / sd

    umap = ad.obsm["X_umap"]

    df = pd.DataFrame({
        "cell_id": ad.obs_names.astype(str),
        "Region": args.region,
        "Mode": args.mode,
        "UMAP1": umap[:, 0],
        "UMAP2": umap[:, 1],
        "Org_celltype": ad.obs[args.celltype_col].astype(str).values,
        "plot_group": plot_group.astype(str).values,
        args.score_col: score.values,
        "scdrs_ppr_z_display": score_z.values,
    })

    outdir = os.path.dirname(args.output_csv)
    if outdir:
        os.makedirs(outdir, exist_ok=True)

    df.to_csv(args.output_csv, index=False)

    summary = (
        df
        .groupby("plot_group", observed=True)["scdrs_ppr_z_display"]
        .median()
        .sort_values(ascending=False)
        .reset_index()
        .rename(columns={"scdrs_ppr_z_display": "median_display_ppr_z"})
    )

    summary_fp = args.output_csv.replace(".csv", "_summary.tsv")
    summary.to_csv(summary_fp, sep="\t", index=False)

    print("[saved]", args.output_csv)
    print("[saved]", summary_fp)


if __name__ == "__main__":
    main()
