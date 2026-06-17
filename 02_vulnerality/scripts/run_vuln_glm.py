#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import argparse
import importlib
import importlib.util
import json
import sys
from pathlib import Path

import matplotlib as mpl
mpl.use("Agg")
import matplotlib.pyplot as plt
import scanpy as sc


def parse_args():
    p = argparse.ArgumentParser(
        description="Run annotation-based vulnerable neuron GLM analysis on one h5ad file."
    )
    p.add_argument("--input", required=True, help="Input h5ad file")
    p.add_argument("--output", required=True, help="Output CSV path")
    p.add_argument("--subset-column", default="CellType", help="obs column used to subset cells")
    p.add_argument("--subset-value", required=True, help="obs value to keep, e.g. In or Ex")
    p.add_argument("--status-col", default="SampleStatus")
    p.add_argument("--cluster-col", default="Org_celltype")
    p.add_argument("--donor-col", default="Sample_ID")
    p.add_argument("--control-label", default="control")
    p.add_argument("--direction", default="vulnerable")
    p.add_argument("--p-cut", type=float, default=0.05)
    p.add_argument("--use-fdr-in-plot", action="store_true")
    p.add_argument("--plot", action="store_true")
    p.add_argument("--random-seed", type=int, default=666)
    p.add_argument("--covariate-cols", nargs="*", default=["Sex", "DevoStage"])
    p.add_argument("--robust-cov", default="HC3")
    p.add_argument("--standardize-numeric", action="store_true")
    p.add_argument("--donor-weight-mode", default="capped")
    p.add_argument("--weight-cap", default="q75")
    p.add_argument("--strict-covariates", action="store_true")
    p.add_argument("--bounds-scope", default="used")
    p.add_argument("--cat-agg", default="mode")
    p.add_argument("--verbose", type=int, default=1)
    p.add_argument("--progress", action="store_true")
    p.add_argument("--save-full", action="store_true", help="Save the full dataframe instead of only key columns")
    p.add_argument("--summary-json", help="Optional path to write a small run summary JSON")
    p.add_argument(
        "--vglm-path",
        help=(
            "Path to vulnScan_glm.py or vuln_glm.py, or a directory containing one of them."
        ),
    )
    return p.parse_args()


def load_vglm(vglm_path=None):
    candidate_files = []

    if vglm_path:
        p = Path(vglm_path).resolve()
        if p.is_file():
            sys.path.insert(0, str(p.parent))
            candidate_files.append(p)
        elif p.is_dir():
            sys.path.insert(0, str(p))
            candidate_files.extend([
                p / "vulnScan_glm.py",
                p / "vuln_glm.py",
            ])
        else:
            raise FileNotFoundError(f"The provided --vglm-path does not exist: {vglm_path}")

    for mod_name in ["vulnScan_glm", "vuln_glm"]:
        try:
            return importlib.import_module(mod_name)
        except ModuleNotFoundError:
            pass

    for fp in candidate_files:
        if fp.exists():
            mod_name = fp.stem
            spec = importlib.util.spec_from_file_location(mod_name, str(fp))
            if spec is None or spec.loader is None:
                continue
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            return module

    raise ModuleNotFoundError(
        "Could not load vulnScan_glm.py or vuln_glm.py. Please check --vglm-path."
    )


def main():
    args = parse_args()

    out_csv = Path(args.output)
    out_csv.parent.mkdir(parents=True, exist_ok=True)

    mpl.rcdefaults()
    plt.style.use("default")

    adata = sc.read_h5ad(args.input)
    if args.subset_column not in adata.obs.columns:
        raise ValueError(f"Column {args.subset_column!r} not found in adata.obs")

    mask = adata.obs[args.subset_column].astype(str) == str(args.subset_value)
    if int(mask.sum()) == 0:
        raise ValueError(
            f"No cells found for {args.subset_column} == {args.subset_value!r} in {args.input}"
        )
    adata_sub = adata[mask].copy()

    vglm = load_vglm(args.vglm_path)

    df = vglm.vulnerable_neurons_analysis_v6_6_5(
        adata=adata_sub,
        status_col=args.status_col,
        cluster_col=args.cluster_col,
        donor_col=args.donor_col,
        control_label=args.control_label,
        direction=args.direction,
        p_cut=args.p_cut,
        use_fdr_in_plot=args.use_fdr_in_plot,
        plot=args.plot,
        random_seed=args.random_seed,
        covariate_cols=args.covariate_cols,
        robust_cov=args.robust_cov,
        standardize_numeric=args.standardize_numeric,
        donor_weight_mode=args.donor_weight_mode,
        weight_cap=args.weight_cap,
        strict_covariates=args.strict_covariates,
        bounds_scope=args.bounds_scope,
        cat_agg=args.cat_agg,
        verbose=args.verbose,
        progress=args.progress,
    )

    if args.save_full:
        out_df = df.copy()
    else:
        required = ["cluster", "Donor_P", "Donor_log2_OR"]
        missing = [c for c in required if c not in df.columns]
        if missing:
            raise ValueError(f"Missing required columns in vuln GLM output: {missing}")
        out_df = df[required].copy()

    out_df.to_csv(out_csv, index=False)

    if args.summary_json:
        summary = {
            "input": str(args.input),
            "output": str(out_csv),
            "subset_column": args.subset_column,
            "subset_value": args.subset_value,
            "n_cells_subset": int(adata_sub.n_obs),
            "n_clusters_tested": int(df.shape[0]),
            "n_significant_vulnerable": None,
            "covariate_cols": list(args.covariate_cols),
            "vglm_path": args.vglm_path,
        }
        if {"Donor_P", "Donor_log2_OR"}.issubset(df.columns):
            summary["n_significant_vulnerable"] = int(
                ((df["Donor_P"] < args.p_cut) & (df["Donor_log2_OR"] > 0)).sum()
            )

        summary_path = Path(args.summary_json)
        summary_path.parent.mkdir(parents=True, exist_ok=True)
        with open(summary_path, "w", encoding="utf-8") as f:
            json.dump(summary, f, ensure_ascii=False, indent=2)

    print(f"[OK] saved: {out_csv}")


if __name__ == "__main__":
    main()
