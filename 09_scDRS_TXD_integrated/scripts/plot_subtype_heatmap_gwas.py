# #!/usr/bin/env python
# import argparse
# import numpy as np
# import pandas as pd
# import scanpy as sc
# import matplotlib.pyplot as plt
# import matplotlib.colors as mcolors


# def main():
#     parser = argparse.ArgumentParser()
#     parser.add_argument("--input-h5ad", required=True)
#     parser.add_argument("--summary-tsv", required=True)
#     parser.add_argument("--mode", choices=["In", "Ex"], required=True)
#     parser.add_argument("--region", required=True)
#     parser.add_argument("--output-pdf", required=True)
#     parser.add_argument("--output-png", required=True)
#     parser.add_argument("--output-table", required=True)
#     parser.add_argument("--celltype-col", default="Org_celltype")
#     parser.add_argument("--score-col", default="scdrs_ppr")
#     args = parser.parse_args()

#     adata = sc.read_h5ad(args.input_h5ad)
#     if args.score_col not in adata.obs.columns:
#         raise ValueError(f"{args.score_col} not found in adata.obs")
#     df_obs = adata.obs[[args.celltype_col, args.score_col]].dropna().copy()
#     df_obs[args.celltype_col] = df_obs[args.celltype_col].astype(str)

#     if args.mode == "In":
#         mask_keep = df_obs[args.celltype_col].str.contains("PV", case=False, na=False) | df_obs[args.celltype_col].str.contains("5HT3aR", case=False, na=False)
#         df_obs = df_obs[mask_keep].copy()
#         df_obs[args.celltype_col] = df_obs[args.celltype_col].replace({
#             "In.5HT3aR.CDH4_CCK": "In.5HT3aR.CDH4",
#             "In.5HT3aR.CDH4_SCGN": "In.5HT3aR.CDH4",
#         })
#         cbar_label = "Z-score\nwithin PV + 5HT3aR"
#         title_prefix = f"ALS {args.region} In"
#     else:
#         df_obs = df_obs[df_obs[args.celltype_col].str.startswith("Ex.")].copy()
#         df_obs[args.celltype_col] = df_obs[args.celltype_col].replace({
#             "Ex.L5.VAT1L_EYA4": "Ex.L5.VAT1L_plus",
#             "Ex.L5.VAT1L_THSD4": "Ex.L5.VAT1L_plus",
#         })
#         cbar_label = "Z-score\nwithin Ex"
#         title_prefix = f"ALS {args.region} Ex"

#     # df_ct = df_obs.groupby(args.celltype_col, observed=True)[args.score_col].median().to_frame("median_score")
#     # ms = df_ct["median_score"]
#     # sd = ms.std(ddof=0)
#     # if sd == 0 or np.isnan(sd):
#     #     sd = 1.0
#     # df_ct["suscept_z"] = (ms - ms.mean()) / sd

#     s = df_obs["scdrs_ppr"].astype(float).replace([np.inf, -np.inf], np.nan)
#     sd = s.std(skipna=True)
#     if sd == 0 or np.isnan(sd):
#         sd = 1.0

#     df_obs["scdrs_ppr_z_panel"] = (s - s.mean(skipna=True)) / sd

#     df_ct = (
#         df_obs
#         .groupby(args.celltype_col, observed=True)["scdrs_ppr_z_panel"]
#         .median()
#         .to_frame("median_score")
#     )


#     df_enrich = pd.read_csv(args.summary_tsv, sep="\t")[["celltype", "n_sig_genes"]]
#     df_enrich["celltype"] = df_enrich["celltype"].astype(str)
#     if args.mode == "In":
#         df_enrich = df_enrich[df_enrich["celltype"].str.contains("PV", case=False, na=False) | df_enrich["celltype"].str.contains("5HT3aR", case=False, na=False)].copy()
#     else:
#         df_enrich = df_enrich[df_enrich["celltype"].str.startswith("Ex.")].copy()

#     df_plot = df_ct.merge(df_enrich, left_index=True, right_on="celltype", how="left").set_index("celltype")
#     df_plot = df_plot.dropna(subset=["median_score", "suscept_z"])
#     df_plot["n_sig_genes"] = df_plot["n_sig_genes"].fillna(0).astype(int)
#     df_plot = df_plot.sort_values("suscept_z", ascending=False)
#     df_plot.reset_index().to_csv(args.output_table, sep="\t", index=False)

#     n_ct = df_plot.shape[0]
#     ypos = np.arange(n_ct)
#     fig, (ax_heat, ax_bar) = plt.subplots(nrows=1, ncols=2, figsize=(7.5, 0.38 * n_ct + 1.3), gridspec_kw={"width_ratios": [0.45, 1.65]}, sharey=True)
#     vmax_abs = np.nanmax(np.abs(df_plot["suscept_z"].values))
#     if vmax_abs == 0 or np.isnan(vmax_abs):
#         vmax_abs = 1.0
#     norm = mcolors.TwoSlopeNorm(vmin=-vmax_abs, vcenter=0.0, vmax=vmax_abs)
#     im = ax_heat.imshow(df_plot[["suscept_z"]].values, aspect="auto", cmap="coolwarm", norm=norm, origin="upper")
#     ax_heat.set_xticks([])
#     ax_heat.set_yticks(ypos)
#     ax_heat.set_yticklabels([])
#     ax_heat.set_title("Median\nsusceptibility", fontsize=10)
#     cbar = plt.colorbar(im, ax=ax_heat, fraction=0.08, pad=0.04)
#     cbar.set_label(cbar_label, fontsize=8)

#     ax_bar.barh(ypos, df_plot["n_sig_genes"].values, edgecolor="none")
#     ax_bar.set_yticks(ypos)
#     ax_bar.set_yticklabels(df_plot.index, fontsize=8)
#     ax_bar.invert_yaxis(); ax_heat.invert_yaxis()
#     ax_bar.set_xlabel("# of enriched GWAS-linked genes")
#     ax_bar.set_title("GWAS gene enrichment", fontsize=10)
#     max_val = df_plot["n_sig_genes"].max()
#     if max_val == 0:
#         max_val = 1
#     for y, val in zip(ypos, df_plot["n_sig_genes"].values):
#         ax_bar.text(val + max_val * 0.02, y, str(val), va="center", ha="left", fontsize=8)
#     ax_bar.axvline(0, linewidth=0.5)
#     fig.suptitle(title_prefix, fontsize=12, y=1.02)
#     plt.tight_layout()
#     plt.savefig(args.output_pdf, bbox_inches="tight")
#     plt.savefig(args.output_png, dpi=300, bbox_inches="tight")
#     plt.close()

# if __name__ == "__main__":
#     main()
#!/usr/bin/env python
import argparse
import numpy as np
import pandas as pd
import scanpy as sc
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-h5ad", required=True)
    parser.add_argument("--summary-tsv", required=True)
    parser.add_argument("--mode", choices=["In", "Ex"], required=True)
    parser.add_argument("--region", required=True)
    parser.add_argument("--output-pdf", required=True)
    parser.add_argument("--output-png", required=True)
    parser.add_argument("--output-table", required=True)
    parser.add_argument("--celltype-col", default="Org_celltype")
    parser.add_argument("--score-col", default="scdrs_ppr")
    args = parser.parse_args()

    adata = sc.read_h5ad(args.input_h5ad)

    if args.score_col not in adata.obs.columns:
        raise ValueError(f"{args.score_col} not found in adata.obs")

    if args.celltype_col not in adata.obs.columns:
        raise ValueError(f"{args.celltype_col} not found in adata.obs")

    df_obs = adata.obs[[args.celltype_col, args.score_col]].dropna().copy()
    df_obs[args.celltype_col] = df_obs[args.celltype_col].astype(str)

    if args.mode == "In":
        mask_keep = (
            df_obs[args.celltype_col].str.contains("PV", case=False, na=False) |
            df_obs[args.celltype_col].str.contains("5HT3aR", case=False, na=False)
        )
        df_obs = df_obs[mask_keep].copy()

        df_obs[args.celltype_col] = df_obs[args.celltype_col].replace({
            "In.5HT3aR.CDH4_CCK": "In.5HT3aR.CDH4",
            "In.5HT3aR.CDH4_SCGN": "In.5HT3aR.CDH4",
            "Ex.L5.VAT1L_EYA4": "Ex.L5.VAT1L",
            "Ex.L5.VAT1L_THSD4": "Ex.L5.VAT1L",
        })

        cbar_label = "PPR-Z\nwithin PV + 5HT3aR"
        title_prefix = f"ALS {args.region} In"

    else:
        df_obs = df_obs[df_obs[args.celltype_col].str.startswith("Ex.")].copy()

        cbar_label = "PPR-Z\nwithin Ex"
        title_prefix = f"ALS {args.region} Ex"

    if df_obs.shape[0] == 0:
        raise ValueError(f"No cells left after mode filtering: {args.mode}")

    s = df_obs[args.score_col].astype(float).replace([np.inf, -np.inf], np.nan)
    sd = s.std(skipna=True)

    if sd == 0 or np.isnan(sd):
        sd = 1.0

    df_obs["scdrs_ppr_z_panel"] = (s - s.mean(skipna=True)) / sd

    df_ct = (
        df_obs
        .groupby(args.celltype_col, observed=True)["scdrs_ppr_z_panel"]
        .median()
        .to_frame("median_score")
    )

    df_enrich = pd.read_csv(args.summary_tsv, sep="\t")

    if "celltype" not in df_enrich.columns:
        raise ValueError("summary_tsv must contain column: celltype")

    if "n_sig_genes" not in df_enrich.columns:
        raise ValueError("summary_tsv must contain column: n_sig_genes")

    df_enrich = df_enrich[["celltype", "n_sig_genes"]].copy()
    df_enrich["celltype"] = df_enrich["celltype"].astype(str)

    if args.mode == "In":
        df_enrich = df_enrich[
            df_enrich["celltype"].str.contains("PV", case=False, na=False) |
            df_enrich["celltype"].str.contains("5HT3aR", case=False, na=False)
        ].copy()

        if df_enrich["celltype"].isin([
            "In.5HT3aR.CDH4_CCK",
            "In.5HT3aR.CDH4_SCGN"
        ]).any():
            raise ValueError(
                "summary_tsv contains unmerged CDH4 subtypes; "
                "rerun gwas_enrichment_merged.py with CDH4 merged."
            )

    else:
        df_enrich = df_enrich[df_enrich["celltype"].str.startswith("Ex.")].copy()

    df_plot = (
        df_ct
        .merge(df_enrich, left_index=True, right_on="celltype", how="left")
        .set_index("celltype")
    )

    df_plot = df_plot.dropna(subset=["median_score"])
    df_plot["n_sig_genes"] = df_plot["n_sig_genes"].fillna(0).astype(int)
    df_plot = df_plot.sort_values("median_score", ascending=False)

    df_plot.reset_index().to_csv(args.output_table, sep="\t", index=False)

    n_ct = df_plot.shape[0]

    if n_ct == 0:
        raise ValueError(f"No cell types left for plotting: {args.mode}")

    ypos = np.arange(n_ct)

    # ============================================================
    # Plot
    # colorbar is placed on the right side as an independent axis
    # ============================================================

    fig = plt.figure(figsize=(8.6, 0.38 * n_ct + 1.5))

    gs = fig.add_gridspec(
        nrows=1,
        ncols=3,
        width_ratios=[0.45, 1.90, 0.10],
        wspace=0.08
    )

    ax_heat = fig.add_subplot(gs[0, 0])
    ax_bar = fig.add_subplot(gs[0, 1], sharey=ax_heat)
    cax = fig.add_subplot(gs[0, 2])

    vmax_abs = np.nanmax(np.abs(df_plot["median_score"].values))
    if vmax_abs == 0 or np.isnan(vmax_abs):
        vmax_abs = 1.0

    norm = mcolors.TwoSlopeNorm(
        vmin=-vmax_abs,
        vcenter=0.0,
        vmax=vmax_abs,
    )

    im = ax_heat.imshow(
        df_plot[["median_score"]].values,
        aspect="auto",
        cmap="coolwarm",
        norm=norm,
        origin="upper",
    )

    ax_heat.set_xticks([])
    ax_heat.set_yticks(ypos)
    ax_heat.set_yticklabels([])
    ax_heat.set_title("Median\nsusceptibility", fontsize=10)

    # Right-side colorbar
    cbar = fig.colorbar(
        im,
        cax=cax,
        orientation="vertical"
    )
    cbar.set_label(cbar_label, fontsize=8)
    cbar.ax.tick_params(labelsize=7)

    ax_bar.barh(
        ypos,
        df_plot["n_sig_genes"].values,
        edgecolor="none"
    )

    ax_bar.set_yticks(ypos)
    ax_bar.set_yticklabels(df_plot.index, fontsize=8)

    # Only invert once because ax_bar shares y-axis with ax_heat
    ax_heat.invert_yaxis()

    ax_bar.set_xlabel("# of enriched GWAS-linked genes")
    ax_bar.set_title("GWAS gene enrichment", fontsize=10)

    max_val = df_plot["n_sig_genes"].max()
    if max_val == 0:
        max_val = 1

    for y, val in zip(ypos, df_plot["n_sig_genes"].values):
        ax_bar.text(
            val + max_val * 0.02,
            y,
            str(val),
            va="center",
            ha="left",
            fontsize=8,
        )

    ax_bar.axvline(0, linewidth=0.5)

    fig.suptitle(title_prefix, fontsize=12, y=0.99)

    fig.tight_layout(rect=[0, 0, 1, 0.96])

    plt.savefig(args.output_pdf, bbox_inches="tight")
    plt.savefig(args.output_png, dpi=300, bbox_inches="tight")
    plt.close()


if __name__ == "__main__":
    main()