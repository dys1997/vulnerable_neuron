

PIPELINE_DIR = "/root/autodl-tmp/jupyter/vulnerable_neurons/09_scDRS_TXD_integrated"
SCRIPT_DIR   = f"{PIPELINE_DIR}/scripts"
OUTDIR       = f"{PIPELINE_DIR}/results"

PYTHON  = "/mnt/workspace/tools/envs/pysodb/bin/python"
RSCRIPT = "/mnt/workspace/tools/envs/r-base2/bin/Rscript"

REGIONS = ["PFC", "MCX"]
MODES   = ["In", "Ex"]

TXD_CASES = ["SALS_PFC", "SALS_MCX"]
TXD_CORR_MODES = ["all", "neuron"]

TXD_GO_CASES = ["SALS_PFC", "SALS_MCX"]

H5AD = {
    "PFC": "/root/autodl-tmp/jupyter/prepare/harmony/SALS_PFC_control_concat_QC_harmony_VulnAnnotation.h5ad",
    "MCX": "/root/autodl-tmp/jupyter/prepare/harmony/SALS_MCX_control_concat_QC_harmony_VulnAnnotation.h5ad",
}

SCDRS_SCORE = {
    "PFC": "/root/autodl-tmp/jupyter/GWAS_ALS/scDRS_out/ALS_PFC/ALS.score.gz",
    "MCX": "/root/autodl-tmp/jupyter/GWAS_ALS/scDRS_out/ALS_MCX/ALS.score.gz",
}

GWAS_GS = "/root/autodl-tmp/jupyter/GWAS_ALS/ALS_top1000.symbol.gs"

TXD_H5AD = {
    "SALS_PFC": "/root/autodl-tmp/jupyter/prepare/data/SALS_PFC_control_concat.h5ad",
    "SALS_MCX": "/root/autodl-tmp/jupyter/prepare/data/SALS_MCX_control_concat.h5ad",
}

TXD_GROUP_COL = {
    "SALS_PFC": "Group",
    "SALS_MCX": "Group",
}

TXD_GROUPS = {
    "SALS_PFC": "PN ALS",
    "SALS_MCX": "PN ALS",
}

TXD_CONTROL = {
    "SALS_PFC": "PN",
    "SALS_MCX": "PN",
}

TXD_DISEASE = {
    "SALS_PFC": "ALS",
    "SALS_MCX": "ALS",
}

TXD_REGION = {
    "SALS_PFC": "PFC",
    "SALS_MCX": "MCX",
}

TXD_TRAIT = {
    "SALS_PFC": "ALS",
    "SALS_MCX": "ALS",
}

SUSCEPT_H5AD = {
    "SALS_PFC": f"{OUTDIR}/PFC/adata_PFC_scdrs_ppr.h5ad",
    "SALS_MCX": f"{OUTDIR}/MCX/adata_MCX_scdrs_ppr.h5ad",
}

SUSCEPT_CONTROL = {
    "SALS_PFC": "PN",
    "SALS_MCX": "PN",
}

COMBINED_MODES = ["In", "Ex"]

rule all:
    input:
        expand(f"{OUTDIR}/{{region}}/adata_{{region}}_scdrs_ppr.h5ad", region=REGIONS),

        expand(f"{OUTDIR}/{{region}}/gwas_enrichment/ALS_top1000_gwas_enrichment_summary_merged.tsv", region=REGIONS),
        expand(f"{OUTDIR}/{{region}}/gwas_enrichment/ALS_top1000_gwas_enrichment_detail_merged.tsv", region=REGIONS),
        expand(f"{OUTDIR}/{{region}}/gwas_enrichment/ALS_celltype_stats_merged.tsv", region=REGIONS),

        expand(f"{OUTDIR}/{{region}}/figures/{{mode}}_scDRS_PPRZ_umap.pdf", region=REGIONS, mode=MODES),
        expand(f"{OUTDIR}/{{region}}/figures/{{mode}}_scDRS_PPRZ_umap.png", region=REGIONS, mode=MODES),
        expand(f"{OUTDIR}/{{region}}/tables/{{mode}}_scDRS_PPRZ_umap_median.tsv", region=REGIONS, mode=MODES),

        expand(f"{OUTDIR}/{{region}}/figures/{{mode}}_subtype_median_scDRS_GWAS.pdf", region=REGIONS, mode=MODES),
        expand(f"{OUTDIR}/{{region}}/figures/{{mode}}_subtype_median_scDRS_GWAS.png", region=REGIONS, mode=MODES),
        expand(f"{OUTDIR}/{{region}}/tables/{{mode}}_subtype_median_scDRS_GWAS.tsv", region=REGIONS, mode=MODES),

        # expand(f"{OUTDIR}/txd/{{case}}/txd_pseudobulk_build_summary.tsv", case=TXD_CASES),
        # expand(f"{OUTDIR}/txd/{{case}}/TxD_by_subtype_logmean.tsv", case=TXD_CASES),

        # expand(f"{OUTDIR}/txd_correlation/{{case}}/{{case}}_{{mode}}_suscept_TxD_correlation.tsv", case=TXD_CASES, mode=TXD_CORR_MODES),
        # expand(f"{OUTDIR}/txd_correlation/{{case}}/{{case}}_{{mode}}_suscept_TxD_matched.tsv", case=TXD_CASES, mode=TXD_CORR_MODES),
        # expand(f"{OUTDIR}/txd_correlation/{{case}}/{{case}}_{{mode}}_suscept_TxD_heatmap.pdf", case=TXD_CASES, mode=TXD_CORR_MODES),
        # expand(f"{OUTDIR}/txd_correlation/{{case}}/{{case}}_{{mode}}_suscept_TxD_heatmap.png", case=TXD_CASES, mode=TXD_CORR_MODES),
        # expand(f"{OUTDIR}/combined/Combined_{{mode}}_susceptibility_GWAS.pdf", mode=COMBINED_MODES),
        # expand(f"{OUTDIR}/combined/Combined_{{mode}}_susceptibility_GWAS.png", mode=COMBINED_MODES),
        # expand(f"{OUTDIR}/combined/Combined_{{mode}}_susceptibility_GWAS.tsv", mode=COMBINED_MODES),
        # expand(f"{OUTDIR}/txd_gene_association/{{case}}/TxD_GO.done", case=TXD_GO_CASES),

rule compute_ppr_score:
    input:
        h5ad=lambda wc: H5AD[wc.region],
        score=lambda wc: SCDRS_SCORE[wc.region]
    output:
        h5ad=f"{OUTDIR}/{{region}}/adata_{{region}}_scdrs_ppr.h5ad"
    log:
        f"{OUTDIR}/{{region}}/logs/compute_ppr_score.log"
    shell:
        """
        mkdir -p {OUTDIR}/{wildcards.region}/logs
        {PYTHON} {SCRIPT_DIR}/compute_ppr_score.py \
            --input-h5ad {input.h5ad} \
            --score-file {input.score} \
            --output-h5ad {output.h5ad} \
            --celltype-col Org_celltype \
            --use-rep X_pca_harmony \
            > {log} 2>&1
        """


rule gwas_enrichment_merged:
    input:
        h5ad=lambda wc: H5AD[wc.region],
        gwas_gs=GWAS_GS
    output:
        summary=f"{OUTDIR}/{{region}}/gwas_enrichment/ALS_top1000_gwas_enrichment_summary_merged.tsv",
        detail=f"{OUTDIR}/{{region}}/gwas_enrichment/ALS_top1000_gwas_enrichment_detail_merged.tsv",
        stats=f"{OUTDIR}/{{region}}/gwas_enrichment/ALS_celltype_stats_merged.tsv"
    log:
        f"{OUTDIR}/{{region}}/logs/gwas_enrichment_merged.log"
    shell:
        """
        mkdir -p {OUTDIR}/{wildcards.region}/logs {OUTDIR}/{wildcards.region}/gwas_enrichment
        {PYTHON} {SCRIPT_DIR}/gwas_enrichment_merged.py \
            --input-h5ad {input.h5ad} \
            --gwas-gs {input.gwas_gs} \
            --trait ALS \
            --celltype-col Org_celltype \
            --output-dir {OUTDIR}/{wildcards.region}/gwas_enrichment \
            --n-trials 10 \
            --n-per-clust 150 \
            --min-cells 20 \
            --z-cut 1.0 \
            --fdr-cut 0.001 \
            > {log} 2>&1
        """


rule plot_scdrs_umap:
    input:
        h5ad=f"{OUTDIR}/{{region}}/adata_{{region}}_scdrs_ppr.h5ad"
    output:
        pdf=f"{OUTDIR}/{{region}}/figures/{{mode}}_scDRS_PPRZ_umap.pdf",
        png=f"{OUTDIR}/{{region}}/figures/{{mode}}_scDRS_PPRZ_umap.png",
        table=f"{OUTDIR}/{{region}}/tables/{{mode}}_scDRS_PPRZ_umap_median.tsv"
    log:
        f"{OUTDIR}/{{region}}/logs/plot_{{mode}}_umap.log"
    shell:
        """
        mkdir -p {OUTDIR}/{wildcards.region}/figures {OUTDIR}/{wildcards.region}/tables {OUTDIR}/{wildcards.region}/logs
        {PYTHON} {SCRIPT_DIR}/plot_scdrs_umap.py \
            --input-h5ad {input.h5ad} \
            --mode {wildcards.mode} \
            --region {wildcards.region} \
            --output-pdf {output.pdf} \
            --output-png {output.png} \
            --output-table {output.table} \
            > {log} 2>&1
        """


rule plot_subtype_heatmap_gwas:
    input:
        h5ad=f"{OUTDIR}/{{region}}/adata_{{region}}_scdrs_ppr.h5ad",
        summary=f"{OUTDIR}/{{region}}/gwas_enrichment/ALS_top1000_gwas_enrichment_summary_merged.tsv"
    output:
        pdf=f"{OUTDIR}/{{region}}/figures/{{mode}}_subtype_median_scDRS_GWAS.pdf",
        png=f"{OUTDIR}/{{region}}/figures/{{mode}}_subtype_median_scDRS_GWAS.png",
        table=f"{OUTDIR}/{{region}}/tables/{{mode}}_subtype_median_scDRS_GWAS.tsv"
    log:
        f"{OUTDIR}/{{region}}/logs/plot_{{mode}}_subtype_heatmap_gwas.log"
    shell:
        """
        mkdir -p {OUTDIR}/{wildcards.region}/figures {OUTDIR}/{wildcards.region}/tables {OUTDIR}/{wildcards.region}/logs
        {PYTHON} {SCRIPT_DIR}/plot_subtype_heatmap_gwas.py \
            --input-h5ad {input.h5ad} \
            --summary-tsv {input.summary} \
            --mode {wildcards.mode} \
            --region {wildcards.region} \
            --output-pdf {output.pdf} \
            --output-png {output.png} \
            --output-table {output.table} \
            > {log} 2>&1
        """


rule build_txd_logmean_pseudobulk:
    input:
        h5ad=lambda wc: TXD_H5AD[wc.case]
    output:
        summary=f"{OUTDIR}/txd/{{case}}/txd_pseudobulk_build_summary.tsv"
    log:
        f"{OUTDIR}/txd/{{case}}/logs/build_txd_logmean_pseudobulk.log"
    params:
        groups=lambda wc: TXD_GROUPS[wc.case],
        group_col=lambda wc: TXD_GROUP_COL[wc.case]
    shell:
        """
        mkdir -p {OUTDIR}/txd/{wildcards.case}/logs
        {PYTHON} {SCRIPT_DIR}/build_txd_logmean_pseudobulk.py \
            --input-h5ad {input.h5ad} \
            --outdir {OUTDIR}/txd/{wildcards.case} \
            --celltype-col Org_celltype \
            --donor-col Donor_ID \
            --group-col {params.group_col} \
            --groups {params.groups} \
            --counts-layer counts \
            --min-cells-per-pb 10 \
            --gene-frac-cutoff 0.10 \
            --min-donors-per-group 4 \
            > {log} 2>&1
        """


rule compute_txd_from_logmean:
    input:
        summary=f"{OUTDIR}/txd/{{case}}/txd_pseudobulk_build_summary.tsv"
    output:
        txd=f"{OUTDIR}/txd/{{case}}/TxD_by_subtype_logmean.tsv"
    log:
        f"{OUTDIR}/txd/{{case}}/logs/compute_txd_from_logmean.log"
    params:
        control=lambda wc: TXD_CONTROL[wc.case],
        disease=lambda wc: TXD_DISEASE[wc.case]
    shell:
        """
        mkdir -p {OUTDIR}/txd/{wildcards.case}/logs
        {RSCRIPT} {SCRIPT_DIR}/compute_txd_from_logmean.R \
            --txd-dir {OUTDIR}/txd/{wildcards.case} \
            --out-tsv {output.txd} \
            --control-label {params.control} \
            --disease-label {params.disease} \
            --min-donors-per-group 4 \
            --use-sva true \
            --max-sv 3 \
            > {log} 2>&1
        """


rule correlate_suscept_txd:
    input:
        scdrs=lambda wc: SUSCEPT_H5AD[wc.case],
        txd=f"{OUTDIR}/txd/{{case}}/TxD_by_subtype_logmean.tsv"
    output:
        summary=f"{OUTDIR}/txd_correlation/{{case}}/{{case}}_{{mode}}_suscept_TxD_correlation.tsv",
        matched=f"{OUTDIR}/txd_correlation/{{case}}/{{case}}_{{mode}}_suscept_TxD_matched.tsv",
        pdf=f"{OUTDIR}/txd_correlation/{{case}}/{{case}}_{{mode}}_suscept_TxD_heatmap.pdf",
        png=f"{OUTDIR}/txd_correlation/{{case}}/{{case}}_{{mode}}_suscept_TxD_heatmap.png"
    log:
        f"{OUTDIR}/txd_correlation/{{case}}/logs/{{mode}}_correlate_suscept_txd.log"
    params:
        trait=lambda wc: TXD_TRAIT[wc.case],
        region=lambda wc: TXD_REGION[wc.case],
        control=lambda wc: SUSCEPT_CONTROL[wc.case]
    shell:
        """
        mkdir -p {OUTDIR}/txd_correlation/{wildcards.case}/logs
        {PYTHON} {SCRIPT_DIR}/correlate_suscept_txd.py \
            --scdrs-h5ad {input.scdrs} \
            --txd-tsv {input.txd} \
            --outdir {OUTDIR}/txd_correlation/{wildcards.case} \
            --case-name {wildcards.case} \
            --trait-name {params.trait} \
            --region {params.region} \
            --mode {wildcards.mode} \
            --celltype-col Org_celltype \
            --score-col scdrs_ppr_z \
            --group-col Group \
            --control-label {params.control} \
            > {log} 2>&1
        """

rule plot_combined_region_scdrs_gwas:
    input:
        pfc_h5ad=f"{OUTDIR}/PFC/adata_PFC_scdrs_ppr.h5ad",
        mcx_h5ad=f"{OUTDIR}/MCX/adata_MCX_scdrs_ppr.h5ad",
        pfc_summary=f"{OUTDIR}/PFC/gwas_enrichment/ALS_top1000_gwas_enrichment_summary_merged.tsv",
        mcx_summary=f"{OUTDIR}/MCX/gwas_enrichment/ALS_top1000_gwas_enrichment_summary_merged.tsv"
    output:
        pdf=f"{OUTDIR}/combined/Combined_{{mode}}_susceptibility_GWAS.pdf",
        png=f"{OUTDIR}/combined/Combined_{{mode}}_susceptibility_GWAS.png",
        table=f"{OUTDIR}/combined/Combined_{{mode}}_susceptibility_GWAS.tsv"
    log:
        f"{OUTDIR}/combined/logs/Combined_{{mode}}_susceptibility_GWAS.log"
    shell:
        """
        mkdir -p {OUTDIR}/combined {OUTDIR}/combined/logs
        {PYTHON} {SCRIPT_DIR}/plot_combined_region_scdrs_gwas.py \
            --pfc-h5ad {input.pfc_h5ad} \
            --mcx-h5ad {input.mcx_h5ad} \
            --pfc-summary {input.pfc_summary} \
            --mcx-summary {input.mcx_summary} \
            --mode {wildcards.mode} \
            --output-prefix {OUTDIR}/combined/Combined_{wildcards.mode}_susceptibility_GWAS \
            --celltype-col Org_celltype \
            --score-col scdrs_ppr \
            > {log} 2>&1
        """
rule find_txd_associated_genes_and_GO:
    input:
        txd_tsv=f"{OUTDIR}/txd/{{case}}/TxD_by_subtype_logmean.tsv"
    output:
        done=f"{OUTDIR}/txd_gene_association/{{case}}/TxD_GO.done"
    log:
        f"{OUTDIR}/txd_gene_association/{{case}}/logs/TxD_GO.log"
    params:
        txd_dir=lambda wc: f"{OUTDIR}/txd/{wc.case}",
        outdir=lambda wc: f"{OUTDIR}/txd_gene_association/{wc.case}",
        region=lambda wc: TXD_REGION[wc.case],
        control=lambda wc: TXD_CONTROL[wc.case]
    shell:
        """
        mkdir -p {params.outdir}/logs

        {RSCRIPT} {SCRIPT_DIR}/find_txd_associated_genes_and_GO.R \
            --txd_dir {params.txd_dir} \
            --txd_tsv {input.txd_tsv} \
            --outdir {params.outdir} \
            --region {params.region} \
            --trait ALS \
            --control_label {params.control} \
            > {log} 2>&1

        touch {output.done}
        """