#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(reticulate)
  library(CellChat)
  library(data.table)
  library(Matrix)
})

args <- commandArgs(trailingOnly = TRUE)

h5ad_fp <- args[1]
out_fp  <- args[2]
region  <- args[3]
target_key <- args[4]
target_labels <- unlist(strsplit(args[5], ","))

write_empty <- function(reason) {
  message("[WARN] Writing empty CellChat table: ", reason)
  empty <- data.table(
    source=character(), target=character(), ligand=character(), receptor=character(),
    interaction_name=character(), interaction_name_2=character(),
    pathway_name=character(), annotation=character(),
    prob=numeric(), pval=numeric(), region=character(), target_key=character(),
    reason=character()
  )
  dir.create(dirname(out_fp), recursive=TRUE, showWarnings=FALSE)
  fwrite(empty, out_fp, sep="\t")
  quit(save="no", status=0)
}

message("[INFO] h5ad: ", h5ad_fp)
message("[INFO] output: ", out_fp)
message("[INFO] region: ", region)
message("[INFO] target_key: ", target_key)
message("[INFO] target_labels: ", paste(target_labels, collapse=", "))

use_python("/mnt/workspace/tools/envs/pysodb/bin/python", required=TRUE)
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

if (!("Org_celltype" %in% colnames(meta))) {
  stop("Missing obs column: Org_celltype")
}

meta$cell_group_raw <- as.character(meta$Org_celltype)

keep_sender <- c(
  "Glia.Astro.GFAP-neg",
  "Glia.Astro.GFAP-pos",
  "Glia.Oligo",
  "Glia.OPC",
  "Glia.Micro"
)

keep <- meta$cell_group_raw %in% c(keep_sender, target_labels)

expr <- expr[, keep, drop=FALSE]
meta <- meta[keep, , drop=FALSE]

meta$cell_group <- meta$cell_group_raw
meta$cell_group[meta$cell_group_raw %in% target_labels] <- target_key
meta$cell_group <- factor(meta$cell_group)

message("[INFO] kept cells: ", ncol(expr))
print(table(meta$cell_group))

if (!(target_key %in% meta$cell_group)) {
  write_empty(paste0("target_not_present_", target_key, "_", region))
}

n_target <- sum(meta$cell_group == target_key)
if (n_target < 10) {
  write_empty(paste0("target_cells_less_than_10_n=", n_target))
}

if (length(unique(meta$cell_group)) < 2) {
  write_empty("fewer_than_2_cell_groups")
}

cellchat <- tryCatch({
  x <- createCellChat(object=expr, meta=meta, group.by="cell_group")
  x@DB <- CellChatDB.human
  x <- subsetData(x)
  x <- identifyOverExpressedGenes(x)
  x <- identifyOverExpressedInteractions(x)
  x <- computeCommunProb(x, raw.use=TRUE)
  x <- filterCommunication(x, min.cells=10)
  x
}, error=function(e) {
  message("[WARN] CellChat failed: ", conditionMessage(e))
  NULL
})

if (is.null(cellchat)) {
  write_empty("cellchat_failed")
}

df.net <- tryCatch({
  subsetCommunication(cellchat)
}, error=function(e) {
  message("[WARN] subsetCommunication failed: ", conditionMessage(e))
  data.frame()
})

if (nrow(df.net) == 0) {
  write_empty("no_interactions")
}

df.net <- as.data.table(df.net)
df.net$region <- region
df.net$target_key <- target_key
df.net$reason <- "ok"

dir.create(dirname(out_fp), recursive=TRUE, showWarnings=FALSE)
fwrite(df.net, out_fp, sep="\t")

message("[INFO] saved: ", out_fp)
