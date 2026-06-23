
#!/usr/bin/env python

import argparse
import numpy as np
import scanpy as sc
import matplotlib.pyplot as plt
from matplotlib.patches import Ellipse


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


def add_ellipse(
    ax,
    adata,
    group_col,
    group,
    label,
    core_frac=0.65,
    pad_factor=1.30,
    min_width=0.6,
    min_height=0.6,
    label_fontsize=10,
):
    """
    Draw ellipse around the dense core of a target group.

    This avoids huge ellipses caused by elongated UMAP tails.
    """

    if "X_umap" not in adata.obsm:
        raise ValueError("X_umap not found in adata.obsm")

    umap = adata.obsm["X_umap"]
    mask = adata.obs[group_col].astype(str).eq(group).values
    xy = umap[mask, :]

    if xy.shape[0] == 0:
        print(f"[Warning] no cells found for {group}")
        return

    # =========================
    # 1. Find dense core cells
    # =========================
    center0 = np.median(xy, axis=0)

    dist = np.sqrt(
        (xy[:, 0] - center0[0]) ** 2 +
        (xy[:, 1] - center0[1]) ** 2
    )

    cutoff = np.quantile(dist, core_frac)
    xy_core = xy[dist <= cutoff, :]

    if xy_core.shape[0] < 10:
        xy_core = xy

    x_center = np.median(xy_core[:, 0])
    y_center = np.median(xy_core[:, 1])

    # Use robust range of the dense core
    x_q1, x_q2 = np.percentile(xy_core[:, 0], [5, 95])
    y_q1, y_q2 = np.percentile(xy_core[:, 1], [5, 95])

    x_width = max((x_q2 - x_q1) * pad_factor, min_width)
    y_width = max((y_q2 - y_q1) * pad_factor, min_height)

    ellipse = Ellipse(
        (x_center, y_center),
        x_width,
        y_width,
        angle=0,
        fill=False,
        edgecolor="black",
        linewidth=2.4,
        linestyle="--",
    )
    ax.add_patch(ellipse)

    # =========================
    # 2. Smart label placement
    # =========================
    xmin, xmax = ax.get_xlim()
    ymin, ymax = ax.get_ylim()

    x_range = xmax - xmin
    y_range = ymax - ymin

    x_pad = x_range * 0.025
    y_pad = y_range * 0.025

    rel_x = (x_center - xmin) / x_range
    rel_y = (y_center - ymin) / y_range

    # Right-edge cluster: put label to the LEFT of ellipse
    if rel_x > 0.68:
        label_x = x_center - x_width / 2 - x_pad
        label_y = y_center
        ha = "right"
        va = "center"

    # Left-edge cluster: put label to the RIGHT of ellipse
    elif rel_x < 0.32:
        label_x = x_center + x_width / 2 + x_pad
        label_y = y_center
        ha = "left"
        va = "center"

    # Top cluster: put label below ellipse
    elif rel_y > 0.75:
        label_x = x_center
        label_y = y_center - y_width / 2 - y_pad
        ha = "center"
        va = "top"

    # Default: put label above ellipse
    else:
        label_x = x_center
        label_y = y_center + y_width / 2 + y_pad
        ha = "center"
        va = "bottom"

    # Keep anchor inside axes
    label_x = np.clip(label_x, xmin + x_pad, xmax - x_pad)
    label_y = np.clip(label_y, ymin + y_pad, ymax - y_pad)

    ax.text(
        label_x,
        label_y,
        label,
        fontsize=label_fontsize,
        ha=ha,
        va=va,
        weight="bold",
        color="black",
        clip_on=True,
        bbox=dict(
            facecolor="white",
            edgecolor="none",
            alpha=0.70,
            pad=1.5,
        ),
    )


def main():
    parser = argparse.ArgumentParser()

    parser.add_argument("--input-h5ad", required=True)
    parser.add_argument("--mode", choices=["In", "Ex"], required=True)
    parser.add_argument("--region", required=True)
    parser.add_argument("--output-pdf", required=True)
    parser.add_argument("--output-png", required=True)
    parser.add_argument("--output-table", required=True)

    parser.add_argument("--celltype-col", default="Org_celltype")
    parser.add_argument("--score-col", default="scdrs_ppr")

    # Optional controls
    parser.add_argument("--label-fontsize", type=float, default=10)
    parser.add_argument("--use-full-label", action="store_true")

    parser.add_argument("--core-frac-default", type=float, default=0.65)
    parser.add_argument("--core-frac-cemip", type=float, default=0.50)
    parser.add_argument("--core-frac-cdh4", type=float, default=0.70)
    parser.add_argument("--core-frac-vat1l", type=float, default=0.65)

    args = parser.parse_args()

    adata = sc.read_h5ad(args.input_h5ad)

    if args.score_col not in adata.obs.columns:
        raise ValueError(
            f"{args.score_col} not found. Run compute_ppr_score.py first."
        )

    if args.celltype_col not in adata.obs.columns:
        raise ValueError(
            f"{args.celltype_col} not found in adata.obs"
        )

    if "X_umap" not in adata.obsm:
        raise ValueError("X_umap not found in adata.obsm")

    org = adata.obs[args.celltype_col].astype(str)

    # =========================
    # 1. Select cells and merge subtypes
    # =========================
    if args.mode == "In":
        mask_keep = (
            org.str.contains("PV", case=False, na=False) |
            org.str.contains("5HT3aR", case=False, na=False)
        )

        ad = adata[mask_keep].copy()

        ad.obs["plot_group"] = merge_subtypes(
            ad.obs[args.celltype_col],
            mode="In",
        )

        target_groups = [
            "In.PV.PVALB_PTHLH",
            "In.PV.PVALB_CEMIP",
            "In.5HT3aR.CDH4",
        ]

        if args.use_full_label:
            label_map = {
                "In.PV.PVALB_PTHLH": "In.PV.PVALB_PTHLH",
                "In.PV.PVALB_CEMIP": "In.PV.PVALB_CEMIP",
                "In.5HT3aR.CDH4": "In.5HT3aR.CDH4",
            }
        else:
            label_map = {
                "In.PV.PVALB_PTHLH": "PTHLH",
                "In.PV.PVALB_CEMIP": "CEMIP",
                "In.5HT3aR.CDH4": "CDH4",
            }

        title = f"ALS {args.region} scDRS PPR-Z in PV and 5HT3aR neurons"
        size = 8

    else:
        mask_keep = org.str.startswith("Ex.", na=False)

        ad = adata[mask_keep].copy()

        ad.obs["plot_group"] = merge_subtypes(
            ad.obs[args.celltype_col],
            mode="Ex",
        )

        target_groups = [
            "Ex.L5.VAT1L",
            "Ex.L5.PCP4_NXPH2",
        ]

        if args.use_full_label:
            label_map = {
                "Ex.L5.VAT1L": "Ex.L5.VAT1L",
                "Ex.L5.PCP4_NXPH2": "Ex.L5.PCP4_NXPH2",
            }
        else:
            label_map = {
                "Ex.L5.VAT1L": "VAT1L",
                "Ex.L5.PCP4_NXPH2": "PCP4_NXPH2",
            }

        title = f"ALS {args.region} scDRS PPR-Z in excitatory neurons"
        size = 6

    if ad.n_obs == 0:
        raise ValueError(f"No cells left for {args.region} {args.mode}")

    # =========================
    # 2. Z-score within displayed panel
    # =========================
    s = ad.obs[args.score_col].astype(float).replace([np.inf, -np.inf], np.nan)

    sd = s.std(skipna=True)
    if sd == 0 or np.isnan(sd):
        sd = 1.0

    ad.obs["scdrs_ppr_z_display"] = (s - s.mean(skipna=True)) / sd

    # =========================
    # 3. Output median score table
    # =========================
    summary = (
        ad.obs
        .groupby("plot_group", observed=True)["scdrs_ppr_z_display"]
        .median()
        .sort_values(ascending=False)
        .reset_index()
        .rename(columns={
            "scdrs_ppr_z_display": "median_display_ppr_z"
        })
    )

    summary.to_csv(args.output_table, sep="\t", index=False)

    # =========================
    # 4. Plot UMAP
    # =========================
    ax = sc.pl.umap(
        ad,
        color="scdrs_ppr_z_display",
        cmap="coolwarm",
        vmin=-2,
        vmax=2,
        size=size,
        alpha=0.9,
        title=title,
        show=False,
    )

    # =========================
    # 5. Add ellipses
    # =========================
    for group in target_groups:
        if group == "In.PV.PVALB_CEMIP":
            core_frac = args.core_frac_cemip
            pad_factor = 1.20

        elif group == "In.5HT3aR.CDH4":
            core_frac = args.core_frac_cdh4
            pad_factor = 1.25

        elif group == "Ex.L5.VAT1L":
            core_frac = args.core_frac_vat1l
            pad_factor = 1.25

        else:
            core_frac = args.core_frac_default
            pad_factor = 1.30

        add_ellipse(
            ax=ax,
            adata=ad,
            group_col="plot_group",
            group=group,
            label=label_map[group],
            core_frac=core_frac,
            pad_factor=pad_factor,
            min_width=0.6,
            min_height=0.6,
            label_fontsize=args.label_fontsize,
        )

    plt.tight_layout()
    plt.savefig(args.output_pdf, bbox_inches="tight")
    plt.savefig(args.output_png, dpi=300, bbox_inches="tight")
    plt.close()

    print("[saved]", args.output_table)
    print("[saved]", args.output_pdf)
    print("[saved]", args.output_png)


if __name__ == "__main__":
    main()