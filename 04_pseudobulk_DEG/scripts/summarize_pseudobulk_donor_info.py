#!/usr/bin/env python3

import argparse
import os
import json
import numpy as np
import pandas as pd


def parse_args():
    parser = argparse.ArgumentParser(
        description="Summarize donor information after pseudo-bulk construction."
    )

    parser.add_argument("--meta", required=True)
    parser.add_argument("--counts", required=True)
    parser.add_argument("--out-summary", required=True)
    parser.add_argument("--out-donor-detail", required=True)
    parser.add_argument("--out-txt", required=True)

    parser.add_argument("--rep", required=True)
    parser.add_argument("--contrast", required=True)

    parser.add_argument("--sample-col", default="Sample_ID")
    parser.add_argument("--group-col", default="group")
    parser.add_argument("--target-group", required=True)
    parser.add_argument("--reference-group", required=True)

    parser.add_argument("--min-cells", type=int, default=10)

    return parser.parse_args()


def detect_cell_count_col(meta):
    candidates = [
        "n_cells",
        "cell_count",
        "n_cell",
        "cells",
        "nCells",
        "N_cells",
        "num_cells",
    ]

    for c in candidates:
        if c in meta.columns:
            return c

    return None


def read_counts_header(counts_fp):
    if not os.path.exists(counts_fp):
        return [], 0

    try:
        header = pd.read_csv(counts_fp, sep="\t", nrows=0)
        cols = list(header.columns)
    except Exception:
        return [], 0

    if len(cols) == 0:
        return [], 0

    # Usually first column is gene ID / unnamed index.
    sample_cols = cols[1:] if len(cols) > 1 else []
    return sample_cols, len(sample_cols)


def main():
    args = parse_args()

    os.makedirs(os.path.dirname(args.out_summary), exist_ok=True)
    os.makedirs(os.path.dirname(args.out_donor_detail), exist_ok=True)
    os.makedirs(os.path.dirname(args.out_txt), exist_ok=True)

    if not os.path.exists(args.meta):
        raise FileNotFoundError(f"Meta file not found: {args.meta}")

    meta = pd.read_csv(args.meta, sep="\t")

    required_cols = [args.sample_col, args.group_col]
    missing = [c for c in required_cols if c not in meta.columns]
    if missing:
        raise ValueError(
            f"Missing columns in meta file: {missing}. "
            f"Available columns: {list(meta.columns)}"
        )

    meta[args.sample_col] = meta[args.sample_col].astype(str)
    meta[args.group_col] = meta[args.group_col].astype(str)

    cell_col = detect_cell_count_col(meta)

    if cell_col is not None:
        meta[cell_col] = pd.to_numeric(meta[cell_col], errors="coerce")
    else:
        meta["_n_cells_missing_"] = np.nan
        cell_col = "_n_cells_missing_"

    target_meta = meta[meta[args.group_col] == args.target_group].copy()
    ref_meta = meta[meta[args.group_col] == args.reference_group].copy()

    target_donors = set(target_meta[args.sample_col].dropna().astype(str))
    ref_donors = set(ref_meta[args.sample_col].dropna().astype(str))

    paired_donors = sorted(target_donors.intersection(ref_donors))
    target_only = sorted(target_donors - ref_donors)
    reference_only = sorted(ref_donors - target_donors)

    all_donors = sorted(set(meta[args.sample_col].dropna().astype(str)))

    count_sample_cols, n_count_samples = read_counts_header(args.counts)

    def group_cell_summary(df):
        if df.shape[0] == 0:
            return {
                "n_meta_rows": 0,
                "n_donors": 0,
                "n_cells_min": np.nan,
                "n_cells_median": np.nan,
                "n_cells_max": np.nan,
                "n_cells_sum": np.nan,
            }

        return {
            "n_meta_rows": int(df.shape[0]),
            "n_donors": int(df[args.sample_col].nunique()),
            "n_cells_min": float(df[cell_col].min()) if df[cell_col].notna().any() else np.nan,
            "n_cells_median": float(df[cell_col].median()) if df[cell_col].notna().any() else np.nan,
            "n_cells_max": float(df[cell_col].max()) if df[cell_col].notna().any() else np.nan,
            "n_cells_sum": float(df[cell_col].sum()) if df[cell_col].notna().any() else np.nan,
        }

    target_sum = group_cell_summary(target_meta)
    ref_sum = group_cell_summary(ref_meta)

    paired_ok = (
        len(paired_donors) > 0
        and len(target_only) == 0
        and len(reference_only) == 0
    )

    summary = {
        "rep": args.rep,
        "contrast": args.contrast,
        "min_cells_requested": args.min_cells,
        "sample_col": args.sample_col,
        "group_col": args.group_col,
        "target_group": args.target_group,
        "reference_group": args.reference_group,
        "meta_file": args.meta,
        "counts_file": args.counts,
        "meta_rows_total": int(meta.shape[0]),
        "counts_sample_columns": int(n_count_samples),
        "donors_total": int(len(all_donors)),
        "donors_target": int(len(target_donors)),
        "donors_reference": int(len(ref_donors)),
        "donors_paired": int(len(paired_donors)),
        "donors_target_only": int(len(target_only)),
        "donors_reference_only": int(len(reference_only)),
        "paired_design_ok": bool(paired_ok),

        "target_meta_rows": target_sum["n_meta_rows"],
        "target_n_cells_min": target_sum["n_cells_min"],
        "target_n_cells_median": target_sum["n_cells_median"],
        "target_n_cells_max": target_sum["n_cells_max"],
        "target_n_cells_sum": target_sum["n_cells_sum"],

        "reference_meta_rows": ref_sum["n_meta_rows"],
        "reference_n_cells_min": ref_sum["n_cells_min"],
        "reference_n_cells_median": ref_sum["n_cells_median"],
        "reference_n_cells_max": ref_sum["n_cells_max"],
        "reference_n_cells_sum": ref_sum["n_cells_sum"],

        "cell_count_column": None if cell_col == "_n_cells_missing_" else cell_col,
        "paired_donor_ids": ";".join(paired_donors),
        "target_only_donor_ids": ";".join(target_only),
        "reference_only_donor_ids": ";".join(reference_only),
    }

    summary_df = pd.DataFrame([summary])
    summary_df.to_csv(args.out_summary, sep="\t", index=False)

    detail_rows = []
    for donor in all_donors:
        donor_df = meta[meta[args.sample_col] == donor].copy()

        target_rows = donor_df[donor_df[args.group_col] == args.target_group]
        ref_rows = donor_df[donor_df[args.group_col] == args.reference_group]

        detail_rows.append({
            "rep": args.rep,
            "contrast": args.contrast,
            "Sample_ID": donor,
            "has_target": donor in target_donors,
            "has_reference": donor in ref_donors,
            "is_paired": donor in paired_donors,
            "target_meta_rows": int(target_rows.shape[0]),
            "reference_meta_rows": int(ref_rows.shape[0]),
            "target_n_cells_sum": float(target_rows[cell_col].sum()) if target_rows[cell_col].notna().any() else np.nan,
            "reference_n_cells_sum": float(ref_rows[cell_col].sum()) if ref_rows[cell_col].notna().any() else np.nan,
            "groups_present": ";".join(sorted(donor_df[args.group_col].unique())),
        })

    detail_df = pd.DataFrame(detail_rows)
    detail_df.to_csv(args.out_donor_detail, sep="\t", index=False)

    with open(args.out_txt, "w") as f:
        f.write("Pseudo-bulk donor QC summary\n")
        f.write("============================\n\n")
        f.write(f"rep: {args.rep}\n")
        f.write(f"contrast: {args.contrast}\n")
        f.write(f"min_cells_requested: {args.min_cells}\n")
        f.write(f"target_group: {args.target_group}\n")
        f.write(f"reference_group: {args.reference_group}\n\n")

        f.write(f"meta_rows_total: {meta.shape[0]}\n")
        f.write(f"counts_sample_columns: {n_count_samples}\n")
        f.write(f"donors_total: {len(all_donors)}\n")
        f.write(f"donors_target: {len(target_donors)}\n")
        f.write(f"donors_reference: {len(ref_donors)}\n")
        f.write(f"donors_paired: {len(paired_donors)}\n")
        f.write(f"donors_target_only: {len(target_only)}\n")
        f.write(f"donors_reference_only: {len(reference_only)}\n")
        f.write(f"paired_design_ok: {paired_ok}\n\n")

        f.write("Target cell count summary:\n")
        f.write(json.dumps(target_sum, indent=2, ensure_ascii=False))
        f.write("\n\nReference cell count summary:\n")
        f.write(json.dumps(ref_sum, indent=2, ensure_ascii=False))
        f.write("\n\n")

        f.write("Paired donors:\n")
        f.write("\n".join(paired_donors) + "\n\n")

        if len(target_only) > 0:
            f.write("Target-only donors:\n")
            f.write("\n".join(target_only) + "\n\n")

        if len(reference_only) > 0:
            f.write("Reference-only donors:\n")
            f.write("\n".join(reference_only) + "\n\n")

    print(f"[DONE] summary: {args.out_summary}")
    print(f"[DONE] donor detail: {args.out_donor_detail}")
    print(f"[DONE] text report: {args.out_txt}")


if __name__ == "__main__":
    main()
