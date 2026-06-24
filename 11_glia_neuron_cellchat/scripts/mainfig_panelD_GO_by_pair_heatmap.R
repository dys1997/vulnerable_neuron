#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(stringr)
  library(tidyr)
  library(ggplot2)
  library(clusterProfiler)
  library(org.Hs.eg.db)
})

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 5) {
  stop(
    "Usage: Rscript mainfig_panelD_GO_by_pair_heatmap.R ",
    "<altered.tsv> <out.pdf> <out.png> <out.long.tsv> <out.matrix.tsv> ",
    "[top_pairs=24] [top_terms=20] [min_genes=3]"
  )
}

altered_fp <- args[1]
out_pdf <- args[2]
out_png <- args[3]
out_long <- args[4]
out_matrix <- args[5]
top_pairs <- ifelse(length(args) >= 6, as.integer(args[6]), 24)
top_terms <- ifelse(length(args) >= 7, as.integer(args[7]), 20)
min_genes <- ifelse(length(args) >= 8, as.integer(args[8]), 3)

df <- read_tsv(altered_fp, show_col_types = FALSE)

required_cols <- c(
  "source", "target", "ligand", "receptor", "interaction_name",
  "delta_MCX_minus_PFC", "direction", "abs_delta", "direction_mode"
)

missing_cols <- setdiff(required_cols, colnames(df))
if (length(missing_cols) > 0) {
  stop(
    "Missing required columns: ",
    paste(missing_cols, collapse = ", "),
    "\nCurrent columns are:\n",
    paste(colnames(df), collapse = ", ")
  )
}

simplify_source <- function(x) {
  case_when(
    str_detect(x, regex("GFAP[-_ ]?neg|Astro.*neg|Ast.*neg", ignore_case = TRUE)) ~ "Astro GFAP-",
    str_detect(x, regex("GFAP[-_ ]?pos|Astro.*pos|Ast.*pos", ignore_case = TRUE)) ~ "Astro GFAP+",
    str_detect(x, regex("Astro|Ast", ignore_case = TRUE)) ~ "Astro",
    str_detect(x, regex("OPC", ignore_case = TRUE)) ~ "OPC",
    str_detect(x, regex("Olig|Olg|OL", ignore_case = TRUE)) ~ "Oligo",
    str_detect(x, regex("Micro|Mic", ignore_case = TRUE)) ~ "Micro",
    TRUE ~ x
  )
}

simplify_target <- function(x) {
  case_when(
    str_detect(x, regex("PTHLH", ignore_case = TRUE)) ~ "PTHLH",
    str_detect(x, regex("CEMIP", ignore_case = TRUE)) ~ "CEMIP",
    str_detect(x, regex("PCP4|NXPH2", ignore_case = TRUE)) ~ "PCP4_NXPH2",
    str_detect(x, regex("CDH4|CDH4_plus|CDH4_CCK|CDH4_SCGN", ignore_case = TRUE)) ~ "CDH4+",
    TRUE ~ x
  )
}

split_genes <- function(x) {
  x <- unique(unlist(strsplit(x, "_|\\||\\+|;|,", perl = TRUE)))
  x <- trimws(x)
  x <- x[!is.na(x) & x != ""]
  x
}

dat <- df %>%
  filter(
    direction_mode == "glia_to_neuron",
    direction == "MCX_higher"
  ) %>%
  mutate(
    source_simple = simplify_source(source),
    target_simple = simplify_target(target),
    pair = paste0(source_simple, " -> ", target_simple),
    abs_delta_value = as.numeric(abs_delta)
  ) %>%
  filter(
    target_simple %in% c("PTHLH", "CEMIP", "PCP4_NXPH2", "CDH4+")
  )

if (nrow(dat) == 0) {
  stop("No MCX_higher glia_to_neuron interactions found.")
}

top_pair_tbl <- dat %>%
  group_by(pair, source_simple, target_simple) %>%
  summarise(
    pair_weight = sum(abs_delta_value, na.rm = TRUE),
    n_interactions = n(),
    .groups = "drop"
  ) %>%
  arrange(desc(pair_weight)) %>%
  slice_head(n = top_pairs)

keep_pairs <- top_pair_tbl$pair

dat_top <- dat %>%
  filter(pair %in% keep_pairs)

run_go_one_pair <- function(pair_name, sub_df) {
  ligand_genes <- split_genes(sub_df$ligand)
  receptor_genes <- split_genes(sub_df$receptor)
  genes <- unique(c(ligand_genes, receptor_genes))
  genes <- genes[!is.na(genes) & genes != ""]

  if (length(genes) < min_genes) {
    return(NULL)
  }

  ego <- tryCatch({
    enrichGO(
      gene = genes,
      OrgDb = org.Hs.eg.db,
      keyType = "SYMBOL",
      ont = "BP",
      pAdjustMethod = "BH",
      readable = FALSE
    )
  }, error = function(e) {
    message("[WARN] enrichGO failed for ", pair_name, ": ", conditionMessage(e))
    NULL
  })

  if (is.null(ego)) return(NULL)

  res <- as.data.frame(ego)
  if (nrow(res) == 0) return(NULL)

  res$pair <- pair_name
  res$n_input_genes <- length(genes)
  res$input_genes <- paste(genes, collapse = ";")
  res
}

go_list <- dat_top %>%
  group_split(pair) %>%
  lapply(function(x) {
    run_go_one_pair(unique(x$pair), x)
  })

go_df <- bind_rows(go_list)

if (nrow(go_df) == 0) {
  stop("No GO enrichment result was generated for selected source-target pairs.")
}

go_df2 <- go_df %>%
  mutate(
    neglog10p = -log10(pvalue + 1e-300),
    GeneRatio_num = sapply(GeneRatio, function(x) {
      parts <- strsplit(x, "/")[[1]]
      as.numeric(parts[1]) / as.numeric(parts[2])
    })
  )

top_terms_tbl <- go_df2 %>%
  group_by(ID, Description) %>%
  summarise(
    max_neglog10p = max(neglog10p, na.rm = TRUE),
    total_count = sum(Count, na.rm = TRUE),
    n_pairs = n_distinct(pair),
    .groups = "drop"
  ) %>%
  arrange(desc(max_neglog10p), desc(n_pairs), desc(total_count)) %>%
  slice_head(n = top_terms)

keep_terms <- top_terms_tbl$Description

plot_long <- go_df2 %>%
  filter(Description %in% keep_terms) %>%
  dplyr::select(
    pair, ID, Description, pvalue, p.adjust, qvalue,
    Count, GeneRatio, GeneRatio_num, neglog10p,
    geneID, n_input_genes, input_genes
  ) %>%
  left_join(top_pair_tbl, by = "pair")

write_tsv(plot_long, out_long)

mat_df <- plot_long %>%
  group_by(Description, pair) %>%
  summarise(score = max(neglog10p, na.rm = TRUE), .groups = "drop") %>%
  complete(
    Description = keep_terms,
    pair = keep_pairs,
    fill = list(score = 0)
  )

mat_wide <- mat_df %>%
  pivot_wider(
    names_from = pair,
    values_from = score,
    values_fill = 0
  )

write_tsv(mat_wide, out_matrix)

mat <- as.data.frame(mat_wide)
rownames(mat) <- mat$Description
mat$Description <- NULL
mat <- as.matrix(mat)

mat <- mat[rowSums(mat) > 0, colSums(mat) > 0, drop = FALSE]

if (nrow(mat) == 0 || ncol(mat) == 0) {
  stop("Heatmap matrix is empty after filtering.")
}

mat_cap <- pmin(mat, 20)

if (requireNamespace("pheatmap", quietly = TRUE)) {
  library(pheatmap)

  hm_colors <- colorRampPalette(c("grey92", "#fee08b", "#fdae61", "#f46d43", "#a50026"))(100)

  pdf(out_pdf, width = max(10, 0.35 * ncol(mat_cap) + 5), height = max(7, 0.28 * nrow(mat_cap) + 3))
  pheatmap(
    mat_cap,
    color = hm_colors,
    cluster_rows = TRUE,
    cluster_cols = TRUE,
    border_color = NA,
    fontsize_row = 10,
    fontsize_col = 8,
    angle_col = 90,
    main = "Top enriched GO terms by interacting glia-neuron pairs",
    legend = TRUE
  )
  dev.off()

  png(out_png, width = max(3200, 150 * ncol(mat_cap) + 1200), height = max(2400, 120 * nrow(mat_cap) + 900), res = 300)
  pheatmap(
    mat_cap,
    color = hm_colors,
    cluster_rows = TRUE,
    cluster_cols = TRUE,
    border_color = NA,
    fontsize_row = 10,
    fontsize_col = 8,
    angle_col = 90,
    main = "Top enriched GO terms by interacting glia-neuron pairs",
    legend = TRUE
  )
  dev.off()

} else {
  message("[WARN] package pheatmap not installed. Using ggplot heatmap without dendrogram.")

  plot_df <- as.data.frame(as.table(mat_cap))
  colnames(plot_df) <- c("GO_term", "Pair", "score")

  p <- ggplot(plot_df, aes(x = Pair, y = GO_term, fill = score)) +
    geom_tile(color = "white", size = 0.15) +
    scale_fill_gradientn(
      colours = c("grey92", "#fee08b", "#fdae61", "#f46d43", "#a50026"),
      name = "-log10(P)"
    ) +
    labs(
      title = "Top enriched GO terms by interacting glia-neuron pairs",
      x = "Interacting glia-neuron pair",
      y = "GO biological process"
    ) +
    theme_minimal(base_size = 12) +
    theme(
      plot.title = element_text(face = "bold", hjust = 0.5, size = 16),
      axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5, size = 8),
      axis.text.y = element_text(size = 9),
      panel.grid = element_blank()
    )

  ggsave(out_pdf, p, width = max(10, 0.35 * ncol(mat_cap) + 5), height = max(7, 0.28 * nrow(mat_cap) + 3), useDingbats = FALSE)
  ggsave(out_png, p, width = max(10, 0.35 * ncol(mat_cap) + 5), height = max(7, 0.28 * nrow(mat_cap) + 3), dpi = 300)
}

message("[INFO] Saved heatmap: ", out_pdf)
message("[INFO] Saved long table: ", out_long)
message("[INFO] Saved matrix table: ", out_matrix)
