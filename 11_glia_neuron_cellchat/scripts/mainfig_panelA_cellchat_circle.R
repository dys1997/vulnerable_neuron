# # #!/usr/bin/env Rscript

# # ============================================================
# # Panel A - V2 style, THSD4 removed
# # PFC + MCX CellChat circle plots in one figure
# #
# # Key settings kept from V2:
# #   - two circle plots in one figure
# #   - shared edge.weight.max = max(c(mat_pfc, mat_mcx))
# #   - vertex.size used
# #   - CellChat netVisual_circle
# #
# # THSD4 is removed because it only exists in MCX.
# #
# # Only visualization parameters are modified:
# #   - smaller figure size
# #   - thicker edges
# #   - tighter margins
# # ============================================================

# suppressPackageStartupMessages({
#   library(CellChat)
# })

# args <- commandArgs(trailingOnly = TRUE)

# if (length(args) < 4) {
#   stop("Usage: Rscript mainfig_panelA_cellchat_circle.R pfc.rds mcx.rds out.pdf out.png [out.tsv]")
# }

# pfc_rds <- args[1]
# mcx_rds <- args[2]
# out_pdf <- args[3]
# out_png <- args[4]
# out_tsv <- ifelse(length(args) >= 5, args[5], NA)

# cellchat_pfc <- readRDS(pfc_rds)
# cellchat_mcx <- readRDS(mcx_rds)

# get_weight_mat <- function(obj) {
#   if (!is.null(obj@net$weight)) return(obj@net$weight)
#   if (!is.null(obj@net$count)) return(obj@net$count)
#   stop("Cannot find obj@net$weight or obj@net$count")
# }

# is_glia <- function(x) {
#   grepl("Astro|GFAP|OPC|Oligo|Olg|Micro", x, ignore.case = TRUE)
# }

# is_target <- function(x) {
#   # THSD4 intentionally removed
#   grepl("PTHLH|CEMIP|PCP4|NXPH2|CDH4", x, ignore.case = TRUE)
# }

# short_label <- function(x) {
#   x <- gsub("Glia\\.", "", x)
#   x <- gsub("Astro\\.GFAP-neg", "Astro-", x)
#   x <- gsub("Astro\\.GFAP-pos", "Astro+", x)
#   x <- gsub("PCP4_NXPH2", "PCP4", x)
#   x <- gsub("CDH4_plus", "CDH4+", x)
#   x
# }

# make_mat <- function(obj) {
#   mat <- get_weight_mat(obj)

#   keep <- rownames(mat)[is_glia(rownames(mat)) | is_target(rownames(mat))]
#   keep <- keep[!grepl("THSD4", keep, ignore.case = TRUE)]

#   mat <- mat[keep, keep, drop = FALSE]

#   for (i in seq_len(nrow(mat))) {
#     for (j in seq_len(ncol(mat))) {
#       src <- rownames(mat)[i]
#       tgt <- colnames(mat)[j]

#       keep_edge <- is_glia(src) &&
#         is_target(tgt) &&
#         !grepl("THSD4", tgt, ignore.case = TRUE)

#       if (!keep_edge) {
#         mat[i, j] <- 0
#       }
#     }
#   }

#   rownames(mat) <- short_label(rownames(mat))
#   colnames(mat) <- short_label(colnames(mat))

#   mat
# }

# expand_mat <- function(mat, nodes) {
#   out <- matrix(0, nrow = length(nodes), ncol = length(nodes))
#   rownames(out) <- nodes
#   colnames(out) <- nodes

#   rr <- intersect(rownames(mat), nodes)
#   cc <- intersect(colnames(mat), nodes)

#   if (length(rr) > 0 && length(cc) > 0) {
#     out[rr, cc] <- mat[rr, cc, drop = FALSE]
#   }

#   out
# }

# mat_pfc0 <- make_mat(cellchat_pfc)
# mat_mcx0 <- make_mat(cellchat_mcx)

# node_order <- c(
#   "Astro-",
#   "Astro+",
#   "Oligo",
#   "OPC",
#   "Micro",
#   "PTHLH",
#   "CEMIP",
#   "PCP4",
#   "CDH4+"
# )

# nodes <- unique(c(node_order, rownames(mat_pfc0), rownames(mat_mcx0)))
# nodes <- nodes[nodes %in% unique(c(rownames(mat_pfc0), rownames(mat_mcx0)))]
# nodes <- nodes[!grepl("THSD4", nodes, ignore.case = TRUE)]

# mat_pfc <- expand_mat(mat_pfc0, nodes)
# mat_mcx <- expand_mat(mat_mcx0, nodes)

# max_weight <- max(c(mat_pfc, mat_mcx), na.rm = TRUE)

# if (is.na(max_weight) || max_weight <= 0) {
#   max_weight <- 1
# }

# vertex_size <- rowSums(mat_pfc + mat_mcx) + colSums(mat_pfc + mat_mcx)
# vertex_size[vertex_size == 0] <- 1

# if (!is.na(out_tsv)) {
#   df_pfc <- as.data.frame(as.table(mat_pfc))
#   colnames(df_pfc) <- c("source", "target", "strength")
#   df_pfc$region <- "PFC"

#   df_mcx <- as.data.frame(as.table(mat_mcx))
#   colnames(df_mcx) <- c("source", "target", "strength")
#   df_mcx$region <- "MCX"

#   df <- rbind(df_pfc, df_mcx)
#   df <- df[df$strength > 0, c("region", "source", "target", "strength")]
#   write.table(df, out_tsv, sep = "\t", quote = FALSE, row.names = FALSE)
# }

# message("[INFO] THSD4 removed from Panel A.")
# message("[INFO] Nodes: ", paste(nodes, collapse = ", "))
# message("[INFO] PFC nonzero edges: ", sum(mat_pfc > 0))
# message("[INFO] MCX nonzero edges: ", sum(mat_mcx > 0))
# message("[INFO] PFC total strength: ", sum(mat_pfc))
# message("[INFO] MCX total strength: ", sum(mat_mcx))
# message("[INFO] max_weight: ", max_weight)
# message("[INFO] saved Panel A: ", out_pdf)

# plot_panel <- function() {
#   oldpar <- par(no.readonly = TRUE)
#   on.exit(par(oldpar), add = TRUE)

#   par(
#     mfrow = c(1, 2),
#     xpd = TRUE,
#     mar = c(0.6, 0.6, 1.8, 0.6),
#     oma = c(0, 0, 0, 0),
#     pty = "s"
#   )

#   netVisual_circle(
#     mat_pfc,
#     weight.scale = TRUE,
#     edge.weight.max = max_weight,
#     edge.width.max = 8,
#     vertex.size = vertex_size,
#     vertex.label.cex = 0.90,
#     edge.curved = 0.18,
#     margin = 0.4,
#     label.edge = FALSE,
#     title.name = "PFC"
#   )

#   netVisual_circle(
#     mat_mcx,
#     weight.scale = TRUE,
#     edge.weight.max = max_weight,
#     edge.width.max = 8,
#     vertex.size = vertex_size,
#     vertex.label.cex = 0.90,
#     edge.curved = 0.18,
#     margin = 0.4,
#     label.edge = FALSE,
#     title.name = "MCX"
#   )
# }

# grDevices::cairo_pdf(out_pdf, width = 10.5, height = 5.2)
# plot_panel()
# dev.off()

# png(out_png, width = 3150, height = 1560, res = 300)
# plot_panel()
# dev.off()
#!/usr/bin/env Rscript

#!/usr/bin/env Rscript

# ============================================================
# Panel A - V2 style, THSD4 removed
# PFC + MCX CellChat circle plots in one figure
#
# Key settings kept from V2:
#   - two circle plots in one figure
#   - shared edge.weight.max = max(c(mat_pfc, mat_mcx))
#   - vertex.size used
#   - CellChat netVisual_circle
#
# THSD4 is removed because it only exists in MCX.
#
# Visualization update:
#   - keep CellChat original netVisual_circle()
#   - smaller canvas
#   - tighter margins
#   - thicker edges
# ============================================================
#!/usr/bin/env Rscript

# ============================================================
# Panel A - V2 style, THSD4 removed
# PFC + MCX CellChat circle plots in one facet-style figure
#
# Key settings kept:
#   - shared edge.weight.max = max(c(mat_pfc, mat_mcx))
#   - vertex.size used
#   - CellChat netVisual_circle
#   - THSD4 removed
#
# Visualization:
#   - MCX / PFC colored facet strips
#   - left-side row strip
#   - CellChat circle plots rendered separately, then composed by grid
#   - avoids layout() conflict with netVisual_circle()
# ============================================================

suppressPackageStartupMessages({
  library(CellChat)
  library(grid)
})

if (!requireNamespace("png", quietly = TRUE)) {
  stop(
    "R package 'png' is required for facet composition. ",
    "Install it first, e.g. install.packages('png')."
  )
}

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 4) {
  stop("Usage: Rscript mainfig_panelA_cellchat_circle.R pfc.rds mcx.rds out.pdf out.png [out.tsv]")
}

pfc_rds <- args[1]
mcx_rds <- args[2]
out_pdf <- args[3]
out_png <- args[4]
out_tsv <- ifelse(length(args) >= 5, args[5], NA)

cellchat_pfc <- readRDS(pfc_rds)
cellchat_mcx <- readRDS(mcx_rds)

get_weight_mat <- function(obj) {
  if (!is.null(obj@net$weight)) return(obj@net$weight)
  if (!is.null(obj@net$count)) return(obj@net$count)
  stop("Cannot find obj@net$weight or obj@net$count")
}

is_glia <- function(x) {
  grepl("Astro|GFAP|OPC|Oligo|Olg|Micro", x, ignore.case = TRUE)
}

is_target <- function(x) {
  # THSD4 intentionally removed
  grepl("PTHLH|CEMIP|PCP4|NXPH2|CDH4", x, ignore.case = TRUE)
}

short_label <- function(x) {
  x <- gsub("Glia\\.", "", x)
  x <- gsub("Astro\\.GFAP-neg", "Astro-", x)
  x <- gsub("Astro\\.GFAP-pos", "Astro+", x)
  x <- gsub("PCP4_NXPH2", "PCP4", x)
  x <- gsub("CDH4_plus", "CDH4+", x)
  x
}

make_mat <- function(obj) {
  mat <- get_weight_mat(obj)

  keep <- rownames(mat)[is_glia(rownames(mat)) | is_target(rownames(mat))]
  keep <- keep[!grepl("THSD4", keep, ignore.case = TRUE)]

  mat <- mat[keep, keep, drop = FALSE]

  for (i in seq_len(nrow(mat))) {
    for (j in seq_len(ncol(mat))) {
      src <- rownames(mat)[i]
      tgt <- colnames(mat)[j]

      keep_edge <- is_glia(src) &&
        is_target(tgt) &&
        !grepl("THSD4", tgt, ignore.case = TRUE)

      if (!keep_edge) {
        mat[i, j] <- 0
      }
    }
  }

  rownames(mat) <- short_label(rownames(mat))
  colnames(mat) <- short_label(colnames(mat))

  mat
}

expand_mat <- function(mat, nodes) {
  out <- matrix(0, nrow = length(nodes), ncol = length(nodes))
  rownames(out) <- nodes
  colnames(out) <- nodes

  rr <- intersect(rownames(mat), nodes)
  cc <- intersect(colnames(mat), nodes)

  if (length(rr) > 0 && length(cc) > 0) {
    out[rr, cc] <- mat[rr, cc, drop = FALSE]
  }

  out
}

mat_pfc0 <- make_mat(cellchat_pfc)
mat_mcx0 <- make_mat(cellchat_mcx)

node_order <- c(
  "Astro-",
  "Astro+",
  "Oligo",
  "OPC",
  "Micro",
  "PTHLH",
  "CEMIP",
  "PCP4",
  "CDH4+"
)

nodes <- unique(c(node_order, rownames(mat_pfc0), rownames(mat_mcx0)))
nodes <- nodes[nodes %in% unique(c(rownames(mat_pfc0), rownames(mat_mcx0)))]
nodes <- nodes[!grepl("THSD4", nodes, ignore.case = TRUE)]

mat_pfc <- expand_mat(mat_pfc0, nodes)
mat_mcx <- expand_mat(mat_mcx0, nodes)

max_weight <- max(c(mat_pfc, mat_mcx), na.rm = TRUE)

if (is.na(max_weight) || max_weight <= 0) {
  max_weight <- 1
}

vertex_size <- rowSums(mat_pfc + mat_mcx) + colSums(mat_pfc + mat_mcx)
vertex_size[vertex_size == 0] <- 1

if (!is.na(out_tsv)) {
  df_pfc <- as.data.frame(as.table(mat_pfc))
  colnames(df_pfc) <- c("source", "target", "strength")
  df_pfc$region <- "PFC"

  df_mcx <- as.data.frame(as.table(mat_mcx))
  colnames(df_mcx) <- c("source", "target", "strength")
  df_mcx$region <- "MCX"

  df <- rbind(df_pfc, df_mcx)
  df <- df[df$strength > 0, c("region", "source", "target", "strength")]
  write.table(df, out_tsv, sep = "\t", quote = FALSE, row.names = FALSE)
}

message("[INFO] THSD4 removed from Panel A.")
message("[INFO] Nodes: ", paste(nodes, collapse = ", "))
message("[INFO] PFC nonzero edges: ", sum(mat_pfc > 0))
message("[INFO] MCX nonzero edges: ", sum(mat_mcx > 0))
message("[INFO] PFC total strength: ", sum(mat_pfc))
message("[INFO] MCX total strength: ", sum(mat_mcx))
message("[INFO] max_weight: ", max_weight)

# ============================================================
# Render each CellChat circle plot into a temporary PNG
# This keeps CellChat's original visualization method unchanged.
# ============================================================

render_circle_png <- function(mat, file) {
  png(file, width = 1800, height = 1800, res = 300)

  oldpar <- par(no.readonly = TRUE)
  on.exit({
    par(oldpar)
    dev.off()
  }, add = TRUE)

  par(
    mar = c(0, 0, 0, 0),
    oma = c(0, 0, 0, 0),
    xpd = TRUE,
    pty = "s"
  )

  netVisual_circle(
    mat,
    weight.scale = TRUE,
    edge.weight.max = max_weight,
    edge.width.max = 8,
    vertex.size = vertex_size,
    vertex.label.cex = 0.90,
    edge.curved = 0.18,
    margin = 0.35,
    label.edge = FALSE,
    title.name = ""
  )
}

# ============================================================
# Draw final facet-style figure
# ============================================================

draw_header_strip <- function(label, fill) {
  grid.rect(
    gp = gpar(
      fill = fill,
      col = "black",
      lwd = 1.2
    )
  )

  grid.text(
    label,
    x = 0.5,
    y = 0.5,
    gp = gpar(
      col = "white",
      fontsize = 18,
      fontface = "bold"
    )
  )
}

draw_side_strip <- function(label, fill = "#29B6E6") {
  grid.rect(
    gp = gpar(
      fill = fill,
      col = "black",
      lwd = 1.2
    )
  )

  grid.text(
    label,
    x = 0.5,
    y = 0.5,
    rot = 90,
    gp = gpar(
      col = "white",
      fontsize = 15,
      fontface = "bold"
    )
  )
}

draw_panel_image <- function(img) {
  grid.rect(
    gp = gpar(
      fill = "white",
      col = "black",
      lwd = 0.8
    )
  )

  grid.raster(
    img,
    x = 0.5,
    y = 0.5,
    width = unit(1, "npc"),
    height = unit(1, "npc"),
    interpolate = TRUE
  )
}

draw_facet_figure <- function(mcx_img, pfc_img) {
  grid.newpage()

  lay <- grid.layout(
    nrow = 2,
    ncol = 2,
    widths = unit.c(
      unit(1, "null"),
      unit(1, "null")
    ),
    heights = unit.c(
      unit(0.38, "in"),
      unit(1, "null")
    )
  )

  pushViewport(viewport(layout = lay))

  # Top facet strips
  pushViewport(viewport(layout.pos.row = 1, layout.pos.col = 1))
  draw_header_strip("MCX", "#ec4f93")
  popViewport()

  pushViewport(viewport(layout.pos.row = 1, layout.pos.col = 2))
  draw_header_strip("DLPFC", "#2ca25f")
  popViewport()

  # Main panels
  pushViewport(viewport(layout.pos.row = 2, layout.pos.col = 1))
  draw_panel_image(mcx_img)
  popViewport()

  pushViewport(viewport(layout.pos.row = 2, layout.pos.col = 2))
  draw_panel_image(pfc_img)
  popViewport()

  popViewport()
}

# ============================================================
# Render temporary panels and compose final PDF/PNG
# ============================================================

tmp_mcx <- tempfile(fileext = ".png")
tmp_pfc <- tempfile(fileext = ".png")

render_circle_png(mat_mcx, tmp_mcx)
render_circle_png(mat_pfc, tmp_pfc)

mcx_img <- png::readPNG(tmp_mcx)
pfc_img <- png::readPNG(tmp_pfc)

grDevices::cairo_pdf(out_pdf, width = 11.5, height = 5.8)
draw_facet_figure(mcx_img, pfc_img)
dev.off()

png(out_png, width = 3450, height = 1740, res = 300)
draw_facet_figure(mcx_img, pfc_img)
dev.off()

unlink(c(tmp_mcx, tmp_pfc))

message("[INFO] Saved PDF: ", out_pdf)
message("[INFO] Saved PNG: ", out_png)