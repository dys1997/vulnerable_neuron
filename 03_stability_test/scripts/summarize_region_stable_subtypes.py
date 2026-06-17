#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import argparse
import pandas as pd
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


REGION_MAP = {
    "FTLD_PFC_Ctrl_Concat_QC_harmony_filted": "PFC",
    "SALS_PFC_control_concat_QC_harmony": "PFC",
    "FTLD_MCX_Control_Concat_QC_harmony_filted": "MCX",
    "SALS_MCX_control_concat_QC_harmony": "MCX"
}


def load_one_summary(tsv_file, rep_name):
    df = pd.read_csv(tsv_file, sep="\t")

    need_cols = ["subtype", "k_min", "capture_rate_any_hit"]
    miss = [c for c in need_cols if c not in df.columns]
    if miss:
        raise ValueError(f"{tsv_file} 缺少必要列: {miss}")

    df["k_min"] = pd.to_numeric(df["k_min"], errors="coerce")
    df["capture_rate_any_hit"] = pd.to_numeric(
        df["capture_rate_any_hit"], errors="coerce"
    ).fillna(0)

    df["rep"] = rep_name
    df["region"] = REGION_MAP[rep_name]
    return df


def summarize_one_rep(df, capture_threshold=50.0, min_prop=0.5, max_threshold=70.0):
    """
    对单个rep内每个subtype做汇总，并判断该 subtype 在该rep中是否稳定出现
    """
    out = []

    for subtype, subdf in df.groupby("subtype"):
        n_k = subdf["k_min"].nunique()
        n_hit = (subdf["capture_rate_any_hit"] >= capture_threshold).sum()
        prop_hit = n_hit / n_k if n_k > 0 else 0.0
        max_capture = subdf["capture_rate_any_hit"].max()
        mean_capture = subdf["capture_rate_any_hit"].mean()
        median_capture = subdf["capture_rate_any_hit"].median()
        min_capture = subdf["capture_rate_any_hit"].min()

        stable_in_rep = (prop_hit >= min_prop) and (max_capture >= max_threshold)

        out.append({
            "rep": subdf["rep"].iloc[0],
            "region": subdf["region"].iloc[0],
            "subtype": subtype,
            "n_kmin": n_k,
            "n_kmin_ge_capture_threshold": int(n_hit),
            "prop_kmin_ge_capture_threshold": prop_hit,
            "max_capture": max_capture,
            "mean_capture": mean_capture,
            "median_capture": median_capture,
            "min_capture": min_capture,
            "stable_in_rep": stable_in_rep
        })

    return pd.DataFrame(out)


def collect_prefix_summary(outdir_base, reps, prefix,
                           capture_threshold=50.0,
                           min_prop=0.5,
                           max_threshold=70.0):
    dfs = []

    for rep in reps:
        fp = os.path.join(
            outdir_base,
            rep,
            f"{prefix}_all_subtypes_vulnerability_kmin_summary.tsv"
        )
        if not os.path.exists(fp):
            print(f"[warn] file not found: {fp}", flush=True)
            continue

        raw = load_one_summary(fp, rep)
        one = summarize_one_rep(
            raw,
            capture_threshold=capture_threshold,
            min_prop=min_prop,
            max_threshold=max_threshold
        )
        dfs.append(one)

    if not dfs:
        return pd.DataFrame()

    return pd.concat(dfs, ignore_index=True)


def region_level_call(rep_summary_df):
    """
    基于两个重复，判定 subtype 在 PFC / MCX 是否稳定出现
    """
    if rep_summary_df.empty:
        return pd.DataFrame()

    out = []

    for region in ["MCX", "PFC"]:
        reg_df = rep_summary_df[rep_summary_df["region"] == region].copy()
        if reg_df.empty:
            continue

        for subtype, subdf in reg_df.groupby("subtype"):
            reps_present = sorted(subdf["rep"].unique().tolist())
            n_reps_present = len(reps_present)
            n_reps_stable = int(subdf["stable_in_rep"].sum())

            region_stable = (n_reps_present == 2) and (n_reps_stable == 2)
            # region_stable = (n_reps_stable >= 1)


            out.append({
                "region": region,
                "subtype": subtype,
                "reps_present": ",".join(reps_present),
                "n_reps_present": n_reps_present,
                "n_reps_stable": n_reps_stable,
                "region_stable": region_stable,
                "mean_of_mean_capture": subdf["mean_capture"].mean(),
                "mean_of_median_capture": subdf["median_capture"].mean(),
                "mean_of_max_capture": subdf["max_capture"].mean(),
                "min_of_max_capture": subdf["max_capture"].min(),
                "mean_prop_kmin_ge_threshold": subdf["prop_kmin_ge_capture_threshold"].mean(),
                "min_prop_kmin_ge_threshold": subdf["prop_kmin_ge_capture_threshold"].min()
            })

    return pd.DataFrame(out)


def merge_cross_region(region_df):
    """
    把 MCX / PFC 结果合并，给出：
    - MCX stable only
    - PFC stable only
    - Cross-region stable
    """
    if region_df.empty:
        return pd.DataFrame()

    mcx = region_df[region_df["region"] == "MCX"].copy()
    pfc = region_df[region_df["region"] == "PFC"].copy()

    mcx = mcx.rename(columns={
        "region_stable": "MCX_stable",
        "mean_of_mean_capture": "MCX_mean_of_mean_capture",
        "mean_of_median_capture": "MCX_mean_of_median_capture",
        "mean_of_max_capture": "MCX_mean_of_max_capture",
        "min_of_max_capture": "MCX_min_of_max_capture",
        "mean_prop_kmin_ge_threshold": "MCX_mean_prop_kmin_ge_threshold",
        "min_prop_kmin_ge_threshold": "MCX_min_prop_kmin_ge_threshold",
        "reps_present": "MCX_reps_present",
        "n_reps_present": "MCX_n_reps_present",
        "n_reps_stable": "MCX_n_reps_stable"
    }).drop(columns=["region"])

    pfc = pfc.rename(columns={
        "region_stable": "PFC_stable",
        "mean_of_mean_capture": "PFC_mean_of_mean_capture",
        "mean_of_median_capture": "PFC_mean_of_median_capture",
        "mean_of_max_capture": "PFC_mean_of_max_capture",
        "min_of_max_capture": "PFC_min_of_max_capture",
        "mean_prop_kmin_ge_threshold": "PFC_mean_prop_kmin_ge_threshold",
        "min_prop_kmin_ge_threshold": "PFC_min_prop_kmin_ge_threshold",
        "reps_present": "PFC_reps_present",
        "n_reps_present": "PFC_n_reps_present",
        "n_reps_stable": "PFC_n_reps_stable"
    }).drop(columns=["region"])

    merged = pd.merge(mcx, pfc, on="subtype", how="outer")

    for col in ["MCX_stable", "PFC_stable"]:
        if col in merged.columns:
            merged[col] = merged[col].fillna(False)

    merged["stable_class"] = "not_stable"
    merged.loc[(merged["MCX_stable"]) & (~merged["PFC_stable"]), "stable_class"] = "MCX_specific_stable"
    merged.loc[(~merged["MCX_stable"]) & (merged["PFC_stable"]), "stable_class"] = "PFC_specific_stable"
    merged.loc[(merged["MCX_stable"]) & (merged["PFC_stable"]), "stable_class"] = "Cross_region_stable"

    merged = merged.sort_values(
        by=["stable_class", "subtype"],
        ascending=[True, True]
    ).reset_index(drop=True)

    return merged


def write_txt_report(merged_df, out_txt, prefix,
                     capture_threshold, min_prop, max_threshold):
    with open(out_txt, "w", encoding="utf-8") as f:
        f.write(f"Stable subtype summary for {prefix}\n")
        f.write("=" * 70 + "\n\n")

        f.write("Criterion for stable detection within one replicate:\n")
        f.write(f"  1) proportion of k_min with capture_rate_any_hit >= {capture_threshold} >= {min_prop}\n")
        f.write(f"  2) max_capture >= {max_threshold}\n\n")

        f.write("Criterion for region-level stability:\n")
        f.write("  subtype must satisfy the replicate-level criterion in both replicates of the same region\n\n")

        if merged_df.empty:
            f.write("No result.\n")
            return

        for cls in ["MCX_specific_stable", "PFC_specific_stable", "Cross_region_stable"]:
            sub = merged_df[merged_df["stable_class"] == cls].copy()
            f.write(f"{cls}\n")
            f.write("-" * 70 + "\n")
            if sub.empty:
                f.write("None\n\n")
                continue

            for _, row in sub.iterrows():
                f.write(f"{row['subtype']}\n")
            f.write("\n")


def plot_region_stable_heatmap(merged_df, out_png, prefix):
    """
    画稳定性总览热图：
    行是 subtype，列是 MCX/PFC
    值：0=not stable, 1=stable
    """
    if merged_df.empty:
        return

    plot_df = merged_df.copy()
    plot_df["MCX_stable_num"] = plot_df["MCX_stable"].fillna(False).astype(int)
    plot_df["PFC_stable_num"] = plot_df["PFC_stable"].fillna(False).astype(int)

    mat = plot_df.set_index("subtype")[["MCX_stable_num", "PFC_stable_num"]].copy()

    # 排序：Cross > MCX-specific > PFC-specific > not stable
    class_order = {
        "Cross_region_stable": 0,
        "MCX_specific_stable": 1,
        "PFC_specific_stable": 2,
        "not_stable": 3
    }
    plot_df["class_order"] = plot_df["stable_class"].map(class_order).fillna(9)
    ordered_subtypes = plot_df.sort_values(
        by=["class_order", "subtype"]
    )["subtype"].tolist()
    mat = mat.loc[ordered_subtypes]

    fig_h = max(4, 0.38 * mat.shape[0])
    fig, ax = plt.subplots(figsize=(4.8, fig_h))

    im = ax.imshow(mat.values, aspect="auto", interpolation="nearest", vmin=0, vmax=1)

    ax.set_xticks(range(mat.shape[1]))
    ax.set_xticklabels(["MCX", "PFC"])
    ax.set_yticks(range(mat.shape[0]))
    ax.set_yticklabels(mat.index)

    ax.set_title(f"{prefix} stable subtype overview")
    ax.set_xlabel("Region")
    ax.set_ylabel("Subtype")

    # 标数字
    for i in range(mat.shape[0]):
        for j in range(mat.shape[1]):
            val = int(mat.iloc[i, j])
            ax.text(j, i, str(val), ha="center", va="center", fontsize=8)

    cbar = plt.colorbar(im, ax=ax)
    cbar.set_label("Stable in region (0/1)")

    plt.tight_layout()
    plt.savefig(out_png, dpi=300, bbox_inches="tight")
    plt.close()


def plot_region_stable_bubble(region_df, out_png, prefix):
    """
    画气泡图：
    x = region
    y = subtype
    size = mean_of_mean_capture
    color = min_of_max_capture
    仅对 region_stable=True 的 subtype 作图
    """
    if region_df.empty:
        return

    plot_df = region_df[region_df["region_stable"] == True].copy()
    if plot_df.empty:
        return

    region_order = ["MCX", "PFC"]
    plot_df["region"] = pd.Categorical(plot_df["region"], categories=region_order, ordered=True)
    plot_df = plot_df.sort_values(["region", "mean_of_mean_capture"], ascending=[True, False])

    subtypes = sorted(plot_df["subtype"].unique().tolist())
    y_map = {s: i for i, s in enumerate(subtypes)}
    x_map = {"MCX": 0, "PFC": 1}

    x = plot_df["region"].map(x_map).values
    y = plot_df["subtype"].map(y_map).values

    sizes = plot_df["mean_of_mean_capture"].fillna(0).values * 8
    colors = plot_df["min_of_max_capture"].fillna(0).values

    fig_h = max(4, 0.5 * len(subtypes))
    fig, ax = plt.subplots(figsize=(6, fig_h))

    sc = ax.scatter(
        x, y,
        s=sizes,
        c=colors,
        alpha=0.85
    )

    ax.set_xticks([0, 1])
    ax.set_xticklabels(region_order)
    ax.set_yticks(range(len(subtypes)))
    ax.set_yticklabels(subtypes)

    ax.set_xlabel("Region")
    ax.set_ylabel("Subtype")
    ax.set_title(f"{prefix} stable subtype strength")

    cbar = plt.colorbar(sc, ax=ax)
    cbar.set_label("Min of max capture")

    plt.tight_layout()
    plt.savefig(out_png, dpi=300, bbox_inches="tight")
    plt.close()


def run_for_prefix(outdir_base, reps, prefix, outdir,
                   capture_threshold=50.0,
                   min_prop=0.5,
                   max_threshold=70.0):
    rep_summary = collect_prefix_summary(
        outdir_base=outdir_base,
        reps=reps,
        prefix=prefix,
        capture_threshold=capture_threshold,
        min_prop=min_prop,
        max_threshold=max_threshold
    )

    region_summary = region_level_call(rep_summary)
    merged = merge_cross_region(region_summary)

    rep_fp = os.path.join(outdir, f"{prefix}_rep_level_summary.tsv")
    region_fp = os.path.join(outdir, f"{prefix}_region_level_summary.tsv")
    merged_fp = os.path.join(outdir, f"{prefix}_stable_classification.tsv")

    rep_summary.to_csv(rep_fp, sep="\t", index=False)
    region_summary.to_csv(region_fp, sep="\t", index=False)
    merged.to_csv(merged_fp, sep="\t", index=False)

    # 各类单独导出
    for cls, name in [
        ("MCX_specific_stable", f"MCX_stable_{prefix}.tsv"),
        ("PFC_specific_stable", f"PFC_stable_{prefix}.tsv"),
        ("Cross_region_stable", f"Cross_region_stable_{prefix}.tsv")
    ]:
        sub = merged[merged["stable_class"] == cls].copy()
        sub.to_csv(os.path.join(outdir, name), sep="\t", index=False)

    write_txt_report(
        merged_df=merged,
        out_txt=os.path.join(outdir, f"{prefix}_stable_summary.txt"),
        prefix=prefix,
        capture_threshold=capture_threshold,
        min_prop=min_prop,
        max_threshold=max_threshold
    )

    # 画图
    plot_region_stable_heatmap(
        merged_df=merged,
        out_png=os.path.join(outdir, f"{prefix}_region_stable_heatmap.png"),
        prefix=prefix
    )

    plot_region_stable_bubble(
        region_df=region_summary,
        out_png=os.path.join(outdir, f"{prefix}_region_stable_bubble.png"),
        prefix=prefix
    )

    print(f"[done] {prefix} summary saved.", flush=True)


def main():
    parser = argparse.ArgumentParser(
        description="Summarize region-stable vulnerable subtypes from four datasets."
    )
    parser.add_argument(
        "--outdir-base",
        required=True,
        help="Base directory containing rep subfolders"
    )
    parser.add_argument(
        "--outdir",
        required=True,
        help="Directory to save final summary files"
    )
    parser.add_argument(
        "--reps",
        nargs="+",
        default=[
            "FTLD_PFC_Ctrl_Concat_QC_harmony_filted",
            "FTLD_MCX_Control_Concat_QC_harmony_filted",
            "SALS_PFC_control_concat_QC_harmony",
            "SALS_MCX_control_concat_QC_harmony"
        ],
        help="Dataset folder names"
    )
    parser.add_argument(
        "--capture-threshold",
        type=float,
        default=50.0,
        help="capture threshold used to count stable k_min"
    )
    parser.add_argument(
        "--min-prop",
        type=float,
        default=0.5,
        help="minimum proportion of k_min reaching capture threshold"
    )
    parser.add_argument(
        "--max-threshold",
        type=float,
        default=70.0,
        help="minimum max_capture within one replicate"
    )
    args = parser.parse_args()

    os.makedirs(args.outdir, exist_ok=True)

    run_for_prefix(
        outdir_base=args.outdir_base,
        reps=args.reps,
        prefix="In",
        outdir=args.outdir,
        capture_threshold=args.capture_threshold,
        min_prop=args.min_prop,
        max_threshold=args.max_threshold
    )

    run_for_prefix(
        outdir_base=args.outdir_base,
        reps=args.reps,
        prefix="Ex",
        outdir=args.outdir,
        capture_threshold=args.capture_threshold,
        min_prop=args.min_prop,
        max_threshold=args.max_threshold
    )

    print(f"[all done] outputs saved to: {args.outdir}", flush=True)


if __name__ == "__main__":
    main()