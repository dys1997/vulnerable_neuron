#!/usr/bin/env Rscript
suppressPackageStartupMessages({library(data.table)})
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) stop("Usage: Rscript combine_all_altered_interactions.R cellchat_dir out.tsv")
cellchat_dir <- args[1]; out_fp <- args[2]
files <- list.files(cellchat_dir, pattern="^altered_interactions\\.tsv$", recursive=TRUE, full.names=TRUE)
message("[INFO] files: ", length(files)); if (length(files)==0) stop("No altered_interactions.tsv files found.")
lst <- lapply(files, function(fp){x <- fread(fp, fill=TRUE); x$source_file <- fp; x})
res <- rbindlist(lst, fill=TRUE)
dir.create(dirname(out_fp), recursive=TRUE, showWarnings=FALSE); fwrite(res, out_fp, sep="\t")
message("[INFO] saved: ", out_fp); message("[INFO] rows: ", nrow(res))
