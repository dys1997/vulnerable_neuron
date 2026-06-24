#!/usr/bin/env Rscript
suppressPackageStartupMessages({library(data.table)})
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 5) stop("Usage: Rscript compare_target_interactions.R pfc.tsv mcx.tsv out.tsv target_key direction")
pfc_fp <- args[1]; mcx_fp <- args[2]; out_fp <- args[3]; target_key <- args[4]; direction_mode <- args[5]
message("[INFO] PFC: ", pfc_fp); message("[INFO] MCX: ", mcx_fp); message("[INFO] target_key: ", target_key); message("[INFO] direction_mode: ", direction_mode)
pfc <- fread(pfc_fp); mcx <- fread(mcx_fp)
glia_types <- c("Glia.Astro.GFAP-neg","Glia.Astro.GFAP-pos","Glia.Oligo","Glia.OPC","Glia.Micro")
required_cols <- c("source","target","interaction_name","prob")
missing_pfc <- setdiff(required_cols, colnames(pfc)); missing_mcx <- setdiff(required_cols, colnames(mcx))
if (length(missing_pfc)>0) stop("PFC missing columns: ", paste(missing_pfc, collapse=", "))
if (length(missing_mcx)>0) stop("MCX missing columns: ", paste(missing_mcx, collapse=", "))
if (direction_mode == "glia_to_neuron") {pfc <- pfc[source %in% glia_types & target == target_key]; mcx <- mcx[source %in% glia_types & target == target_key]
} else if (direction_mode == "neuron_to_glia") {pfc <- pfc[source == target_key & target %in% glia_types]; mcx <- mcx[source == target_key & target %in% glia_types]
} else stop("Unknown direction_mode: ", direction_mode)
message("[INFO] PFC selected rows: ", nrow(pfc)); message("[INFO] MCX selected rows: ", nrow(mcx))
optional_cols <- c("ligand","receptor","pathway_name","interaction_name_2","annotation")
cols <- required_cols
for (cc in optional_cols) if (cc %in% colnames(pfc) && cc %in% colnames(mcx)) cols <- c(cols, cc)
cols <- unique(cols)
pfc <- pfc[, ..cols]; mcx <- mcx[, ..cols]
setnames(pfc, "prob", "prob_PFC"); setnames(mcx, "prob", "prob_MCX")
merge_cols <- setdiff(intersect(colnames(pfc), colnames(mcx)), c("prob_PFC","prob_MCX"))
merged <- merge(pfc, mcx, by=merge_cols, all=TRUE)
merged[is.na(prob_PFC), prob_PFC := 0]; merged[is.na(prob_MCX), prob_MCX := 0]
merged[, delta_MCX_minus_PFC := prob_MCX - prob_PFC]
merged[, direction := fifelse(delta_MCX_minus_PFC > 0, "MCX_higher", fifelse(delta_MCX_minus_PFC < 0, "PFC_higher", "No_change"))]
merged[, abs_delta := abs(delta_MCX_minus_PFC)]
merged[, target_key := target_key]; merged[, direction_mode := direction_mode]
setorder(merged, -abs_delta)
dir.create(dirname(out_fp), recursive=TRUE, showWarnings=FALSE)
fwrite(merged, out_fp, sep="\t")
write_top <- function(dt, direction_name, out_name) {sub <- dt[direction == direction_name]; if (nrow(sub)==0) {fwrite(data.table(), file.path(dirname(out_fp), out_name), sep="\t"); return(NULL)}; q <- quantile(sub$abs_delta, 0.9, na.rm=TRUE); top <- sub[abs_delta >= q]; setorder(top, -abs_delta); fwrite(top, file.path(dirname(out_fp), out_name), sep="\t")}
write_top(merged, "MCX_higher", "top_MCX_higher_interactions.tsv")
write_top(merged, "PFC_higher", "top_PFC_higher_interactions.tsv")
message("[INFO] saved: ", out_fp)
