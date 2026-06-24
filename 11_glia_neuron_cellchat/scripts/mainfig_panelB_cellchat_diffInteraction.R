

# # ============================================================
# # Panel B
# # CellChat built-in differential interaction network
# #
# # Reference-style method:
# #   mergeCellChat()
# #   netVisual_diffInteraction()
# #
# # Red  = MCX higher
# # Blue = PFC higher
# #
# # THSD4 is excluded because it only exists in MCX.
# # This version does NOT use subsetCellChat(), because subsetCellChat()
# # can fail on some CellChat objects with:
# #   incorrect number of dimensions
# #
# # Only visualization parameters are modified:
# #   - remove long title
# #   - remove legends
# #   - smaller figure size
# #   - thicker edges
# # ============================================================

# suppressPackageStartupMessages({
#   library(CellChat)
#   library(dplyr)
#   library(readr)
# })

# args <- commandArgs(trailingOnly = TRUE)

# if (length(args) < 5) {
#   stop(
#     "Usage: Rscript mainfig_panelB_cellchat_diffInteraction.R ",
#     "<mcx.rds> <pfc.rds> <out.pdf> <out.png> <out.edges.tsv> ",
#     "[top_frac=0.10] [measure=weight]"
#   )
# }

# mcx_rds   <- args[1]
# pfc_rds   <- args[2]
# out_pdf   <- args[3]
# out_png   <- args[4]
# out_edges <- args[5]

# top_frac <- ifelse(length(args) >= 6, as.numeric(args[6]), 0.10)
# measure  <- ifelse(length(args) >= 7, args[7], "weight")

# if (!file.exists(mcx_rds)) stop("MCX RDS not found: ", mcx_rds)
# if (!file.exists(pfc_rds)) stop("PFC RDS not found: ", pfc_rds)

# if (!measure %in% c("weight", "count")) {
#   stop("measure must be 'weight' or 'count'. Current: ", measure)
# }

# message("[INFO] Reading MCX CellChat object: ", mcx_rds)
# message("[INFO] Reading PFC CellChat object: ", pfc_rds)

# cellchat_mcx <- readRDS(mcx_rds)
# cellchat_pfc <- readRDS(pfc_rds)

# # ============================================================
# # Helper functions
# # ============================================================

# is_glia <- function(x) {
#   grepl("Astro|Ast|GFAP|OPC|Olig|Olg|Micro|Mic", x, ignore.case = TRUE)
# }

# is_vulnerable_target <- function(x) {
#   # THSD4 intentionally excluded
#   grepl("PTHLH|CEMIP|PCP4|NXPH2|CDH4", x, ignore.case = TRUE)
# }

# is_thsd4 <- function(x) {
#   grepl("THSD4", x, ignore.case = TRUE)
# }

# short_label <- function(x) {
#   x <- gsub("Glia\\.", "", x)
#   x <- gsub("Astro\\.GFAP-neg", "Astro GFAP-", x)
#   x <- gsub("Astro\\.GFAP-pos", "Astro GFAP+", x)
#   x <- gsub("PCP4_NXPH2", "PCP4", x)
#   x <- gsub("CDH4_plus", "CDH4+", x)
#   x
# }

# get_net_mat <- function(obj, measure = "weight") {
#   if (measure == "weight") {
#     if (!is.null(obj@net$weight)) return(obj@net$weight)
#   }
#   if (measure == "count") {
#     if (!is.null(obj@net$count)) return(obj@net$count)
#   }
#   stop("Cannot find obj@net$", measure)
# }

# # ============================================================
# # Manually restrict CellChat object to common groups
# # This avoids subsetCellChat().
# # ============================================================

# restrict_cellchat_to_groups <- function(obj, keep_groups) {
#   keep_groups <- as.character(keep_groups)

#   # restrict idents levels
#   obj@idents <- factor(as.character(obj@idents), levels = keep_groups)

#   # restrict meta if available
#   if (!is.null(obj@meta) && nrow(obj@meta) > 0) {
#     if ("labels" %in% colnames(obj@meta)) {
#       obj@meta <- obj@meta[obj@meta$labels %in% keep_groups, , drop = FALSE]
#     }
#   }

#   # restrict object@net matrices
#   if (!is.null(obj@net)) {
#     for (nm in names(obj@net)) {
#       x <- obj@net[[nm]]

#       if (is.matrix(x) || is.data.frame(x)) {
#         x <- as.matrix(x)

#         common_r <- intersect(keep_groups, rownames(x))
#         common_c <- intersect(keep_groups, colnames(x))

#         new_x <- matrix(0, nrow = length(keep_groups), ncol = length(keep_groups))
#         rownames(new_x) <- keep_groups
#         colnames(new_x) <- keep_groups

#         if (length(common_r) > 0 && length(common_c) > 0) {
#           new_x[common_r, common_c] <- x[common_r, common_c, drop = FALSE]
#         }

#         obj@net[[nm]] <- new_x
#       }
#     }
#   }

#   # restrict object@netP arrays where possible
#   if (!is.null(obj@netP)) {
#     for (nm in names(obj@netP)) {
#       x <- obj@netP[[nm]]

#       if (length(dim(x)) == 3) {
#         common_r <- intersect(keep_groups, dimnames(x)[[1]])
#         common_c <- intersect(keep_groups, dimnames(x)[[2]])

#         new_x <- array(
#           0,
#           dim = c(length(keep_groups), length(keep_groups), dim(x)[3]),
#           dimnames = list(
#             keep_groups,
#             keep_groups,
#             dimnames(x)[[3]]
#           )
#         )

#         if (length(common_r) > 0 && length(common_c) > 0) {
#           new_x[common_r, common_c, ] <- x[common_r, common_c, , drop = FALSE]
#         }

#         obj@netP[[nm]] <- new_x
#       }
#     }
#   }

#   obj
# }

# zero_non_glia_to_vulnerable <- function(obj) {
#   for (slot_name in c("weight", "count")) {
#     if (!is.null(obj@net[[slot_name]])) {
#       mat <- obj@net[[slot_name]]

#       for (i in seq_len(nrow(mat))) {
#         for (j in seq_len(ncol(mat))) {
#           src <- rownames(mat)[i]
#           tgt <- colnames(mat)[j]

#           keep_edge <- is_glia(src) &&
#             is_vulnerable_target(tgt) &&
#             !is_thsd4(tgt)

#           if (!keep_edge) {
#             mat[i, j] <- 0
#           }
#         }
#       }

#       obj@net[[slot_name]] <- mat
#     }
#   }

#   obj
# }

# # ============================================================
# # 1. Keep shared groups only and remove THSD4
# # ============================================================

# mcx_groups <- levels(cellchat_mcx@idents)
# pfc_groups <- levels(cellchat_pfc@idents)

# common_groups <- intersect(mcx_groups, pfc_groups)
# common_groups <- common_groups[!is_thsd4(common_groups)]

# message("[INFO] MCX groups: ", paste(mcx_groups, collapse = ", "))
# message("[INFO] PFC groups: ", paste(pfc_groups, collapse = ", "))
# message("[INFO] Shared groups used for Panel B: ", paste(common_groups, collapse = ", "))

# if (length(common_groups) < 2) {
#   stop("Too few common groups after excluding THSD4.")
# }

# cellchat_mcx_sub <- restrict_cellchat_to_groups(cellchat_mcx, common_groups)
# cellchat_pfc_sub <- restrict_cellchat_to_groups(cellchat_pfc, common_groups)

# cellchat_mcx_sub <- zero_non_glia_to_vulnerable(cellchat_mcx_sub)
# cellchat_pfc_sub <- zero_non_glia_to_vulnerable(cellchat_pfc_sub)

# # ============================================================
# # 2. Save edge table for checking
# # ============================================================

# mcx_mat <- get_net_mat(cellchat_mcx_sub, measure)
# pfc_mat <- get_net_mat(cellchat_pfc_sub, measure)

# mcx_mat <- mcx_mat[common_groups, common_groups, drop = FALSE]
# pfc_mat <- pfc_mat[common_groups, common_groups, drop = FALSE]

# delta_mat <- mcx_mat - pfc_mat

# edge_df <- as.data.frame(as.table(delta_mat)) %>%
#   dplyr::rename(
#     source_raw = Var1,
#     target_raw = Var2,
#     delta_MCX_minus_PFC = Freq
#   ) %>%
#   dplyr::mutate(
#     source = short_label(as.character(source_raw)),
#     target = short_label(as.character(target_raw)),
#     abs_delta = abs(delta_MCX_minus_PFC),
#     direction = dplyr::case_when(
#       delta_MCX_minus_PFC > 0 ~ "MCX_higher",
#       delta_MCX_minus_PFC < 0 ~ "PFC_higher",
#       TRUE ~ "no_change"
#     ),
#     top_fraction = top_frac,
#     measure = measure,
#     note = "THSD4 excluded; shared groups only; glia_to_vulnerable direction only"
#   ) %>%
#   dplyr::filter(abs_delta > 0) %>%
#   dplyr::arrange(dplyr::desc(abs_delta))

# if (nrow(edge_df) == 0) {
#   stop("No differential glia -> vulnerable neuron edges found after excluding THSD4.")
# }

# n_top <- max(1, ceiling(nrow(edge_df) * top_frac))

# edge_out <- edge_df %>%
#   dplyr::slice_head(n = n_top)

# readr::write_tsv(edge_out, out_edges)

# message("[INFO] Top fraction: ", top_frac)
# message("[INFO] Measure: ", measure)
# message("[INFO] Top edges saved: ", out_edges)
# message("[INFO] Number of top edges: ", nrow(edge_out))
# message("[INFO] MCX higher edges in top set: ", sum(edge_out$direction == "MCX_higher"))
# message("[INFO] PFC higher edges in top set: ", sum(edge_out$direction == "PFC_higher"))

# # ============================================================
# # 3. Reference-style CellChat built-in plot
# # ============================================================

# # 为了让 Panel B 的标签风格接近 Panel A，只改显示标签，不改网络内容
# rename_cellchat_groups_for_plot <- function(obj) {
#   old_levels <- levels(obj@idents)
#   new_levels <- short_label(old_levels)

#   obj@idents <- factor(
#     short_label(as.character(obj@idents)),
#     levels = new_levels
#   )

#   if (!is.null(obj@meta) && nrow(obj@meta) > 0) {
#     if ("labels" %in% colnames(obj@meta)) {
#       obj@meta$labels <- short_label(as.character(obj@meta$labels))
#     }
#   }

#   if (!is.null(obj@net)) {
#     for (nm in names(obj@net)) {
#       x <- obj@net[[nm]]

#       if (is.matrix(x) || is.data.frame(x)) {
#         x <- as.matrix(x)
#         rownames(x) <- short_label(rownames(x))
#         colnames(x) <- short_label(colnames(x))
#         obj@net[[nm]] <- x
#       }
#     }
#   }

#   if (!is.null(obj@netP)) {
#     for (nm in names(obj@netP)) {
#       x <- obj@netP[[nm]]

#       if (length(dim(x)) == 3) {
#         dimnames(x)[[1]] <- short_label(dimnames(x)[[1]])
#         dimnames(x)[[2]] <- short_label(dimnames(x)[[2]])
#         obj@netP[[nm]] <- x
#       }
#     }
#   }

#   obj
# }

# cellchat_mcx_plot <- rename_cellchat_groups_for_plot(cellchat_mcx_sub)
# cellchat_pfc_plot <- rename_cellchat_groups_for_plot(cellchat_pfc_sub)

# cellchat_merged <- mergeCellChat(
#   list(MCX = cellchat_mcx_plot, PFC = cellchat_pfc_plot),
#   add.names = c("MCX", "PFC")
# )

# # According to your reference code logic:
# # comparison = c(2,1) makes red represent the second condition higher.
# # Here red should be MCX > PFC.
# COMP <- c(2, 1)

# has_top_arg <- "top" %in% names(formals(CellChat::netVisual_diffInteraction))
# if (!has_top_arg) {
#   stop(
#     "Your CellChat::netVisual_diffInteraction() has no 'top' argument. ",
#     "Cannot use reference-style top differential interaction plotting."
#   )
# }

# # ============================================================
# # Render Panel B as one square plot first
# # Then compose it into a single-panel facet canvas.
# #
# # This makes Panel B match ONE panel of Panel A, not the whole Panel A.
# # ============================================================

# suppressPackageStartupMessages({
#   library(grid)
# })

# if (!requireNamespace("png", quietly = TRUE)) {
#   stop(
#     "R package 'png' is required. ",
#     "Install it first, e.g. install.packages('png')."
#   )
# }

# plot_fun <- function() {
#   old_par <- par(no.readonly = TRUE)
#   on.exit(par(old_par), add = TRUE)

#   par(
#     xpd = NA,
#     mar = c(0, 0, 0, 0),
#     oma = c(0, 0, 0, 0),
#     pty = "s"
#   )

#   plot_args <- list(
#     object = cellchat_merged,
#     comparison = COMP,
#     measure = measure,
#     weight.scale = TRUE,
#     top = top_frac,
#     title.name = ""
#   )

#   if ("edge.width.max" %in% names(formals(CellChat::netVisual_diffInteraction))) {
#     plot_args$edge.width.max <- 8
#   }

#   if ("vertex.label.cex" %in% names(formals(CellChat::netVisual_diffInteraction))) {
#     plot_args$vertex.label.cex <- 0.90
#   }

#   if ("vertex.size.max" %in% names(formals(CellChat::netVisual_diffInteraction))) {
#     plot_args$vertex.size.max <- 12
#   }

#   do.call(CellChat::netVisual_diffInteraction, plot_args)
# }

# render_diff_png <- function(file) {
#   png(file, width = 1800, height = 1800, res = 300)
#   plot_fun()
#   dev.off()
# }

# draw_header_strip <- function(label, fill) {
#   grid.rect(
#     gp = gpar(
#       fill = fill,
#       col = "black",
#       lwd = 1.2
#     )
#   )

#   grid.text(
#     label,
#     x = 0.5,
#     y = 0.5,
#     gp = gpar(
#       col = "white",
#       fontsize = 18,
#       fontface = "bold"
#     )
#   )
# }

# draw_panel_image <- function(img) {
#   grid.rect(
#     gp = gpar(
#       fill = "white",
#       col = "black",
#       lwd = 0.8
#     )
#   )

#   grid.raster(
#     img,
#     x = 0.5,
#     y = 0.5,
#     width = unit(1, "npc"),
#     height = unit(1, "npc"),
#     interpolate = TRUE
#   )
# }

# draw_single_facet_figure <- function(img) {
#   grid.newpage()

#   lay <- grid.layout(
#     nrow = 2,
#     ncol = 1,
#     heights = unit.c(
#       unit(0.38, "in"),
#       unit(1, "null")
#     )
#   )

#   pushViewport(viewport(layout = lay))

#   pushViewport(viewport(layout.pos.row = 1, layout.pos.col = 1))
#   draw_header_strip("Differential", "#ec4f93")
#   popViewport()

#   pushViewport(viewport(layout.pos.row = 2, layout.pos.col = 1))
#   draw_panel_image(img)
#   popViewport()

#   popViewport()
# }

# tmp_diff <- tempfile(fileext = ".png")
# render_diff_png(tmp_diff)
# diff_img <- png::readPNG(tmp_diff)

# # Panel A is two panels in one figure.
# # If Panel A is width = 11.5, height = 5.8,
# # one Panel A subpanel is approximately width = 5.75, height = 5.8.
# grDevices::cairo_pdf(out_pdf, width = 5.75, height = 5.8)
# draw_single_facet_figure(diff_img)
# dev.off()

# png(out_png, width = 1725, height = 1740, res = 300)
# draw_single_facet_figure(diff_img)
# dev.off()

# unlink(tmp_diff)

# message("[INFO] Saved PDF: ", out_pdf)
# message("[INFO] Saved PNG: ", out_png)
#!/usr/bin/env Rscript

# ============================================================
# Panel B
# CellChat built-in differential interaction network
#
# Method:
#   mergeCellChat()
#   netVisual_diffInteraction()
#
# Red  = MCX higher
# Blue = PFC higher
#
# Changes:
#   - remove top facet/header strip
#   - remove long title
#   - add one clean bottom legend
#   - keep output as one clean square network panel
# ============================================================

suppressPackageStartupMessages({
  library(CellChat)
  library(dplyr)
  library(readr)
})

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 5) {
  stop(
    "Usage: Rscript mainfig_panelB_cellchat_diffInteraction.R ",
    "<mcx.rds> <pfc.rds> <out.pdf> <out.png> <out.edges.tsv> ",
    "[top_frac=0.10] [measure=weight]"
  )
}

mcx_rds   <- args[1]
pfc_rds   <- args[2]
out_pdf   <- args[3]
out_png   <- args[4]
out_edges <- args[5]

top_frac <- ifelse(length(args) >= 6, as.numeric(args[6]), 0.10)
measure  <- ifelse(length(args) >= 7, args[7], "weight")

if (!file.exists(mcx_rds)) stop("MCX RDS not found: ", mcx_rds)
if (!file.exists(pfc_rds)) stop("PFC RDS not found: ", pfc_rds)

if (!measure %in% c("weight", "count")) {
  stop("measure must be 'weight' or 'count'. Current: ", measure)
}

message("[INFO] Reading MCX CellChat object: ", mcx_rds)
message("[INFO] Reading PFC CellChat object: ", pfc_rds)

cellchat_mcx <- readRDS(mcx_rds)
cellchat_pfc <- readRDS(pfc_rds)

# ============================================================
# Helper functions
# ============================================================

is_glia <- function(x) {
  grepl("Astro|Ast|GFAP|OPC|Olig|Olg|Micro|Mic", x, ignore.case = TRUE)
}

is_vulnerable_target <- function(x) {
  # THSD4 intentionally excluded
  grepl("PTHLH|CEMIP|PCP4|NXPH2|CDH4", x, ignore.case = TRUE)
}

is_thsd4 <- function(x) {
  grepl("THSD4", x, ignore.case = TRUE)
}

short_label <- function(x) {
  x <- gsub("Glia\\.", "", x)
  x <- gsub("Astro\\.GFAP-neg", "Astro GFAP-", x)
  x <- gsub("Astro\\.GFAP-pos", "Astro GFAP+", x)
  x <- gsub("PCP4_NXPH2", "PCP4", x)
  x <- gsub("CDH4_plus", "CDH4+", x)
  x
}

get_net_mat <- function(obj, measure = "weight") {
  if (measure == "weight") {
    if (!is.null(obj@net$weight)) return(obj@net$weight)
  }

  if (measure == "count") {
    if (!is.null(obj@net$count)) return(obj@net$count)
  }

  stop("Cannot find obj@net$", measure)
}

# ============================================================
# Manually restrict CellChat object to common groups
# This avoids subsetCellChat().
# ============================================================

restrict_cellchat_to_groups <- function(obj, keep_groups) {
  keep_groups <- as.character(keep_groups)

  obj@idents <- factor(as.character(obj@idents), levels = keep_groups)

  if (!is.null(obj@meta) && nrow(obj@meta) > 0) {
    if ("labels" %in% colnames(obj@meta)) {
      obj@meta <- obj@meta[obj@meta$labels %in% keep_groups, , drop = FALSE]
    }
  }

  if (!is.null(obj@net)) {
    for (nm in names(obj@net)) {
      x <- obj@net[[nm]]

      if (is.matrix(x) || is.data.frame(x)) {
        x <- as.matrix(x)

        common_r <- intersect(keep_groups, rownames(x))
        common_c <- intersect(keep_groups, colnames(x))

        new_x <- matrix(0, nrow = length(keep_groups), ncol = length(keep_groups))
        rownames(new_x) <- keep_groups
        colnames(new_x) <- keep_groups

        if (length(common_r) > 0 && length(common_c) > 0) {
          new_x[common_r, common_c] <- x[common_r, common_c, drop = FALSE]
        }

        obj@net[[nm]] <- new_x
      }
    }
  }

  if (!is.null(obj@netP)) {
    for (nm in names(obj@netP)) {
      x <- obj@netP[[nm]]

      if (length(dim(x)) == 3) {
        common_r <- intersect(keep_groups, dimnames(x)[[1]])
        common_c <- intersect(keep_groups, dimnames(x)[[2]])

        new_x <- array(
          0,
          dim = c(length(keep_groups), length(keep_groups), dim(x)[3]),
          dimnames = list(
            keep_groups,
            keep_groups,
            dimnames(x)[[3]]
          )
        )

        if (length(common_r) > 0 && length(common_c) > 0) {
          new_x[common_r, common_c, ] <- x[common_r, common_c, , drop = FALSE]
        }

        obj@netP[[nm]] <- new_x
      }
    }
  }

  obj
}

zero_non_glia_to_vulnerable <- function(obj) {
  for (slot_name in c("weight", "count")) {
    if (!is.null(obj@net[[slot_name]])) {
      mat <- obj@net[[slot_name]]

      for (i in seq_len(nrow(mat))) {
        for (j in seq_len(ncol(mat))) {
          src <- rownames(mat)[i]
          tgt <- colnames(mat)[j]

          keep_edge <- is_glia(src) &&
            is_vulnerable_target(tgt) &&
            !is_thsd4(tgt)

          if (!keep_edge) {
            mat[i, j] <- 0
          }
        }
      }

      obj@net[[slot_name]] <- mat
    }
  }

  obj
}

# ============================================================
# 1. Keep shared groups only and remove THSD4
# ============================================================

mcx_groups <- levels(cellchat_mcx@idents)
pfc_groups <- levels(cellchat_pfc@idents)

common_groups <- intersect(mcx_groups, pfc_groups)
common_groups <- common_groups[!is_thsd4(common_groups)]

message("[INFO] MCX groups: ", paste(mcx_groups, collapse = ", "))
message("[INFO] PFC groups: ", paste(pfc_groups, collapse = ", "))
message("[INFO] Shared groups used for Panel B: ", paste(common_groups, collapse = ", "))

if (length(common_groups) < 2) {
  stop("Too few common groups after excluding THSD4.")
}

cellchat_mcx_sub <- restrict_cellchat_to_groups(cellchat_mcx, common_groups)
cellchat_pfc_sub <- restrict_cellchat_to_groups(cellchat_pfc, common_groups)

cellchat_mcx_sub <- zero_non_glia_to_vulnerable(cellchat_mcx_sub)
cellchat_pfc_sub <- zero_non_glia_to_vulnerable(cellchat_pfc_sub)

# ============================================================
# 2. Save edge table for checking
# ============================================================

mcx_mat <- get_net_mat(cellchat_mcx_sub, measure)
pfc_mat <- get_net_mat(cellchat_pfc_sub, measure)

mcx_mat <- mcx_mat[common_groups, common_groups, drop = FALSE]
pfc_mat <- pfc_mat[common_groups, common_groups, drop = FALSE]

delta_mat <- mcx_mat - pfc_mat

edge_df <- as.data.frame(as.table(delta_mat)) %>%
  dplyr::rename(
    source_raw = Var1,
    target_raw = Var2,
    delta_MCX_minus_PFC = Freq
  ) %>%
  dplyr::mutate(
    source = short_label(as.character(source_raw)),
    target = short_label(as.character(target_raw)),
    abs_delta = abs(delta_MCX_minus_PFC),
    direction = dplyr::case_when(
      delta_MCX_minus_PFC > 0 ~ "MCX_higher",
      delta_MCX_minus_PFC < 0 ~ "PFC_higher",
      TRUE ~ "no_change"
    ),
    top_fraction = top_frac,
    measure = measure,
    note = "THSD4 excluded; shared groups only; glia_to_vulnerable direction only"
  ) %>%
  dplyr::filter(abs_delta > 0) %>%
  dplyr::arrange(dplyr::desc(abs_delta))

if (nrow(edge_df) == 0) {
  stop("No differential glia -> vulnerable neuron edges found after excluding THSD4.")
}

n_top <- max(1, ceiling(nrow(edge_df) * top_frac))

edge_out <- edge_df %>%
  dplyr::slice_head(n = n_top)

readr::write_tsv(edge_out, out_edges)

message("[INFO] Top fraction: ", top_frac)
message("[INFO] Measure: ", measure)
message("[INFO] Top edges saved: ", out_edges)
message("[INFO] Number of top edges: ", nrow(edge_out))
message("[INFO] MCX higher edges in top set: ", sum(edge_out$direction == "MCX_higher"))
message("[INFO] PFC higher edges in top set: ", sum(edge_out$direction == "PFC_higher"))

# ============================================================
# 3. Rename labels for plotting only
# ============================================================

rename_cellchat_groups_for_plot <- function(obj) {
  old_levels <- levels(obj@idents)
  new_levels <- short_label(old_levels)

  obj@idents <- factor(
    short_label(as.character(obj@idents)),
    levels = new_levels
  )

  if (!is.null(obj@meta) && nrow(obj@meta) > 0) {
    if ("labels" %in% colnames(obj@meta)) {
      obj@meta$labels <- short_label(as.character(obj@meta$labels))
    }
  }

  if (!is.null(obj@net)) {
    for (nm in names(obj@net)) {
      x <- obj@net[[nm]]

      if (is.matrix(x) || is.data.frame(x)) {
        x <- as.matrix(x)
        rownames(x) <- short_label(rownames(x))
        colnames(x) <- short_label(colnames(x))
        obj@net[[nm]] <- x
      }
    }
  }

  if (!is.null(obj@netP)) {
    for (nm in names(obj@netP)) {
      x <- obj@netP[[nm]]

      if (length(dim(x)) == 3) {
        dimnames(x)[[1]] <- short_label(dimnames(x)[[1]])
        dimnames(x)[[2]] <- short_label(dimnames(x)[[2]])
        obj@netP[[nm]] <- x
      }
    }
  }

  obj
}

cellchat_mcx_plot <- rename_cellchat_groups_for_plot(cellchat_mcx_sub)
cellchat_pfc_plot <- rename_cellchat_groups_for_plot(cellchat_pfc_sub)

cellchat_merged <- mergeCellChat(
  list(MCX = cellchat_mcx_plot, PFC = cellchat_pfc_plot),
  add.names = c("MCX", "PFC")
)

# comparison = c(2, 1) follows your current script logic:
# red = MCX higher; blue = PFC higher
COMP <- c(2, 1)

has_top_arg <- "top" %in% names(formals(CellChat::netVisual_diffInteraction))
if (!has_top_arg) {
  stop(
    "Your CellChat::netVisual_diffInteraction() has no 'top' argument. ",
    "Cannot use reference-style top differential interaction plotting."
  )
}

# ============================================================
# 4. Plot function without facet header, with clean bottom legend
# ============================================================

plot_fun <- function() {
  old_par <- par(no.readonly = TRUE)
  on.exit(par(old_par), add = TRUE)

  par(
    xpd = NA,
    mar = c(2.2, 0.2, 0.2, 0.2),
    oma = c(0, 0, 0, 0),
    pty = "s"
  )

  plot_args <- list(
    object = cellchat_merged,
    comparison = COMP,
    measure = measure,
    weight.scale = TRUE,
    top = top_frac,
    title.name = ""
  )

  if ("edge.width.max" %in% names(formals(CellChat::netVisual_diffInteraction))) {
    plot_args$edge.width.max <- 8
  }

  if ("vertex.label.cex" %in% names(formals(CellChat::netVisual_diffInteraction))) {
    plot_args$vertex.label.cex <- 0.90
  }

  if ("vertex.size.max" %in% names(formals(CellChat::netVisual_diffInteraction))) {
    plot_args$vertex.size.max <- 12
  }

  do.call(CellChat::netVisual_diffInteraction, plot_args)

  legend(
    x = "bottom",
    inset = c(0, -0.10),
    legend = c("MCX higher", "PFC higher"),
    col = c("red", "blue"),
    lwd = c(4, 4),
    horiz = TRUE,
    bty = "n",
    cex = 0.95,
    xpd = NA,
    seg.len = 2.2,
    text.col = "black"
  )
}

# ============================================================
# 5. Save directly, no facet strip
# ============================================================

grDevices::cairo_pdf(out_pdf, width = 5.75, height = 6.05)
plot_fun()
dev.off()

png(out_png, width = 1725, height = 1815, res = 300)
plot_fun()
dev.off()

message("[INFO] Saved PDF: ", out_pdf)
message("[INFO] Saved PNG: ", out_png)