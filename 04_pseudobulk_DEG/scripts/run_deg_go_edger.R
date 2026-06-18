#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(optparse)
  library(edgeR)
  library(clusterProfiler)
  library(org.Hs.eg.db)
  library(AnnotationDbi)
  library(readr)
  library(dplyr)
  library(ggplot2)
  library(forcats)
  library(stringr)
})

# =========================
# 1. 参数
# =========================
option_list <- list(
  make_option("--counts", type = "character", dest = "counts",
              help = "Pseudo-bulk counts.tsv, genes x samples"),
  make_option("--meta", type = "character", dest = "meta",
              help = "Pseudo-bulk meta.tsv, rows = samples"),
  make_option("--outdir", type = "character", dest = "outdir",
              help = "Output directory"),
  make_option("--prefix", type = "character", dest = "prefix", default = "DEG_result",
              help = "Output file prefix"),

  make_option("--sample-col", type = "character", dest = "sample_col", default = "Sample_ID",
              help = "Sample ID column in meta"),
  make_option("--group-col", type = "character", dest = "group_col", default = "group",
              help = "Group column in meta"),
  make_option("--ref-group", type = "character", dest = "ref_group",
              help = "Reference group name"),
  make_option("--target-group", type = "character", dest = "target_group",
              help = "Target group name"),

  make_option("--paired", action = "store_true", dest = "paired", default = FALSE,
              help = "Use paired design: ~ Sample_ID + group"),

  make_option("--fdr-cutoff", type = "double", dest = "fdr_cutoff", default = 0.05,
              help = "FDR cutoff"),
  make_option("--lfc-cutoff", type = "double", dest = "lfc_cutoff", default = 0.25,
              help = "Absolute logFC cutoff"),
  make_option("--go-ont", type = "character", dest = "go_ont", default = "BP",
              help = "GO ontology: BP / MF / CC"),
  make_option("--organism-db", type = "character", dest = "organism_db", default = "org.Hs.eg.db",
              help = "OrgDb package name"),
  make_option("--plot-top-n", type = "integer", dest = "plot_top_n", default = 10,
              help = "Top N GO terms to show for automatic plot"),

  make_option("--selected-up-terms", type = "character", dest = "selected_up_terms", default = NULL,
              help = "Semicolon-separated selected GO up terms"),
  make_option("--selected-down-terms", type = "character", dest = "selected_down_terms", default = NULL,
              help = "Semicolon-separated selected GO down terms")
)

opt <- parse_args(OptionParser(option_list = option_list))

dir.create(opt$outdir, recursive = TRUE, showWarnings = FALSE)

# =========================
# 2. 读入数据
# =========================
counts <- read.delim(opt$counts, row.names = 1, check.names = FALSE)
meta <- read.delim(opt$meta, row.names = 1, check.names = FALSE)

meta <- meta[colnames(counts), , drop = FALSE]
stopifnot(all(colnames(counts) == rownames(meta)))

if (!(opt$group_col %in% colnames(meta))) {
  stop(paste("Missing group column in meta:", opt$group_col))
}
if (!(opt$sample_col %in% colnames(meta))) {
  stop(paste("Missing sample column in meta:", opt$sample_col))
}

meta[[opt$group_col]] <- factor(meta[[opt$group_col]], levels = c(opt$ref_group, opt$target_group))
meta[[opt$sample_col]] <- factor(meta[[opt$sample_col]])

cat("Group table:\n")
print(table(meta[[opt$group_col]]))

cat("\nSample x group table:\n")
print(table(meta[[opt$sample_col]], meta[[opt$group_col]]))

# =========================
# 3. edgeR DEG
# =========================
y <- DGEList(counts = counts)

if (opt$paired) {
  design <- model.matrix(
    as.formula(paste("~", opt$sample_col, "+", opt$group_col)),
    data = meta
  )
} else {
  design <- model.matrix(
    as.formula(paste("~", opt$group_col)),
    data = meta
  )
}

keep <- filterByExpr(y, design = design)
y <- y[keep, , keep.lib.sizes = FALSE]
y <- calcNormFactors(y, method = "TMM")

if (nrow(y) == 0) {
  stop("No genes left after filterByExpr.")
}

y <- estimateDisp(y, design)
fit <- glmQLFit(y, design, robust = TRUE)

coef_name <- paste0(opt$group_col, opt$target_group)
if (!(coef_name %in% colnames(fit$coefficients))) {
  stop(
    paste0(
      "Cannot find coefficient: ", coef_name,
      "\nAvailable coefficients: ", paste(colnames(fit$coefficients), collapse = ", ")
    )
  )
}

res <- glmQLFTest(fit, coef = coef_name)
deg <- topTags(res, n = Inf)$table
deg$gene <- rownames(deg)
deg <- deg[, c("gene", "logFC", "logCPM", "F", "PValue", "FDR")]

deg_sig <- subset(deg, FDR < opt$fdr_cutoff & abs(logFC) > opt$lfc_cutoff)
deg_up  <- subset(deg_sig, logFC > 0)
deg_dn  <- subset(deg_sig, logFC < 0)

write.table(deg,
            file = file.path(opt$outdir, paste0(opt$prefix, "_edgeR.tsv")),
            sep = "\t", quote = FALSE, row.names = FALSE)

write.table(deg_sig,
            file = file.path(opt$outdir, paste0(opt$prefix, "_edgeR.sig.tsv")),
            sep = "\t", quote = FALSE, row.names = FALSE)

write.table(deg_up,
            file = file.path(opt$outdir, paste0(opt$prefix, "_edgeR.up.tsv")),
            sep = "\t", quote = FALSE, row.names = FALSE)

write.table(deg_dn,
            file = file.path(opt$outdir, paste0(opt$prefix, "_edgeR.down.tsv")),
            sep = "\t", quote = FALSE, row.names = FALSE)

cat("\nDEG summary:\n")
cat("All tested genes:", nrow(deg), "\n")
cat("Sig DEG:", nrow(deg_sig), "\n")
cat("Up:", nrow(deg_up), "\n")
cat("Down:", nrow(deg_dn), "\n")

# =========================
# 4. GO enrichment
# =========================
OrgDb <- get(opt$organism_db)

genes_up <- unique(deg_up$gene)
genes_down <- unique(deg_dn$gene)
universe_genes <- unique(deg$gene)

safe_bitr <- function(x) {
  if (length(x) == 0) {
    return(data.frame(SYMBOL = character(0), ENTREZID = character(0)))
  }
  bitr(x, fromType = "SYMBOL", toType = "ENTREZID", OrgDb = OrgDb)
}

gene_up_df <- safe_bitr(genes_up)
gene_down_df <- safe_bitr(genes_down)
universe_df <- safe_bitr(universe_genes)

genes_up_entrez <- unique(gene_up_df$ENTREZID)
genes_down_entrez <- unique(gene_down_df$ENTREZID)
universe_entrez <- unique(universe_df$ENTREZID)

cat("\nGO mapping summary:\n")
cat("Up mapped:", length(genes_up_entrez), "\n")
cat("Down mapped:", length(genes_down_entrez), "\n")
cat("Universe mapped:", length(universe_entrez), "\n")

run_enrich_go <- function(gene_ids, universe_ids, ont = "BP") {
  if (length(gene_ids) == 0 || length(universe_ids) == 0) {
    return(data.frame())
  }
  ego <- enrichGO(
    gene          = gene_ids,
    universe      = universe_ids,
    OrgDb         = OrgDb,
    keyType       = "ENTREZID",
    ont           = ont,
    pAdjustMethod = "BH",
    pvalueCutoff  = 0.05,
    qvalueCutoff  = 0.2,
    readable      = TRUE
  )
  as.data.frame(ego)
}

go_up <- run_enrich_go(genes_up_entrez, universe_entrez, ont = opt$go_ont)
go_down <- run_enrich_go(genes_down_entrez, universe_entrez, ont = opt$go_ont)

calc_fold_enrichment <- function(geneRatio, bgRatio) {
  g1 <- as.numeric(sapply(strsplit(geneRatio, "/"), `[`, 1))
  g2 <- as.numeric(sapply(strsplit(geneRatio, "/"), `[`, 2))
  b1 <- as.numeric(sapply(strsplit(bgRatio, "/"), `[`, 1))
  b2 <- as.numeric(sapply(strsplit(bgRatio, "/"), `[`, 2))
  (g1 / g2) / (b1 / b2)
}

if (nrow(go_up) > 0) {
  go_up$FoldEnrichment <- calc_fold_enrichment(go_up$GeneRatio, go_up$BgRatio)
}
if (nrow(go_down) > 0) {
  go_down$FoldEnrichment <- calc_fold_enrichment(go_down$GeneRatio, go_down$BgRatio)
}

write.table(go_up,
            file = file.path(opt$outdir, paste0(opt$prefix, "_GO_", opt$go_ont, "_up.tsv")),
            sep = "\t", quote = FALSE, row.names = FALSE)

write.table(go_down,
            file = file.path(opt$outdir, paste0(opt$prefix, "_GO_", opt$go_ont, "_down.tsv")),
            sep = "\t", quote = FALSE, row.names = FALSE)

cat("\nGO summary:\n")
cat("Up terms:", nrow(go_up), "\n")
cat("Down terms:", nrow(go_down), "\n")

# =========================
# 5. 自动 top GO 可视化
# =========================
make_top_plot_df <- function(go_df, direction, top_n = 10) {
  if (nrow(go_df) == 0) return(data.frame())
  go_df %>%
    arrange(p.adjust, desc(FoldEnrichment)) %>%
    head(top_n) %>%
    mutate(
      Direction = direction,
      log10_padj = -log10(p.adjust),
      term_show = str_wrap(Description, width = 35)
    )
}

plot_up_auto <- make_top_plot_df(go_up, paste0(opt$target_group, " up"), opt$plot_top_n)
plot_down_auto <- make_top_plot_df(go_down, paste0(opt$target_group, " down"), opt$plot_top_n)
plot_auto <- bind_rows(plot_up_auto, plot_down_auto)

if (nrow(plot_auto) > 0) {
  plot_auto <- plot_auto %>%
    group_by(Direction) %>%
    arrange(log10_padj, .by_group = TRUE) %>%
    mutate(term_show = factor(term_show, levels = unique(term_show))) %>%
    ungroup()

  p_auto <- ggplot(plot_auto, aes(x = log10_padj, y = term_show, fill = FoldEnrichment)) +
    geom_col(width = 0.7, color = "black") +
    facet_wrap(~Direction, scales = "free_y", ncol = 2) +
    scale_fill_gradient(low = "#9ecae1", high = "#08519c") +
    labs(
      x = expression(-log[10](adjusted~P)),
      y = NULL,
      fill = "Fold enrichment",
      title = paste0("Top GO-", opt$go_ont, " terms: ", opt$target_group, " vs ", opt$ref_group)
    ) +
    theme_bw(base_size = 13) +
    theme(
      strip.background = element_rect(fill = "grey90", color = "black"),
      strip.text = element_text(face = "bold", size = 12),
      axis.text.y = element_text(color = "black", size = 11),
      axis.text.x = element_text(color = "black"),
      axis.title.x = element_text(face = "bold"),
      panel.grid.major.y = element_blank(),
      panel.grid.minor = element_blank(),
      legend.position = "right",
      plot.title = element_text(face = "bold", hjust = 0.5)
    )

  ggsave(file.path(opt$outdir, paste0(opt$prefix, "_GO_", opt$go_ont, "_top_terms.pdf")),
         plot = p_auto, width = 12, height = 6.5)
  ggsave(file.path(opt$outdir, paste0(opt$prefix, "_GO_", opt$go_ont, "_top_terms.png")),
         plot = p_auto, width = 12, height = 6.5, dpi = 300)
}

# =========================
# 6. 手动 selected terms 可视化（可选）
# =========================
split_terms <- function(x) {
  if (is.null(x) || is.na(x) || x == "") return(character(0))
  trimws(unlist(strsplit(x, ";")))
}

terms_up <- split_terms(opt$selected_up_terms)
terms_down <- split_terms(opt$selected_down_terms)

if (length(terms_up) > 0 || length(terms_down) > 0) {
  plot_up_sel <- go_up %>%
    filter(Description %in% terms_up) %>%
    mutate(Direction = paste0(opt$target_group, " up"))

  plot_down_sel <- go_down %>%
    filter(Description %in% terms_down) %>%
    mutate(Direction = paste0(opt$target_group, " down"))

  plot_sel <- bind_rows(plot_up_sel, plot_down_sel)

  if (nrow(plot_sel) > 0) {
    plot_sel <- plot_sel %>%
      mutate(
        log10_padj = -log10(p.adjust),
        term_show = str_wrap(Description, width = 35)
      ) %>%
      group_by(Direction) %>%
      arrange(log10_padj, .by_group = TRUE) %>%
      mutate(term_show = factor(term_show, levels = unique(term_show))) %>%
      ungroup()

    p_sel <- ggplot(plot_sel, aes(x = log10_padj, y = term_show, fill = FoldEnrichment)) +
      geom_col(width = 0.7, color = "black") +
      facet_wrap(~Direction, scales = "free_y", ncol = 2) +
      scale_fill_gradient(low = "#9ecae1", high = "#08519c") +
      labs(
        x = expression(-log[10](adjusted~P)),
        y = NULL,
        fill = "Fold enrichment",
        title = paste0("Selected GO-", opt$go_ont, " terms: ", opt$target_group, " vs ", opt$ref_group)
      ) +
      theme_bw(base_size = 13) +
      theme(
        strip.background = element_rect(fill = "grey90", color = "black"),
        strip.text = element_text(face = "bold", size = 12),
        axis.text.y = element_text(color = "black", size = 11),
        axis.text.x = element_text(color = "black"),
        axis.title.x = element_text(face = "bold"),
        panel.grid.major.y = element_blank(),
        panel.grid.minor = element_blank(),
        legend.position = "right",
        plot.title = element_text(face = "bold", hjust = 0.5)
      )

    ggsave(file.path(opt$outdir, paste0(opt$prefix, "_GO_", opt$go_ont, "_selected_terms.pdf")),
           plot = p_sel, width = 12, height = 6.5)
    ggsave(file.path(opt$outdir, paste0(opt$prefix, "_GO_", opt$go_ont, "_selected_terms.png")),
           plot = p_sel, width = 12, height = 6.5, dpi = 300)
  }
}

cat("\nDone.\n")
