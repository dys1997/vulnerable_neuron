
# suppressPackageStartupMessages({
#   library(dplyr)
#   library(ggplot2)
#   library(ggrepel)
#   library(mascarade)
#   library(scales)
#   library(grid)
# })

# parse_args <- function(args) {
#   if (length(args) %% 2 != 0) {
#     stop("Arguments must be provided as --key value pairs.")
#   }

#   res <- list(
#     mcx_in = NULL,
#     pfc_in = NULL,
#     mcx_ex = NULL,
#     pfc_ex = NULL,
#     out_prefix = NULL,

#     umap1_col = "UMAP1",
#     umap2_col = "UMAP2",
#     group_col = "plot_group",
#     score_col = "scdrs_ppr_z_display",

#     width = 13,
#     height = 10,
#     dpi = 300,

#     point_size = 0.16,
#     point_alpha = 0.85,

#     expand = 0.006,
#     outline_lwd = 0.45,
#     outline_lty = 2,

#     label_size = 3.6,
#     label_mode = "full",

#     zlim = 2,

#     panel_pad = 0.12
#   )

#   i <- 1
#   while (i <= length(args)) {
#     key <- args[[i]]

#     if (!startsWith(key, "--")) stop("Unexpected argument: ", key)
#     key2 <- substring(key, 3)

#     if (!(key2 %in% names(res))) stop("Unknown argument: ", key)

#     if (i == length(args)) stop("Missing value for argument: ", key)

#     res[[key2]] <- args[[i + 1]]
#     i <- i + 2
#   }

#   required <- c("mcx_in", "pfc_in", "mcx_ex", "pfc_ex", "out_prefix")
#   missing <- required[vapply(required, function(x) is.null(res[[x]]), logical(1))]

#   if (length(missing) > 0) {
#     stop("Missing required arguments: ", paste(missing, collapse = ", "))
#   }

#   res$width <- as.numeric(res$width)
#   res$height <- as.numeric(res$height)
#   res$dpi <- as.integer(res$dpi)

#   res$point_size <- as.numeric(res$point_size)
#   res$point_alpha <- as.numeric(res$point_alpha)

#   res$expand <- as.numeric(res$expand)
#   res$outline_lwd <- as.numeric(res$outline_lwd)
#   res$outline_lty <- as.integer(res$outline_lty)

#   res$label_size <- as.numeric(res$label_size)
#   res$zlim <- as.numeric(res$zlim)
#   res$panel_pad <- as.numeric(res$panel_pad)

#   return(res)
# }

# read_one_meta <- function(input, region, mode, args) {
#   message("[INFO] Reading: ", input)

#   df <- read.csv(
#     input,
#     stringsAsFactors = FALSE,
#     check.names = FALSE
#   )

#   required_cols <- c(
#     args$umap1_col,
#     args$umap2_col,
#     args$group_col,
#     args$score_col
#   )

#   missing_cols <- setdiff(required_cols, colnames(df))

#   if (length(missing_cols) > 0) {
#     stop(
#       "Missing required columns in ",
#       input,
#       ": ",
#       paste(missing_cols, collapse = ", "),
#       "\nAvailable columns: ",
#       paste(colnames(df), collapse = " | ")
#     )
#   }

#   df2 <- df %>%
#     transmute(
#       UMAP1_raw = as.numeric(.data[[args$umap1_col]]),
#       UMAP2_raw = as.numeric(.data[[args$umap2_col]]),
#       plot_group = as.character(.data[[args$group_col]]),
#       score = as.numeric(.data[[args$score_col]]),
#       Region = region,
#       Mode = mode,
#       Panel = paste(region, mode)
#     ) %>%
#     filter(
#       !is.na(UMAP1_raw),
#       !is.na(UMAP2_raw),
#       !is.na(plot_group),
#       !is.na(score)
#     )

#   if (nrow(df2) == 0) {
#     stop("No valid rows after filtering: ", input)
#   }

#   return(df2)
# }

# normalize_panel_umap <- function(df, panel_pad = 0.12) {
#   panel_pad <- max(0.02, min(panel_pad, 0.30))
#   inner_scale <- 1 - 2 * panel_pad

#   df %>%
#     group_by(Panel) %>%
#     mutate(
#       x_min = min(UMAP1_raw),
#       x_max = max(UMAP1_raw),
#       y_min = min(UMAP2_raw),
#       y_max = max(UMAP2_raw),

#       x_mid = (x_min + x_max) / 2,
#       y_mid = (y_min + y_max) / 2,

#       x_range = x_max - x_min,
#       y_range = y_max - y_min,

#       panel_scale = max(x_range, y_range),

#       UMAP1 = ((UMAP1_raw - x_mid) / panel_scale) * inner_scale + 0.5,
#       UMAP2 = ((UMAP2_raw - y_mid) / panel_scale) * inner_scale + 0.5
#     ) %>%
#     ungroup() %>%
#     select(
#       -x_min, -x_max, -y_min, -y_max,
#       -x_mid, -y_mid, -x_range, -y_range, -panel_scale
#     )
# }

# get_targets <- function(mode) {
#   if (mode == "In") {
#     return(c(
#       "In.PV.PVALB_PTHLH",
#       "In.PV.PVALB_CEMIP",
#       "In.5HT3aR.CDH4"
#     ))
#   }

#   if (mode == "Ex") {
#     return(c(
#       "Ex.L5.VAT1L",
#       "Ex.L5.PCP4_NXPH2"
#     ))
#   }

#   stop("mode must be In or Ex")
# }

# make_label <- function(x, label_mode) {
#   if (label_mode == "full") {
#     return(x)
#   }

#   dplyr::recode(
#     x,
#     "In.PV.PVALB_PTHLH" = "PTHLH",
#     "In.PV.PVALB_CEMIP" = "CEMIP",
#     "In.5HT3aR.CDH4" = "CDH4",
#     "Ex.L5.VAT1L" = "VAT1L",
#     "Ex.L5.PCP4_NXPH2" = "PCP4_NXPH2",
#     .default = x
#   )
# }

# make_mask_for_one_panel <- function(df_one, expand_val) {
#   df_mask <- df_one %>%
#     transmute(
#       umap_1 = UMAP1,
#       umap_2 = UMAP2,
#       plot_group = plot_group
#     )

#   maskTable <- generateMask(
#     dims = as.matrix(df_mask[, c("umap_1", "umap_2")]),
#     clusters = df_mask$plot_group,
#     expand = expand_val
#   )

#   if (!all(c("umap_1", "umap_2", "group") %in% colnames(maskTable))) {
#     stop(
#       "maskTable does not contain expected columns: umap_1, umap_2, group\n",
#       "Actual columns: ",
#       paste(colnames(maskTable), collapse = " | ")
#     )
#   }

#   maskTable$Region <- unique(df_one$Region)
#   maskTable$Mode <- unique(df_one$Mode)
#   maskTable$Panel <- unique(df_one$Panel)

#   return(maskTable)
# }

# set_rect_fill_recursive <- function(gr, fill, border = "black", lwd = 1.0) {
#   if (inherits(gr, "rect")) {
#     gr$gp$fill <- fill
#     gr$gp$col <- border
#     gr$gp$lwd <- lwd
#     return(gr)
#   }

#   if (!is.null(gr$children)) {
#     gr$children <- lapply(
#       gr$children,
#       set_rect_fill_recursive,
#       fill = fill,
#       border = border,
#       lwd = lwd
#     )
#   }

#   if (!is.null(gr$grobs)) {
#     gr$grobs <- lapply(
#       gr$grobs,
#       set_rect_fill_recursive,
#       fill = fill,
#       border = border,
#       lwd = lwd
#     )
#   }

#   return(gr)
# }

# color_facet_strips <- function(gt) {
#   col_strip_fills <- c(
#     "MCX" = "#E64B9A",
#     "DLPFC" = "#2F9E57"
#   )

#   row_strip_fills <- c(
#     "In" = "#56B4E9",
#     "Ex" = "#FB8072"
#   )

#   strip_t_idx <- which(grepl("^strip-t", gt$layout$name))
#   if (length(strip_t_idx) > 0) {
#     strip_t_idx <- strip_t_idx[order(gt$layout$l[strip_t_idx])]
#     fills <- unname(col_strip_fills[c("MCX", "DLPFC")])

#     for (i in seq_along(strip_t_idx)) {
#       fill_now <- fills[((i - 1) %% length(fills)) + 1]
#       gt$grobs[[strip_t_idx[i]]] <- set_rect_fill_recursive(
#         gt$grobs[[strip_t_idx[i]]],
#         fill = fill_now,
#         border = "black",
#         lwd = 1.0
#       )
#     }
#   }

#   strip_l_idx <- which(grepl("^strip-l", gt$layout$name))
#   if (length(strip_l_idx) > 0) {
#     strip_l_idx <- strip_l_idx[order(gt$layout$t[strip_l_idx])]
#     fills <- unname(row_strip_fills[c("In", "Ex")])

#     for (i in seq_along(strip_l_idx)) {
#       fill_now <- fills[((i - 1) %% length(fills)) + 1]
#       gt$grobs[[strip_l_idx[i]]] <- set_rect_fill_recursive(
#         gt$grobs[[strip_l_idx[i]]],
#         fill = fill_now,
#         border = "black",
#         lwd = 1.0
#       )
#     }
#   }

#   strip_r_idx <- which(grepl("^strip-r", gt$layout$name))
#   if (length(strip_r_idx) > 0) {
#     strip_r_idx <- strip_r_idx[order(gt$layout$t[strip_r_idx])]
#     fills <- unname(row_strip_fills[c("In", "Ex")])

#     for (i in seq_along(strip_r_idx)) {
#       fill_now <- fills[((i - 1) %% length(fills)) + 1]
#       gt$grobs[[strip_r_idx[i]]] <- set_rect_fill_recursive(
#         gt$grobs[[strip_r_idx[i]]],
#         fill = fill_now,
#         border = "black",
#         lwd = 1.0
#       )
#     }
#   }

#   return(gt)
# }

# args <- parse_args(commandArgs(trailingOnly = TRUE))

# df_all <- bind_rows(
#   read_one_meta(args$mcx_in, "MCX", "In", args),
#   read_one_meta(args$pfc_in, "DLPFC", "In", args),
#   read_one_meta(args$mcx_ex, "MCX", "Ex", args),
#   read_one_meta(args$pfc_ex, "DLPFC", "Ex", args)
# )

# df_all <- normalize_panel_umap(
#   df_all,
#   panel_pad = args$panel_pad
# )

# df_all <- df_all %>%
#   mutate(
#     Region = factor(Region, levels = c("MCX", "DLPFC")),
#     Mode = factor(Mode, levels = c("In", "Ex")),
#     Panel = factor(
#       Panel,
#       levels = c("MCX In", "DLPFC In", "MCX Ex", "DLPFC Ex")
#     )
#   )

# df_outline <- df_all %>%
#   group_by(Region, Mode) %>%
#   group_modify(~{
#     mode_now <- as.character(.y$Mode)
#     targets <- get_targets(mode_now)
#     .x %>% filter(plot_group %in% targets)
#   }) %>%
#   ungroup()

# message("[INFO] Target group counts:")
# print(table(df_outline$Region, df_outline$Mode, df_outline$plot_group))

# mask_list <- lapply(
#   split(df_outline, df_outline$Panel),
#   make_mask_for_one_panel,
#   expand_val = args$expand
# )

# maskTable <- bind_rows(mask_list) %>%
#   mutate(
#     Region = factor(Region, levels = c("MCX", "DLPFC")),
#     Mode = factor(Mode, levels = c("In", "Ex")),
#     Panel = factor(
#       Panel,
#       levels = c("MCX In", "DLPFC In", "MCX Ex", "DLPFC Ex")
#     )
#   )

# label_df <- df_outline %>%
#   group_by(Region, Mode, Panel, plot_group) %>%
#   summarise(
#     label_x = median(UMAP1),
#     label_y = median(UMAP2),
#     .groups = "drop"
#   ) %>%
#   mutate(
#     label = make_label(plot_group, args$label_mode),

#     label_x = pmin(pmax(label_x, 0.08), 0.92),
#     label_y = pmin(pmax(label_y, 0.08), 0.92),

#     Region = factor(Region, levels = c("MCX", "DLPFC")),
#     Mode = factor(Mode, levels = c("In", "Ex")),
#     Panel = factor(
#       Panel,
#       levels = c("MCX In", "DLPFC In", "MCX Ex", "DLPFC Ex")
#     )
#   )

# message("[INFO] Labels:")
# print(label_df)

# base_theme <- theme_classic(base_size = 13) +
#   theme(
#     axis.text = element_blank(),
#     axis.ticks = element_blank(),
#     axis.line = element_blank(),
#     axis.title = element_blank(),

#     panel.border = element_rect(
#       color = "black",
#       fill = NA,
#       linewidth = 0.65
#     ),

#     panel.background = element_rect(fill = "white", color = NA),
#     plot.background = element_rect(fill = "white", color = NA),
#     legend.background = element_rect(fill = "white", color = NA),
#     legend.key = element_rect(fill = "white", color = NA),

#     strip.background = element_rect(
#       fill = "grey80",
#       color = "black",
#       linewidth = 0.65
#     ),

#     strip.text.x = element_text(
#       face = "bold",
#       size = 15,
#       color = "white",
#       margin = margin(4, 4, 4, 4)
#     ),
#     strip.text.y.left = element_text(
#       face = "bold",
#       size = 15,
#       color = "white",
#       angle = 90,
#       margin = margin(4, 4, 4, 4)
#     ),
#     strip.text.y = element_text(
#       face = "bold",
#       size = 15,
#       color = "white",
#       margin = margin(4, 4, 4, 4)
#     ),

#     plot.title = element_text(
#       hjust = 0.5,
#       face = "bold",
#       size = 18,
#       margin = margin(b = 8)
#     ),

#     legend.title = element_text(size = 11),
#     legend.text = element_text(size = 10),

#     panel.spacing.x = unit(0.20, "lines"),
#     panel.spacing.y = unit(0.20, "lines"),

#     plot.margin = margin(8, 8, 8, 8)
#   )

# p <- ggplot(
#   df_all,
#   aes(x = UMAP1, y = UMAP2, color = score)
# ) +
#   geom_point(
#     size = args$point_size,
#     alpha = args$point_alpha
#   ) +
#   geom_path(
#     data = maskTable,
#     aes(x = umap_1, y = umap_2, group = interaction(Panel, group)),
#     inherit.aes = FALSE,
#     linewidth = args$outline_lwd,
#     linetype = args$outline_lty,
#     color = "black"
#   ) +
#   geom_text_repel(
#     data = label_df,
#     aes(x = label_x, y = label_y, label = label),
#     inherit.aes = FALSE,
#     color = "black",
#     size = args$label_size,
#     fontface = "bold",
#     box.padding = 0.35,
#     point.padding = 0.20,
#     segment.color = "grey40",
#     segment.size = 0.25,
#     max.overlaps = Inf,
#     seed = 123,
#     xlim = c(0.05, 0.95),
#     ylim = c(0.05, 0.95),
#     show.legend = FALSE
#   ) +
#   scale_color_gradient2(
#     low = "#2166AC",
#     mid = "grey95",
#     high = "#B2182B",
#     midpoint = 0,
#     limits = c(-args$zlim, args$zlim),
#     oob = scales::squish,
#     name = "PPR-Z"
#   ) +
#   scale_x_continuous(
#     limits = c(0, 1),
#     expand = expansion(mult = 0)
#   ) +
#   scale_y_continuous(
#     limits = c(0, 1),
#     expand = expansion(mult = 0)
#   ) +
#   coord_fixed(ratio = 1, clip = "on") +
#   facet_grid(
#     Mode ~ Region,
#     switch = "y"
#   ) +
#   labs(title = "") +
#   base_theme

# g <- ggplotGrob(p)
# g <- color_facet_strips(g)

# png_fp <- paste0(args$out_prefix, ".png")
# pdf_fp <- paste0(args$out_prefix, ".pdf")

# dir.create(dirname(png_fp), recursive = TRUE, showWarnings = FALSE)
# dir.create(dirname(pdf_fp), recursive = TRUE, showWarnings = FALSE)

# ggsave(
#   filename = png_fp,
#   plot = g,
#   width = args$width,
#   height = args$height,
#   dpi = args$dpi,
#   bg = "white"
# )

# ggsave(
#   filename = pdf_fp,
#   plot = g,
#   width = args$width,
#   height = args$height,
#   bg = "white"
# )

# message("[OK] Saved: ", png_fp)
# message("[OK] Saved: ", pdf_fp)
#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(ggrepel)
  library(mascarade)
  library(scales)
  library(grid)
  library(ggrastr)
})

parse_args <- function(args) {
  if (length(args) %% 2 != 0) {
    stop("Arguments must be provided as --key value pairs.")
  }

  res <- list(
    mcx_in = NULL,
    pfc_in = NULL,
    mcx_ex = NULL,
    pfc_ex = NULL,
    out_prefix = NULL,

    umap1_col = "UMAP1",
    umap2_col = "UMAP2",
    group_col = "plot_group",
    score_col = "scdrs_ppr_z_display",

    width = 13,
    height = 10,
    dpi = 300,

    point_size = 0.16,
    point_alpha = 0.85,

    expand = 0.006,
    outline_lwd = 0.45,
    outline_lty = 2,

    label_size = 3.6,
    label_mode = "full",

    zlim = 2,

    panel_pad = 0.12
  )

  i <- 1
  while (i <= length(args)) {
    key <- args[[i]]

    if (!startsWith(key, "--")) stop("Unexpected argument: ", key)
    key2 <- substring(key, 3)

    if (!(key2 %in% names(res))) stop("Unknown argument: ", key)

    if (i == length(args)) stop("Missing value for argument: ", key)

    res[[key2]] <- args[[i + 1]]
    i <- i + 2
  }

  required <- c("mcx_in", "pfc_in", "mcx_ex", "pfc_ex", "out_prefix")
  missing <- required[vapply(required, function(x) is.null(res[[x]]), logical(1))]

  if (length(missing) > 0) {
    stop("Missing required arguments: ", paste(missing, collapse = ", "))
  }

  res$width <- as.numeric(res$width)
  res$height <- as.numeric(res$height)
  res$dpi <- as.integer(res$dpi)

  res$point_size <- as.numeric(res$point_size)
  res$point_alpha <- as.numeric(res$point_alpha)

  res$expand <- as.numeric(res$expand)
  res$outline_lwd <- as.numeric(res$outline_lwd)
  res$outline_lty <- as.integer(res$outline_lty)

  res$label_size <- as.numeric(res$label_size)
  res$zlim <- as.numeric(res$zlim)
  res$panel_pad <- as.numeric(res$panel_pad)

  return(res)
}

read_one_meta <- function(input, region, mode, args) {
  message("[INFO] Reading: ", input)

  df <- read.csv(
    input,
    stringsAsFactors = FALSE,
    check.names = FALSE
  )

  required_cols <- c(
    args$umap1_col,
    args$umap2_col,
    args$group_col,
    args$score_col
  )

  missing_cols <- setdiff(required_cols, colnames(df))

  if (length(missing_cols) > 0) {
    stop(
      "Missing required columns in ",
      input,
      ": ",
      paste(missing_cols, collapse = ", "),
      "\nAvailable columns: ",
      paste(colnames(df), collapse = " | ")
    )
  }

  df2 <- df %>%
    transmute(
      UMAP1_raw = as.numeric(.data[[args$umap1_col]]),
      UMAP2_raw = as.numeric(.data[[args$umap2_col]]),
      plot_group = as.character(.data[[args$group_col]]),
      score = as.numeric(.data[[args$score_col]]),
      Region = region,
      Mode = mode,
      Panel = paste(region, mode)
    ) %>%
    filter(
      !is.na(UMAP1_raw),
      !is.na(UMAP2_raw),
      !is.na(plot_group),
      !is.na(score)
    )

  if (nrow(df2) == 0) {
    stop("No valid rows after filtering: ", input)
  }

  return(df2)
}

normalize_panel_umap <- function(df, panel_pad = 0.12) {
  panel_pad <- max(0.02, min(panel_pad, 0.30))
  inner_scale <- 1 - 2 * panel_pad

  df %>%
    group_by(Panel) %>%
    mutate(
      x_min = min(UMAP1_raw),
      x_max = max(UMAP1_raw),
      y_min = min(UMAP2_raw),
      y_max = max(UMAP2_raw),

      x_mid = (x_min + x_max) / 2,
      y_mid = (y_min + y_max) / 2,

      x_range = x_max - x_min,
      y_range = y_max - y_min,

      panel_scale = max(x_range, y_range),

      UMAP1 = ((UMAP1_raw - x_mid) / panel_scale) * inner_scale + 0.5,
      UMAP2 = ((UMAP2_raw - y_mid) / panel_scale) * inner_scale + 0.5
    ) %>%
    ungroup() %>%
    select(
      -x_min, -x_max, -y_min, -y_max,
      -x_mid, -y_mid, -x_range, -y_range, -panel_scale
    )
}

get_targets <- function(mode) {
  if (mode == "In") {
    return(c(
      "In.PV.PVALB_PTHLH",
      "In.PV.PVALB_CEMIP",
      "In.5HT3aR.CDH4"
    ))
  }

  if (mode == "Ex") {
    return(c(
      "Ex.L5.VAT1L",
      "Ex.L5.PCP4_NXPH2"
    ))
  }

  stop("mode must be In or Ex")
}

make_label <- function(x, label_mode) {
  if (label_mode == "full") {
    return(x)
  }

  dplyr::recode(
    x,
    "In.PV.PVALB_PTHLH" = "PTHLH",
    "In.PV.PVALB_CEMIP" = "CEMIP",
    "In.5HT3aR.CDH4" = "CDH4",
    "Ex.L5.VAT1L" = "VAT1L",
    "Ex.L5.PCP4_NXPH2" = "PCP4_NXPH2",
    .default = x
  )
}

make_mask_for_one_panel <- function(df_one, expand_val) {
  df_mask <- df_one %>%
    transmute(
      umap_1 = UMAP1,
      umap_2 = UMAP2,
      plot_group = plot_group
    )

  maskTable <- generateMask(
    dims = as.matrix(df_mask[, c("umap_1", "umap_2")]),
    clusters = df_mask$plot_group,
    expand = expand_val
  )

  if (!all(c("umap_1", "umap_2", "group") %in% colnames(maskTable))) {
    stop(
      "maskTable does not contain expected columns: umap_1, umap_2, group\n",
      "Actual columns: ",
      paste(colnames(maskTable), collapse = " | ")
    )
  }

  maskTable$Region <- unique(df_one$Region)
  maskTable$Mode <- unique(df_one$Mode)
  maskTable$Panel <- unique(df_one$Panel)

  return(maskTable)
}

set_rect_fill_recursive <- function(gr, fill, border = "black", lwd = 1.0) {
  if (inherits(gr, "rect")) {
    gr$gp$fill <- fill
    gr$gp$col <- border
    gr$gp$lwd <- lwd
    return(gr)
  }

  if (!is.null(gr$children)) {
    gr$children <- lapply(
      gr$children,
      set_rect_fill_recursive,
      fill = fill,
      border = border,
      lwd = lwd
    )
  }

  if (!is.null(gr$grobs)) {
    gr$grobs <- lapply(
      gr$grobs,
      set_rect_fill_recursive,
      fill = fill,
      border = border,
      lwd = lwd
    )
  }

  return(gr)
}

color_facet_strips <- function(gt) {
  col_strip_fills <- c(
    "MCX" = "#E64B9A",
    "DLPFC" = "#2F9E57"
  )

  row_strip_fills <- c(
    "In" = "#56B4E9",
    "Ex" = "#FB8072"
  )

  strip_t_idx <- which(grepl("^strip-t", gt$layout$name))
  if (length(strip_t_idx) > 0) {
    strip_t_idx <- strip_t_idx[order(gt$layout$l[strip_t_idx])]
    fills <- unname(col_strip_fills[c("MCX", "DLPFC")])

    for (i in seq_along(strip_t_idx)) {
      fill_now <- fills[((i - 1) %% length(fills)) + 1]
      gt$grobs[[strip_t_idx[i]]] <- set_rect_fill_recursive(
        gt$grobs[[strip_t_idx[i]]],
        fill = fill_now,
        border = "black",
        lwd = 1.0
      )
    }
  }

  strip_l_idx <- which(grepl("^strip-l", gt$layout$name))
  if (length(strip_l_idx) > 0) {
    strip_l_idx <- strip_l_idx[order(gt$layout$t[strip_l_idx])]
    fills <- unname(row_strip_fills[c("In", "Ex")])

    for (i in seq_along(strip_l_idx)) {
      fill_now <- fills[((i - 1) %% length(fills)) + 1]
      gt$grobs[[strip_l_idx[i]]] <- set_rect_fill_recursive(
        gt$grobs[[strip_l_idx[i]]],
        fill = fill_now,
        border = "black",
        lwd = 1.0
      )
    }
  }

  strip_r_idx <- which(grepl("^strip-r", gt$layout$name))
  if (length(strip_r_idx) > 0) {
    strip_r_idx <- strip_r_idx[order(gt$layout$t[strip_r_idx])]
    fills <- unname(row_strip_fills[c("In", "Ex")])

    for (i in seq_along(strip_r_idx)) {
      fill_now <- fills[((i - 1) %% length(fills)) + 1]
      gt$grobs[[strip_r_idx[i]]] <- set_rect_fill_recursive(
        gt$grobs[[strip_r_idx[i]]],
        fill = fill_now,
        border = "black",
        lwd = 1.0
      )
    }
  }

  return(gt)
}

args <- parse_args(commandArgs(trailingOnly = TRUE))

df_all <- bind_rows(
  read_one_meta(args$mcx_in, "MCX", "In", args),
  read_one_meta(args$pfc_in, "DLPFC", "In", args),
  read_one_meta(args$mcx_ex, "MCX", "Ex", args),
  read_one_meta(args$pfc_ex, "DLPFC", "Ex", args)
)

df_all <- normalize_panel_umap(
  df_all,
  panel_pad = args$panel_pad
)

df_all <- df_all %>%
  mutate(
    Region = factor(Region, levels = c("MCX", "DLPFC")),
    Mode = factor(Mode, levels = c("In", "Ex")),
    Panel = factor(
      Panel,
      levels = c("MCX In", "DLPFC In", "MCX Ex", "DLPFC Ex")
    )
  )

df_outline <- df_all %>%
  group_by(Region, Mode) %>%
  group_modify(~{
    mode_now <- as.character(.y$Mode)
    targets <- get_targets(mode_now)
    .x %>% filter(plot_group %in% targets)
  }) %>%
  ungroup()

message("[INFO] Target group counts:")
print(table(df_outline$Region, df_outline$Mode, df_outline$plot_group))

mask_list <- lapply(
  split(df_outline, df_outline$Panel),
  make_mask_for_one_panel,
  expand_val = args$expand
)

maskTable <- bind_rows(mask_list) %>%
  mutate(
    Region = factor(Region, levels = c("MCX", "DLPFC")),
    Mode = factor(Mode, levels = c("In", "Ex")),
    Panel = factor(
      Panel,
      levels = c("MCX In", "DLPFC In", "MCX Ex", "DLPFC Ex")
    )
  )

label_df <- df_outline %>%
  group_by(Region, Mode, Panel, plot_group) %>%
  summarise(
    label_x = median(UMAP1),
    label_y = median(UMAP2),
    .groups = "drop"
  ) %>%
  mutate(
    label = make_label(plot_group, args$label_mode),

    label_x = pmin(pmax(label_x, 0.08), 0.92),
    label_y = pmin(pmax(label_y, 0.08), 0.92),

    Region = factor(Region, levels = c("MCX", "DLPFC")),
    Mode = factor(Mode, levels = c("In", "Ex")),
    Panel = factor(
      Panel,
      levels = c("MCX In", "DLPFC In", "MCX Ex", "DLPFC Ex")
    )
  )

message("[INFO] Labels:")
print(label_df)

base_theme <- theme_classic(base_size = 13) +
  theme(
    axis.text = element_blank(),
    axis.ticks = element_blank(),
    axis.line = element_blank(),
    axis.title = element_blank(),

    panel.border = element_rect(
      color = "black",
      fill = NA,
      linewidth = 0.65
    ),

    panel.background = element_rect(fill = "white", color = NA),
    plot.background = element_rect(fill = "white", color = NA),
    legend.background = element_rect(fill = "white", color = NA),
    legend.key = element_rect(fill = "white", color = NA),

    strip.background = element_rect(
      fill = "grey80",
      color = "black",
      linewidth = 0.65
    ),

    strip.text.x = element_text(
      face = "bold",
      size = 15,
      color = "white",
      margin = margin(4, 4, 4, 4)
    ),
    strip.text.y.left = element_text(
      face = "bold",
      size = 15,
      color = "white",
      angle = 90,
      margin = margin(4, 4, 4, 4)
    ),
    strip.text.y = element_text(
      face = "bold",
      size = 15,
      color = "white",
      margin = margin(4, 4, 4, 4)
    ),

    plot.title = element_text(
      hjust = 0.5,
      face = "bold",
      size = 18,
      margin = margin(b = 8)
    ),

    legend.title = element_text(size = 11),
    legend.text = element_text(size = 10),

    panel.spacing.x = unit(0.20, "lines"),
    panel.spacing.y = unit(0.20, "lines"),

    plot.margin = margin(8, 8, 8, 8)
  )

p <- ggplot(
  df_all,
  aes(x = UMAP1, y = UMAP2, color = score)
) +
  ggrastr::geom_point_rast(
    size = args$point_size,
    alpha = args$point_alpha,
    raster.dpi = args$dpi
  ) +
  geom_path(
    data = maskTable,
    aes(x = umap_1, y = umap_2, group = interaction(Panel, group)),
    inherit.aes = FALSE,
    linewidth = args$outline_lwd,
    linetype = args$outline_lty,
    color = "black"
  ) +
  geom_text_repel(
    data = label_df,
    aes(x = label_x, y = label_y, label = label),
    inherit.aes = FALSE,
    color = "black",
    size = args$label_size,
    fontface = "bold",
    box.padding = 0.35,
    point.padding = 0.20,
    segment.color = "grey40",
    segment.size = 0.25,
    max.overlaps = Inf,
    seed = 123,
    xlim = c(0.05, 0.95),
    ylim = c(0.05, 0.95),
    show.legend = FALSE
  ) +
  scale_color_gradient2(
    low = "#2166AC",
    mid = "grey95",
    high = "#B2182B",
    midpoint = 0,
    limits = c(-args$zlim, args$zlim),
    oob = scales::squish,
    name = "PPR-Z"
  ) +
  scale_x_continuous(
    limits = c(0, 1),
    expand = expansion(mult = 0)
  ) +
  scale_y_continuous(
    limits = c(0, 1),
    expand = expansion(mult = 0)
  ) +
  coord_fixed(ratio = 1, clip = "on") +
  facet_grid(
    Mode ~ Region,
    switch = "y"
  ) +
  labs(title = "") +
  base_theme

g <- ggplotGrob(p)
g <- color_facet_strips(g)

png_fp <- paste0(args$out_prefix, ".png")
pdf_fp <- paste0(args$out_prefix, ".pdf")

dir.create(dirname(png_fp), recursive = TRUE, showWarnings = FALSE)
dir.create(dirname(pdf_fp), recursive = TRUE, showWarnings = FALSE)

ggsave(
  filename = png_fp,
  plot = g,
  width = args$width,
  height = args$height,
  dpi = args$dpi,
  bg = "white"
)

ggsave(
  filename = pdf_fp,
  plot = g,
  width = args$width,
  height = args$height,
  bg = "white"
)

message("[OK] Saved: ", png_fp)
message("[OK] Saved: ", pdf_fp)