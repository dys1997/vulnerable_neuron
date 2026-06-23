#!/usr/bin/env python
import argparse
import os
import numpy as np
import pandas as pd
import scanpy as sc
from scipy.stats import ranksums
from tqdm import tqdm

RENAME_MAP = {
    "In.5HT3aR.CDH4_CCK": "In.5HT3aR.CDH4",
    "In.5HT3aR.CDH4_SCGN": "In.5HT3aR.CDH4",
    "Ex.L5.VAT1L_EYA4": "Ex.L5.VAT1L",
    "Ex.L5.VAT1L_THSD4": "Ex.L5.VAT1L",
}

def bh_fdr(pvals):
    p = np.asarray(pvals, dtype=float)
    n = p.size
    order = np.argsort(p)
    ranked = p[order]
    q = ranked * n / (np.arange(1, n + 1))
    q = np.minimum.accumulate(q[::-1])[::-1]
    fdr = np.empty_like(q)
    fdr[order] = q
    return np.clip(fdr, 0, 1)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-h5ad", required=True)
    parser.add_argument("--gwas-gs", required=True)
    parser.add_argument("--trait", default="ALS")
    parser.add_argument("--celltype-col", default="Org_celltype")
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--n-trials", type=int, default=10)
    parser.add_argument("--n-per-clust", type=int, default=150)
    parser.add_argument("--min-cells", type=int, default=20)
    parser.add_argument("--z-cut", type=float, default=1.0)
    parser.add_argument("--fdr-cut", type=float, default=0.001)
    parser.add_argument("--random-seed", type=int, default=666)
    args = parser.parse_args()
    os.makedirs(args.output_dir, exist_ok=True)
    rng = np.random.default_rng(args.random_seed)

    df_gs = pd.read_csv(args.gwas_gs, sep="\t")
    row = df_gs.loc[df_gs["TRAIT"] == args.trait].iloc[0]
    genes_all = [g.strip() for g in row["GENESET"].split(",") if g.strip()]
    print(f"[GWAS genes] {len(genes_all)}")

    adata = sc.read_h5ad(args.input_h5ad)

    if "Group" not in adata.obs.columns:
        raise ValueError("Group column not found in adata.obs")

    print("[Before PN subset]")
    print(adata.obs["Group"].astype(str).value_counts(dropna=False))

    adata = adata[adata.obs["Group"].astype(str).eq("PN")].copy()

    print("[After PN subset]")
    print(adata.obs["Group"].astype(str).value_counts(dropna=False))
    if adata.raw is None:
        raise ValueError("adata.raw is None; normalized log expression should be stored in .raw")
    ad = adata.raw.to_adata()
    ad.obs = adata.obs.copy()
    ad.obs[args.celltype_col] = ad.obs[args.celltype_col].astype(str).replace(RENAME_MAP).astype("category")
    clusters = ad.obs[args.celltype_col].cat.categories.tolist()

    ad_gwas = ad[:, ad.var_names.isin(genes_all)].copy()
    X = ad_gwas.X
    if hasattr(X, "toarray"):
        X = X.toarray()
    n_cells, n_genes = X.shape
    genes = np.array(ad_gwas.var_names.tolist(), dtype=str)
    print(f"[matrix] cells={n_cells}, GWAS genes found={n_genes}")

    labels = ad_gwas.obs[args.celltype_col].astype(str).values
    analyzed_clusters = []
    stats = []
    for cl in clusters:
        n_cl = int(np.sum(labels == cl))
        can = n_cl >= args.min_cells
        stats.append({"celltype": cl, "n_self": n_cl, "can_analyze": can, "status": "analyzed" if can else "skipped"})
        if can:
            analyzed_clusters.append(cl)

    LFC_store = {cl: [] for cl in analyzed_clusters}
    FDR_store = {cl: [] for cl in analyzed_clusters}
    trial_counts = {cl: 0 for cl in analyzed_clusters}

    for _ in tqdm(range(args.n_trials), desc="GWAS enrichment trials"):
        for cl in analyzed_clusters:
            idx_self_all = np.where(labels == cl)[0]
            sample_self = rng.choice(idx_self_all, size=min(args.n_per_clust, len(idx_self_all)), replace=False)
            sample_other = []
            for other_cl in clusters:
                if other_cl == cl:
                    continue
                idx_other_all = np.where(labels == other_cl)[0]
                if len(idx_other_all) == 0:
                    continue
                sample_other.extend(rng.choice(idx_other_all, size=min(args.n_per_clust, len(idx_other_all)), replace=False))
            if len(sample_other) < args.min_cells:
                continue
            sample_other = np.asarray(sample_other, dtype=int)
            X1 = X[sample_self, :]
            X2 = X[sample_other, :]
            lfc = X1.mean(axis=0) - X2.mean(axis=0)
            pvals = np.zeros(n_genes, dtype=float)
            for j in range(n_genes):
                _, p = ranksums(X1[:, j], X2[:, j], alternative="two-sided")
                pvals[j] = p
            fdr = bh_fdr(pvals)
            LFC_store[cl].append(lfc)
            FDR_store[cl].append(fdr)
            trial_counts[cl] += 1

    rows_summary, rows_detail = [], []
    for cl in analyzed_clusters:
        n_used = trial_counts[cl]
        if n_used == 0:
            continue
        mean_L = np.mean(LFC_store[cl], axis=0)
        mean_F = np.mean(FDR_store[cl], axis=0)
        sd_L = mean_L.std()
        if sd_L == 0 or np.isnan(sd_L):
            sd_L = 1.0
        z = (mean_L - mean_L.mean()) / sd_L
        sig_mask = (z > args.z_cut) & (mean_F < args.fdr_cut)
        sig_genes = genes[sig_mask]
        rows_summary.append({"celltype": cl, "n_sig_genes": int(sig_genes.size), "n_trials_used": int(n_used), "sig_genes": ";".join(sig_genes)})
        for i, gene in enumerate(genes):
            rows_detail.append({"celltype": cl, "gene": gene, "mean_LFC": mean_L[i], "mean_FDR": mean_F[i], "Z_score": z[i], "is_sig": bool(sig_mask[i])})

    pd.DataFrame(rows_summary).sort_values("n_sig_genes", ascending=False).to_csv(os.path.join(args.output_dir, f"{args.trait}_top1000_gwas_enrichment_summary_merged.tsv"), sep="\t", index=False)
    pd.DataFrame(rows_detail).to_csv(os.path.join(args.output_dir, f"{args.trait}_top1000_gwas_enrichment_detail_merged.tsv"), sep="\t", index=False)
    pd.DataFrame(stats).to_csv(os.path.join(args.output_dir, f"{args.trait}_celltype_stats_merged.tsv"), sep="\t", index=False)

if __name__ == "__main__":
    main()
