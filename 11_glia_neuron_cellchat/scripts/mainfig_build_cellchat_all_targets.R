#!/usr/bin/env Rscript
# Build one CellChat object per region containing:
#   glia subtypes + vulnerable neuron subtypes
# This object is used only for main figure visualization.

suppressPackageStartupMessages({
  library(reticulate)
  library(CellChat)
  library(data.table)
  library(Matrix)
})

parse_args <- function(args) {
  out <- list()
  i <- 1
  while (i <= length(args)) {
    key <- sub("^--", "", args[i])
    if (i == length(args) || grepl("^--", args[i + 1])) {
      out[[key]] <- TRUE
      i <- i + 1
    } else {
      out[[key]] <- args[i + 1]
      i <- i + 2
    }
  }
  out
}

args <- parse_args(commandArgs(trailingOnly = TRUE))
required <- c("h5ad", "out-rds", "out-interactions", "out-aggregate", "region", "celltype-col", "min-cells", "python")
miss <- setdiff(required, names(args))
if (length(miss) > 0) stop("Missing arguments: ", paste(miss, collapse = ", "))

h5ad_fp <- args[["h5ad"]]
out_rds <- args[["out-rds"]]
out_interactions <- args[["out-interactions"]]
out_aggregate <- args[["out-aggregate"]]
region <- args[["region"]]
celltype_col <- args[["celltype-col"]]
min_cells <- as.integer(args[["min-cells"]])
python_bin <- args[["python"]]

message("[INFO] h5ad: ", h5ad_fp)
message("[INFO] region: ", region)
message("[INFO] output RDS: ", out_rds)

use_python(python_bin, required = TRUE)
anndata <- import("anndata")
ad <- anndata$read_h5ad(h5ad_fp)

expr <- py_to_r(ad$X)
expr <- as.matrix(expr)
expr <- t(expr)

genes <- py_to_r(ad$var_names$to_list())
cells <- py_to_r(ad$obs_names$to_list())
rownames(expr) <- make.unique(as.character(genes))
colnames(expr) <- make.unique(as.character(cells))

meta <- py_to_r(ad$obs)
if (!(celltype_col %in% colnames(meta))) {
  stop("Missing obs column: ", celltype_col)
}
rownames(meta) <- colnames(expr)
meta$cell_group_raw <- as.character(meta[[celltype_col]])

# Original fine labels in your h5ad.
glia_types <- c(
  "Glia.Astro.GFAP-neg",
  "Glia.Astro.GFAP-pos",
  "Glia.Oligo",
  "Glia.OPC",
  "Glia.Micro"
)

target_map <- list(
  PTHLH = c("In.PV.PVALB_PTHLH"),
  CEMIP = c("In.PV.PVALB_CEMIP"),
  THSD4 = c("Ex.L5.VAT1L_THSD4"),
  PCP4_NXPH2 = c("Ex.L5.PCP4_NXPH2"),
  CDH4_plus = c("In.5HT3aR.CDH4_CCK", "In.5HT3aR.CDH4_SCGN")
)

target_labels <- unique(unlist(target_map))
keep <- meta$cell_group_raw %in% c(glia_types, target_labels)
expr <- expr[, keep, drop = FALSE]
meta <- meta[keep, , drop = FALSE]

meta$cell_group <- meta$cell_group_raw
for (nm in names(target_map)) {
  meta$cell_group[meta$cell_group_raw %in% target_map[[nm]]] <- nm
}

# Keep group order stable across PFC/MCX.
group_order <- c(glia_types, names(target_map))
meta$cell_group <- factor(meta$cell_group, levels = group_order)

# Remove empty or very tiny groups before CellChat.
grp_n <- table(meta$cell_group)
message("[INFO] cell counts by group before min-cell filter:")
print(grp_n)
valid_groups <- names(grp_n)[grp_n >= min_cells]
keep2 <- as.character(meta$cell_group) %in% valid_groups
expr <- expr[, keep2, drop = FALSE]
meta <- meta[keep2, , drop = FALSE]
meta$cell_group <- droplevels(meta$cell_group)

message("[INFO] cell counts by group after min-cell filter:")
print(table(meta$cell_group))

if (length(unique(meta$cell_group)) < 2) {
  stop("Fewer than 2 cell groups after filtering; cannot build CellChat object.")
}

cellchat <- createCellChat(object = expr, meta = meta, group.by = "cell_group")
cellchat@DB <- CellChatDB.human

cellchat <- subsetData(cellchat)
cellchat <- identifyOverExpressedGenes(cellchat)
cellchat <- identifyOverExpressedInteractions(cellchat)
cellchat <- computeCommunProb(cellchat, raw.use = TRUE)
cellchat <- filterCommunication(cellchat, min.cells = min_cells)
cellchat <- computeCommunProbPathway(cellchat)
cellchat <- aggregateNet(cellchat)

# Save full object.
dir.create(dirname(out_rds), recursive = TRUE, showWarnings = FALSE)
saveRDS(cellchat, out_rds)

# Save communication table.
df.net <- as.data.table(subsetCommunication(cellchat))
if (nrow(df.net) == 0) {
  df.net <- data.table(
    source = character(), target = character(), ligand = character(), receptor = character(),
    interaction_name = character(), interaction_name_2 = character(), pathway_name = character(),
    annotation = character(), prob = numeric(), pval = numeric()
  )
}
df.net[, region := region]
fwrite(df.net, out_interactions, sep = "\t")

# Save aggregate edge strength from CellChat object net matrix.
mat <- cellchat@net$weight
if (is.null(mat)) stop("cellchat@net$weight is NULL after aggregateNet.")
agg <- as.data.table(as.table(mat))
setnames(agg, c("source", "target", "strength"))
agg <- agg[strength > 0]
agg[, region := region]
fwrite(agg, out_aggregate, sep = "\t")

message("[INFO] saved RDS: ", out_rds)
message("[INFO] saved interactions: ", out_interactions)
message("[INFO] saved aggregate: ", out_aggregate)
