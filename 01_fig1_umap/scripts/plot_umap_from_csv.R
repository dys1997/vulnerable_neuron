
# suppressPackageStartupMessages({
#   library(dplyr)
#   library(ggplot2)
#   library(ggrastr)
#   library(ragg)
#   library(mascarade)
#   library(ggrepel)
#   library(cowplot)
#   library(grid)
# })

# options(bitmapType = "cairo")

# # ============================================================
# # 1. Parse arguments
# # ============================================================

# parse_args <- function(args) {
#   if (length(args) %% 2 != 0) {
#     stop("Arguments must be provided as --key value pairs.")
#   }

#   res <- list(
#     input = NULL,
#     out_prefix = NULL,
#     region_col = "Region",
#     disease_col = "disease",
#     celltype_col = "CellType",
#     org_col = "Org_celltype",
#     umap1_col = "UMAP1",
#     umap2_col = "UMAP2",
#     seed = 123,
#     width = 14,
#     height = 14,
#     dpi = 300
#   )

#   i <- 1
#   while (i <= length(args)) {
#     key <- sub("^--", "", args[i])
#     value <- args[i + 1]
#     res[[key]] <- value
#     i <- i + 2
#   }

#   required <- c("input", "out_prefix")
#   missing <- required[vapply(required, function(x) is.null(res[[x]]), logical(1))]

#   if (length(missing) > 0) {
#     stop("Missing required arguments: ", paste(missing, collapse = ", "))
#   }

#   res$seed <- as.integer(res$seed)
#   res$width <- as.numeric(res$width)
#   res$height <- as.numeric(res$height)
#   res$dpi <- as.integer(res$dpi)

#   res
# }

# args <- parse_args(commandArgs(trailingOnly = TRUE))

# # ============================================================
# # 2. Read data
# # ============================================================

# message("[INFO] Reading: ", args$input)

# df <- read.csv(
#   args$input,
#   stringsAsFactors = FALSE,
#   check.names = FALSE
# )

# required_cols <- c(
#   args$umap1_col,
#   args$umap2_col,
#   args$region_col,
#   args$disease_col,
#   args$celltype_col,
#   args$org_col
# )

# missing_cols <- setdiff(required_cols, colnames(df))

# if (length(missing_cols) > 0) {
#   stop("Missing required columns in CSV: ", paste(missing_cols, collapse = ", "))
# }

# df <- df %>%
#   mutate(
#     Region_plot       = .data[[args$region_col]],
#     Disease_plot      = .data[[args$disease_col]],
#     CellType_plot     = .data[[args$celltype_col]],
#     Org_celltype_plot = .data[[args$org_col]],
#     UMAP1_plot        = .data[[args$umap1_col]],
#     UMAP2_plot        = .data[[args$umap2_col]]
#   ) %>%
#   mutate(
#     Region_plot       = as.character(Region_plot),
#     Disease_plot      = as.character(Disease_plot),
#     CellType_plot     = as.character(CellType_plot),
#     Org_celltype_plot = as.character(Org_celltype_plot),

#     Region_plot = dplyr::case_when(
#       tolower(Region_plot) %in% c("motor cortex", "mcx", "m1") ~ "MCX",
#       tolower(Region_plot) %in% c(
#         "pfc",
#         "prefrontal cortex",
#         "dlpfc",
#         "dorsolateral prefrontal cortex"
#       ) ~ "DLPFC",
#       TRUE ~ Region_plot
#     ),

#     CellType_plot = ifelse(CellType_plot == "Others", "T Cell", CellType_plot)
#   ) %>%
#   filter(
#     !is.na(UMAP1_plot),
#     !is.na(UMAP2_plot),
#     !is.na(Region_plot),
#     !is.na(Disease_plot),
#     !is.na(CellType_plot),
#     !is.na(Org_celltype_plot)
#   )

# set.seed(args$seed)
# df_plot <- df %>% slice_sample(prop = 1)

# message("[INFO] Cells: ", nrow(df_plot))
# message("[INFO] Region levels: ", paste(sort(unique(df_plot$Region_plot)), collapse = " | "))
# message("[INFO] Disease levels: ", paste(sort(unique(df_plot$Disease_plot)), collapse = " | "))
# message("[INFO] CellType levels: ", paste(sort(unique(df_plot$CellType_plot)), collapse = " | "))

# # ============================================================
# # 3. User-defined colors
# # ============================================================

# class_colors <- c(
#   "Ex" = "#FB8072",
#   "In" = "#56B4E9"
# )

# region_colors_user <- c(
#   "MCX"   = "#ec4f93",
#   "DLPFC" = "#2ca25f"
# )

# disease_colors_user <- c(
#   "Control" = "#4C78A8",
#   "FTD"     = "#1B9E77",
#   "ALS"     = "#E45756"
# )

# other_class_colors <- c(
#   "Ast"    = "#66C2A5",
#   "Olg"    = "#8DD3C7",
#   "OPC"    = "#BEBADA",
#   "Mic"    = "#8073AC",
#   "End"    = "#1B9E77",
#   "Fib"    = "#A6761D",
#   "SMC"    = "#E7298A",
#   "Peri"   = "#D95F02",
#   "T Cell" = "#B09C85"
# )

# major_base_cols <- c(class_colors, other_class_colors)

# fallback_seed <- c(
#   "#7F7F7F", "#BCBD22", "#17BECF", "#9467BD", "#8C564B",
#   "#E377C2", "#AEC7E8", "#FFBB78", "#98DF8A", "#C5B0D5"
# )

# make_fallback_palette <- function(n) {
#   if (n <= 0) return(character(0))
#   if (n <= length(fallback_seed)) return(fallback_seed[seq_len(n)])
#   grDevices::colorRampPalette(fallback_seed)(n)
# }

# make_named_palette <- function(levels_vec, named_cols) {
#   values <- named_cols[levels_vec]
#   names(values) <- levels_vec

#   missing_levels <- names(values)[is.na(values)]

#   if (length(missing_levels) > 0) {
#     extra_cols <- make_fallback_palette(length(missing_levels))
#     values[missing_levels] <- extra_cols
#     message("[WARN] Missing colors for levels: ", paste(missing_levels, collapse = " | "))
#     message("[WARN] Fallback colors assigned.")
#   }

#   values
# }

# mix_hex <- function(col1, col2, w = 0.5) {
#   rgb1 <- grDevices::col2rgb(col1)
#   rgb2 <- grDevices::col2rgb(col2)
#   rgb_new <- round((1 - w) * rgb1 + w * rgb2)
#   grDevices::rgb(rgb_new[1], rgb_new[2], rgb_new[3], maxColorValue = 255)
# }

# make_subtype_palette <- function(base_col, n) {
#   if (n <= 0) return(character(0))
#   if (n == 1) return(base_col)

#   light_col <- mix_hex(base_col, "#FFFFFF", w = 0.42)
#   dark_col  <- mix_hex(base_col, "#000000", w = 0.18)

#   grDevices::colorRampPalette(c(light_col, base_col, dark_col))(n)
# }

# infer_major_class <- function(celltype, org_celltype) {
#   x <- paste(as.character(celltype), as.character(org_celltype), sep = "__")

#   if (grepl("(^|[._[:space:]-])Ex([._[:space:]-]|$)|Excitatory|Glut", x, ignore.case = TRUE)) {
#     return("Ex")
#   }

#   if (grepl("(^|[._[:space:]-])In([._[:space:]-]|$)|Inhibitory|GABA", x, ignore.case = TRUE)) {
#     return("In")
#   }

#   if (grepl("Ast|Astro", x, ignore.case = TRUE)) return("Ast")
#   if (grepl("OPC", x, ignore.case = TRUE)) return("OPC")
#   if (grepl("Olg|Olig|Oligodendrocyte", x, ignore.case = TRUE)) return("Olg")
#   if (grepl("Mic|Micro", x, ignore.case = TRUE)) return("Mic")
#   if (grepl("End|Endothelial", x, ignore.case = TRUE)) return("End")
#   if (grepl("Fib|Fibro", x, ignore.case = TRUE)) return("Fib")
#   if (grepl("SMC|Smooth", x, ignore.case = TRUE)) return("SMC")
#   if (grepl("Peri|Pericyte", x, ignore.case = TRUE)) return("Peri")
#   if (grepl("T Cell|T_cell|Tcell|T-cell", x, ignore.case = TRUE)) return("T Cell")

#   return(as.character(celltype))
# }

# # ============================================================
# # 4. Factor order and color mapping
# # ============================================================

# region_order <- c("MCX", "DLPFC")

# region_levels_present <- unique(df_plot$Region_plot)
# region_levels_final <- c(
#   region_order[region_order %in% region_levels_present],
#   sort(setdiff(region_levels_present, region_order))
# )

# df_plot$Region_plot <- factor(df_plot$Region_plot, levels = region_levels_final)
# region_cols <- make_named_palette(levels(df_plot$Region_plot), region_colors_user)

# disease_order <- c("Control", "FTD", "ALS")

# disease_levels_present <- unique(df_plot$Disease_plot)
# disease_levels_final <- c(
#   disease_order[disease_order %in% disease_levels_present],
#   sort(setdiff(disease_levels_present, disease_order))
# )

# df_plot$Disease_plot <- factor(df_plot$Disease_plot, levels = disease_levels_final)
# disease_cols <- make_named_palette(levels(df_plot$Disease_plot), disease_colors_user)

# org_map <- df_plot %>%
#   distinct(CellType_plot, Org_celltype_plot) %>%
#   mutate(
#     Major_class = mapply(
#       infer_major_class,
#       CellType_plot,
#       Org_celltype_plot,
#       USE.NAMES = FALSE
#     )
#   )

# major_order <- c(
#   "Ex", "In", "Ast", "Olg", "OPC", "Mic", "End", "Fib", "SMC", "Peri", "T Cell"
# )

# major_levels_final <- c(
#   major_order[major_order %in% unique(org_map$Major_class)],
#   sort(setdiff(unique(org_map$Major_class), major_order))
# )

# org_map <- org_map %>%
#   mutate(
#     Major_class = factor(Major_class, levels = major_levels_final)
#   ) %>%
#   arrange(Major_class, Org_celltype_plot)

# missing_major <- setdiff(as.character(unique(org_map$Major_class)), names(major_base_cols))

# if (length(missing_major) > 0) {
#   extra_cols <- make_fallback_palette(length(missing_major))
#   names(extra_cols) <- missing_major
#   major_base_cols <- c(major_base_cols, extra_cols)
# }

# org_cols_df <- org_map %>%
#   group_by(Major_class) %>%
#   group_modify(~{
#     major <- as.character(.y$Major_class[[1]])
#     base_col <- major_base_cols[major]

#     .x %>%
#       arrange(Org_celltype_plot) %>%
#       mutate(
#         org_col = make_subtype_palette(base_col, nrow(.x))
#       )
#   }) %>%
#   ungroup()

# org_cols <- org_cols_df$org_col
# names(org_cols) <- org_cols_df$Org_celltype_plot

# df_plot$Org_celltype_plot <- factor(
#   df_plot$Org_celltype_plot,
#   levels = org_cols_df$Org_celltype_plot
# )

# df_plot$CellType_plot <- factor(
#   df_plot$CellType_plot,
#   levels = unique(org_map$CellType_plot)
# )

# # ============================================================
# # 5. Themes
# # ============================================================

# base_theme <- theme_classic(base_size = 14, base_family = "Arial") +
#   theme(
#     text            = element_text(family = "Arial"),
#     axis.text       = element_blank(),
#     axis.ticks      = element_blank(),
#     axis.line       = element_blank(),
#     axis.title      = element_blank(),
#     plot.title      = element_blank(),
#     legend.position = "none",
#     plot.margin     = margin(2, 2, 2, 2)
#   )

# legend_theme <- theme_void(base_size = 11, base_family = "Arial") +
#   theme(
#     text = element_text(family = "Arial"),
#     plot.margin = margin(0, 0, 0, 0),
#     legend.position = "none"
#   )

# # ============================================================
# # 6. Manual legend
# # ============================================================

# make_manual_legend <- function(color_map,
#                                title = NULL,
#                                ncol = 1,
#                                point_size = 3.2,
#                                text_size = 3.0,
#                                title_size = NULL,
#                                x_point = 0.035,
#                                x_text = 0.075,
#                                col_gap = 0.30,
#                                reserve_title_space = FALSE) {
#   labs <- names(color_map)
#   cols <- unname(color_map)
#   n <- length(labs)

#   if (n == 0) {
#     return(ggplot() + theme_void())
#   }

#   nrow <- ceiling(n / ncol)
#   has_title_space <- !is.null(title) || isTRUE(reserve_title_space)

#   y_top <- if (has_title_space) 0.86 else 0.72
#   y_bottom <- if (has_title_space) 0.05 else 0.28
#   y_step <- if (nrow > 1) (y_top - y_bottom) / (nrow - 1) else 0

#   legend_df <- data.frame(
#     label = labs,
#     color = cols,
#     idx = seq_len(n),
#     stringsAsFactors = FALSE
#   ) %>%
#     mutate(
#       col_id = ceiling(idx / nrow),
#       row_id = idx - (col_id - 1) * nrow,
#       x_point = x_point + (col_id - 1) * col_gap,
#       x_text = x_text + (col_id - 1) * col_gap,
#       y = if (nrow == 1) 0.50 else y_top - (row_id - 1) * y_step
#     )

#   p <- ggplot(legend_df) +
#     geom_point(
#       aes(x = x_point, y = y),
#       color = legend_df$color,
#       size = point_size,
#       show.legend = FALSE
#     ) +
#     geom_text(
#       aes(x = x_text, y = y, label = label),
#       hjust = 0,
#       vjust = 0.5,
#       size = text_size,
#       family = "Arial",
#       show.legend = FALSE
#     ) +
#     coord_cartesian(
#       xlim = c(0, 1),
#       ylim = c(0, 1),
#       clip = "off"
#     ) +
#     legend_theme

#   if (!is.null(title)) {
#     if (is.null(title_size)) {
#       title_size <- text_size + 1.7
#     }

#     title_df <- data.frame(
#       x = x_point,
#       y = 0.985,
#       label = title
#     )

#     p <- p +
#       geom_text(
#         data = title_df,
#         aes(x = x, y = y, label = label),
#         hjust = 0,
#         vjust = 1,
#         fontface = "bold",
#         size = title_size,
#         family = "Arial",
#         inherit.aes = FALSE,
#         show.legend = FALSE
#       )
#   }

#   p
# }

# # ============================================================
# # 7. Plot functions
# # ============================================================

# plot_umap_core <- function(data,
#                            color_col,
#                            title_text = NULL,
#                            color_map,
#                            point_size = 0.08,
#                            alpha_val = 0.30) {
#   ggplot(
#     data,
#     aes(x = UMAP1_plot, y = UMAP2_plot)
#   ) +
#     ggrastr::geom_point_rast(
#       aes(color = .data[[color_col]]),
#       size = point_size,
#       alpha = alpha_val,
#       raster.dpi = args$dpi,
#       show.legend = FALSE
#     ) +
#     coord_equal(expand = FALSE) +
#     labs(title = NULL) +
#     scale_color_manual(values = color_map, drop = FALSE, guide = "none") +
#     base_theme
# }

# plot_umap_org_core <- function(data,
#                                point_size = 0.10,
#                                alpha_val = 0.80,
#                                expand_val = 0.006,
#                                outline_lwd = 0.40,
#                                outline_lty = 2,
#                                outline_color = "black",
#                                label_size = 5,
#                                title_text = NULL) {
#   df2 <- data %>%
#     transmute(
#       umap_1       = UMAP1_plot,
#       umap_2       = UMAP2_plot,
#       Org_celltype = Org_celltype_plot,
#       CellType     = CellType_plot
#     ) %>%
#     filter(
#       !is.na(umap_1),
#       !is.na(umap_2),
#       !is.na(Org_celltype),
#       !is.na(CellType)
#     )

#   maskTable <- tryCatch(
#     {
#       generateMask(
#         dims     = as.matrix(df2[, c("umap_1", "umap_2")]),
#         clusters = df2$CellType,
#         expand   = expand_val
#       )
#     },
#     error = function(e) {
#       message("[WARN] generateMask failed: ", conditionMessage(e))
#       NULL
#     }
#   )

#   label_df <- df2 %>%
#     group_by(CellType) %>%
#     summarise(
#       label_x = median(umap_1),
#       label_y = median(umap_2),
#       .groups = "drop"
#     )

#   p <- ggplot(df2, aes(x = umap_1, y = umap_2)) +
#     ggrastr::geom_point_rast(
#       aes(color = Org_celltype),
#       size = point_size,
#       alpha = alpha_val,
#       raster.dpi = args$dpi,
#       show.legend = FALSE
#     ) +
#     coord_equal(expand = FALSE) +
#     labs(title = NULL) +
#     scale_color_manual(values = org_cols, drop = FALSE, guide = "none") +
#     base_theme

#   if (!is.null(maskTable) && nrow(maskTable) > 0) {
#     p <- p +
#       geom_path(
#         data = maskTable,
#         aes(x = umap_1, y = umap_2, group = group),
#         inherit.aes = FALSE,
#         linewidth = outline_lwd,
#         linetype = outline_lty,
#         color = outline_color,
#         show.legend = FALSE
#       )
#   }

#   p <- p +
#     geom_text_repel(
#       data = label_df,
#       aes(x = label_x, y = label_y, label = CellType),
#       inherit.aes = FALSE,
#       color = "black",
#       size = label_size,
#       family = "Arial",
#       fontface = "bold",
#       box.padding = 0.35,
#       point.padding = 0.20,
#       segment.color = "grey40",
#       segment.size = 0.3,
#       max.overlaps = Inf,
#       seed = 123,
#       show.legend = FALSE
#     )

#   p
# }

# # ============================================================
# # 8. Build plots
# # ============================================================

# p_region_core <- plot_umap_core(
#   data = df_plot,
#   color_col = "Region_plot",
#   title_text = NULL,
#   color_map = region_cols,
#   point_size = 0.08,
#   alpha_val = 0.30
# )

# p_disease_core <- plot_umap_core(
#   data = df_plot,
#   color_col = "Disease_plot",
#   title_text = NULL,
#   color_map = disease_cols,
#   point_size = 0.05,
#   alpha_val = 0.22
# )

# p_anno_core <- plot_umap_org_core(
#   data = df_plot,
#   point_size = 0.10,
#   alpha_val = 0.80,
#   expand_val = 0.006,
#   outline_lwd = 0.40,
#   outline_lty = 2,
#   outline_color = "black",
#   label_size = 6,
#   title_text = NULL
# )

# legend_region <- make_manual_legend(
#   color_map = region_cols,
#   title = NULL,
#   ncol = length(region_cols),
#   point_size = 6.0,
#   text_size = 5.6,
#   x_point = 0.22,
#   x_text = 0.30,
#   col_gap = 0.36
# )

# legend_disease <- make_manual_legend(
#   color_map = disease_cols,
#   title = NULL,
#   ncol = length(disease_cols),
#   point_size = 6.0,
#   text_size = 5.6,
#   x_point = 0.10,
#   x_text = 0.18,
#   col_gap = 0.28
# )

# org_n <- length(org_cols)
# org_break <- ceiling(org_n / 2)

# org_left <- org_cols[seq_len(org_break)]

# if (org_break < org_n) {
#   org_right <- org_cols[(org_break + 1):org_n]
# } else {
#   org_right <- org_cols[0]
# }

# legend_org_left <- make_manual_legend(
#   color_map = org_left,
#   title = "celltype",
#   ncol = 1,
#   point_size = 5.4,
#   text_size = 5.0,
#   title_size = 6.7,
#   x_point = 0.035,
#   x_text = 0.075,
#   reserve_title_space = TRUE
# )

# legend_org_right <- make_manual_legend(
#   color_map = org_right,
#   title = NULL,
#   ncol = 1,
#   point_size = 5.4,
#   text_size = 5.0,
#   x_point = 0.035,
#   x_text = 0.075,
#   reserve_title_space = TRUE
# )

# legend_org <- cowplot::plot_grid(
#   legend_org_left,
#   legend_org_right,
#   ncol = 2,
#   rel_widths = c(1.0, 1.0),
#   align = "h"
# )

# p_region <- cowplot::plot_grid(
#   p_region_core,
#   legend_region,
#   ncol = 1,
#   rel_heights = c(1, 0.20),
#   align = "v"
# )

# p_disease <- cowplot::plot_grid(
#   p_disease_core,
#   legend_disease,
#   ncol = 1,
#   rel_heights = c(1, 0.20),
#   align = "v"
# )

# p_anno <- cowplot::plot_grid(
#   p_anno_core,
#   legend_org,
#   ncol = 2,
#   rel_widths = c(1.42, 1.05),
#   align = "h"
# )

# bottom_row <- cowplot::plot_grid(
#   p_region,
#   p_disease,
#   ncol = 2,
#   rel_widths = c(1, 1),
#   align = "h"
# )

# p_all <- cowplot::plot_grid(
#   p_anno,
#   bottom_row,
#   ncol = 1,
#   rel_heights = c(1.35, 1),
#   align = "v"
# )

# # ============================================================
# # 9. Save outputs
# # ============================================================

# png_region  <- paste0(args$out_prefix, "_region.png")
# pdf_region  <- paste0(args$out_prefix, "_region.pdf")

# png_disease <- paste0(args$out_prefix, "_disease.png")
# pdf_disease <- paste0(args$out_prefix, "_disease.pdf")

# png_org     <- paste0(args$out_prefix, "_orgcelltype_outline.png")
# pdf_org     <- paste0(args$out_prefix, "_orgcelltype_outline.pdf")

# png_layout  <- paste0(args$out_prefix, "_layout.png")
# pdf_layout  <- paste0(args$out_prefix, "_layout.pdf")

# save_png <- function(filename, plot, width, height, dpi) {
#   ggplot2::ggsave(
#     filename = filename,
#     plot = plot,
#     width = width,
#     height = height,
#     dpi = dpi,
#     bg = "white",
#     device = ragg::agg_png
#   )
# }

# save_pdf <- function(filename, plot, width, height) {
#   ggplot2::ggsave(
#     filename = filename,
#     plot = plot,
#     width = width,
#     height = height,
#     bg = "white",
#     device = grDevices::cairo_pdf
#   )
# }

# save_png(png_region,  p_region,  width = 8, height = 6.5, dpi = args$dpi)
# save_pdf(pdf_region,  p_region,  width = 8, height = 6.5)

# save_png(png_disease, p_disease, width = 8, height = 6.5, dpi = args$dpi)
# save_pdf(pdf_disease, p_disease, width = 8, height = 6.5)

# save_png(png_org, p_anno, width = 16, height = 9, dpi = args$dpi)
# save_pdf(pdf_org, p_anno, width = 16, height = 9)

# save_png(png_layout, p_all, width = args$width, height = args$height, dpi = args$dpi)
# save_pdf(pdf_layout, p_all, width = args$width, height = args$height)

# message("[OK] Saved: ", png_region)
# message("[OK] Saved: ", pdf_region)
# message("[OK] Saved: ", png_disease)
# message("[OK] Saved: ", pdf_disease)
# message("[OK] Saved: ", png_org)
# message("[OK] Saved: ", pdf_org)
# message("[OK] Saved: ", png_layout)
# message("[OK] Saved: ", pdf_layout)

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(ggrastr)
  library(ragg)
  library(mascarade)
  library(ggrepel)
  library(cowplot)
  library(grid)
})

options(bitmapType = "cairo")

# ============================================================
# 1. Parse arguments
# ============================================================

parse_args <- function(args) {
  if (length(args) %% 2 != 0) {
    stop("Arguments must be provided as --key value pairs.")
  }

  res <- list(
    input = NULL,
    out_prefix = NULL,
    region_col = "Region",
    disease_col = "disease",
    celltype_col = "CellType",
    org_col = "Org_celltype",
    umap1_col = "UMAP1",
    umap2_col = "UMAP2",
    seed = 123,
    width = 14,
    height = 14,
    dpi = 300
  )

  i <- 1
  while (i <= length(args)) {
    key <- sub("^--", "", args[i])
    value <- args[i + 1]
    res[[key]] <- value
    i <- i + 2
  }

  required <- c("input", "out_prefix")
  missing <- required[vapply(required, function(x) is.null(res[[x]]), logical(1))]

  if (length(missing) > 0) {
    stop("Missing required arguments: ", paste(missing, collapse = ", "))
  }

  res$seed <- as.integer(res$seed)
  res$width <- as.numeric(res$width)
  res$height <- as.numeric(res$height)
  res$dpi <- as.integer(res$dpi)

  res
}

args <- parse_args(commandArgs(trailingOnly = TRUE))
raster_dpi <- max(args$dpi, 600)

# ============================================================
# 2. Read data
# ============================================================

message("[INFO] Reading: ", args$input)

df <- read.csv(
  args$input,
  stringsAsFactors = FALSE,
  check.names = FALSE
)

required_cols <- c(
  args$umap1_col,
  args$umap2_col,
  args$region_col,
  args$disease_col,
  args$celltype_col,
  args$org_col
)

missing_cols <- setdiff(required_cols, colnames(df))

if (length(missing_cols) > 0) {
  stop("Missing required columns in CSV: ", paste(missing_cols, collapse = ", "))
}

df <- df %>%
  mutate(
    Region_plot       = .data[[args$region_col]],
    Disease_plot      = .data[[args$disease_col]],
    CellType_plot     = .data[[args$celltype_col]],
    Org_celltype_plot = .data[[args$org_col]],
    UMAP1_plot        = .data[[args$umap1_col]],
    UMAP2_plot        = .data[[args$umap2_col]]
  ) %>%
  mutate(
    Region_plot       = as.character(Region_plot),
    Disease_plot      = as.character(Disease_plot),
    CellType_plot     = as.character(CellType_plot),
    Org_celltype_plot = as.character(Org_celltype_plot),

    Region_plot = dplyr::case_when(
      tolower(Region_plot) %in% c("motor cortex", "mcx", "m1") ~ "MCX",
      tolower(Region_plot) %in% c(
        "pfc",
        "prefrontal cortex",
        "dlpfc",
        "dorsolateral prefrontal cortex"
      ) ~ "DLPFC",
      TRUE ~ Region_plot
    ),

    CellType_plot = ifelse(CellType_plot == "Others", "T Cell", CellType_plot)
  ) %>%
  filter(
    !is.na(UMAP1_plot),
    !is.na(UMAP2_plot),
    !is.na(Region_plot),
    !is.na(Disease_plot),
    !is.na(CellType_plot),
    !is.na(Org_celltype_plot)
  )

set.seed(args$seed)
df_plot <- df %>% slice_sample(prop = 1)

message("[INFO] Cells: ", nrow(df_plot))
message("[INFO] Region levels: ", paste(sort(unique(df_plot$Region_plot)), collapse = " | "))
message("[INFO] Disease levels: ", paste(sort(unique(df_plot$Disease_plot)), collapse = " | "))
message("[INFO] CellType levels: ", paste(sort(unique(df_plot$CellType_plot)), collapse = " | "))

# ============================================================
# 3. User-defined colors
# ============================================================

class_colors <- c(
  "Ex" = "#FB8072",
  "In" = "#56B4E9"
)

region_colors_user <- c(
  "MCX"   = "#ec4f93",
  "DLPFC" = "#2ca25f"
)

disease_colors_user <- c(
  "Control" = "#4C78A8",
  "FTD"     = "#1B9E77",
  "ALS"     = "#E45756"
)

other_class_colors <- c(
  "Ast"    = "#66C2A5",
  "Olg"    = "#8DD3C7",
  "OPC"    = "#BEBADA",
  "Mic"    = "#8073AC",
  "End"    = "#1B9E77",
  "Fib"    = "#A6761D",
  "SMC"    = "#E7298A",
  "Peri"   = "#D95F02",
  "T Cell" = "#B09C85"
)

major_base_cols <- c(class_colors, other_class_colors)

fallback_seed <- c(
  "#7F7F7F", "#BCBD22", "#17BECF", "#9467BD", "#8C564B",
  "#E377C2", "#AEC7E8", "#FFBB78", "#98DF8A", "#C5B0D5"
)

make_fallback_palette <- function(n) {
  if (n <= 0) return(character(0))
  if (n <= length(fallback_seed)) return(fallback_seed[seq_len(n)])
  grDevices::colorRampPalette(fallback_seed)(n)
}

make_named_palette <- function(levels_vec, named_cols) {
  values <- named_cols[levels_vec]
  names(values) <- levels_vec

  missing_levels <- names(values)[is.na(values)]

  if (length(missing_levels) > 0) {
    extra_cols <- make_fallback_palette(length(missing_levels))
    values[missing_levels] <- extra_cols
    message("[WARN] Missing colors for levels: ", paste(missing_levels, collapse = " | "))
    message("[WARN] Fallback colors assigned.")
  }

  values
}

mix_hex <- function(col1, col2, w = 0.5) {
  rgb1 <- grDevices::col2rgb(col1)
  rgb2 <- grDevices::col2rgb(col2)
  rgb_new <- round((1 - w) * rgb1 + w * rgb2)
  grDevices::rgb(rgb_new[1], rgb_new[2], rgb_new[3], maxColorValue = 255)
}

make_subtype_palette <- function(base_col, n) {
  if (n <= 0) return(character(0))
  if (n == 1) return(base_col)

  light_col <- mix_hex(base_col, "#FFFFFF", w = 0.42)
  dark_col  <- mix_hex(base_col, "#000000", w = 0.18)

  grDevices::colorRampPalette(c(light_col, base_col, dark_col))(n)
}

infer_major_class <- function(celltype, org_celltype) {
  x <- paste(as.character(celltype), as.character(org_celltype), sep = "__")

  if (grepl("(^|[._[:space:]-])Ex([._[:space:]-]|$)|Excitatory|Glut", x, ignore.case = TRUE)) {
    return("Ex")
  }

  if (grepl("(^|[._[:space:]-])In([._[:space:]-]|$)|Inhibitory|GABA", x, ignore.case = TRUE)) {
    return("In")
  }

  if (grepl("Ast|Astro", x, ignore.case = TRUE)) return("Ast")
  if (grepl("OPC", x, ignore.case = TRUE)) return("OPC")
  if (grepl("Olg|Olig|Oligodendrocyte", x, ignore.case = TRUE)) return("Olg")
  if (grepl("Mic|Micro", x, ignore.case = TRUE)) return("Mic")
  if (grepl("End|Endothelial", x, ignore.case = TRUE)) return("End")
  if (grepl("Fib|Fibro", x, ignore.case = TRUE)) return("Fib")
  if (grepl("SMC|Smooth", x, ignore.case = TRUE)) return("SMC")
  if (grepl("Peri|Pericyte", x, ignore.case = TRUE)) return("Peri")
  if (grepl("T Cell|T_cell|Tcell|T-cell", x, ignore.case = TRUE)) return("T Cell")

  return(as.character(celltype))
}

# ============================================================
# 4. Factor order and color mapping
# ============================================================

region_order <- c("MCX", "DLPFC")

region_levels_present <- unique(df_plot$Region_plot)
region_levels_final <- c(
  region_order[region_order %in% region_levels_present],
  sort(setdiff(region_levels_present, region_order))
)

df_plot$Region_plot <- factor(df_plot$Region_plot, levels = region_levels_final)
region_cols <- make_named_palette(levels(df_plot$Region_plot), region_colors_user)

disease_order <- c("Control", "FTD", "ALS")

disease_levels_present <- unique(df_plot$Disease_plot)
disease_levels_final <- c(
  disease_order[disease_order %in% disease_levels_present],
  sort(setdiff(disease_levels_present, disease_order))
)

df_plot$Disease_plot <- factor(df_plot$Disease_plot, levels = disease_levels_final)
disease_cols <- make_named_palette(levels(df_plot$Disease_plot), disease_colors_user)

org_map <- df_plot %>%
  distinct(CellType_plot, Org_celltype_plot) %>%
  mutate(
    Major_class = mapply(
      infer_major_class,
      CellType_plot,
      Org_celltype_plot,
      USE.NAMES = FALSE
    )
  )

major_order <- c(
  "Ex", "In", "Ast", "Olg", "OPC", "Mic", "End", "Fib", "SMC", "Peri", "T Cell"
)

major_levels_final <- c(
  major_order[major_order %in% unique(org_map$Major_class)],
  sort(setdiff(unique(org_map$Major_class), major_order))
)

org_map <- org_map %>%
  mutate(
    Major_class = factor(Major_class, levels = major_levels_final)
  ) %>%
  arrange(Major_class, Org_celltype_plot)

missing_major <- setdiff(as.character(unique(org_map$Major_class)), names(major_base_cols))

if (length(missing_major) > 0) {
  extra_cols <- make_fallback_palette(length(missing_major))
  names(extra_cols) <- missing_major
  major_base_cols <- c(major_base_cols, extra_cols)
}

org_cols_df <- org_map %>%
  group_by(Major_class) %>%
  group_modify(~{
    major <- as.character(.y$Major_class[[1]])
    base_col <- major_base_cols[major]

    .x %>%
      arrange(Org_celltype_plot) %>%
      mutate(
        org_col = make_subtype_palette(base_col, nrow(.x))
      )
  }) %>%
  ungroup()

org_cols <- org_cols_df$org_col
names(org_cols) <- org_cols_df$Org_celltype_plot

df_plot$Org_celltype_plot <- factor(
  df_plot$Org_celltype_plot,
  levels = org_cols_df$Org_celltype_plot
)

df_plot$CellType_plot <- factor(
  df_plot$CellType_plot,
  levels = unique(org_map$CellType_plot)
)

# ============================================================
# 5. Themes
# ============================================================

base_theme <- theme_classic(base_size = 14, base_family = "Arial") +
  theme(
    text            = element_text(family = "Arial"),
    axis.text       = element_blank(),
    axis.ticks      = element_blank(),
    axis.line       = element_blank(),
    axis.title      = element_blank(),
    plot.title      = element_blank(),
    legend.position = "none",
    plot.margin     = margin(2, 2, 2, 2)
  )

legend_theme <- theme_void(base_size = 11, base_family = "Arial") +
  theme(
    text = element_text(family = "Arial"),
    plot.margin = margin(0, 0, 0, 0),
    legend.position = "none"
  )

# ============================================================
# 6. Manual legends
# ============================================================

make_horizontal_legend <- function(color_map,
                                   point_size = 6.2,
                                   text_size = 6.0,
                                   x_start = 0.20,
                                   x_gap = 0.34,
                                   x_text_offset = 0.085,
                                   y = 0.50) {
  labs <- names(color_map)
  cols <- unname(color_map)
  n <- length(labs)

  if (n == 0) {
    return(ggplot() + theme_void())
  }

  legend_df <- data.frame(
    label = labs,
    color = cols,
    idx = seq_len(n),
    stringsAsFactors = FALSE
  ) %>%
    mutate(
      x_point = x_start + (idx - 1) * x_gap,
      x_text = x_point + x_text_offset,
      y = y
    )

  ggplot(legend_df) +
    geom_point(
      aes(x = x_point, y = y),
      color = legend_df$color,
      size = point_size,
      show.legend = FALSE
    ) +
    geom_text(
      aes(x = x_text, y = y, label = label),
      hjust = 0,
      vjust = 0.5,
      size = text_size,
      family = "Arial",
      show.legend = FALSE
    ) +
    coord_cartesian(
      xlim = c(0, 1),
      ylim = c(0, 1),
      clip = "off"
    ) +
    legend_theme
}

make_vertical_legend <- function(color_map,
                                 title = NULL,
                                 point_size = 5.4,
                                 text_size = 5.0,
                                 title_size = 6.7,
                                 x_point = 0.035,
                                 x_text = 0.075,
                                 reserve_title_space = FALSE) {
  labs <- names(color_map)
  cols <- unname(color_map)
  n <- length(labs)

  if (n == 0) {
    return(ggplot() + theme_void())
  }

  has_title_space <- !is.null(title) || isTRUE(reserve_title_space)
  y_top <- if (has_title_space) 0.86 else 0.94
  y_bottom <- 0.05
  y_step <- if (n > 1) (y_top - y_bottom) / (n - 1) else 0

  legend_df <- data.frame(
    label = labs,
    color = cols,
    row_id = seq_len(n),
    stringsAsFactors = FALSE
  ) %>%
    mutate(
      x_point = x_point,
      x_text = x_text,
      y = if (n == 1) 0.50 else y_top - (row_id - 1) * y_step
    )

  p <- ggplot(legend_df) +
    geom_point(
      aes(x = x_point, y = y),
      color = legend_df$color,
      size = point_size,
      show.legend = FALSE
    ) +
    geom_text(
      aes(x = x_text, y = y, label = label),
      hjust = 0,
      vjust = 0.5,
      size = text_size,
      family = "Arial",
      show.legend = FALSE
    ) +
    coord_cartesian(
      xlim = c(0, 1),
      ylim = c(0, 1),
      clip = "off"
    ) +
    legend_theme

  if (!is.null(title)) {
    title_df <- data.frame(
      x = x_point,
      y = 0.985,
      label = title
    )

    p <- p +
      geom_text(
        data = title_df,
        aes(x = x, y = y, label = label),
        hjust = 0,
        vjust = 1,
        fontface = "bold",
        size = title_size,
        family = "Arial",
        inherit.aes = FALSE,
        show.legend = FALSE
      )
  }

  p
}

# ============================================================
# 7. Plot functions
# ============================================================

plot_umap_core <- function(data,
                           color_col,
                           color_map,
                           point_size = 0.035,
                           alpha_val = 0.55) {
  ggplot(
    data,
    aes(x = UMAP1_plot, y = UMAP2_plot)
  ) +
    ggrastr::geom_point_rast(
      aes(color = .data[[color_col]]),
      size = point_size,
      alpha = alpha_val,
      raster.dpi = raster_dpi,
      show.legend = FALSE
    ) +
    coord_equal(expand = FALSE) +
    labs(title = NULL) +
    scale_color_manual(values = color_map, drop = FALSE, guide = "none") +
    base_theme
}

plot_umap_org_core <- function(data,
                               point_size = 0.10,
                               alpha_val = 0.80,
                               expand_val = 0.006,
                               outline_lwd = 0.40,
                               outline_lty = 2,
                               outline_color = "black",
                               label_size = 6) {
  df2 <- data %>%
    transmute(
      umap_1       = UMAP1_plot,
      umap_2       = UMAP2_plot,
      Org_celltype = Org_celltype_plot,
      CellType     = CellType_plot
    ) %>%
    filter(
      !is.na(umap_1),
      !is.na(umap_2),
      !is.na(Org_celltype),
      !is.na(CellType)
    )

  maskTable <- tryCatch(
    {
      generateMask(
        dims     = as.matrix(df2[, c("umap_1", "umap_2")]),
        clusters = df2$CellType,
        expand   = expand_val
      )
    },
    error = function(e) {
      message("[WARN] generateMask failed: ", conditionMessage(e))
      NULL
    }
  )

  label_df <- df2 %>%
    group_by(CellType) %>%
    summarise(
      label_x = median(umap_1),
      label_y = median(umap_2),
      .groups = "drop"
    )

  p <- ggplot(df2, aes(x = umap_1, y = umap_2)) +
    ggrastr::geom_point_rast(
      aes(color = Org_celltype),
      size = point_size,
      alpha = alpha_val,
      raster.dpi = raster_dpi,
      show.legend = FALSE
    ) +
    coord_equal(expand = FALSE) +
    labs(title = NULL) +
    scale_color_manual(values = org_cols, drop = FALSE, guide = "none") +
    base_theme

  if (!is.null(maskTable) && nrow(maskTable) > 0) {
    p <- p +
      geom_path(
        data = maskTable,
        aes(x = umap_1, y = umap_2, group = group),
        inherit.aes = FALSE,
        linewidth = outline_lwd,
        linetype = outline_lty,
        color = outline_color,
        show.legend = FALSE
      )
  }

  p <- p +
    geom_text_repel(
      data = label_df,
      aes(x = label_x, y = label_y, label = CellType),
      inherit.aes = FALSE,
      color = "black",
      size = label_size,
      family = "Arial",
      fontface = "bold",
      box.padding = 0.35,
      point.padding = 0.20,
      segment.color = "grey40",
      segment.size = 0.3,
      max.overlaps = Inf,
      seed = 123,
      show.legend = FALSE
    )

  p
}

# ============================================================
# 8. Build plots
# ============================================================

p_region_core <- plot_umap_core(
  data = df_plot,
  color_col = "Region_plot",
  color_map = region_cols,
  point_size = 0.032,
  alpha_val = 0.60
)

p_disease_core <- plot_umap_core(
  data = df_plot,
  color_col = "Disease_plot",
  color_map = disease_cols,
  point_size = 0.030,
  alpha_val = 0.50
)

p_anno_core <- plot_umap_org_core(
  data = df_plot,
  point_size = 0.10,
  alpha_val = 0.80,
  expand_val = 0.006,
  outline_lwd = 0.40,
  outline_lty = 2,
  outline_color = "black",
  label_size = 6
)

legend_region <- make_horizontal_legend(
  color_map = region_cols,
  point_size = 6.2,
  text_size = 6.0,
  x_start = 0.24,
  x_gap = 0.34,
  x_text_offset = 0.090,
  y = 0.52
)

legend_disease <- make_horizontal_legend(
  color_map = disease_cols,
  point_size = 6.2,
  text_size = 6.0,
  x_start = 0.10,
  x_gap = 0.28,
  x_text_offset = 0.085,
  y = 0.52
)

org_n <- length(org_cols)
org_break <- ceiling(org_n / 2)

org_left <- org_cols[seq_len(org_break)]

if (org_break < org_n) {
  org_right <- org_cols[(org_break + 1):org_n]
} else {
  org_right <- org_cols[0]
}

legend_org_left <- make_vertical_legend(
  color_map = org_left,
  title = "celltype",
  point_size = 5.4,
  text_size = 5.0,
  title_size = 6.7,
  x_point = 0.035,
  x_text = 0.075,
  reserve_title_space = TRUE
)

legend_org_right <- make_vertical_legend(
  color_map = org_right,
  title = NULL,
  point_size = 5.4,
  text_size = 5.0,
  title_size = 6.7,
  x_point = 0.035,
  x_text = 0.075,
  reserve_title_space = TRUE
)

legend_org <- cowplot::plot_grid(
  legend_org_left,
  legend_org_right,
  ncol = 2,
  rel_widths = c(1.0, 1.0),
  align = "h"
)

p_region <- cowplot::plot_grid(
  p_region_core,
  legend_region,
  ncol = 1,
  rel_heights = c(1, 0.18),
  align = "v"
)

p_disease <- cowplot::plot_grid(
  p_disease_core,
  legend_disease,
  ncol = 1,
  rel_heights = c(1, 0.18),
  align = "v"
)

p_anno <- cowplot::plot_grid(
  p_anno_core,
  legend_org,
  ncol = 2,
  rel_widths = c(1.42, 1.05),
  align = "h"
)

bottom_row <- cowplot::plot_grid(
  p_region,
  p_disease,
  ncol = 2,
  rel_widths = c(1, 1),
  align = "h"
)

p_all <- cowplot::plot_grid(
  p_anno,
  bottom_row,
  ncol = 1,
  rel_heights = c(1.35, 1),
  align = "v"
)

# ============================================================
# 9. Save outputs
# ============================================================

png_region  <- paste0(args$out_prefix, "_region.png")
pdf_region  <- paste0(args$out_prefix, "_region.pdf")

png_disease <- paste0(args$out_prefix, "_disease.png")
pdf_disease <- paste0(args$out_prefix, "_disease.pdf")

png_org     <- paste0(args$out_prefix, "_orgcelltype_outline.png")
pdf_org     <- paste0(args$out_prefix, "_orgcelltype_outline.pdf")

png_layout  <- paste0(args$out_prefix, "_layout.png")
pdf_layout  <- paste0(args$out_prefix, "_layout.pdf")

save_png <- function(filename, plot, width, height, dpi) {
  ggplot2::ggsave(
    filename = filename,
    plot = plot,
    width = width,
    height = height,
    dpi = dpi,
    bg = "white",
    device = ragg::agg_png
  )
}

save_pdf <- function(filename, plot, width, height) {
  ggplot2::ggsave(
    filename = filename,
    plot = plot,
    width = width,
    height = height,
    bg = "white",
    device = grDevices::cairo_pdf
  )
}

save_png(png_region,  p_region,  width = 8, height = 6.5, dpi = args$dpi)
save_pdf(pdf_region,  p_region,  width = 8, height = 6.5)

save_png(png_disease, p_disease, width = 8, height = 6.5, dpi = args$dpi)
save_pdf(pdf_disease, p_disease, width = 8, height = 6.5)

save_png(png_org, p_anno, width = 16, height = 9, dpi = args$dpi)
save_pdf(pdf_org, p_anno, width = 16, height = 9)

save_png(png_layout, p_all, width = args$width, height = args$height, dpi = args$dpi)
save_pdf(pdf_layout, p_all, width = args$width, height = args$height)

message("[OK] Saved: ", png_region)
message("[OK] Saved: ", pdf_region)
message("[OK] Saved: ", png_disease)
message("[OK] Saved: ", pdf_disease)
message("[OK] Saved: ", png_org)
message("[OK] Saved: ", pdf_org)
message("[OK] Saved: ", png_layout)
message("[OK] Saved: ", pdf_layout)