#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Identify barcode-level stable vulnerable and stable non-vulnerable PV cell states
from existing In_analysis_input.h5ad.

This script is designed to be plugged into the existing stability-test pipeline.

Input:
    {rep}/In_analysis_input.h5ad

Main idea:
    1. Reuse the existing In_analysis_input.h5ad.
    2. Re-run multi-k_min vulnerable cluster scan in the same In representation.
    3. For each PV barcode, calculate how often it falls into vulnerable hit clusters.
    4. Define:
        stable_vulnerable      : hit_fraction >= cutoff
        stable_nonvulnerable   : hit_fraction <= cutoff
        intermediate           : between
    5. Output barcode lists for downstream barcode-based pseudo-bulk DEG.

Why barcode-level:
    Stable non-vulnerable PV cells may be mixed inside CEMIP, MYBPC1, PTHLH,
    or other original Org_celltype labels. Therefore, reference should be
    defined by stable cell state, not by whole original subtype.
"""

import os
os.environ["OPENBLAS_NUM_THREADS"] = "2"
os.environ["OMP_NUM_THREADS"] = "2"
os.environ["MKL_NUM_THREADS"] = "2"
os.environ["VECLIB_MAXIMUM_THREADS"] = "2"
os.environ["NUMEXPR_NUM_THREADS"] = "2"

import sys
import argparse
import pickle
import numpy as np
import pandas as pd
import scanpy as sc

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


def log(msg: str):
    print(msg, flush=True)


def to_bool(s: pd.Series) -> pd.Series:
    if s.dtype == bool:
        return s.fillna(False)

    s = s.fillna(False)

    if pd.api.types.is_numeric_dtype(s):
        return s.astype(float) != 0

    return s.astype(str).str.strip().str.lower().isin(
        ["true", "t", "1", "yes", "y"]
    )


def get_all_hit_clusters(df_hit: pd.DataFrame, call_by: str = "p", p_cut: float = 0.05):
    """
    Extract vulnerable hit clusters from a df_hit table returned by vulnScan_glm.

    A hit cluster must satisfy:
        1. direction_flag == vulnerable, if this column exists
        2. Significant_call == True, if this column exists
           otherwise Donor_P < p_cut or FDR_Donor < p_cut
    """

    if "cluster" not in df_hit.columns:
        raise ValueError("df_hit does not contain column: cluster")

    if "direction_flag" in df_hit.columns:
        dir_mask = df_hit["direction_flag"].astype(str).str.lower().eq("vulnerable")
    else:
        dir_mask = pd.Series(True, index=df_hit.index)

    if "Significant_call" in df_hit.columns:
        sig_mask = to_bool(df_hit["Significant_call"])
        return (
            df_hit.loc[sig_mask & dir_mask, "cluster"]
            .astype(str)
            .drop_duplicates()
            .tolist()
        )

    if call_by == "p" and "Donor_P" in df_hit.columns:
        sig_mask = df_hit["Donor_P"] < p_cut
        return (
            df_hit.loc[sig_mask & dir_mask, "cluster"]
            .astype(str)
            .drop_duplicates()
            .tolist()
        )

    if call_by == "fdr" and "FDR_Donor" in df_hit.columns:
        sig_mask = df_hit["FDR_Donor"] < p_cut
        return (
            df_hit.loc[sig_mask & dir_mask, "cluster"]
            .astype(str)
            .drop_duplicates()
            .tolist()
        )

    raise ValueError(
        "Cannot identify hit clusters. Need Significant_call, Donor_P, or FDR_Donor."
    )


def run_multik_scan_on_existing_in_object(
    adata,
    vglm,
    outdir: str,
    status_col: str,
    donor_col: str,
    control_label: str,
    use_rep: str,
    k_min_start: int,
    k_min_end: int,
    k_max: int,
    p_cut: float,
    covariate_cols,
    random_state: int,
):
    """
    Re-run multi-k_min vulnerability scan on existing In_analysis_input.h5ad.

    This does not rebuild PCA/Harmony. It reuses X_pca_harmony.
    """

    if use_rep not in adata.obsm.keys():
        raise ValueError(f"{use_rep} not found in adata.obsm. Available: {list(adata.obsm.keys())}")

    kmin_list = list(range(k_min_start, k_min_end + 1))
    all_results = {}

    for kmin in kmin_list:
        log(f"\n[INFO] Run vulnerable scan on In object: k_min={kmin}")

        out = vglm.stagewise_find_largest_vulnerable(
            adata=adata,
            k_min=kmin,
            k_max=k_max,
            start_r=0.01,
            status_col=status_col,
            donor_col=donor_col,
            control_label=control_label,
            use_rep=use_rep,
            direction="vulnerable",
            p_cut=p_cut,
            store="full",
            early_stop_use_fdr=False,
            call_by="p",
            covariate_cols=covariate_cols,
            robust_cov="HC3",
            standardize_numeric=True,
            donor_weight_mode="capped",
            weight_cap="q75",
            random_state=random_state,
            top_n_per_k=20,
            scan_all=False,
            stage_plot_mode="none",
            strict_covariates=False,
            bounds_scope="used",
            cat_agg="mode",
        )

        all_results[kmin] = out

    pkl_fp = os.path.join(outdir, "PV_recomputed_In_all_results_for_cellstate.pkl")
    with open(pkl_fp, "wb") as f:
        pickle.dump(all_results, f)

    log(f"[INFO] Saved recomputed all_results: {pkl_fp}")

    scan_h5ad_fp = os.path.join(outdir, "In_analysis_input_with_recomputed_scan_clusters.h5ad")
    adata.write(scan_h5ad_fp)
    log(f"[INFO] Saved In object with recomputed scan cluster columns: {scan_h5ad_fp}")

    return all_results, kmin_list


def calculate_pv_cell_hit_fraction(
    adata,
    all_results,
    kmin_list,
    outdir: str,
    org_col: str,
    donor_col: str,
    status_col: str,
    sample_col: str,
    pv_prefix: str,
    p_cut: float,
):
    """
    Calculate cell-level hit fraction for PV cells.

    For each k_min:
        - get chosen clustering key
        - get significant vulnerable hit clusters
        - mark each PV cell as inside / outside vulnerable hit clusters

    Output:
        PV_cell_kmin_hit_matrix_long.tsv
        PV_kmin_chosen_hit_clusters.tsv
        PV_cell_hit_fraction.tsv
    """

    obs = adata.obs.copy()
    obs["barcode"] = obs.index.astype(str)

    # Convert to string to avoid category-related issues
    obs[org_col] = obs[org_col].astype(str)

    pv_mask = obs[org_col].str.startswith(pv_prefix)
    pv_barcodes = obs.loc[pv_mask, "barcode"].astype(str).tolist()

    log(f"[INFO] Total In cells: {adata.n_obs}")
    log(f"[INFO] Total PV cells with prefix {pv_prefix}: {len(pv_barcodes)}")

    if len(pv_barcodes) == 0:
        unique_preview = obs[org_col].drop_duplicates().head(50).tolist()
        raise ValueError(
            f"No PV cells found with prefix: {pv_prefix}. "
            f"First 50 Org_celltype values: {unique_preview}"
        )

    meta_cols = [org_col, donor_col, status_col, sample_col, "barcode"]
    missing_meta = [c for c in meta_cols if c not in obs.columns]
    if missing_meta:
        raise ValueError(f"Missing required obs columns: {missing_meta}")

    pv_meta = obs.loc[pv_mask, meta_cols].copy()
    for c in [org_col, donor_col, status_col, sample_col, "barcode"]:
        pv_meta[c] = pv_meta[c].astype(str)

    hit_records = []
    kmin_records = []

    for kmin in kmin_list:
        out = all_results[kmin]
        chosen = out.get("chosen", None)

        if chosen is None:
            log(f"[INFO] k_min={kmin}: no chosen hit. All PV cells are non-hit for this k_min.")

            tmp = pd.DataFrame({
                "barcode": pv_barcodes,
                "k_min": kmin,
                "chosen_k": np.nan,
                "chosen_key": np.nan,
                "cluster": np.nan,
                "is_in_hit_cluster": False,
            })

            hit_records.append(tmp)

            kmin_records.append({
                "k_min": kmin,
                "chosen_k": np.nan,
                "chosen_key": np.nan,
                "n_hit_clusters": 0,
                "hit_clusters": "",
            })

            continue

        k_hit = chosen["k"]
        chosen_key = chosen["key"]

        if chosen_key not in adata.obs.columns:
            raise ValueError(
                f"chosen_key {chosen_key} not found in adata.obs. "
                "This usually means the scan did not write cluster labels into adata.obs."
            )

        df_hit = out["by_k"][k_hit]["df"].copy()
        hit_clusters = get_all_hit_clusters(df_hit, call_by="p", p_cut=p_cut)
        hit_clusters_str = [str(x) for x in hit_clusters]

        log(
            f"[INFO] k_min={kmin}, chosen_k={k_hit}, chosen_key={chosen_key}, "
            f"n_hit_clusters={len(hit_clusters)}, hit_clusters={hit_clusters_str}"
        )

        tmp = pd.DataFrame({
            "barcode": obs.loc[pv_mask, "barcode"].astype(str).values,
            "k_min": kmin,
            "chosen_k": k_hit,
            "chosen_key": chosen_key,
            "cluster": adata.obs.loc[pv_mask, chosen_key].astype(str).values,
        })

        tmp["is_in_hit_cluster"] = tmp["cluster"].astype(str).isin(hit_clusters_str)

        hit_records.append(tmp)

        kmin_records.append({
            "k_min": kmin,
            "chosen_k": k_hit,
            "chosen_key": chosen_key,
            "n_hit_clusters": len(hit_clusters),
            "hit_clusters": ",".join(hit_clusters_str),
        })

    cell_kmin_hit = pd.concat(hit_records, axis=0, ignore_index=True)

    cell_kmin_fp = os.path.join(outdir, "PV_cell_kmin_hit_matrix_long.tsv")
    cell_kmin_hit.to_csv(cell_kmin_fp, sep="\t", index=False)
    log(f"[INFO] Saved cell-kmin hit matrix: {cell_kmin_fp}")

    kmin_info = pd.DataFrame(kmin_records)
    kmin_info_fp = os.path.join(outdir, "PV_kmin_chosen_hit_clusters.tsv")
    kmin_info.to_csv(kmin_info_fp, sep="\t", index=False)
    log(f"[INFO] Saved kmin hit cluster info: {kmin_info_fp}")

    summary = (
        cell_kmin_hit
        .groupby("barcode", as_index=False, observed=True)
        .agg(
            hit_count=("is_in_hit_cluster", "sum"),
            observed_kmin_count=("k_min", "nunique"),
        )
    )

    summary["hit_fraction"] = summary["hit_count"] / summary["observed_kmin_count"]
    summary = summary.merge(pv_meta, on="barcode", how="left")

    summary = summary[
        [
            "barcode",
            org_col,
            donor_col,
            status_col,
            sample_col,
            "hit_count",
            "observed_kmin_count",
            "hit_fraction",
        ]
    ].copy()

    cell_summary_fp = os.path.join(outdir, "PV_cell_hit_fraction.tsv")
    summary.to_csv(cell_summary_fp, sep="\t", index=False)
    log(f"[INFO] Saved cell hit fraction summary: {cell_summary_fp}")

    return summary, cell_kmin_hit, kmin_info


def assign_stable_state(
    cell_summary: pd.DataFrame,
    outdir: str,
    org_col: str,
    stable_vulnerable_cutoff: float,
    stable_nonvulnerable_cutoff: float,
    min_observed_kmin: int,
):
    """
    Assign stable PV cell state by hit_fraction.

    stable_vulnerable:
        hit_fraction >= stable_vulnerable_cutoff

    stable_nonvulnerable:
        hit_fraction <= stable_nonvulnerable_cutoff

    intermediate:
        everything between.
    """

    df = cell_summary.copy()

    df["stable_state"] = "intermediate"

    df.loc[
        (df["hit_fraction"] >= stable_vulnerable_cutoff)
        & (df["observed_kmin_count"] >= min_observed_kmin),
        "stable_state"
    ] = "stable_vulnerable"

    df.loc[
        (df["hit_fraction"] <= stable_nonvulnerable_cutoff)
        & (df["observed_kmin_count"] >= min_observed_kmin),
        "stable_state"
    ] = "stable_nonvulnerable"

    # Important: convert categorical columns to str to avoid pandas categorical groupby bug
    df["stable_state"] = df["stable_state"].astype(str)
    df[org_col] = df[org_col].astype(str)
    df["barcode"] = df["barcode"].astype(str)

    out_fp = os.path.join(outdir, "PV_cell_stable_state.tsv")
    df.to_csv(out_fp, sep="\t", index=False)
    log(f"[INFO] Saved PV cell stable state table: {out_fp}")

    for state in ["stable_vulnerable", "stable_nonvulnerable", "intermediate"]:
        barcodes = df.loc[df["stable_state"] == state, "barcode"].astype(str).tolist()
        fp = os.path.join(outdir, f"PV_{state}_barcodes.txt")

        with open(fp, "w") as f:
            for bc in barcodes:
                f.write(bc + "\n")

        log(f"[INFO] Saved {state} barcodes: {fp} n={len(barcodes)}")

    # Composition by original annotation
    comp = (
        df.groupby(["stable_state", org_col], as_index=False, observed=True)
        .agg(n_cells=("barcode", "count"))
    )

    comp["stable_state"] = comp["stable_state"].astype(str)
    comp[org_col] = comp[org_col].astype(str)

    comp["state_total"] = comp.groupby("stable_state", observed=True)["n_cells"].transform("sum")
    comp["fraction_in_state"] = comp["n_cells"] / comp["state_total"]
    comp["percent_in_state"] = (100 * comp["fraction_in_state"]).round(2)

    comp = comp.sort_values(
        ["stable_state", "n_cells"],
        ascending=[True, False]
    )

    comp_fp = os.path.join(outdir, "PV_stable_state_composition_by_Org_celltype.tsv")
    comp.to_csv(comp_fp, sep="\t", index=False)
    log(f"[INFO] Saved stable state composition: {comp_fp}")

    return df, comp


def summarize_by_original_subtype(
    cell_state_df: pd.DataFrame,
    outdir: str,
    org_col: str,
):
    """
    Summarize hit_fraction and stable state composition for each original Org_celltype.
    """

    df = cell_state_df.copy()

    # Important: convert categorical columns to str to avoid pandas categorical groupby bug
    df["stable_state"] = df["stable_state"].astype(str)
    df[org_col] = df[org_col].astype(str)
    df["barcode"] = df["barcode"].astype(str)

    base = (
        df.groupby(org_col, as_index=False, observed=True)
        .agg(
            n_cells=("barcode", "count"),
            mean_hit_fraction=("hit_fraction", "mean"),
            median_hit_fraction=("hit_fraction", "median"),
            max_hit_fraction=("hit_fraction", "max"),
        )
    )

    state_counts = (
        df.groupby([org_col, "stable_state"], as_index=False, observed=True)
        .agg(n_state=("barcode", "count"))
    )

    state_wide = state_counts.pivot(
        index=org_col,
        columns="stable_state",
        values="n_state"
    ).fillna(0).reset_index()

    for col in ["stable_vulnerable", "stable_nonvulnerable", "intermediate"]:
        if col not in state_wide.columns:
            state_wide[col] = 0

    out = base.merge(state_wide, on=org_col, how="left")

    out["frac_stable_vulnerable"] = out["stable_vulnerable"] / out["n_cells"]
    out["frac_stable_nonvulnerable"] = out["stable_nonvulnerable"] / out["n_cells"]
    out["frac_intermediate"] = out["intermediate"] / out["n_cells"]

    out = out.sort_values(
        ["mean_hit_fraction", "frac_stable_vulnerable"],
        ascending=False
    )

    fp = os.path.join(outdir, "PV_original_subtype_cellstate_summary.tsv")
    out.to_csv(fp, sep="\t", index=False)
    log(f"[INFO] Saved original subtype summary: {fp}")

    return out


def plot_hit_fraction_histogram(cell_state_df: pd.DataFrame, outdir: str):
    fig, ax = plt.subplots(figsize=(6, 4))
    ax.hist(cell_state_df["hit_fraction"], bins=30)
    ax.set_xlabel("Cell-level hit fraction across k_min")
    ax.set_ylabel("Number of PV cells")
    ax.set_title("PV cell vulnerability stability")
    plt.tight_layout()

    fp = os.path.join(outdir, "PV_cell_hit_fraction_histogram.png")
    plt.savefig(fp, dpi=300, bbox_inches="tight")
    plt.close()

    log(f"[INFO] Saved hit fraction histogram: {fp}")


def plot_umap_state(adata, cell_state_df: pd.DataFrame, outdir: str, org_col: str):
    """
    Plot In UMAP, but only PV cells are colored by stable state / hit_fraction.
    """

    state_map = cell_state_df.set_index("barcode")["stable_state"].to_dict()
    hit_map = cell_state_df.set_index("barcode")["hit_fraction"].to_dict()

    adata_plot = adata.copy()
    adata_plot.obs["pv_stable_state"] = adata_plot.obs_names.astype(str).map(state_map)
    adata_plot.obs["pv_hit_fraction"] = adata_plot.obs_names.astype(str).map(hit_map)

    pv_mask = adata_plot.obs["pv_stable_state"].notna()
    adata_pv_plot = adata_plot[pv_mask].copy()

    if "X_umap" not in adata_pv_plot.obsm.keys():
        log("[WARN] X_umap not found. Skip UMAP plotting.")
        return

    # Ensure categorical string
    adata_pv_plot.obs["pv_stable_state"] = adata_pv_plot.obs["pv_stable_state"].astype(str).astype("category")
    if org_col in adata_pv_plot.obs.columns:
        adata_pv_plot.obs[org_col] = adata_pv_plot.obs[org_col].astype(str).astype("category")

    sc.pl.umap(
        adata_pv_plot,
        color=["pv_stable_state"],
        frameon=False,
        show=False,
        title="PV stable state"
    )
    fp1 = os.path.join(outdir, "PV_umap_stable_state.png")
    plt.savefig(fp1, dpi=300, bbox_inches="tight")
    plt.close()
    log(f"[INFO] Saved UMAP stable state: {fp1}")

    sc.pl.umap(
        adata_pv_plot,
        color=["pv_hit_fraction"],
        frameon=False,
        show=False,
        title="PV cell hit fraction"
    )
    fp2 = os.path.join(outdir, "PV_umap_hit_fraction.png")
    plt.savefig(fp2, dpi=300, bbox_inches="tight")
    plt.close()
    log(f"[INFO] Saved UMAP hit fraction: {fp2}")

    if org_col in adata_pv_plot.obs.columns:
        sc.pl.umap(
            adata_pv_plot,
            color=[org_col],
            frameon=False,
            show=False,
            title="PV Org_celltype"
        )
        fp3 = os.path.join(outdir, "PV_umap_Org_celltype.png")
        plt.savefig(fp3, dpi=300, bbox_inches="tight")
        plt.close()
        log(f"[INFO] Saved UMAP Org_celltype: {fp3}")


def main():
    parser = argparse.ArgumentParser(
        description="Identify barcode-level stable vulnerable/non-vulnerable PV cells from existing In_analysis_input.h5ad."
    )

    parser.add_argument("--in-h5ad", required=True, help="Existing In_analysis_input.h5ad")
    parser.add_argument("--outdir", required=True, help="Output directory")
    parser.add_argument("--vglm-dir", required=True, help="Directory containing vulnScan_glm.py")

    parser.add_argument("--org-col", default="Org_celltype")
    parser.add_argument("--donor-col", default="Donor_ID")
    parser.add_argument("--status-col", default="SampleStatus")
    parser.add_argument("--sample-col", default="Sample_ID")
    parser.add_argument("--control-label", default="control")
    parser.add_argument("--pv-prefix", default="In.PV.")

    parser.add_argument("--use-rep", default="X_pca_harmony")

    parser.add_argument("--k-min-start", type=int, default=2)
    parser.add_argument("--k-min-end", type=int, default=24)
    parser.add_argument("--k-max", type=int, default=32)
    parser.add_argument("--p-cut", type=float, default=0.05)
    parser.add_argument("--random-state", type=int, default=666)

    parser.add_argument(
        "--covariate-cols",
        nargs="*",
        default=["Sex", "DevoStage"],
        help="Covariate columns passed to vulnScan_glm"
    )

    parser.add_argument(
        "--stable-vulnerable-cutoff",
        type=float,
        default=0.8,
        help="hit_fraction >= this value is stable vulnerable"
    )

    parser.add_argument(
        "--stable-nonvulnerable-cutoff",
        type=float,
        default=0.1,
        help="hit_fraction <= this value is stable non-vulnerable"
    )

    parser.add_argument(
        "--min-observed-kmin",
        type=int,
        default=10,
        help="minimum observed k_min count required for stable state assignment"
    )

    args = parser.parse_args()

    os.makedirs(args.outdir, exist_ok=True)

    sys.path.append(args.vglm_dir)
    import vulnScan_glm as vglm

    log(f"[INFO] Reading In analysis object: {args.in_h5ad}")
    adata = sc.read_h5ad(args.in_h5ad)
    log(f"[INFO] adata shape: {adata.shape}")

    needed = [
        args.org_col,
        args.donor_col,
        args.status_col,
        args.sample_col,
    ]

    missing = [c for c in needed if c not in adata.obs.columns]
    if missing:
        raise ValueError(f"Missing required obs columns: {missing}")

    for cov in args.covariate_cols:
        if cov not in adata.obs.columns:
            log(f"[WARN] Covariate {cov} not found in adata.obs")

    all_results, kmin_list = run_multik_scan_on_existing_in_object(
        adata=adata,
        vglm=vglm,
        outdir=args.outdir,
        status_col=args.status_col,
        donor_col=args.donor_col,
        control_label=args.control_label,
        use_rep=args.use_rep,
        k_min_start=args.k_min_start,
        k_min_end=args.k_min_end,
        k_max=args.k_max,
        p_cut=args.p_cut,
        covariate_cols=args.covariate_cols,
        random_state=args.random_state,
    )

    cell_summary, cell_kmin_hit, kmin_info = calculate_pv_cell_hit_fraction(
        adata=adata,
        all_results=all_results,
        kmin_list=kmin_list,
        outdir=args.outdir,
        org_col=args.org_col,
        donor_col=args.donor_col,
        status_col=args.status_col,
        sample_col=args.sample_col,
        pv_prefix=args.pv_prefix,
        p_cut=args.p_cut,
    )

    cell_state_df, comp = assign_stable_state(
        cell_summary=cell_summary,
        outdir=args.outdir,
        org_col=args.org_col,
        stable_vulnerable_cutoff=args.stable_vulnerable_cutoff,
        stable_nonvulnerable_cutoff=args.stable_nonvulnerable_cutoff,
        min_observed_kmin=args.min_observed_kmin,
    )

    summarize_by_original_subtype(
        cell_state_df=cell_state_df,
        outdir=args.outdir,
        org_col=args.org_col,
    )

    plot_hit_fraction_histogram(cell_state_df, args.outdir)
    plot_umap_state(adata, cell_state_df, args.outdir, args.org_col)

    # Save final In h5ad with PV cell state annotation.
    state_map = cell_state_df.set_index("barcode")["stable_state"].to_dict()
    hit_map = cell_state_df.set_index("barcode")["hit_fraction"].to_dict()

    adata.obs["pv_stable_state"] = adata.obs_names.astype(str).map(state_map)
    adata.obs["pv_hit_fraction"] = adata.obs_names.astype(str).map(hit_map)

    final_fp = os.path.join(args.outdir, "In_analysis_with_PV_cellstate_stability.h5ad")
    adata.write(final_fp)
    log(f"[INFO] Saved final annotated In h5ad: {final_fp}")

    log("[INFO] ALL DONE.")


if __name__ == "__main__":
    main()