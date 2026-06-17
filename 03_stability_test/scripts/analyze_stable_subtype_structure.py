# #!/usr/bin/env python3
# # -*- coding: utf-8 -*-

# import os
# import argparse
# import pickle
# from collections import defaultdict, Counter

# import numpy as np
# import pandas as pd
# import scanpy as sc


# REGION_MAP = {
#     "FTLD_PFC_Ctrl_Concat_QC_harmony_filted": "PFC",
#     "SALS_PFC_control_concat_QC_harmony": "PFC",
#     "FTLD_MCX_Control_Concat_QC_harmony_filted": "MCX",
#     "SALS_MCX_control_concat_QC_harmony": "MCX"
# }


# def log(msg: str):
#     print(msg, flush=True)


# def to_bool(s: pd.Series) -> pd.Series:
#     if s.dtype == bool:
#         return s.fillna(False)
#     s = s.fillna(False)
#     if pd.api.types.is_numeric_dtype(s):
#         return s.astype(float) != 0
#     return s.astype(str).str.strip().str.lower().isin(["true", "t", "1", "yes", "y"])


# def get_all_hit_clusters(df_hit: pd.DataFrame, call_by: str = "p", p_cut: float = 0.05):
#     if "cluster" not in df_hit.columns:
#         raise ValueError("df_hit does not contain 'cluster' column")

#     df_hit = df_hit.copy()
#     df_hit["cluster"] = df_hit["cluster"].astype(str)

#     if "direction_flag" in df_hit.columns:
#         dir_mask = df_hit["direction_flag"].astype(str).str.lower().eq("vulnerable")
#     else:
#         dir_mask = pd.Series(True, index=df_hit.index)

#     if "Significant_call" in df_hit.columns:
#         sig_mask = to_bool(df_hit["Significant_call"])
#         return (
#             df_hit.loc[sig_mask & dir_mask, "cluster"]
#             .astype(str)
#             .drop_duplicates()
#             .tolist()
#         )

#     if call_by == "p" and "Donor_P" in df_hit.columns:
#         sig_mask = pd.to_numeric(df_hit["Donor_P"], errors="coerce") < p_cut
#         return (
#             df_hit.loc[sig_mask & dir_mask, "cluster"]
#             .astype(str)
#             .drop_duplicates()
#             .tolist()
#         )

#     if call_by == "fdr" and "FDR_Donor" in df_hit.columns:
#         sig_mask = pd.to_numeric(df_hit["FDR_Donor"], errors="coerce") < p_cut
#         return (
#             df_hit.loc[sig_mask & dir_mask, "cluster"]
#             .astype(str)
#             .drop_duplicates()
#             .tolist()
#         )

#     raise ValueError("Cannot identify hit clusters from df_hit")


# def ensure_neighbors(adata, use_rep="X_pca_harmony", n_neighbors=15, random_state=666):
#     if "connectivities" in adata.obsp and adata.obsp["connectivities"].shape[0] == adata.n_obs:
#         return

#     if use_rep not in adata.obsm:
#         raise ValueError(
#             f"Neither neighbor graph nor {use_rep} was found in adata. "
#             "Cannot rebuild clustering."
#         )
#     sc.pp.neighbors(adata, use_rep=use_rep, n_neighbors=n_neighbors, random_state=random_state)


# def ensure_cluster_column(adata, cluster_key: str, resolution: float,
#                           use_rep="X_pca_harmony", random_state=666):
#     """
#     如果 analysis_input.h5ad 中没有对应的 chosen_key，就按保存下来的 resolution 重新生成。
#     """
#     if cluster_key in adata.obs.columns:
#         return

#     ensure_neighbors(adata, use_rep=use_rep, random_state=random_state)
#     sc.tl.leiden(
#         adata,
#         resolution=float(resolution),
#         key_added=cluster_key,
#         random_state=random_state
#     )


# def format_top_subtypes(series: pd.Series, top_n=5, exclude=None):
#     s = series.copy()
#     s = s[s > 0]

#     if exclude is not None:
#         if isinstance(exclude, (list, tuple, set)):
#             s = s.drop(labels=[x for x in exclude if x in s.index], errors="ignore")
#         else:
#             s = s.drop(labels=[exclude], errors="ignore")

#     if s.empty:
#         return ""

#     total = float(s.sum())
#     out = []
#     for subtype, n in s.sort_values(ascending=False).head(top_n).items():
#         frac = 100.0 * float(n) / total if total > 0 else 0.0
#         out.append(f"{subtype}:{int(n)}({frac:.1f}%)")
#     return ";".join(out)


# def choose_region_stable_subtypes(stable_df: pd.DataFrame, region: str):
#     if stable_df.empty:
#         return pd.DataFrame()

#     stable_df = stable_df.copy()
#     stable_df["stable_class"] = stable_df["stable_class"].astype(str)

#     allowed = {"Cross_region_stable"}
#     if region == "MCX":
#         allowed.add("MCX_specific_stable")
#     elif region == "PFC":
#         allowed.add("PFC_specific_stable")
#     else:
#         raise ValueError(f"Unknown region: {region}")

#     sub = stable_df[stable_df["stable_class"].isin(allowed)].copy()
#     return sub


# def classify_structure(capture_rate_any_hit,
#                        n_hit_clusters,
#                        purity_in_main_hit_cluster,
#                        n_nonhit_clusters_with_subtype,
#                        full_capture_cutoff=99.9,
#                        purity_cutoff=70.0):
#     if pd.isna(capture_rate_any_hit) or float(capture_rate_any_hit) <= 0 or int(n_hit_clusters) == 0:
#         return "no_hit"

#     if float(capture_rate_any_hit) >= full_capture_cutoff:
#         if int(n_hit_clusters) == 1:
#             if pd.notna(purity_in_main_hit_cluster) and float(purity_in_main_hit_cluster) >= purity_cutoff:
#                 return "single_pure_hit"
#             return "single_mixed_hit"
#         return "multi_hit_only"

#     if int(n_nonhit_clusters_with_subtype) > 0:
#         return "hit_nonhit_split"

#     return "partial_hit"


# def safe_read_tsv(fp):
#     if not os.path.exists(fp):
#         raise FileNotFoundError(fp)
#     return pd.read_csv(fp, sep="\t")


# def dominant_value(series: pd.Series):
#     s = series.dropna().astype(str)
#     if s.empty:
#         return ""
#     return s.value_counts().idxmax()


# def summarize_partner_string(df_partner, group_cols, partner_col="partner_subtype",
#                              weight_col="shared_subtype_cells", top_n=5):
#     if df_partner.empty:
#         return pd.DataFrame(columns=group_cols + ["top_partners"])

#     rows = []
#     for keys, sub in df_partner.groupby(group_cols):
#         agg = (
#             sub.groupby(partner_col, as_index=False)[weight_col]
#             .sum()
#             .sort_values(weight_col, ascending=False)
#         )
#         txt = ";".join(
#             f"{r[partner_col]}:{int(r[weight_col])}"
#             for _, r in agg.head(top_n).iterrows()
#         )
#         if not isinstance(keys, tuple):
#             keys = (keys,)
#         row = dict(zip(group_cols, keys))
#         row["top_partners"] = txt
#         rows.append(row)

#     return pd.DataFrame(rows)


# def build_consensus_rep(kmin_df: pd.DataFrame, partner_df: pd.DataFrame):
#     if kmin_df.empty:
#         return pd.DataFrame()

#     structure_order = [
#         "single_pure_hit",
#         "single_mixed_hit",
#         "multi_hit_only",
#         "hit_nonhit_split",
#         "partial_hit",
#         "no_hit"
#     ]

#     rows = []
#     group_cols = ["rep", "region", "prefix", "subtype", "stable_class"]

#     for keys, sub in kmin_df.groupby(group_cols):
#         sub = sub.copy()
#         structure_counts = sub["structure_class"].value_counts()
#         n_k = sub.shape[0]

#         row = dict(zip(group_cols, keys))
#         row["n_kmin_analyzed"] = int(n_k)
#         row["mean_capture_rate_any_hit"] = sub["capture_rate_any_hit"].mean()
#         row["mean_capture_rate_main_hit"] = sub["capture_rate_main_hit"].mean()
#         row["mean_n_hit_clusters"] = sub["n_hit_clusters"].mean()
#         row["mean_n_nonhit_clusters_with_subtype"] = sub["n_nonhit_clusters_with_subtype"].mean()
#         row["most_common_structure_class"] = dominant_value(sub["structure_class"])
#         row["top_main_hit_clusters"] = ";".join(
#             f"{cl}:{cnt}" for cl, cnt in sub["main_hit_cluster"].dropna().astype(str).value_counts().head(5).items()
#         )

#         for cls in structure_order:
#             row[f"prop_{cls}"] = float((sub["structure_class"] == cls).mean())

#         rows.append(row)

#     rep_df = pd.DataFrame(rows)

#     partner_top = summarize_partner_string(
#         df_partner=partner_df,
#         group_cols=["rep", "region", "prefix", "subtype"],
#         partner_col="partner_subtype",
#         weight_col="shared_subtype_cells",
#         top_n=5
#     )

#     if not partner_top.empty:
#         rep_df = rep_df.merge(
#             partner_top,
#             on=["rep", "region", "prefix", "subtype"],
#             how="left"
#         )
#     else:
#         rep_df["top_partners"] = ""

#     rep_df["top_partners"] = rep_df["top_partners"].fillna("")
#     return rep_df


# def build_consensus_region(kmin_df: pd.DataFrame, partner_df: pd.DataFrame):
#     if kmin_df.empty:
#         return pd.DataFrame()

#     structure_order = [
#         "single_pure_hit",
#         "single_mixed_hit",
#         "multi_hit_only",
#         "hit_nonhit_split",
#         "partial_hit",
#         "no_hit"
#     ]

#     rows = []
#     group_cols = ["region", "prefix", "subtype", "stable_class"]

#     for keys, sub in kmin_df.groupby(group_cols):
#         sub = sub.copy()
#         row = dict(zip(group_cols, keys))
#         row["n_rep_present"] = int(sub["rep"].nunique())
#         row["reps_present"] = ",".join(sorted(sub["rep"].astype(str).unique().tolist()))
#         row["n_kmin_analyzed"] = int(sub.shape[0])
#         row["mean_capture_rate_any_hit"] = sub["capture_rate_any_hit"].mean()
#         row["mean_capture_rate_main_hit"] = sub["capture_rate_main_hit"].mean()
#         row["mean_n_hit_clusters"] = sub["n_hit_clusters"].mean()
#         row["mean_n_nonhit_clusters_with_subtype"] = sub["n_nonhit_clusters_with_subtype"].mean()
#         row["most_common_structure_class"] = dominant_value(sub["structure_class"])
#         row["top_main_hit_clusters"] = ";".join(
#             f"{cl}:{cnt}" for cl, cnt in sub["main_hit_cluster"].dropna().astype(str).value_counts().head(5).items()
#         )

#         for cls in structure_order:
#             row[f"prop_{cls}"] = float((sub["structure_class"] == cls).mean())

#         rows.append(row)

#     region_df = pd.DataFrame(rows)

#     partner_top = summarize_partner_string(
#         df_partner=partner_df,
#         group_cols=["region", "prefix", "subtype"],
#         partner_col="partner_subtype",
#         weight_col="shared_subtype_cells",
#         top_n=5
#     )

#     if not partner_top.empty:
#         region_df = region_df.merge(
#             partner_top,
#             on=["region", "prefix", "subtype"],
#             how="left"
#         )
#     else:
#         region_df["top_partners"] = ""

#     region_df["top_partners"] = region_df["top_partners"].fillna("")
#     return region_df


# def analyze_one_rep_prefix(
#     rep: str,
#     prefix: str,
#     region: str,
#     repdir: str,
#     stable_df: pd.DataFrame,
#     org_col: str = "Org_celltype",
#     use_rep: str = "X_pca_harmony",
#     p_cut: float = 0.05,
#     call_by: str = "p",
#     purity_cutoff: float = 70.0,
#     random_state: int = 666,
# ):
#     summary_fp = os.path.join(repdir, f"{prefix}_all_subtypes_vulnerability_kmin_summary.tsv")
#     pkl_fp = os.path.join(repdir, f"{prefix}_all_results.pkl")
#     h5ad_fp = os.path.join(repdir, f"{prefix}_analysis_input.h5ad")

#     if not os.path.exists(summary_fp):
#         raise FileNotFoundError(summary_fp)
#     if not os.path.exists(pkl_fp):
#         raise FileNotFoundError(pkl_fp)
#     if not os.path.exists(h5ad_fp):
#         raise FileNotFoundError(h5ad_fp)

#     region_stable_df = choose_region_stable_subtypes(stable_df, region)
#     target_subtypes = sorted(region_stable_df["subtype"].astype(str).unique().tolist())
#     stable_class_map = dict(
#         zip(region_stable_df["subtype"].astype(str), region_stable_df["stable_class"].astype(str))
#     )

#     if len(target_subtypes) == 0:
#         log(f"[INFO] {rep} {prefix}: no stable subtypes for region {region}.")
#         return [], [], [], []

#     log(f"[INFO] {rep} {prefix}: loading files ...")
#     summary_df = safe_read_tsv(summary_fp)
#     summary_df["subtype"] = summary_df["subtype"].astype(str)
#     summary_df["k_min"] = pd.to_numeric(summary_df["k_min"], errors="coerce")

#     summary_lookup = summary_df.set_index(["subtype", "k_min"], drop=False)

#     with open(pkl_fp, "rb") as f:
#         all_results = pickle.load(f)

#     adata = sc.read_h5ad(h5ad_fp)
#     if org_col not in adata.obs.columns:
#         raise ValueError(f"{org_col} not found in {h5ad_fp}")
#     adata.obs[org_col] = adata.obs[org_col].astype(str)

#     kmin_structure_rows = []
#     cluster_comp_rows = []
#     hit_cluster_rows = []
#     partner_rows = []

#     for kmin in sorted(all_results.keys(), key=lambda x: int(x)):
#         out = all_results[kmin]
#         chosen = out.get("chosen", None)
#         if chosen is None:
#             continue

#         k_hit = int(chosen["k"])
#         chosen_r = float(chosen["r"])
#         chosen_key = str(chosen["key"])
#         chosen_cluster = str(chosen["cluster"])

#         ensure_cluster_column(
#             adata=adata,
#             cluster_key=chosen_key,
#             resolution=chosen_r,
#             use_rep=use_rep,
#             random_state=random_state
#         )

#         if chosen_key not in adata.obs.columns:
#             raise RuntimeError(f"Failed to rebuild cluster key: {chosen_key}")

#         obs = adata.obs[[org_col, chosen_key]].copy()
#         obs[chosen_key] = obs[chosen_key].astype(str)
#         obs[org_col] = obs[org_col].astype(str)

#         df_hit = out["by_k"][k_hit]["df"].copy()
#         df_hit["cluster"] = df_hit["cluster"].astype(str)

#         hit_clusters = get_all_hit_clusters(df_hit, call_by=call_by, p_cut=p_cut)
#         hit_set = set(hit_clusters)

#         if len(hit_set) == 0:
#             continue

#         cluster_sizes = obs[chosen_key].value_counts().to_dict()
#         cluster_subtype_counts = pd.crosstab(obs[chosen_key], obs[org_col])

#         # hit cluster summary
#         hit_only_df = df_hit[df_hit["cluster"].isin(hit_set)].copy()
#         for _, hr in hit_only_df.iterrows():
#             cl = str(hr["cluster"])
#             cluster_size = int(cluster_sizes.get(cl, 0))

#             if cl in cluster_subtype_counts.index:
#                 subtype_series = cluster_subtype_counts.loc[cl]
#                 dominant_subtype = (
#                     subtype_series[subtype_series > 0].sort_values(ascending=False).index[0]
#                     if (subtype_series > 0).any() else ""
#                 )
#                 dominant_cells = int(subtype_series.max()) if (subtype_series > 0).any() else 0
#                 dominant_frac = 100.0 * dominant_cells / cluster_size if cluster_size > 0 else np.nan
#                 n_subtypes = int((subtype_series > 0).sum())
#                 top_subtypes = format_top_subtypes(subtype_series, top_n=8)
#             else:
#                 dominant_subtype = ""
#                 dominant_frac = np.nan
#                 n_subtypes = 0
#                 top_subtypes = ""

#             hit_cluster_rows.append({
#                 "rep": rep,
#                 "region": region,
#                 "prefix": prefix,
#                 "k_min": int(kmin),
#                 "chosen_k": k_hit,
#                 "chosen_r": chosen_r,
#                 "chosen_key": chosen_key,
#                 "chosen_cluster": chosen_cluster,
#                 "cluster": cl,
#                 "is_hit_cluster": True,
#                 "Donor_P": hr["Donor_P"] if "Donor_P" in hr.index else np.nan,
#                 "FDR_Donor": hr["FDR_Donor"] if "FDR_Donor" in hr.index else np.nan,
#                 "Donor_log2_OR": hr["Donor_log2_OR"] if "Donor_log2_OR" in hr.index else np.nan,
#                 "direction_flag": hr["direction_flag"] if "direction_flag" in hr.index else "",
#                 "Significant_call": hr["Significant_call"] if "Significant_call" in hr.index else np.nan,
#                 "cluster_size": cluster_size,
#                 "dominant_subtype": dominant_subtype,
#                 "dominant_subtype_fraction": dominant_frac,
#                 "n_subtypes_in_cluster": n_subtypes,
#                 "top_subtypes": top_subtypes,
#             })

#         # subtype-level structure
#         for subtype in target_subtypes:
#             sub_obs = obs[obs[org_col] == subtype].copy()
#             total_cells = int(sub_obs.shape[0])
#             if total_cells == 0:
#                 continue

#             counts = sub_obs[chosen_key].value_counts()
#             hit_counts = counts[counts.index.isin(hit_set)].sort_values(ascending=False)
#             nonhit_counts = counts[~counts.index.isin(hit_set)].sort_values(ascending=False)

#             cells_in_any_hit = int(hit_counts.sum()) if len(hit_counts) > 0 else 0
#             capture_rate_any_hit = 100.0 * cells_in_any_hit / total_cells if total_cells > 0 else 0.0

#             n_hit_clusters = int(len(hit_counts))
#             n_nonhit_clusters_with_subtype = int(len(nonhit_counts))

#             if len(hit_counts) > 0:
#                 main_hit_cluster = str(hit_counts.index[0])
#                 cells_in_main_hit_cluster = int(hit_counts.iloc[0])
#                 capture_rate_main_hit = 100.0 * cells_in_main_hit_cluster / total_cells
#                 main_cluster_size = int(cluster_sizes.get(main_hit_cluster, 0))
#                 purity_in_main_hit_cluster = (
#                     100.0 * cells_in_main_hit_cluster / main_cluster_size
#                     if main_cluster_size > 0 else np.nan
#                 )
#             else:
#                 main_hit_cluster = np.nan
#                 cells_in_main_hit_cluster = 0
#                 capture_rate_main_hit = np.nan
#                 purity_in_main_hit_cluster = np.nan

#             structure_class = classify_structure(
#                 capture_rate_any_hit=capture_rate_any_hit,
#                 n_hit_clusters=n_hit_clusters,
#                 purity_in_main_hit_cluster=purity_in_main_hit_cluster,
#                 n_nonhit_clusters_with_subtype=n_nonhit_clusters_with_subtype,
#                 purity_cutoff=purity_cutoff
#             )

#             if (subtype, float(kmin)) in summary_lookup.index:
#                 sr = summary_lookup.loc[(subtype, float(kmin))]
#                 stored_capture_rate_any_hit = sr["capture_rate_any_hit"]
#                 stored_main_hit_cluster = sr["main_hit_cluster"]
#                 stored_capture_rate_main_hit = sr["capture_rate_main_hit"]
#                 stored_purity_in_main_hit_cluster = sr["purity_in_main_hit_cluster"]
#                 stored_n_hit_clusters = sr["n_hit_clusters"]
#             else:
#                 stored_capture_rate_any_hit = np.nan
#                 stored_main_hit_cluster = np.nan
#                 stored_capture_rate_main_hit = np.nan
#                 stored_purity_in_main_hit_cluster = np.nan
#                 stored_n_hit_clusters = np.nan

#             shared_partner_counter = defaultdict(int)

#             # composition rows
#             for cl, n_cells in counts.items():
#                 cl = str(cl)
#                 cluster_size = int(cluster_sizes.get(cl, 0))
#                 frac_of_subtype = 100.0 * int(n_cells) / total_cells if total_cells > 0 else 0.0
#                 frac_of_cluster_from_subtype = (
#                     100.0 * int(n_cells) / cluster_size if cluster_size > 0 else np.nan
#                 )

#                 if cl in cluster_subtype_counts.index:
#                     subtype_series = cluster_subtype_counts.loc[cl]
#                     top_other_subtypes = format_top_subtypes(
#                         subtype_series,
#                         top_n=6,
#                         exclude=subtype
#                     )
#                     others = subtype_series.drop(labels=[subtype], errors="ignore")
#                     others = others[others > 0]
#                 else:
#                     top_other_subtypes = ""
#                     others = pd.Series(dtype=float)

#                 cluster_comp_rows.append({
#                     "rep": rep,
#                     "region": region,
#                     "prefix": prefix,
#                     "subtype": subtype,
#                     "stable_class": stable_class_map.get(subtype, ""),
#                     "k_min": int(kmin),
#                     "chosen_k": k_hit,
#                     "chosen_r": chosen_r,
#                     "chosen_key": chosen_key,
#                     "chosen_cluster": chosen_cluster,
#                     "cluster": cl,
#                     "is_hit_cluster": cl in hit_set,
#                     "n_cells_of_subtype_in_cluster": int(n_cells),
#                     "frac_of_subtype": frac_of_subtype,
#                     "cluster_size": cluster_size,
#                     "frac_of_cluster_from_subtype": frac_of_cluster_from_subtype,
#                     "top_other_subtypes": top_other_subtypes,
#                 })

#                 if cl in hit_set and not others.empty:
#                     for partner_subtype, partner_cells in others.items():
#                         shared_partner_counter[str(partner_subtype)] += int(n_cells)
#                         partner_rows.append({
#                             "rep": rep,
#                             "region": region,
#                             "prefix": prefix,
#                             "subtype": subtype,
#                             "stable_class": stable_class_map.get(subtype, ""),
#                             "k_min": int(kmin),
#                             "chosen_key": chosen_key,
#                             "cluster": cl,
#                             "partner_subtype": str(partner_subtype),
#                             "shared_subtype_cells": int(n_cells),
#                             "partner_cells_in_cluster": int(partner_cells),
#                             "cluster_size": cluster_size,
#                             "frac_of_subtype_in_this_hit_cluster": frac_of_subtype,
#                         })

#             top_partners_this_k = ";".join(
#                 f"{p}:{c}" for p, c in sorted(shared_partner_counter.items(), key=lambda x: (-x[1], x[0]))[:6]
#             )

#             kmin_structure_rows.append({
#                 "rep": rep,
#                 "region": region,
#                 "prefix": prefix,
#                 "subtype": subtype,
#                 "stable_class": stable_class_map.get(subtype, ""),
#                 "k_min": int(kmin),
#                 "chosen_k": k_hit,
#                 "chosen_r": chosen_r,
#                 "chosen_key": chosen_key,
#                 "chosen_cluster": chosen_cluster,
#                 "n_total_cells": total_cells,
#                 "cells_in_any_hit": cells_in_any_hit,
#                 "capture_rate_any_hit": round(capture_rate_any_hit, 4),
#                 "main_hit_cluster": main_hit_cluster,
#                 "cells_in_main_hit_cluster": cells_in_main_hit_cluster,
#                 "capture_rate_main_hit": round(capture_rate_main_hit, 4) if pd.notna(capture_rate_main_hit) else np.nan,
#                 "purity_in_main_hit_cluster": round(purity_in_main_hit_cluster, 4) if pd.notna(purity_in_main_hit_cluster) else np.nan,
#                 "n_hit_clusters": n_hit_clusters,
#                 "n_nonhit_clusters_with_subtype": n_nonhit_clusters_with_subtype,
#                 "all_hit_clusters": ",".join(sorted(hit_set)),
#                 "top_partners_this_kmin": top_partners_this_k,
#                 "structure_class": structure_class,
#                 # for checking consistency with your original summary file
#                 "stored_capture_rate_any_hit": stored_capture_rate_any_hit,
#                 "stored_main_hit_cluster": stored_main_hit_cluster,
#                 "stored_capture_rate_main_hit": stored_capture_rate_main_hit,
#                 "stored_purity_in_main_hit_cluster": stored_purity_in_main_hit_cluster,
#                 "stored_n_hit_clusters": stored_n_hit_clusters,
#             })

#     return kmin_structure_rows, cluster_comp_rows, hit_cluster_rows, partner_rows


# def main():
#     parser = argparse.ArgumentParser(
#         description="Analyze cluster structure of final stable vulnerable subtypes."
#     )
#     parser.add_argument(
#         "--outdir-base",
#         required=True,
#         help="Base directory containing rep subfolders"
#     )
#     parser.add_argument(
#         "--final-summary-dir",
#         required=True,
#         help="Directory containing In_stable_classification.tsv and Ex_stable_classification.tsv"
#     )
#     parser.add_argument(
#         "--outdir",
#         required=True,
#         help="Output directory for structure analysis tables"
#     )
#     parser.add_argument(
#         "--reps",
#         nargs="+",
#         default=[
#             "FTLD_PFC_Ctrl_Concat_QC_harmony_filted",
#             "FTLD_MCX_Control_Concat_QC_harmony_filted",
#             "SALS_PFC_control_concat_QC_harmony",
#             "SALS_MCX_control_concat_QC_harmony"
#         ],
#         help="Dataset folder names"
#     )
#     parser.add_argument("--org-col", default="Org_celltype")
#     parser.add_argument("--use-rep", default="X_pca_harmony")
#     parser.add_argument("--p-cut", type=float, default=0.05)
#     parser.add_argument("--call-by", choices=["p", "fdr"], default="p")
#     parser.add_argument("--purity-cutoff", type=float, default=70.0)
#     parser.add_argument("--random-state", type=int, default=666)
#     parser.add_argument("--in-prefix", default="In")
#     parser.add_argument("--ex-prefix", default="Ex")
#     args = parser.parse_args()

#     os.makedirs(args.outdir, exist_ok=True)

#     stable_tables = {}
#     for prefix in [args.in_prefix, args.ex_prefix]:
#         fp = os.path.join(args.final_summary_dir, f"{prefix}_stable_classification.tsv")
#         if not os.path.exists(fp):
#             raise FileNotFoundError(fp)
#         stable_df = safe_read_tsv(fp)
#         stable_df["subtype"] = stable_df["subtype"].astype(str)
#         stable_df["stable_class"] = stable_df["stable_class"].astype(str)
#         stable_tables[prefix] = stable_df

#     all_kmin_rows = []
#     all_comp_rows = []
#     all_hit_rows = []
#     all_partner_rows = []

#     for rep in args.reps:
#         if rep not in REGION_MAP:
#             raise ValueError(f"{rep} not found in REGION_MAP")
#         region = REGION_MAP[rep]
#         repdir = os.path.join(args.outdir_base, rep)

#         for prefix in [args.in_prefix, args.ex_prefix]:
#             log(f"[INFO] Processing rep={rep}, region={region}, prefix={prefix}")
#             k_rows, comp_rows, hit_rows, partner_rows = analyze_one_rep_prefix(
#                 rep=rep,
#                 prefix=prefix,
#                 region=region,
#                 repdir=repdir,
#                 stable_df=stable_tables[prefix],
#                 org_col=args.org_col,
#                 use_rep=args.use_rep,
#                 p_cut=args.p_cut,
#                 call_by=args.call_by,
#                 purity_cutoff=args.purity_cutoff,
#                 random_state=args.random_state,
#             )
#             all_kmin_rows.extend(k_rows)
#             all_comp_rows.extend(comp_rows)
#             all_hit_rows.extend(hit_rows)
#             all_partner_rows.extend(partner_rows)

#     kmin_df = pd.DataFrame(all_kmin_rows)
#     comp_df = pd.DataFrame(all_comp_rows)
#     hit_df = pd.DataFrame(all_hit_rows)
#     partner_detail_df = pd.DataFrame(all_partner_rows)

#     if not kmin_df.empty:
#         partner_summary_df = (
#             partner_detail_df.groupby(
#                 ["rep", "region", "prefix", "subtype", "stable_class", "partner_subtype"],
#                 as_index=False
#             )
#             .agg(
#                 n_kmin_shared=("k_min", "nunique"),
#                 n_hit_clusters_shared=("cluster", "nunique"),
#                 shared_subtype_cells=("shared_subtype_cells", "sum"),
#                 mean_frac_of_subtype_in_partnered_hit_clusters=("frac_of_subtype_in_this_hit_cluster", "mean"),
#             )
#             .sort_values(
#                 ["rep", "region", "prefix", "subtype", "shared_subtype_cells"],
#                 ascending=[True, True, True, True, False]
#             )
#         )
#         rep_consensus_df = build_consensus_rep(kmin_df, partner_summary_df)
#         region_consensus_df = build_consensus_region(kmin_df, partner_summary_df)
#     else:
#         partner_summary_df = pd.DataFrame()
#         rep_consensus_df = pd.DataFrame()
#         region_consensus_df = pd.DataFrame()

#     # save
#     kmin_fp = os.path.join(args.outdir, "stable_subtype_kmin_structure.tsv")
#     comp_fp = os.path.join(args.outdir, "stable_subtype_cluster_composition.tsv")
#     hit_fp = os.path.join(args.outdir, "stable_hit_cluster_summary.tsv")
#     partner_detail_fp = os.path.join(args.outdir, "stable_subtype_partner_detail.tsv")
#     partner_summary_fp = os.path.join(args.outdir, "stable_subtype_partner_summary.tsv")
#     rep_consensus_fp = os.path.join(args.outdir, "stable_subtype_structure_consensus_rep.tsv")
#     region_consensus_fp = os.path.join(args.outdir, "stable_subtype_structure_consensus_region.tsv")

#     kmin_df.to_csv(kmin_fp, sep="\t", index=False)
#     comp_df.to_csv(comp_fp, sep="\t", index=False)
#     hit_df.to_csv(hit_fp, sep="\t", index=False)
#     partner_detail_df.to_csv(partner_detail_fp, sep="\t", index=False)
#     partner_summary_df.to_csv(partner_summary_fp, sep="\t", index=False)
#     rep_consensus_df.to_csv(rep_consensus_fp, sep="\t", index=False)
#     region_consensus_df.to_csv(region_consensus_fp, sep="\t", index=False)

#     log(f"[DONE] saved: {kmin_fp}")
#     log(f"[DONE] saved: {comp_fp}")
#     log(f"[DONE] saved: {hit_fp}")
#     log(f"[DONE] saved: {partner_detail_fp}")
#     log(f"[DONE] saved: {partner_summary_fp}")
#     log(f"[DONE] saved: {rep_consensus_fp}")
#     log(f"[DONE] saved: {region_consensus_fp}")


# if __name__ == "__main__":
#     main()
#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import argparse
import pickle
import json
from collections import defaultdict, Counter

import numpy as np
import pandas as pd
import scanpy as sc


REGION_MAP = {
    "FTLD_PFC_Ctrl_Concat_QC_harmony_filted": "PFC",
    "SALS_PFC_control_concat_QC_harmony": "PFC",
    "FTLD_MCX_Control_Concat_QC_harmony_filted": "MCX",
    "SALS_MCX_control_concat_QC_harmony": "MCX"
}


def log(msg: str):
    print(msg, flush=True)


def to_bool(s: pd.Series) -> pd.Series:
    if s.dtype == bool:
        return s.fillna(False)
    s = s.fillna(False)
    if pd.api.types.is_numeric_dtype(s):
        return s.astype(float) != 0
    return s.astype(str).str.strip().str.lower().isin(["true", "t", "1", "yes", "y"])


def get_all_hit_clusters(df_hit: pd.DataFrame, call_by: str = "p", p_cut: float = 0.05):
    if "cluster" not in df_hit.columns:
        raise ValueError("df_hit does not contain 'cluster' column")

    df_hit = df_hit.copy()
    df_hit["cluster"] = df_hit["cluster"].astype(str)

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
        sig_mask = pd.to_numeric(df_hit["Donor_P"], errors="coerce") < p_cut
        return (
            df_hit.loc[sig_mask & dir_mask, "cluster"]
            .astype(str)
            .drop_duplicates()
            .tolist()
        )

    if call_by == "fdr" and "FDR_Donor" in df_hit.columns:
        sig_mask = pd.to_numeric(df_hit["FDR_Donor"], errors="coerce") < p_cut
        return (
            df_hit.loc[sig_mask & dir_mask, "cluster"]
            .astype(str)
            .drop_duplicates()
            .tolist()
        )

    raise ValueError("Cannot identify hit clusters from df_hit")


def ensure_neighbors(adata, use_rep="X_pca_harmony", n_neighbors=15, random_state=666):
    if "connectivities" in adata.obsp and adata.obsp["connectivities"].shape[0] == adata.n_obs:
        return

    if use_rep not in adata.obsm:
        raise ValueError(
            f"Neither neighbor graph nor {use_rep} was found in adata. "
            "Cannot rebuild clustering."
        )
    sc.pp.neighbors(adata, use_rep=use_rep, n_neighbors=n_neighbors, random_state=random_state)


def ensure_cluster_column(adata, cluster_key: str, resolution: float,
                          use_rep="X_pca_harmony", random_state=666):
    """
    如果 analysis_input.h5ad 中没有对应的 chosen_key，就按保存下来的 resolution 重新生成。
    """
    if cluster_key in adata.obs.columns:
        return

    ensure_neighbors(adata, use_rep=use_rep, random_state=random_state)
    sc.tl.leiden(
        adata,
        resolution=float(resolution),
        key_added=cluster_key,
        random_state=random_state
    )


def format_top_subtypes(series: pd.Series, top_n=5, exclude=None):
    s = series.copy()
    s = s[s > 0]

    if exclude is not None:
        if isinstance(exclude, (list, tuple, set)):
            s = s.drop(labels=[x for x in exclude if x in s.index], errors="ignore")
        else:
            s = s.drop(labels=[exclude], errors="ignore")

    if s.empty:
        return ""

    total = float(s.sum())
    out = []
    for subtype, n in s.sort_values(ascending=False).head(top_n).items():
        frac = 100.0 * float(n) / total if total > 0 else 0.0
        out.append(f"{subtype}:{int(n)}({frac:.1f}%)")
    return ";".join(out)


def safe_json(x):
    return json.dumps(x, ensure_ascii=False)


def choose_region_stable_subtypes(stable_df: pd.DataFrame, region: str):
    if stable_df.empty:
        return pd.DataFrame()

    stable_df = stable_df.copy()
    stable_df["stable_class"] = stable_df["stable_class"].astype(str)

    allowed = {"Cross_region_stable"}
    if region == "MCX":
        allowed.add("MCX_specific_stable")
    elif region == "PFC":
        allowed.add("PFC_specific_stable")
    else:
        raise ValueError(f"Unknown region: {region}")

    sub = stable_df[stable_df["stable_class"].isin(allowed)].copy()
    return sub


def classify_structure(capture_rate_any_hit,
                       n_hit_clusters,
                       purity_in_main_hit_cluster,
                       n_nonhit_clusters_with_subtype,
                       full_capture_cutoff=99.9,
                       purity_cutoff=70.0):
    if pd.isna(capture_rate_any_hit) or float(capture_rate_any_hit) <= 0 or int(n_hit_clusters) == 0:
        return "no_hit"

    if float(capture_rate_any_hit) >= full_capture_cutoff:
        if int(n_hit_clusters) == 1:
            if pd.notna(purity_in_main_hit_cluster) and float(purity_in_main_hit_cluster) >= purity_cutoff:
                return "single_pure_hit"
            return "single_mixed_hit"
        return "multi_hit_only"

    if int(n_nonhit_clusters_with_subtype) > 0:
        return "hit_nonhit_split"

    return "partial_hit"


def safe_read_tsv(fp):
    if not os.path.exists(fp):
        raise FileNotFoundError(fp)
    return pd.read_csv(fp, sep="\t")


def dominant_value(series: pd.Series):
    s = series.dropna().astype(str)
    if s.empty:
        return ""
    return s.value_counts().idxmax()


def summarize_partner_string(df_partner, group_cols, partner_col="partner_subtype",
                             weight_col="shared_subtype_cells", top_n=5):
    if df_partner.empty:
        return pd.DataFrame(columns=group_cols + ["top_partners"])

    rows = []
    for keys, sub in df_partner.groupby(group_cols):
        agg = (
            sub.groupby(partner_col, as_index=False)[weight_col]
            .sum()
            .sort_values(weight_col, ascending=False)
        )
        txt = ";".join(
            f"{r[partner_col]}:{int(r[weight_col])}"
            for _, r in agg.head(top_n).iterrows()
        )
        if not isinstance(keys, tuple):
            keys = (keys,)
        row = dict(zip(group_cols, keys))
        row["top_partners"] = txt
        rows.append(row)

    return pd.DataFrame(rows)


def build_consensus_rep(kmin_df: pd.DataFrame, partner_df: pd.DataFrame):
    if kmin_df.empty:
        return pd.DataFrame()

    structure_order = [
        "single_pure_hit",
        "single_mixed_hit",
        "multi_hit_only",
        "hit_nonhit_split",
        "partial_hit",
        "no_hit"
    ]

    rows = []
    group_cols = ["rep", "region", "prefix", "subtype", "stable_class"]

    for keys, sub in kmin_df.groupby(group_cols):
        sub = sub.copy()
        structure_counts = sub["structure_class"].value_counts()
        n_k = sub.shape[0]

        row = dict(zip(group_cols, keys))
        row["n_kmin_analyzed"] = int(n_k)
        row["mean_capture_rate_any_hit"] = sub["capture_rate_any_hit"].mean()
        row["mean_capture_rate_main_hit"] = sub["capture_rate_main_hit"].mean()
        row["mean_n_hit_clusters"] = sub["n_hit_clusters"].mean()
        row["mean_n_nonhit_clusters_with_subtype"] = sub["n_nonhit_clusters_with_subtype"].mean()
        row["most_common_structure_class"] = dominant_value(sub["structure_class"])
        row["top_main_hit_clusters"] = ";".join(
            f"{cl}:{cnt}" for cl, cnt in sub["main_hit_cluster"].dropna().astype(str).value_counts().head(5).items()
        )

        for cls in structure_order:
            row[f"prop_{cls}"] = float((sub["structure_class"] == cls).mean())

        rows.append(row)

    rep_df = pd.DataFrame(rows)

    partner_top = summarize_partner_string(
        df_partner=partner_df,
        group_cols=["rep", "region", "prefix", "subtype"],
        partner_col="partner_subtype",
        weight_col="shared_subtype_cells",
        top_n=5
    )

    if not partner_top.empty:
        rep_df = rep_df.merge(
            partner_top,
            on=["rep", "region", "prefix", "subtype"],
            how="left"
        )
    else:
        rep_df["top_partners"] = ""

    rep_df["top_partners"] = rep_df["top_partners"].fillna("")
    return rep_df


def build_consensus_region(kmin_df: pd.DataFrame, partner_df: pd.DataFrame):
    if kmin_df.empty:
        return pd.DataFrame()

    structure_order = [
        "single_pure_hit",
        "single_mixed_hit",
        "multi_hit_only",
        "hit_nonhit_split",
        "partial_hit",
        "no_hit"
    ]

    rows = []
    group_cols = ["region", "prefix", "subtype", "stable_class"]

    for keys, sub in kmin_df.groupby(group_cols):
        sub = sub.copy()
        row = dict(zip(group_cols, keys))
        row["n_rep_present"] = int(sub["rep"].nunique())
        row["reps_present"] = ",".join(sorted(sub["rep"].astype(str).unique().tolist()))
        row["n_kmin_analyzed"] = int(sub.shape[0])
        row["mean_capture_rate_any_hit"] = sub["capture_rate_any_hit"].mean()
        row["mean_capture_rate_main_hit"] = sub["capture_rate_main_hit"].mean()
        row["mean_n_hit_clusters"] = sub["n_hit_clusters"].mean()
        row["mean_n_nonhit_clusters_with_subtype"] = sub["n_nonhit_clusters_with_subtype"].mean()
        row["most_common_structure_class"] = dominant_value(sub["structure_class"])
        row["top_main_hit_clusters"] = ";".join(
            f"{cl}:{cnt}" for cl, cnt in sub["main_hit_cluster"].dropna().astype(str).value_counts().head(5).items()
        )

        for cls in structure_order:
            row[f"prop_{cls}"] = float((sub["structure_class"] == cls).mean())

        rows.append(row)

    region_df = pd.DataFrame(rows)

    partner_top = summarize_partner_string(
        df_partner=partner_df,
        group_cols=["region", "prefix", "subtype"],
        partner_col="partner_subtype",
        weight_col="shared_subtype_cells",
        top_n=5
    )

    if not partner_top.empty:
        region_df = region_df.merge(
            partner_top,
            on=["region", "prefix", "subtype"],
            how="left"
        )
    else:
        region_df["top_partners"] = ""

    region_df["top_partners"] = region_df["top_partners"].fillna("")
    return region_df


def analyze_one_rep_prefix(
    rep: str,
    prefix: str,
    region: str,
    repdir: str,
    stable_df: pd.DataFrame,
    org_col: str = "Org_celltype",
    use_rep: str = "X_pca_harmony",
    p_cut: float = 0.05,
    call_by: str = "p",
    purity_cutoff: float = 70.0,
    random_state: int = 666,
):
    summary_fp = os.path.join(repdir, f"{prefix}_all_subtypes_vulnerability_kmin_summary.tsv")
    pkl_fp = os.path.join(repdir, f"{prefix}_all_results.pkl")
    h5ad_fp = os.path.join(repdir, f"{prefix}_analysis_input.h5ad")

    if not os.path.exists(summary_fp):
        raise FileNotFoundError(summary_fp)
    if not os.path.exists(pkl_fp):
        raise FileNotFoundError(pkl_fp)
    if not os.path.exists(h5ad_fp):
        raise FileNotFoundError(h5ad_fp)

    region_stable_df = choose_region_stable_subtypes(stable_df, region)
    target_subtypes = sorted(region_stable_df["subtype"].astype(str).unique().tolist())
    stable_class_map = dict(
        zip(region_stable_df["subtype"].astype(str), region_stable_df["stable_class"].astype(str))
    )

    if len(target_subtypes) == 0:
        log(f"[INFO] {rep} {prefix}: no stable subtypes for region {region}.")
        return [], [], [], []

    log(f"[INFO] {rep} {prefix}: loading files ...")
    summary_df = safe_read_tsv(summary_fp)
    summary_df["subtype"] = summary_df["subtype"].astype(str)
    summary_df["k_min"] = pd.to_numeric(summary_df["k_min"], errors="coerce")

    summary_lookup = summary_df.set_index(["subtype", "k_min"], drop=False)

    with open(pkl_fp, "rb") as f:
        all_results = pickle.load(f)

    adata = sc.read_h5ad(h5ad_fp)
    if org_col not in adata.obs.columns:
        raise ValueError(f"{org_col} not found in {h5ad_fp}")
    adata.obs[org_col] = adata.obs[org_col].astype(str)

    kmin_structure_rows = []
    cluster_comp_rows = []
    hit_cluster_rows = []
    partner_rows = []

    for kmin in sorted(all_results.keys(), key=lambda x: int(x)):
        out = all_results[kmin]
        chosen = out.get("chosen", None)
        if chosen is None:
            continue

        k_hit = int(chosen["k"])
        chosen_r = float(chosen["r"])
        chosen_key = str(chosen["key"])
        chosen_cluster = str(chosen["cluster"])

        ensure_cluster_column(
            adata=adata,
            cluster_key=chosen_key,
            resolution=chosen_r,
            use_rep=use_rep,
            random_state=random_state
        )

        if chosen_key not in adata.obs.columns:
            raise RuntimeError(f"Failed to rebuild cluster key: {chosen_key}")

        obs = adata.obs[[org_col, chosen_key]].copy()
        obs[chosen_key] = obs[chosen_key].astype(str)
        obs[org_col] = obs[org_col].astype(str)

        df_hit = out["by_k"][k_hit]["df"].copy()
        df_hit["cluster"] = df_hit["cluster"].astype(str)

        hit_clusters = get_all_hit_clusters(df_hit, call_by=call_by, p_cut=p_cut)
        hit_set = set(hit_clusters)

        if len(hit_set) == 0:
            continue

        cluster_sizes = obs[chosen_key].value_counts().to_dict()
        cluster_subtype_counts = pd.crosstab(obs[chosen_key], obs[org_col])

        # hit cluster summary
        hit_only_df = df_hit[df_hit["cluster"].isin(hit_set)].copy()
        for _, hr in hit_only_df.iterrows():
            cl = str(hr["cluster"])
            cluster_size = int(cluster_sizes.get(cl, 0))

            if cl in cluster_subtype_counts.index:
                subtype_series = cluster_subtype_counts.loc[cl]
                subtype_series = subtype_series[subtype_series > 0].sort_values(ascending=False)

                dominant_subtype = subtype_series.index[0] if len(subtype_series) > 0 else ""
                dominant_cells = int(subtype_series.iloc[0]) if len(subtype_series) > 0 else 0
                dominant_frac = 100.0 * dominant_cells / cluster_size if cluster_size > 0 else np.nan
                n_subtypes = int(subtype_series.shape[0])
                top_subtypes = format_top_subtypes(subtype_series, top_n=8)
                subtype_count_json = safe_json({
                    str(k): int(v) for k, v in subtype_series.to_dict().items()
                })
            else:
                dominant_subtype = ""
                dominant_frac = np.nan
                n_subtypes = 0
                top_subtypes = ""
                subtype_count_json = "{}"

            hit_cluster_rows.append({
                "rep": rep,
                "region": region,
                "prefix": prefix,
                "k_min": int(kmin),
                "chosen_k": k_hit,
                "chosen_r": chosen_r,
                "chosen_key": chosen_key,
                "chosen_cluster": chosen_cluster,
                "cluster": cl,
                "is_hit_cluster": True,
                "Donor_P": hr["Donor_P"] if "Donor_P" in hr.index else np.nan,
                "FDR_Donor": hr["FDR_Donor"] if "FDR_Donor" in hr.index else np.nan,
                "Donor_log2_OR": hr["Donor_log2_OR"] if "Donor_log2_OR" in hr.index else np.nan,
                "direction_flag": hr["direction_flag"] if "direction_flag" in hr.index else "",
                "Significant_call": hr["Significant_call"] if "Significant_call" in hr.index else np.nan,
                "cluster_size": cluster_size,
                "dominant_subtype": dominant_subtype,
                "dominant_subtype_fraction": dominant_frac,
                "n_subtypes_in_cluster": n_subtypes,
                "top_subtypes": top_subtypes,
                "subtype_count_json": subtype_count_json,
            })

        # subtype-level structure
        for subtype in target_subtypes:
            sub_obs = obs[obs[org_col] == subtype].copy()
            total_cells = int(sub_obs.shape[0])
            if total_cells == 0:
                continue

            counts = sub_obs[chosen_key].value_counts()
            hit_counts = counts[counts.index.isin(hit_set)].sort_values(ascending=False)
            nonhit_counts = counts[~counts.index.isin(hit_set)].sort_values(ascending=False)

            cells_in_any_hit = int(hit_counts.sum()) if len(hit_counts) > 0 else 0
            capture_rate_any_hit = 100.0 * cells_in_any_hit / total_cells if total_cells > 0 else 0.0

            n_hit_clusters = int(len(hit_counts))
            n_nonhit_clusters_with_subtype = int(len(nonhit_counts))

            if len(hit_counts) > 0:
                main_hit_cluster = str(hit_counts.index[0])
                cells_in_main_hit_cluster = int(hit_counts.iloc[0])
                capture_rate_main_hit = 100.0 * cells_in_main_hit_cluster / total_cells
                main_cluster_size = int(cluster_sizes.get(main_hit_cluster, 0))
                purity_in_main_hit_cluster = (
                    100.0 * cells_in_main_hit_cluster / main_cluster_size
                    if main_cluster_size > 0 else np.nan
                )
            else:
                main_hit_cluster = np.nan
                cells_in_main_hit_cluster = 0
                capture_rate_main_hit = np.nan
                purity_in_main_hit_cluster = np.nan

            structure_class = classify_structure(
                capture_rate_any_hit=capture_rate_any_hit,
                n_hit_clusters=n_hit_clusters,
                purity_in_main_hit_cluster=purity_in_main_hit_cluster,
                n_nonhit_clusters_with_subtype=n_nonhit_clusters_with_subtype,
                purity_cutoff=purity_cutoff
            )

            if (subtype, float(kmin)) in summary_lookup.index:
                sr = summary_lookup.loc[(subtype, float(kmin))]
                stored_capture_rate_any_hit = sr["capture_rate_any_hit"]
                stored_main_hit_cluster = sr["main_hit_cluster"]
                stored_capture_rate_main_hit = sr["capture_rate_main_hit"]
                stored_purity_in_main_hit_cluster = sr["purity_in_main_hit_cluster"]
                stored_n_hit_clusters = sr["n_hit_clusters"]
            else:
                stored_capture_rate_any_hit = np.nan
                stored_main_hit_cluster = np.nan
                stored_capture_rate_main_hit = np.nan
                stored_purity_in_main_hit_cluster = np.nan
                stored_n_hit_clusters = np.nan

            shared_partner_counter = defaultdict(int)

            # composition rows
            for cl, n_cells in counts.items():
                cl = str(cl)
                cluster_size = int(cluster_sizes.get(cl, 0))
                frac_of_subtype = 100.0 * int(n_cells) / total_cells if total_cells > 0 else 0.0
                frac_of_cluster_from_subtype = (
                    100.0 * int(n_cells) / cluster_size if cluster_size > 0 else np.nan
                )

                if cl in cluster_subtype_counts.index:
                    subtype_series = cluster_subtype_counts.loc[cl]
                    top_other_subtypes = format_top_subtypes(
                        subtype_series,
                        top_n=6,
                        exclude=subtype
                    )
                    others = subtype_series.drop(labels=[subtype], errors="ignore")
                    others = others[others > 0]
                else:
                    top_other_subtypes = ""
                    others = pd.Series(dtype=float)

                cluster_comp_rows.append({
                    "rep": rep,
                    "region": region,
                    "prefix": prefix,
                    "subtype": subtype,
                    "stable_class": stable_class_map.get(subtype, ""),
                    "k_min": int(kmin),
                    "chosen_k": k_hit,
                    "chosen_r": chosen_r,
                    "chosen_key": chosen_key,
                    "chosen_cluster": chosen_cluster,
                    "cluster": cl,
                    "is_hit_cluster": cl in hit_set,
                    "n_cells_of_subtype_in_cluster": int(n_cells),
                    "frac_of_subtype": frac_of_subtype,
                    "cluster_size": cluster_size,
                    "frac_of_cluster_from_subtype": frac_of_cluster_from_subtype,
                    "top_other_subtypes": top_other_subtypes,
                })

                if cl in hit_set and not others.empty:
                    for partner_subtype, partner_cells in others.items():
                        shared_partner_counter[str(partner_subtype)] += int(n_cells)
                        partner_rows.append({
                            "rep": rep,
                            "region": region,
                            "prefix": prefix,
                            "subtype": subtype,
                            "stable_class": stable_class_map.get(subtype, ""),
                            "k_min": int(kmin),
                            "chosen_key": chosen_key,
                            "cluster": cl,
                            "partner_subtype": str(partner_subtype),
                            "shared_subtype_cells": int(n_cells),
                            "partner_cells_in_cluster": int(partner_cells),
                            "cluster_size": cluster_size,
                            "frac_of_subtype_in_this_hit_cluster": frac_of_subtype,
                        })

            top_partners_this_k = ";".join(
                f"{p}:{c}" for p, c in sorted(shared_partner_counter.items(), key=lambda x: (-x[1], x[0]))[:6]
            )

            kmin_structure_rows.append({
                "rep": rep,
                "region": region,
                "prefix": prefix,
                "subtype": subtype,
                "stable_class": stable_class_map.get(subtype, ""),
                "k_min": int(kmin),
                "chosen_k": k_hit,
                "chosen_r": chosen_r,
                "chosen_key": chosen_key,
                "chosen_cluster": chosen_cluster,
                "n_total_cells": total_cells,
                "cells_in_any_hit": cells_in_any_hit,
                "capture_rate_any_hit": round(capture_rate_any_hit, 4),
                "main_hit_cluster": main_hit_cluster,
                "cells_in_main_hit_cluster": cells_in_main_hit_cluster,
                "capture_rate_main_hit": round(capture_rate_main_hit, 4) if pd.notna(capture_rate_main_hit) else np.nan,
                "purity_in_main_hit_cluster": round(purity_in_main_hit_cluster, 4) if pd.notna(purity_in_main_hit_cluster) else np.nan,
                "n_hit_clusters": n_hit_clusters,
                "n_nonhit_clusters_with_subtype": n_nonhit_clusters_with_subtype,
                "all_hit_clusters": ",".join(sorted(hit_set)),
                "top_partners_this_kmin": top_partners_this_k,
                "structure_class": structure_class,
                # for checking consistency with your original summary file
                "stored_capture_rate_any_hit": stored_capture_rate_any_hit,
                "stored_main_hit_cluster": stored_main_hit_cluster,
                "stored_capture_rate_main_hit": stored_capture_rate_main_hit,
                "stored_purity_in_main_hit_cluster": stored_purity_in_main_hit_cluster,
                "stored_n_hit_clusters": stored_n_hit_clusters,
            })

    return kmin_structure_rows, cluster_comp_rows, hit_cluster_rows, partner_rows


def main():
    parser = argparse.ArgumentParser(
        description="Analyze cluster structure of final stable vulnerable subtypes."
    )
    parser.add_argument(
        "--outdir-base",
        required=True,
        help="Base directory containing rep subfolders"
    )
    parser.add_argument(
        "--final-summary-dir",
        required=True,
        help="Directory containing In_stable_classification.tsv and Ex_stable_classification.tsv"
    )
    parser.add_argument(
        "--outdir",
        required=True,
        help="Output directory for structure analysis tables"
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
    parser.add_argument("--org-col", default="Org_celltype")
    parser.add_argument("--use-rep", default="X_pca_harmony")
    parser.add_argument("--p-cut", type=float, default=0.05)
    parser.add_argument("--call-by", choices=["p", "fdr"], default="p")
    parser.add_argument("--purity-cutoff", type=float, default=70.0)
    parser.add_argument("--random-state", type=int, default=666)
    parser.add_argument("--in-prefix", default="In")
    parser.add_argument("--ex-prefix", default="Ex")
    args = parser.parse_args()

    os.makedirs(args.outdir, exist_ok=True)

    stable_tables = {}
    for prefix in [args.in_prefix, args.ex_prefix]:
        fp = os.path.join(args.final_summary_dir, f"{prefix}_stable_classification.tsv")
        if not os.path.exists(fp):
            raise FileNotFoundError(fp)
        stable_df = safe_read_tsv(fp)
        stable_df["subtype"] = stable_df["subtype"].astype(str)
        stable_df["stable_class"] = stable_df["stable_class"].astype(str)
        stable_tables[prefix] = stable_df

    all_kmin_rows = []
    all_comp_rows = []
    all_hit_rows = []
    all_partner_rows = []

    for rep in args.reps:
        if rep not in REGION_MAP:
            raise ValueError(f"{rep} not found in REGION_MAP")
        region = REGION_MAP[rep]
        repdir = os.path.join(args.outdir_base, rep)

        for prefix in [args.in_prefix, args.ex_prefix]:
            log(f"[INFO] Processing rep={rep}, region={region}, prefix={prefix}")
            k_rows, comp_rows, hit_rows, partner_rows = analyze_one_rep_prefix(
                rep=rep,
                prefix=prefix,
                region=region,
                repdir=repdir,
                stable_df=stable_tables[prefix],
                org_col=args.org_col,
                use_rep=args.use_rep,
                p_cut=args.p_cut,
                call_by=args.call_by,
                purity_cutoff=args.purity_cutoff,
                random_state=args.random_state,
            )
            all_kmin_rows.extend(k_rows)
            all_comp_rows.extend(comp_rows)
            all_hit_rows.extend(hit_rows)
            all_partner_rows.extend(partner_rows)

    kmin_df = pd.DataFrame(all_kmin_rows)
    comp_df = pd.DataFrame(all_comp_rows)
    hit_df = pd.DataFrame(all_hit_rows)
    partner_detail_df = pd.DataFrame(all_partner_rows)

    if not kmin_df.empty:
        partner_summary_df = (
            partner_detail_df.groupby(
                ["rep", "region", "prefix", "subtype", "stable_class", "partner_subtype"],
                as_index=False
            )
            .agg(
                n_kmin_shared=("k_min", "nunique"),
                n_hit_clusters_shared=("cluster", "nunique"),
                shared_subtype_cells=("shared_subtype_cells", "sum"),
                mean_frac_of_subtype_in_partnered_hit_clusters=("frac_of_subtype_in_this_hit_cluster", "mean"),
            )
            .sort_values(
                ["rep", "region", "prefix", "subtype", "shared_subtype_cells"],
                ascending=[True, True, True, True, False]
            )
        )
        rep_consensus_df = build_consensus_rep(kmin_df, partner_summary_df)
        region_consensus_df = build_consensus_region(kmin_df, partner_summary_df)
    else:
        partner_summary_df = pd.DataFrame()
        rep_consensus_df = pd.DataFrame()
        region_consensus_df = pd.DataFrame()

    # save
    kmin_fp = os.path.join(args.outdir, "stable_subtype_kmin_structure.tsv")
    comp_fp = os.path.join(args.outdir, "stable_subtype_cluster_composition.tsv")
    hit_fp = os.path.join(args.outdir, "stable_hit_cluster_summary.tsv")
    partner_detail_fp = os.path.join(args.outdir, "stable_subtype_partner_detail.tsv")
    partner_summary_fp = os.path.join(args.outdir, "stable_subtype_partner_summary.tsv")
    rep_consensus_fp = os.path.join(args.outdir, "stable_subtype_structure_consensus_rep.tsv")
    region_consensus_fp = os.path.join(args.outdir, "stable_subtype_structure_consensus_region.tsv")

    kmin_df.to_csv(kmin_fp, sep="\t", index=False)
    comp_df.to_csv(comp_fp, sep="\t", index=False)
    hit_df.to_csv(hit_fp, sep="\t", index=False)
    partner_detail_df.to_csv(partner_detail_fp, sep="\t", index=False)
    partner_summary_df.to_csv(partner_summary_fp, sep="\t", index=False)
    rep_consensus_df.to_csv(rep_consensus_fp, sep="\t", index=False)
    region_consensus_df.to_csv(region_consensus_fp, sep="\t", index=False)

    log(f"[DONE] saved: {kmin_fp}")
    log(f"[DONE] saved: {comp_fp}")
    log(f"[DONE] saved: {hit_fp}")
    log(f"[DONE] saved: {partner_detail_fp}")
    log(f"[DONE] saved: {partner_summary_fp}")
    log(f"[DONE] saved: {rep_consensus_fp}")
    log(f"[DONE] saved: {region_consensus_fp}")


if __name__ == "__main__":
    main()
