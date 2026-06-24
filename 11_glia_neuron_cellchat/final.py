# ============================================================
# Full CellChat pipeline:
# h5ad -> CellChat RDS -> per-target altered interactions
#      -> main figure v4
#
# Final output:
#   results2/main_figure_cellchat_v4/
#
# This workflow combines:
#   1) Build all-target CellChat RDS objects
#   2) Run per-target CellChat interaction extraction
#   3) Compare PFC vs MCX altered interactions
#   4) Combine all altered interactions
#   5) Draw main figure v4 panels A-D
# ============================================================

PROJECT_DIR = "/root/autodl-tmp/jupyter/vulnerable_neurons/11_glia_neuron_cellchat"

# New-server interpreters
RSCRIPT = "/mnt/workspace/tools/envs/r-base2/bin/Rscript"
PYTHON = "/mnt/workspace/tools/envs/pysodb/bin/python"

# Input h5ad files
PFC_H5AD = "/root/autodl-tmp/download/control_pfc_count.h5ad"
MCX_H5AD = "/root/autodl-tmp/jupyter/prepare/data/SALS_MCX_control.h5ad"

# Scripts
# Main scripts should be under PROJECT_DIR/scripts.
# If mainfig_build_cellchat_all_targets.R only exists in cellchat_main_figure_pipeline/scripts,
# copy it into PROJECT_DIR/scripts or change RDS_SCRIPT_DIR below.
SCRIPT_DIR = f"{PROJECT_DIR}/scripts"
RDS_SCRIPT_DIR = f"{PROJECT_DIR}/scripts"

# Use results2 to avoid mixing with your old partial runs.
RESULT_DIR = f"{PROJECT_DIR}/results"

LOG_DIR = f"{RESULT_DIR}/logs/full_h5ad_to_mainfig_v4"

OBJ_DIR = f"{RESULT_DIR}/cellchat_objects_main_figure"
CELLCHAT_DIR = f"{RESULT_DIR}/cellchat_per_target"
MAINFIG_DIR = f"{RESULT_DIR}/main_figure_cellchat_v4"

# ============================================================
# Cell type / target settings
# ============================================================

CELLTYPE_COL = "Org_celltype"
MIN_CELLS = 10

TARGETS = ["PTHLH", "CEMIP", "THSD4", "PCP4_NXPH2", "CDH4_plus"]

TARGET_MAP = {
    "PTHLH": "In.PV.PVALB_PTHLH",
    "CEMIP": "In.PV.PVALB_CEMIP",
    "THSD4": "Ex.L5.VAT1L_THSD4",
    "PCP4_NXPH2": "Ex.L5.PCP4_NXPH2",
    "CDH4_plus": "In.5HT3aR.CDH4_CCK,In.5HT3aR.CDH4_SCGN",
}

DIRECTIONS = ["glia_to_neuron", "neuron_to_glia"]

# ============================================================
# Main figure v4 parameters
# ============================================================

PANELC_TOP_CLASSES = 6
PANELD_TOP_PAIRS = 24
PANELD_TOP_TERMS = 20
PANELD_MIN_GENES = 3

PFC_CELLCHAT_RDS = f"{OBJ_DIR}/PFC_all_targets_cellchat.rds"
MCX_CELLCHAT_RDS = f"{OBJ_DIR}/MCX_all_targets_cellchat.rds"

ALTERED_ALL = f"{CELLCHAT_DIR}/all_targets_all_directions_altered_interactions.tsv"

# ============================================================
# Final outputs
# ============================================================

rule all:
    input:
        # Upstream CellChat RDS
        PFC_CELLCHAT_RDS,
        MCX_CELLCHAT_RDS,

        # Combined altered interaction table
        ALTERED_ALL,

        # Main figure v4 outputs
        f"{MAINFIG_DIR}/panelA_global_circle.pdf",
        f"{MAINFIG_DIR}/panelA_global_circle.png",
        f"{MAINFIG_DIR}/panelA_global_strength.tsv",

        f"{MAINFIG_DIR}/panelB_top_differential_network.pdf",
        f"{MAINFIG_DIR}/panelB_top_differential_network.png",
        f"{MAINFIG_DIR}/panelB_top_differential_network_edges.tsv",

        f"{MAINFIG_DIR}/panelC_MCX_higher_alluvial.pdf",
        f"{MAINFIG_DIR}/panelC_MCX_higher_alluvial.png",
        f"{MAINFIG_DIR}/panelC_MCX_higher_alluvial_selected.tsv",

        f"{MAINFIG_DIR}/panelD_GO_by_pair_heatmap.pdf",
        f"{MAINFIG_DIR}/panelD_GO_by_pair_heatmap.png",
        f"{MAINFIG_DIR}/panelD_GO_by_pair_long.tsv",
        f"{MAINFIG_DIR}/panelD_GO_by_pair_matrix.tsv"


# ============================================================
# Step 1: Build all-target CellChat RDS objects
# h5ad -> PFC/MCX CellChat RDS
# ============================================================

rule build_cellchat_all_targets:
    input:
        h5ad=lambda wc: PFC_H5AD if wc.region == "PFC" else MCX_H5AD,
        script=f"{RDS_SCRIPT_DIR}/mainfig_build_cellchat_all_targets.R"
    output:
        rds=f"{OBJ_DIR}/{{region}}_all_targets_cellchat.rds",
        interactions=f"{OBJ_DIR}/{{region}}_all_targets_interactions.tsv",
        aggregate=f"{OBJ_DIR}/{{region}}_all_targets_aggregate_strength.tsv"
    log:
        f"{LOG_DIR}/build_cellchat_all_targets_{{region}}.log"
    params:
        region=lambda wc: wc.region,
        celltype_col=CELLTYPE_COL,
        min_cells=MIN_CELLS
    shell:
        r"""
        mkdir -p {OBJ_DIR} {LOG_DIR}

        echo "[INFO] Region: {params.region}" > {log}
        echo "[INFO] h5ad: {input.h5ad}" >> {log}
        echo "[INFO] Rscript: {RSCRIPT}" >> {log}
        echo "[INFO] Python: {PYTHON}" >> {log}
        echo "[INFO] celltype column: {params.celltype_col}" >> {log}
        echo "[INFO] min cells: {params.min_cells}" >> {log}

        {RSCRIPT} {input.script} \
          --h5ad {input.h5ad} \
          --out-rds {output.rds} \
          --out-interactions {output.interactions} \
          --out-aggregate {output.aggregate} \
          --region {params.region} \
          --celltype-col {params.celltype_col} \
          --min-cells {params.min_cells} \
          --python {PYTHON} >> {log} 2>&1

        test -s {output.rds}
        test -s {output.interactions}
        test -s {output.aggregate}
        """


# ============================================================
# Step 2: Run per-target CellChat extraction
# h5ad -> per-target / per-region interaction table
# ============================================================

rule run_cellchat_region_target:
    input:
        h5ad=lambda wc: PFC_H5AD if wc.region == "PFC" else MCX_H5AD,
        script=f"{SCRIPT_DIR}/run_cellchat_region_target.R"
    output:
        tsv=f"{CELLCHAT_DIR}/{{target}}/{{region}}/cellchat_interactions.tsv"
    log:
        f"{LOG_DIR}/run_cellchat_{{target}}_{{region}}.log"
    params:
        region=lambda wc: wc.region,
        target_labels=lambda wc: TARGET_MAP[wc.target]
    shell:
        r"""
        mkdir -p {CELLCHAT_DIR}/{wildcards.target}/{wildcards.region} {LOG_DIR}

        {RSCRIPT} {input.script} \
          {input.h5ad} \
          {output.tsv} \
          "{params.region}" \
          "{wildcards.target}" \
          "{params.target_labels}" \
          > {log} 2>&1

        test -s {output.tsv}
        """


# ============================================================
# Step 3: Compare PFC vs MCX for each target and direction
# per-target PFC/MCX interaction tables -> altered_interactions.tsv
# ============================================================

rule compare_target_direction:
    input:
        pfc=f"{CELLCHAT_DIR}/{{target}}/PFC/cellchat_interactions.tsv",
        mcx=f"{CELLCHAT_DIR}/{{target}}/MCX/cellchat_interactions.tsv",
        script=f"{SCRIPT_DIR}/compare_target_interactions.R"
    output:
        altered=f"{CELLCHAT_DIR}/{{target}}/{{direction}}/altered_interactions.tsv",
        top_mcx=f"{CELLCHAT_DIR}/{{target}}/{{direction}}/top_MCX_higher_interactions.tsv",
        top_pfc=f"{CELLCHAT_DIR}/{{target}}/{{direction}}/top_PFC_higher_interactions.tsv"
    log:
        f"{LOG_DIR}/compare_{{target}}_{{direction}}.log"
    params:
        direction=lambda wc: wc.direction
    shell:
        r"""
        mkdir -p {CELLCHAT_DIR}/{wildcards.target}/{wildcards.direction} {LOG_DIR}

        {RSCRIPT} {input.script} \
          {input.pfc} \
          {input.mcx} \
          {output.altered} \
          "{wildcards.target}" \
          "{params.direction}" \
          > {log} 2>&1

        test -s {output.altered}
        """


# ============================================================
# Step 4: Combine all target/direction altered interactions
# altered_interactions.tsv -> all_targets_all_directions_altered_interactions.tsv
# ============================================================

rule combine_all_altered_interactions:
    input:
        altered=expand(
            f"{CELLCHAT_DIR}/{{target}}/{{direction}}/altered_interactions.tsv",
            target=TARGETS,
            direction=DIRECTIONS
        ),
        script=f"{SCRIPT_DIR}/combine_all_altered_interactions.R"
    output:
        altered_all=ALTERED_ALL
    log:
        f"{LOG_DIR}/combine_all_altered_interactions.log"
    shell:
        r"""
        mkdir -p {CELLCHAT_DIR} {LOG_DIR}

        {RSCRIPT} {input.script} \
          {CELLCHAT_DIR} \
          {output.altered_all} \
          > {log} 2>&1

        test -s {output.altered_all}
        """


# ============================================================
# Step 5A: Panel A - global CellChat circle plots
# ============================================================

rule panelA_global_circle:
    input:
        pfc_rds=PFC_CELLCHAT_RDS,
        mcx_rds=MCX_CELLCHAT_RDS,
        script=f"{SCRIPT_DIR}/mainfig_panelA_cellchat_circle.R"
    output:
        pdf=f"{MAINFIG_DIR}/panelA_global_circle.pdf",
        png=f"{MAINFIG_DIR}/panelA_global_circle.png",
        tsv=f"{MAINFIG_DIR}/panelA_global_strength.tsv"
    log:
        f"{LOG_DIR}/panelA_global_circle.log"
    shell:
        r"""
        mkdir -p {MAINFIG_DIR} {LOG_DIR}

        {RSCRIPT} {input.script} \
          {input.pfc_rds} \
          {input.mcx_rds} \
          {output.pdf} \
          {output.png} \
          {output.tsv} \
          > {log} 2>&1

        test -s {output.pdf}
        test -s {output.png}
        test -s {output.tsv}
        """


# ============================================================
# Step 5B: Panel B - top differential glia -> vulnerable neuron network
# ============================================================

rule panelB_top_differential_network:
    input:
        pfc_rds=PFC_CELLCHAT_RDS,
        mcx_rds=MCX_CELLCHAT_RDS,
        script=f"{SCRIPT_DIR}/mainfig_panelB_cellchat_diffInteraction.R"
    output:
        pdf=f"{MAINFIG_DIR}/panelB_top_differential_network.pdf",
        png=f"{MAINFIG_DIR}/panelB_top_differential_network.png",
        edges=f"{MAINFIG_DIR}/panelB_top_differential_network_edges.tsv"
    log:
        f"{LOG_DIR}/panelB_top_differential_network.log"
    params:
        top_frac=0.90,
        measure="weight"
    shell:
        r"""
        mkdir -p {MAINFIG_DIR} {LOG_DIR}

        {RSCRIPT} {input.script} \
          {input.mcx_rds} \
          {input.pfc_rds} \
          {output.pdf} \
          {output.png} \
          {output.edges} \
          {params.top_frac} \
          {params.measure} \
          > {log} 2>&1

        test -s {output.pdf}
        test -s {output.png}
        test -s {output.edges}
        """


# ============================================================
# Step 5C: Panel C - MCX-higher interaction-class alluvial plot
# ============================================================

rule panelC_MCX_higher_alluvial:
    input:
        altered=ALTERED_ALL,
        script=f"{SCRIPT_DIR}/mainfig_panelC_mcx_higher_alluvial.R"
    output:
        pdf=f"{MAINFIG_DIR}/panelC_MCX_higher_alluvial.pdf",
        png=f"{MAINFIG_DIR}/panelC_MCX_higher_alluvial.png",
        selected=f"{MAINFIG_DIR}/panelC_MCX_higher_alluvial_selected.tsv"
    log:
        f"{LOG_DIR}/panelC_MCX_higher_alluvial.log"
    params:
        top_classes=PANELC_TOP_CLASSES,
        min_abs_delta=0
    shell:
        r"""
        mkdir -p {MAINFIG_DIR} {LOG_DIR}

        {RSCRIPT} {input.script} \
          {input.altered} \
          {output.pdf} \
          {output.png} \
          {output.selected} \
          {params.top_classes} \
          {params.min_abs_delta} \
          > {log} 2>&1

        test -s {output.pdf}
        test -s {output.png}
        test -s {output.selected}
        """


# ============================================================
# Step 5D: Panel D - GO heatmap by interacting glia-neuron pairs
# ============================================================

rule panelD_GO_by_pair_heatmap:
    input:
        altered=ALTERED_ALL,
        script=f"{SCRIPT_DIR}/mainfig_panelD_GO_by_pair_heatmap.R"
    output:
        pdf=f"{MAINFIG_DIR}/panelD_GO_by_pair_heatmap.pdf",
        png=f"{MAINFIG_DIR}/panelD_GO_by_pair_heatmap.png",
        long=f"{MAINFIG_DIR}/panelD_GO_by_pair_long.tsv",
        matrix=f"{MAINFIG_DIR}/panelD_GO_by_pair_matrix.tsv"
    log:
        f"{LOG_DIR}/panelD_GO_by_pair_heatmap.log"
    params:
        top_pairs=PANELD_TOP_PAIRS,
        top_terms=PANELD_TOP_TERMS,
        min_genes=PANELD_MIN_GENES
    shell:
        r"""
        mkdir -p {MAINFIG_DIR} {LOG_DIR}

        {RSCRIPT} {input.script} \
          {input.altered} \
          {output.pdf} \
          {output.png} \
          {output.long} \
          {output.matrix} \
          {params.top_pairs} \
          {params.top_terms} \
          {params.min_genes} \
          > {log} 2>&1

        test -s {output.pdf}
        test -s {output.png}
        test -s {output.long}
        test -s {output.matrix}
        """
