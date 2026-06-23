#!/usr/bin/env python
import argparse
import numpy as np
import pandas as pd
import scanpy as sc
from scipy import sparse


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-h5ad", required=True)
    parser.add_argument("--score-file", required=True)
    parser.add_argument("--output-h5ad", required=True)
    parser.add_argument("--celltype-col", default="Org_celltype")
    parser.add_argument("--use-rep", default="X_pca_harmony")
    parser.add_argument("--n-neighbors", type=int, default=15)
    parser.add_argument("--n-pcs", type=int, default=50)
    parser.add_argument("--alpha", type=float, default=0.15)
    parser.add_argument("--max-iter", type=int, default=200)
    parser.add_argument("--tol", type=float, default=1e-6)
    args = parser.parse_args()

    adata = sc.read_h5ad(args.input_h5ad)

    # ------------------------------------------------------------
    # PN-only subset
    # PPR susceptibility should be calculated only in control/PN cells
    # ------------------------------------------------------------
    if "Group" not in adata.obs.columns:
        raise ValueError("Group column not found in adata.obs")

    print("[Before PN subset: cell counts]")
    print(adata.obs["Group"].astype(str).value_counts(dropna=False))

    adata = adata[adata.obs["Group"].astype(str).eq("PN")].copy()

    print("[After PN subset: cell counts]")
    print(adata.obs["Group"].astype(str).value_counts(dropna=False))

    if adata.n_obs == 0:
        raise ValueError("No PN cells left after subsetting Group == PN")

    # ------------------------------------------------------------
    # Remove old mixed PN+ALS graph
    # Then neighbors will be recalculated on PN-only cells
    # Existing UMAP coordinates will NOT be changed unless sc.tl.umap is rerun
    # ------------------------------------------------------------
    if "neighbors" in adata.uns:
        del adata.uns["neighbors"]

    for k in ["distances", "connectivities"]:
        if k in adata.obsp:
            del adata.obsp[k]
            
    df_score = pd.read_csv(args.score_file, sep="\t", index_col=0)
    print("[scDRS columns]", list(df_score.columns))
    if "raw_score" not in df_score.columns:
        raise ValueError("score file does not contain raw_score")

    df_score = df_score[["raw_score"]].copy()
    df_score = df_score[~df_score.index.duplicated(keep="first")]
    df_score = df_score.add_prefix("scdrs_")

    old_cols = [c for c in adata.obs.columns if c.startswith("scdrs_")]
    if old_cols:
        adata.obs = adata.obs.drop(columns=old_cols)

    adata.obs = adata.obs.join(df_score, how="left")
    score_col = "scdrs_raw_score"
    if score_col not in adata.obs.columns:
        raise ValueError("scdrs_raw_score not found after join")
    n_non_na = adata.obs[score_col].notna().sum()
    print(f"[coverage] {score_col}: {n_non_na}/{adata.n_obs}")
    if n_non_na == 0:
        raise ValueError("No matched barcodes between scDRS score and AnnData")

    if "connectivities" not in adata.obsp:
        print("[Info] connectivities not found; running neighbors")
        if args.use_rep not in adata.obsm:
            raise ValueError(f"{args.use_rep} not found in adata.obsm")
        sc.pp.neighbors(adata, n_neighbors=args.n_neighbors, n_pcs=args.n_pcs, use_rep=args.use_rep)

    W = adata.obsp["connectivities"].tocsr().astype(np.float64)
    row_sum = np.array(W.sum(axis=1)).ravel()
    row_sum[row_sum == 0] = 1.0
    W_row = sparse.diags(1.0 / row_sum) @ W

    s0 = adata.obs[score_col].astype(float).replace([np.inf, -np.inf], np.nan).fillna(0.0).values
    s = s0.copy()
    for i in range(args.max_iter):
        s_next = args.alpha * s0 + (1.0 - args.alpha) * (W_row @ s)
        if np.abs(s_next - s).mean() < args.tol:
            print(f"[PPR converged] iter={i}")
            s = s_next
            break
        s = s_next

    adata.obs["scdrs_ppr"] = s
    mu = np.nanmean(s)
    sd = np.nanstd(s)
    if sd == 0 or np.isnan(sd):
        sd = 1.0
    adata.obs["scdrs_ppr_z"] = (s - mu) / sd
    print(adata.obs["scdrs_ppr_z"].describe())
    adata.write_h5ad(args.output_h5ad)

if __name__ == "__main__":
    main()
