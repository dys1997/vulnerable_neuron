# #!/usr/bin/env python3
# # -*- coding: utf-8 -*-

# import os
# import json
# import argparse
# from pathlib import Path

# import numpy as np
# import pandas as pd
# import scanpy as sc
# from scipy import sparse


# def parse_args():
#     parser = argparse.ArgumentParser(
#         description="Build pseudo-bulk count matrix from AnnData by target/reference cell-type grouping."
#     )

#     parser.add_argument("--input-h5ad", required=True, help="Input h5ad file")
#     parser.add_argument("--outdir", required=True, help="Output directory")

#     parser.add_argument("--celltype-col", default="Org_celltype", help="Column in adata.obs for cell type")
#     parser.add_argument("--sample-col", default="Sample_ID", help="Column in adata.obs for sample/donor ID")

#     parser.add_argument(
#         "--layer",
#         default="counts",
#         help="Layer to use as counts. Use 'X' to use adata.X directly. Default: counts"
#     )

#     parser.add_argument(
#         "--target-types",
#         nargs="+",
#         required=True,
#         help="Target vulnerable cell types, e.g. In.5HT3aR.CDH4_CCK In.5HT3aR.CDH4_SCGN"
#     )

#     parser.add_argument(
#         "--reference-types",
#         nargs="*",
#         default=None,
#         help="Explicit reference cell types"
#     )

#     parser.add_argument(
#         "--reference-prefix",
#         default=None,
#         help="Use all cell types starting with this prefix as reference candidates"
#     )

#     parser.add_argument(
#         "--reference-exclude",
#         nargs="*",
#         default=None,
#         help="Cell types to exclude from reference candidates"
#     )

#     parser.add_argument(
#         "--target-name",
#         default="target",
#         help="Name of target group in pseudo-bulk metadata"
#     )

#     parser.add_argument(
#         "--reference-name",
#         default="reference",
#         help="Name of reference group in pseudo-bulk metadata"
#     )

#     parser.add_argument(
#         "--paired",
#         action="store_true",
#         help="Require paired target/reference within each sample"
#     )

#     parser.add_argument(
#         "--min-cells",
#         type=int,
#         default=10,
#         help="Minimum number of cells per sample-group pseudo-bulk"
#     )

#     parser.add_argument(
#         "--analysis-name",
#         default="pseudobulk_analysis",
#         help="Analysis name used in summary outputs"
#     )

#     return parser.parse_args()


# def ensure_obs_columns(adata, cols):
#     for col in cols:
#         if col not in adata.obs.columns:
#             raise ValueError(f"Missing required column in adata.obs: {col}")


# def remove_duplicated_genes(adata):
#     if adata.var_names.isnull().any():
#         raise ValueError("adata.var_names contains NA")

#     if adata.var_names.duplicated().any():
#         print("[warn] duplicated gene names found in var_names. Keeping first occurrence.", flush=True)
#         adata = adata[:, ~adata.var_names.duplicated()].copy()
#     return adata


# def get_count_matrix(adata, layer_name):
#     if layer_name == "X":
#         X = adata.X
#         source = "adata.X"
#     else:
#         if layer_name not in adata.layers:
#             raise ValueError(
#                 f"Layer '{layer_name}' not found in adata.layers. "
#                 f"Available layers: {list(adata.layers.keys())}"
#             )
#         X = adata.layers[layer_name]
#         source = f"adata.layers['{layer_name}']"

#     if not sparse.issparse(X):
#         X = sparse.csr_matrix(X)
#     else:
#         X = X.tocsr()

#     return X, source


# def build_reference_types(all_celltypes, target_types, reference_types, reference_prefix, reference_exclude):
#     target_types = set(target_types)

#     if reference_types is not None and len(reference_types) > 0:
#         ref_types = set(reference_types)
#     else:
#         if reference_prefix is None:
#             raise ValueError(
#                 "You must provide either --reference-types or --reference-prefix."
#             )
#         ref_types = {ct for ct in all_celltypes if str(ct).startswith(reference_prefix)}

#     ref_types = ref_types - target_types

#     if reference_exclude is not None:
#         ref_types = ref_types - set(reference_exclude)

#     ref_types = sorted(ref_types)
#     return ref_types


# def annotate_groups(adata, celltype_col, target_types, ref_types, target_name, reference_name):
#     obs_ct = adata.obs[celltype_col].astype(str)

#     group = pd.Series(index=adata.obs.index, dtype="object")
#     group.loc[obs_ct.isin(target_types)] = target_name
#     group.loc[obs_ct.isin(ref_types)] = reference_name

#     keep = group.notna().values
#     adata_sub = adata[keep].copy()
#     adata_sub.obs["pb_group"] = group.loc[adata_sub.obs.index].astype(str).values

#     return adata_sub


# def filter_missing_samples(adata, sample_col):
#     keep = ~adata.obs[sample_col].isna()
#     adata = adata[keep].copy()
#     adata.obs[sample_col] = adata.obs[sample_col].astype(str)
#     return adata


# def get_paired_samples(adata, sample_col, target_name, reference_name):
#     sample_group_check = (
#         adata.obs.groupby(sample_col)["pb_group"]
#         .apply(lambda x: set(x.astype(str)))
#     )

#     paired_samples = sample_group_check[
#         sample_group_check.apply(lambda x: {target_name, reference_name}.issubset(x))
#     ].index.tolist()

#     return paired_samples


# def build_pseudobulk(adata, X, sample_col, celltype_col):
#     adata.obs["sample_group"] = (
#         adata.obs[sample_col].astype(str) + "__" + adata.obs["pb_group"].astype(str)
#     )

#     sample_groups = adata.obs["sample_group"].unique().tolist()
#     gene_names = adata.var_names.tolist()

#     pb_counts = []
#     pb_meta = []

#     obs = adata.obs.reset_index(drop=False).copy()
#     obs["_row_ix"] = np.arange(obs.shape[0])

#     for sg, subobs in obs.groupby("sample_group", sort=False):
#         idx = subobs["_row_ix"].values
#         subX = X[idx]
#         summed = np.asarray(subX.sum(axis=0)).ravel()
#         pb_counts.append(summed)

#         sample_id = subobs[sample_col].iloc[0]
#         pb_group = subobs["pb_group"].iloc[0]
#         n_cells = subobs.shape[0]

#         celltype_counts = subobs[celltype_col].astype(str).value_counts().to_dict()

#         meta_row = {
#             "pseudo_id": sg,
#             "Sample_ID": sample_id,
#             "group": pb_group,
#             "n_cells": n_cells,
#             "celltype_composition": json.dumps(celltype_counts, ensure_ascii=False)
#         }

#         # 额外记录 target 组内部各 subtype 构成
#         for ct, n in celltype_counts.items():
#             safe_ct = ct.replace("/", "_").replace(" ", "_")
#             meta_row[f"n__{safe_ct}"] = int(n)
#             meta_row[f"frac__{safe_ct}"] = float(n / n_cells) if n_cells > 0 else 0.0

#         pb_meta.append(meta_row)

#     pb_counts_df = pd.DataFrame(
#         np.vstack(pb_counts),
#         index=sample_groups,
#         columns=gene_names
#     )

#     pb_meta_df = pd.DataFrame(pb_meta).set_index("pseudo_id")
#     pb_counts_df = pb_counts_df.loc[pb_meta_df.index]

#     return pb_counts_df, pb_meta_df


# def write_summary(
#     out_txt,
#     analysis_name,
#     input_h5ad,
#     layer_used,
#     celltype_col,
#     sample_col,
#     target_types,
#     ref_types,
#     target_name,
#     reference_name,
#     paired,
#     min_cells,
#     n_cells_input,
#     n_cells_after_group_filter,
#     n_cells_after_pair_filter,
#     n_cells_after_min_filter,
#     n_samples_final,
#     pb_meta_df,
# ):
#     with open(out_txt, "w", encoding="utf-8") as f:
#         f.write(f"Pseudo-bulk summary: {analysis_name}\n")
#         f.write("=" * 80 + "\n\n")

#         f.write(f"Input h5ad: {input_h5ad}\n")
#         f.write(f"Count source: {layer_used}\n")
#         f.write(f"Cell type column: {celltype_col}\n")
#         f.write(f"Sample column: {sample_col}\n")
#         f.write(f"Paired mode: {paired}\n")
#         f.write(f"Min cells per pseudo-bulk: {min_cells}\n\n")

#         f.write("Target cell types:\n")
#         for x in target_types:
#             f.write(f"  - {x}\n")
#         f.write("\n")

#         f.write("Reference cell types:\n")
#         for x in ref_types:
#             f.write(f"  - {x}\n")
#         f.write("\n")

#         f.write("Cell filtering summary:\n")
#         f.write(f"  - input cells: {n_cells_input}\n")
#         f.write(f"  - after target/reference selection: {n_cells_after_group_filter}\n")
#         f.write(f"  - after paired filtering: {n_cells_after_pair_filter}\n")
#         f.write(f"  - after min_cells filtering: {n_cells_after_min_filter}\n\n")

#         f.write("Final pseudo-bulk summary:\n")
#         f.write(f"  - number of pseudo-bulk samples: {pb_meta_df.shape[0]}\n")
#         f.write(f"  - number of biological samples: {n_samples_final}\n\n")

#         if not pb_meta_df.empty:
#             f.write("Group counts:\n")
#             vc = pb_meta_df["group"].value_counts()
#             for g, n in vc.items():
#                 f.write(f"  - {g}: {n}\n")
#             f.write("\n")

#             f.write("n_cells by group:\n")
#             desc = pb_meta_df.groupby("group")["n_cells"].describe()
#             f.write(desc.to_string())
#             f.write("\n\n")

#             try:
#                 pivot = pb_meta_df.reset_index().pivot(
#                     index="Sample_ID", columns="group", values="n_cells"
#                 )
#                 f.write("Per-sample paired cell counts:\n")
#                 f.write(pivot.to_string())
#                 f.write("\n\n")
#             except Exception:
#                 pass


# def main():
#     args = parse_args()
#     outdir = Path(args.outdir)
#     outdir.mkdir(parents=True, exist_ok=True)

#     run_info = vars(args).copy()

#     print("[info] reading h5ad...", flush=True)
#     adata = sc.read_h5ad(args.input_h5ad)
#     n_cells_input = adata.n_obs

#     ensure_obs_columns(adata, [args.celltype_col, args.sample_col])
#     adata = remove_duplicated_genes(adata)

#     X_all, layer_used = get_count_matrix(adata, args.layer)

#     all_celltypes = sorted(adata.obs[args.celltype_col].astype(str).unique().tolist())
#     ref_types = build_reference_types(
#         all_celltypes=all_celltypes,
#         target_types=args.target_types,
#         reference_types=args.reference_types,
#         reference_prefix=args.reference_prefix,
#         reference_exclude=args.reference_exclude,
#     )

#     print(f"[info] target types: {len(args.target_types)}", flush=True)
#     print(f"[info] reference types: {len(ref_types)}", flush=True)

#     adata_sub = annotate_groups(
#         adata=adata,
#         celltype_col=args.celltype_col,
#         target_types=set(args.target_types),
#         ref_types=set(ref_types),
#         target_name=args.target_name,
#         reference_name=args.reference_name,
#     )

#     n_cells_after_group_filter = adata_sub.n_obs
#     adata_sub = filter_missing_samples(adata_sub, args.sample_col)

#     # 重新取对应子矩阵
#     sub_idx = adata.obs.index.get_indexer(adata_sub.obs.index)
#     X_sub = X_all[sub_idx]

#     if args.paired:
#         paired_samples = get_paired_samples(
#             adata_sub,
#             sample_col=args.sample_col,
#             target_name=args.target_name,
#             reference_name=args.reference_name,
#         )
#         adata_sub = adata_sub[adata_sub.obs[args.sample_col].isin(paired_samples)].copy()
#         sub_idx = adata.obs.index.get_indexer(adata_sub.obs.index)
#         X_sub = X_all[sub_idx]
#     n_cells_after_pair_filter = adata_sub.n_obs

#     print(f"[info] cells after pairing: {n_cells_after_pair_filter}", flush=True)

#     pb_counts_df, pb_meta_df = build_pseudobulk(
#         adata=adata_sub,
#         X=X_sub,
#         sample_col=args.sample_col,
#         celltype_col=args.celltype_col,
#     )

#     # min_cells 过滤
#     keep_pb = pb_meta_df["n_cells"] >= args.min_cells
#     pb_counts_df = pb_counts_df.loc[keep_pb].copy()
#     pb_meta_df = pb_meta_df.loc[keep_pb].copy()

#     # min_cells 后再次保证 paired
#     if args.paired and not pb_meta_df.empty:
#         paired_after_filter = (
#             pb_meta_df.groupby("Sample_ID")["group"]
#             .apply(lambda x: set(x.astype(str)))
#         )
#         paired_after_filter = paired_after_filter[
#             paired_after_filter.apply(lambda x: {args.target_name, args.reference_name}.issubset(x))
#         ].index.tolist()

#         pb_meta_df = pb_meta_df[pb_meta_df["Sample_ID"].isin(paired_after_filter)].copy()
#         pb_counts_df = pb_counts_df.loc[pb_meta_df.index].copy()

#     n_cells_after_min_filter = int(pb_meta_df["n_cells"].sum()) if not pb_meta_df.empty else 0
#     n_samples_final = pb_meta_df["Sample_ID"].nunique() if not pb_meta_df.empty else 0

#     # 导出
#     prefix = args.analysis_name

#     counts_fp = outdir / f"{prefix}_counts.tsv"
#     meta_fp = outdir / f"{prefix}_meta.tsv"
#     summary_fp = outdir / f"{prefix}_summary.txt"
#     json_fp = outdir / f"{prefix}_run_info.json"

#     pb_counts_df.T.to_csv(counts_fp, sep="\t")
#     pb_meta_df.to_csv(meta_fp, sep="\t")

#     run_info["resolved_reference_types"] = ref_types
#     run_info["count_source_used"] = layer_used
#     with open(json_fp, "w", encoding="utf-8") as f:
#         json.dump(run_info, f, ensure_ascii=False, indent=2)

#     write_summary(
#         out_txt=summary_fp,
#         analysis_name=args.analysis_name,
#         input_h5ad=args.input_h5ad,
#         layer_used=layer_used,
#         celltype_col=args.celltype_col,
#         sample_col=args.sample_col,
#         target_types=args.target_types,
#         ref_types=ref_types,
#         target_name=args.target_name,
#         reference_name=args.reference_name,
#         paired=args.paired,
#         min_cells=args.min_cells,
#         n_cells_input=n_cells_input,
#         n_cells_after_group_filter=n_cells_after_group_filter,
#         n_cells_after_pair_filter=n_cells_after_pair_filter,
#         n_cells_after_min_filter=n_cells_after_min_filter,
#         n_samples_final=n_samples_final,
#         pb_meta_df=pb_meta_df,
#     )

#     print("[done] pseudo-bulk files saved:", flush=True)
#     print(f"  counts:  {counts_fp}", flush=True)
#     print(f"  meta:    {meta_fp}", flush=True)
#     print(f"  summary: {summary_fp}", flush=True)
#     print(f"  runinfo: {json_fp}", flush=True)


# if __name__ == "__main__":
#     main()
#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import json
import argparse
from pathlib import Path

import numpy as np
import pandas as pd
import scanpy as sc
from scipy import sparse


def parse_args():
    parser = argparse.ArgumentParser(
        description="Build pseudo-bulk matrix for target vs reference cell-type groups."
    )

    parser.add_argument("--input-h5ad", required=True)
    parser.add_argument("--outdir", required=True)

    parser.add_argument("--celltype-col", default="Org_celltype")
    parser.add_argument("--sample-col", default="Sample_ID")
    parser.add_argument("--layer", default="X")

    parser.add_argument("--target-types", nargs="+", required=True)

    parser.add_argument("--reference-types", nargs="*", default=None)
    parser.add_argument("--reference-prefix", default=None)
    parser.add_argument("--reference-prefixes", nargs="*", default=None)
    parser.add_argument("--reference-exclude", nargs="*", default=None)

    parser.add_argument("--target-name", default="target")
    parser.add_argument("--reference-name", default="reference")

    parser.add_argument("--paired", action="store_true")
    parser.add_argument("--min-cells", type=int, default=10)
    parser.add_argument("--analysis-name", default="pseudobulk_analysis")

    return parser.parse_args()


def get_matrix(adata, layer):
    if layer == "X":
        X = adata.X
        source = "adata.X"
    else:
        if layer not in adata.layers:
            raise ValueError(f"Layer {layer} not found. Available layers: {list(adata.layers.keys())}")
        X = adata.layers[layer]
        source = f"adata.layers['{layer}']"

    if not sparse.issparse(X):
        X = sparse.csr_matrix(X)
    else:
        X = X.tocsr()

    return X, source


def resolve_reference_types(
    all_celltypes,
    target_types,
    reference_types=None,
    reference_prefix=None,
    reference_prefixes=None,
    reference_exclude=None,
):
    target_types = set(target_types)

    if reference_types is not None and len(reference_types) > 0:
        ref_types = set(reference_types)
    else:
        prefixes = []

        if reference_prefix is not None and reference_prefix != "":
            prefixes.append(reference_prefix)

        if reference_prefixes is not None:
            prefixes.extend([x for x in reference_prefixes if x is not None and x != ""])

        if len(prefixes) == 0:
            raise ValueError(
                "No reference was provided. Use --reference-types, --reference-prefix, or --reference-prefixes."
            )

        ref_types = {
            ct for ct in all_celltypes
            if any(str(ct).startswith(p) for p in prefixes)
        }

    ref_types = ref_types - target_types

    if reference_exclude is not None:
        ref_types = ref_types - set(reference_exclude)

    ref_types = sorted(ref_types)

    if len(ref_types) == 0:
        raise ValueError(
            "No reference cell types were resolved. Check prefix spelling and Org_celltype names."
        )

    return ref_types


def build_grouped_adata(adata, args, ref_types):
    obs_ct = adata.obs[args.celltype_col].astype(str)

    group = pd.Series(index=adata.obs_names, dtype="object")
    group.loc[obs_ct.isin(args.target_types)] = args.target_name
    group.loc[obs_ct.isin(ref_types)] = args.reference_name

    keep = group.notna()
    adata_sub = adata[keep.values].copy()
    adata_sub.obs["pb_group"] = group.loc[adata_sub.obs_names].astype(str).values

    return adata_sub


def filter_paired_samples(adata_sub, sample_col, target_name, reference_name):
    sample_groups = (
        adata_sub.obs.groupby(sample_col)["pb_group"]
        .apply(lambda x: set(x.astype(str)))
    )

    paired_samples = sample_groups[
        sample_groups.apply(lambda x: {target_name, reference_name}.issubset(x))
    ].index.tolist()

    return adata_sub[adata_sub.obs[sample_col].isin(paired_samples)].copy()


def build_pseudobulk(adata_sub, X_sub, sample_col, celltype_col):
    obs = adata_sub.obs.copy()
    obs["sample_group"] = obs[sample_col].astype(str) + "__" + obs["pb_group"].astype(str)

    pb_counts = []
    pb_meta = []

    obs2 = obs.reset_index(drop=False).copy()
    obs2["_row_ix"] = np.arange(obs2.shape[0])

    for sample_group, subobs in obs2.groupby("sample_group", sort=False):
        idx = subobs["_row_ix"].values
        summed = np.asarray(X_sub[idx].sum(axis=0)).ravel()
        pb_counts.append(summed)

        sample_id = subobs[sample_col].iloc[0]
        group = subobs["pb_group"].iloc[0]
        n_cells = subobs.shape[0]
        comp = subobs[celltype_col].astype(str).value_counts().to_dict()

        row = {
            "pseudo_id": sample_group,
            "Sample_ID": sample_id,
            "group": group,
            "n_cells": int(n_cells),
            "celltype_composition": json.dumps(comp, ensure_ascii=False),
        }

        for ct, n in comp.items():
            safe = str(ct).replace("/", "_").replace(" ", "_")
            row[f"n__{safe}"] = int(n)
            row[f"frac__{safe}"] = float(n / n_cells)

        pb_meta.append(row)

    if len(pb_counts) == 0:
        raise ValueError("No pseudo-bulk sample was generated before min_cells filtering.")

    pb_counts_df = pd.DataFrame(
        np.vstack(pb_counts),
        index=[x["pseudo_id"] for x in pb_meta],
        columns=adata_sub.var_names,
    )

    pb_meta_df = pd.DataFrame(pb_meta).set_index("pseudo_id")
    pb_counts_df = pb_counts_df.loc[pb_meta_df.index]

    return pb_counts_df, pb_meta_df


def write_summary(
    out_fp,
    args,
    count_source,
    ref_types,
    n_input,
    n_after_group,
    n_after_pair,
    n_after_min,
    n_samples_final,
    pb_meta_df,
):
    with open(out_fp, "w") as f:
        f.write(f"Pseudo-bulk summary: {args.analysis_name}\n")
        f.write("=" * 80 + "\n\n")

        f.write(f"Input h5ad: {args.input_h5ad}\n")
        f.write(f"Count source: {count_source}\n")
        f.write(f"Celltype column: {args.celltype_col}\n")
        f.write(f"Sample column: {args.sample_col}\n")
        f.write(f"Paired: {args.paired}\n")
        f.write(f"Min cells: {args.min_cells}\n\n")

        f.write("Target types:\n")
        for x in args.target_types:
            f.write(f"  - {x}\n")

        f.write("\nResolved reference types:\n")
        for x in ref_types:
            f.write(f"  - {x}\n")

        f.write("\nFiltering summary:\n")
        f.write(f"  input cells: {n_input}\n")
        f.write(f"  after group selection: {n_after_group}\n")
        f.write(f"  after paired filtering: {n_after_pair}\n")
        f.write(f"  after min_cells filtering: {n_after_min}\n")
        f.write(f"  final biological samples: {n_samples_final}\n")
        f.write(f"  final pseudo-bulk rows: {pb_meta_df.shape[0]}\n\n")

        if not pb_meta_df.empty:
            f.write("Group counts:\n")
            f.write(pb_meta_df["group"].value_counts().to_string())
            f.write("\n\n")

            f.write("n_cells by group:\n")
            f.write(pb_meta_df.groupby("group")["n_cells"].describe().to_string())
            f.write("\n\n")

            try:
                f.write("Per-sample paired cell counts:\n")
                pivot = pb_meta_df.reset_index().pivot(
                    index="Sample_ID",
                    columns="group",
                    values="n_cells"
                )
                f.write(pivot.to_string())
                f.write("\n")
            except Exception:
                pass


def main():
    args = parse_args()
    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    print("[info] reading h5ad...", flush=True)
    adata = sc.read_h5ad(args.input_h5ad)

    if args.celltype_col not in adata.obs.columns:
        raise ValueError(f"Missing celltype column: {args.celltype_col}")
    if args.sample_col not in adata.obs.columns:
        raise ValueError(f"Missing sample column: {args.sample_col}")

    if adata.var_names.duplicated().any():
        print("[warn] duplicated gene names found; keeping first occurrence.", flush=True)
        adata = adata[:, ~adata.var_names.duplicated()].copy()

    n_input = adata.n_obs
    X_all, count_source = get_matrix(adata, args.layer)

    all_celltypes = sorted(adata.obs[args.celltype_col].astype(str).unique())

    ref_types = resolve_reference_types(
        all_celltypes=all_celltypes,
        target_types=args.target_types,
        reference_types=args.reference_types,
        reference_prefix=args.reference_prefix,
        reference_prefixes=args.reference_prefixes,
        reference_exclude=args.reference_exclude,
    )

    print(f"[info] target types: {args.target_types}", flush=True)
    print(f"[info] resolved reference types: {len(ref_types)}", flush=True)
    for x in ref_types:
        print(f"  [ref] {x}", flush=True)

    adata_sub = build_grouped_adata(adata, args, ref_types)
    adata_sub = adata_sub[~adata_sub.obs[args.sample_col].isna()].copy()
    adata_sub.obs[args.sample_col] = adata_sub.obs[args.sample_col].astype(str)

    n_after_group = adata_sub.n_obs

    if args.paired:
        adata_sub = filter_paired_samples(
            adata_sub,
            sample_col=args.sample_col,
            target_name=args.target_name,
            reference_name=args.reference_name,
        )

    n_after_pair = adata_sub.n_obs

    sub_idx = adata.obs_names.get_indexer(adata_sub.obs_names)
    X_sub = X_all[sub_idx]

    print(f"[info] cells after group filter: {n_after_group}", flush=True)
    print(f"[info] cells after paired filter: {n_after_pair}", flush=True)

    pb_counts_df, pb_meta_df = build_pseudobulk(
        adata_sub=adata_sub,
        X_sub=X_sub,
        sample_col=args.sample_col,
        celltype_col=args.celltype_col,
    )

    keep = pb_meta_df["n_cells"] >= args.min_cells
    pb_meta_df = pb_meta_df.loc[keep].copy()
    pb_counts_df = pb_counts_df.loc[pb_meta_df.index].copy()

    if args.paired:
        keep_samples = (
            pb_meta_df.groupby("Sample_ID")["group"]
            .apply(lambda x: set(x.astype(str)))
        )
        keep_samples = keep_samples[
            keep_samples.apply(lambda x: {args.target_name, args.reference_name}.issubset(x))
        ].index.tolist()

        pb_meta_df = pb_meta_df[pb_meta_df["Sample_ID"].isin(keep_samples)].copy()
        pb_counts_df = pb_counts_df.loc[pb_meta_df.index].copy()

    if pb_meta_df.empty:
        raise ValueError(
            "No pseudo-bulk sample remained after min_cells and paired filtering. "
            "Check per-sample target/reference counts."
        )

    n_after_min = int(pb_meta_df["n_cells"].sum())
    n_samples_final = int(pb_meta_df["Sample_ID"].nunique())

    prefix = args.analysis_name

    counts_fp = outdir / f"{prefix}_counts.tsv"
    meta_fp = outdir / f"{prefix}_meta.tsv"
    summary_fp = outdir / f"{prefix}_summary.txt"
    runinfo_fp = outdir / f"{prefix}_run_info.json"

    pb_counts_df.T.to_csv(counts_fp, sep="\t")
    pb_meta_df.to_csv(meta_fp, sep="\t")

    run_info = vars(args).copy()
    run_info["count_source_used"] = count_source
    run_info["resolved_reference_types"] = ref_types

    with open(runinfo_fp, "w") as f:
        json.dump(run_info, f, indent=2, ensure_ascii=False)

    write_summary(
        out_fp=summary_fp,
        args=args,
        count_source=count_source,
        ref_types=ref_types,
        n_input=n_input,
        n_after_group=n_after_group,
        n_after_pair=n_after_pair,
        n_after_min=n_after_min,
        n_samples_final=n_samples_final,
        pb_meta_df=pb_meta_df,
    )

    print("[done] saved pseudo-bulk files", flush=True)
    print(f"  counts:  {counts_fp}", flush=True)
    print(f"  meta:    {meta_fp}", flush=True)
    print(f"  summary: {summary_fp}", flush=True)
    print(f"  runinfo: {runinfo_fp}", flush=True)


if __name__ == "__main__":
    main()