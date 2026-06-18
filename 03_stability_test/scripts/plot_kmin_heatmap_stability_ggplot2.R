
# suppressPackageStartupMessages({
#   library(ggplot2)
#   library(dplyr)
#   library(tidyr)
#   library(stringr)
#   library(patchwork)
#   library(scales)
# })

# # =========================
# # 1. 命令行参数
# # =========================
# parse_args <- function() {
#   defaults <- list(
#     "run-root" = NULL,
#     "stable-dir" = NULL,
#     "outdir" = NULL,
#     "value-col" = "capture_rate_any_hit",
#     "add-top-unstable" = 0L,
#     "kmin-min" = 2L,
#     "kmin-max" = 24L,
#     "save-pdf" = FALSE
#   )

#   args <- commandArgs(trailingOnly = TRUE)

#   if (length(args) == 0) {
#     cat(
#       "Usage:\n",
#       "  Rscript plot_kmin_heatmap_stability_ggplot2.R \\\n",
#       "    --run-root <path> \\\n",
#       "    --stable-dir <path> \\\n",
#       "    --outdir <path> \\\n",
#       "    [--value-col capture_rate_any_hit|capture_rate_main_hit] \\\n",
#       "    [--add-top-unstable 0] \\\n",
#       "    [--kmin-min 2] \\\n",
#       "    [--kmin-max 24] \\\n",
#       "    [--save-pdf]\n",
#       sep = ""
#     )
#     quit(save = "no", status = 1)
#   }

#   i <- 1
#   while (i <= length(args)) {
#     key <- args[[i]]

#     if (!startsWith(key, "--")) {
#       stop("Unexpected argument: ", key)
#     }

#     key2 <- substring(key, 3)

#     if (!(key2 %in% names(defaults))) {
#       stop("Unknown argument: ", key)
#     }

#     if (key2 == "save-pdf") {
#       defaults[[key2]] <- TRUE
#       i <- i + 1
#       next
#     }

#     if (i == length(args)) {
#       stop("Missing value for argument: ", key)
#     }

#     val <- args[[i + 1]]
#     defaults[[key2]] <- val
#     i <- i + 2
#   }

#   if (is.null(defaults[["run-root"]])) stop("--run-root is required")
#   if (is.null(defaults[["stable-dir"]])) stop("--stable-dir is required")
#   if (is.null(defaults[["outdir"]])) stop("--outdir is required")

#   defaults[["add-top-unstable"]] <- as.integer(defaults[["add-top-unstable"]])
#   defaults[["kmin-min"]] <- as.integer(defaults[["kmin-min"]])
#   defaults[["kmin-max"]] <- as.integer(defaults[["kmin-max"]])

#   if (!(defaults[["value-col"]] %in% c("capture_rate_any_hit", "capture_rate_main_hit"))) {
#     stop("--value-col must be one of: capture_rate_any_hit, capture_rate_main_hit")
#   }

#   defaults
# }

# ARGS <- parse_args()

# RUN_ROOT <- ARGS[["run-root"]]
# STABLE_DIR <- ARGS[["stable-dir"]]
# OUTDIR <- ARGS[["outdir"]]
# VALUE_COL <- ARGS[["value-col"]]
# ADD_TOP_UNSTABLE <- ARGS[["add-top-unstable"]]
# KMIN_MIN <- ARGS[["kmin-min"]]
# KMIN_MAX <- ARGS[["kmin-max"]]
# SAVE_PDF <- isTRUE(ARGS[["save-pdf"]])

# if (!dir.exists(OUTDIR)) {
#   dir.create(OUTDIR, recursive = TRUE, showWarnings = FALSE)
# }

# # =========================
# # 2. 配置
# # =========================
# DISPLAY_DATASETS <- tribble(
#   ~dataset_token, ~dataset_display,
#   "FTLD_MCX", "FTLD-MCX",
#   "SALS_MCX", "SALS-MCX",
#   "FTLD_PFC", "FTLD-PFC",
#   "SALS_PFC", "SALS-PFC"
# )

# CLASS_ORDER <- c(
#   "Cross_region_stable",
#   "MCX_specific_stable",
#   "PFC_specific_stable",
#   "not_stable"
# )

# CLASS_LABEL <- c(
#   "Cross_region_stable" = "Cross-region",
#   "MCX_specific_stable" = "MCX-specific",
#   "PFC_specific_stable" = "PFC-specific",
#   "not_stable" = "Not stable"
# )

# CLASS_COLOR <- c(
#   "Cross_region_stable" = "#11A88C",
#   "MCX_specific_stable" = "#E64B35",
#   "PFC_specific_stable" = "#4DBBD5",
#   "not_stable" = "#D0D0D0"
# )

# PREFIXES <- c("In", "Ex")

# HEAT_COLORS <- c(
#   "#08306B",
#   "#6BAED6",
#   "#F7F3EF",
#   "#F4A582",
#   "#B2182B"
# )

# HEAT_VALUES <- rescale(c(0, 25, 50, 75, 100), to = c(0, 1))

# # =========================
# # 3. 工具函数
# # =========================
# find_one_file <- function(run_root, dataset_token, prefix) {
#   hits <- list.files(
#     run_root,
#     pattern = paste0("^", prefix, "_all_subtypes_vulnerability_kmin_summary\\.tsv$"),
#     recursive = TRUE,
#     full.names = TRUE
#   )

#   hits <- hits[str_detect(hits, dataset_token)]

#   if (length(hits) == 0) {
#     stop("Cannot find file for dataset=", dataset_token, ", prefix=", prefix, " under ", run_root)
#   }

#   hits <- hits[order(nchar(hits), hits)]
#   hits[1]
# }

# read_kmin_summary <- function(fp, dataset_name, prefix, value_col) {
#   df <- read.delim(fp, check.names = FALSE)

#   need <- c("subtype", "k_min", value_col)
#   miss <- setdiff(need, colnames(df))

#   if (length(miss) > 0) {
#     stop(fp, " missing columns: ", paste(miss, collapse = ", "))
#   }

#   df %>%
#     mutate(
#       dataset = dataset_name,
#       prefix = prefix,
#       subtype = as.character(subtype),
#       k_min = suppressWarnings(as.integer(k_min)),
#       value = suppressWarnings(as.numeric(.data[[value_col]]))
#     ) %>%
#     select(dataset, prefix, subtype, k_min, value)
# }

# load_all_kmin_tables <- function(run_root, prefix, value_col) {
#   out <- list()

#   for (i in seq_len(nrow(DISPLAY_DATASETS))) {
#     dataset_token <- DISPLAY_DATASETS$dataset_token[i]
#     fp <- find_one_file(run_root, dataset_token, prefix)
#     out[[dataset_token]] <- read_kmin_summary(fp, dataset_token, prefix, value_col)
#   }

#   out
# }

# load_stable_table <- function(stable_dir, prefix) {
#   fp <- file.path(stable_dir, paste0(prefix, "_stable_classification.tsv"))
#   df <- read.delim(fp, check.names = FALSE)

#   need <- c("subtype", "stable_class")
#   miss <- setdiff(need, colnames(df))

#   if (length(miss) > 0) {
#     stop(fp, " missing columns: ", paste(miss, collapse = ", "))
#   }

#   df %>%
#     mutate(
#       subtype = as.character(subtype),
#       stable_class = as.character(stable_class)
#     )
# }

# # =========================
# # 以前版本的展示逻辑：
# # 只展示 stable_class != "not_stable"
# # 不重新定义 stable 标准
# # =========================
# choose_subtypes <- function(stable_df, all_tables, add_top_unstable = 0) {
#   all_df <- bind_rows(all_tables)

#   subtype_stat <- all_df %>%
#     group_by(subtype) %>%
#     summarise(
#       global_max = max(value, na.rm = TRUE),
#       global_mean = mean(value, na.rm = TRUE),
#       .groups = "drop"
#     )

#   stable_only <- stable_df %>%
#     filter(stable_class != "not_stable") %>%
#     mutate(class_rank = match(stable_class, CLASS_ORDER)) %>%
#     left_join(subtype_stat, by = "subtype") %>%
#     arrange(class_rank, desc(global_max), desc(global_mean), subtype) %>%
#     select(subtype, stable_class) %>%
#     distinct()

#   if (add_top_unstable > 0) {
#     unstable_top <- stable_df %>%
#       filter(stable_class == "not_stable") %>%
#       left_join(subtype_stat, by = "subtype") %>%
#       arrange(desc(global_max), desc(global_mean), subtype) %>%
#       select(subtype, stable_class) %>%
#       distinct() %>%
#       slice_head(n = add_top_unstable)

#     stable_only <- bind_rows(stable_only, unstable_top) %>%
#       distinct(subtype, .keep_all = TRUE)
#   }

#   stable_only
# }

# build_support_stats <- function(prefix, chosen_df, all_tables, threshold = 50) {
#   all_df <- bind_rows(all_tables) %>%
#     filter(subtype %in% chosen_df$subtype)

#   grp <- all_df %>%
#     group_by(subtype) %>%
#     summarise(
#       max_capture = max(value, na.rm = TRUE),
#       mean_capture = mean(value, na.rm = TRUE),
#       .groups = "drop"
#     )

#   hit <- all_df %>%
#     mutate(is_hit = ifelse(value >= threshold, 1, 0)) %>%
#     group_by(subtype) %>%
#     summarise(
#       n_ge50 = sum(is_hit, na.rm = TRUE),
#       n_total = n(),
#       prop_ge50 = n_ge50 / n_total,
#       .groups = "drop"
#     )

#   chosen_df %>%
#     left_join(grp, by = "subtype") %>%
#     left_join(hit, by = "subtype") %>%
#     mutate(
#       prefix = prefix,
#       max_capture = replace_na(max_capture, 0),
#       mean_capture = replace_na(mean_capture, 0),
#       n_ge50 = replace_na(n_ge50, 0),
#       n_total = replace_na(n_total, 0),
#       prop_ge50 = replace_na(prop_ge50, 0)
#     )
# }

# save_plot_both <- function(p, out_png, width, height, save_pdf = TRUE) {
#   ggsave(out_png, p, width = width, height = height, dpi = 300, bg = "white")

#   if (save_pdf) {
#     out_pdf <- str_replace(out_png, "\\.png$", ".pdf")
#     ggsave(out_pdf, p, width = width, height = height, bg = "white")
#   }
# }

# prepare_one_prefix_data <- function(prefix, stable_df, all_tables, add_top_unstable, kmin_min, kmin_max) {
#   chosen_df <- choose_subtypes(
#     stable_df = stable_df,
#     all_tables = all_tables,
#     add_top_unstable = add_top_unstable
#   )

#   support_df <- build_support_stats(
#     prefix = prefix,
#     chosen_df = chosen_df,
#     all_tables = all_tables,
#     threshold = 50
#   )

#   subtype_order <- chosen_df$subtype
#   subtype_order_rev <- rev(subtype_order)

#   heat_df <- bind_rows(all_tables) %>%
#     filter(subtype %in% subtype_order) %>%
#     left_join(DISPLAY_DATASETS, by = c("dataset" = "dataset_token")) %>%
#     select(dataset, prefix, dataset_display, subtype, k_min, value) %>%
#     group_by(dataset, prefix, dataset_display) %>%
#     complete(
#       subtype = subtype_order,
#       k_min = seq(kmin_min, kmin_max),
#       fill = list(value = 0)
#     ) %>%
#     ungroup() %>%
#     mutate(
#       subtype = factor(subtype, levels = subtype_order_rev),
#       dataset_display = factor(dataset_display, levels = DISPLAY_DATASETS$dataset_display),
#       stable_class = support_df$stable_class[match(as.character(subtype), support_df$subtype)]
#     )

#   annot_df <- support_df %>%
#     mutate(
#       subtype = factor(subtype, levels = subtype_order_rev),
#       x = 1,
#       stable_class = factor(stable_class, levels = CLASS_ORDER)
#     )

#   label_df <- support_df %>%
#     mutate(
#       subtype = factor(subtype, levels = subtype_order_rev),
#       label = subtype,
#       x = 1,
#       stable_class = factor(stable_class, levels = CLASS_ORDER)
#     )

#   list(
#     chosen_df = chosen_df,
#     support_df = support_df,
#     heat_df = heat_df,
#     annot_df = annot_df,
#     label_df = label_df
#   )
# }

# build_prefix_plot <- function(prefix_dat, plot_title = NULL) {
#   annot_df <- prefix_dat$annot_df
#   label_df <- prefix_dat$label_df
#   heat_df  <- prefix_dat$heat_df

#   p_class <- ggplot(annot_df, aes(x = x, y = subtype, fill = stable_class)) +
#     geom_tile(width = 0.95, height = 0.95) +
#     scale_fill_manual(
#       values = CLASS_COLOR,
#       breaks = CLASS_ORDER,
#       labels = CLASS_LABEL,
#       drop = FALSE,
#       name = "Stable class"
#     ) +
#     labs(title = NULL, x = NULL, y = NULL) +
#     theme_void(base_size = 13) +
#     theme(
#       plot.title = element_blank(),
#       legend.position = "top",
#       plot.margin = margin(6, 0, 6, 6)
#     )

#   p_text <- ggplot(label_df, aes(x = x, y = subtype, label = label, color = stable_class)) +
#     geom_text(hjust = 0, size = 4.8, fontface = "bold") +
#     scale_color_manual(values = CLASS_COLOR, guide = "none") +
#     xlim(1, 6.2) +
#     theme_void(base_size = 13) +
#     theme(
#       plot.margin = margin(6, 8, 6, 0)
#     )

#   p_heat <- ggplot(heat_df, aes(x = k_min, y = subtype, fill = value)) +
#     geom_tile(color = "white", linewidth = 0.28) +
#     facet_grid(. ~ dataset_display, switch = "x") +
#     scale_fill_gradientn(
#       colours = HEAT_COLORS,
#       values = HEAT_VALUES,
#       limits = c(0, 100),
#       breaks = c(0, 25, 50, 75, 100),
#       name = VALUE_COL,
#       oob = squish
#     ) +
#     scale_x_continuous(
#       breaks = seq(KMIN_MIN, KMIN_MAX, by = 1),
#       expand = c(0, 0)
#     ) +
#     labs(
#       x = "k_min",
#       y = NULL,
#       title = NULL
#     ) +
#     theme_minimal(base_size = 14) +
#     theme(
#       plot.title = element_blank(),
#       axis.text.x = element_text(size = 10, colour = "#5A5A5A"),
#       axis.text.y = element_blank(),
#       axis.title.x = element_text(size = 16, face = "bold"),
#       strip.text.x = element_text(size = 15, face = "bold"),
#       strip.background = element_rect(fill = "grey94", color = NA),
#       panel.grid = element_blank(),
#       legend.position = "top",
#       legend.direction = "horizontal",
#       legend.title = element_text(size = 12),
#       legend.text = element_text(size = 11),
#       plot.margin = margin(6, 6, 6, 0)
#     )

#   p_class + p_text + p_heat +
#     plot_layout(widths = c(0.9, 5.2, 16), guides = "collect") &
#     theme(
#       legend.position = "top",
#       legend.box = "horizontal"
#     )
# }

# make_plot_one_prefix <- function(prefix, stable_df, all_tables, outdir, add_top_unstable, kmin_min, kmin_max) {
#   prefix_dat <- prepare_one_prefix_data(
#     prefix = prefix,
#     stable_df = stable_df,
#     all_tables = all_tables,
#     add_top_unstable = add_top_unstable,
#     kmin_min = kmin_min,
#     kmin_max = kmin_max
#   )

#   final_plot <- build_prefix_plot(
#     prefix_dat,
#     plot_title = NULL
#   )

#   plot_h <- max(5, 0.72 * nrow(prefix_dat$chosen_df) + 2.6)

#   out_png <- file.path(
#     outdir,
#     paste0(prefix, "_kmin_heatmap_", VALUE_COL, "_ggplot2_clean.png")
#   )

#   save_plot_both(
#     final_plot,
#     out_png,
#     width = 22,
#     height = plot_h,
#     save_pdf = SAVE_PDF
#   )

#   source_df <- bind_rows(all_tables) %>%
#     filter(subtype %in% prefix_dat$chosen_df$subtype) %>%
#     left_join(prefix_dat$chosen_df, by = "subtype")

#   write.table(
#     source_df,
#     file = file.path(outdir, paste0(prefix, "_kmin_heatmap_source_ggplot2_clean.tsv")),
#     sep = "\t",
#     quote = FALSE,
#     row.names = FALSE
#   )

#   write.table(
#     prefix_dat$support_df,
#     file = file.path(outdir, paste0(prefix, "_kmin_heatmap_row_summary_ggplot2_clean.tsv")),
#     sep = "\t",
#     quote = FALSE,
#     row.names = FALSE
#   )

#   invisible(prefix_dat)
# }

# make_plot_combined <- function(all_prefix_dat, outdir) {
#   prefix_levels <- c("In", "Ex")

#   combined_support <- bind_rows(lapply(prefix_levels, function(px) {
#     x <- all_prefix_dat[[px]]$support_df

#     if (nrow(x) == 0) return(NULL)

#     x %>%
#       mutate(
#         prefix = factor(prefix, levels = prefix_levels),
#         row_id = paste(prefix, subtype, sep = " | "),
#         stable_class = factor(stable_class, levels = CLASS_ORDER)
#       )
#   }))

#   combined_heat <- bind_rows(lapply(prefix_levels, function(px) {
#     x <- all_prefix_dat[[px]]$heat_df

#     if (nrow(x) == 0) return(NULL)

#     x %>%
#       mutate(
#         prefix = factor(prefix, levels = prefix_levels),
#         row_id = paste(prefix, as.character(subtype), sep = " | ")
#       )
#   }))

#   row_levels <- c(
#     rev(combined_support$row_id[combined_support$prefix == "Ex"]),
#     rev(combined_support$row_id[combined_support$prefix == "In"])
#   )

#   row_levels <- unique(row_levels)

#   combined_support <- combined_support %>%
#     mutate(row_id = factor(row_id, levels = row_levels))

#   combined_heat <- combined_heat %>%
#     mutate(
#       row_id = factor(row_id, levels = row_levels),
#       dataset_display = factor(dataset_display, levels = DISPLAY_DATASETS$dataset_display)
#     )

#   annot_df <- combined_support %>%
#     mutate(x = 1)

#   label_df <- combined_support %>%
#     mutate(
#       x = 1,
#       label = subtype
#     )

#   p_class <- ggplot(annot_df, aes(x = x, y = row_id, fill = stable_class)) +
#     geom_tile(width = 0.95, height = 0.95) +
#     facet_grid(prefix ~ ., scales = "free_y", space = "free_y", switch = "y") +
#     scale_fill_manual(
#       values = CLASS_COLOR,
#       breaks = CLASS_ORDER,
#       labels = CLASS_LABEL,
#       drop = FALSE,
#       name = "Stable class"
#     ) +
#     labs(title = NULL, x = NULL, y = NULL) +
#     theme_void(base_size = 13) +
#     theme(
#       plot.title = element_blank(),
#       strip.text.y.left = element_text(size = 14, face = "bold", angle = 0),
#       strip.background = element_rect(fill = "grey94", color = NA),
#       legend.position = "top",
#       plot.margin = margin(6, 0, 6, 6)
#     )

#   p_text <- ggplot(label_df, aes(x = x, y = row_id, label = label, color = stable_class)) +
#     geom_text(hjust = 0, size = 4.8, fontface = "bold") +
#     facet_grid(prefix ~ ., scales = "free_y", space = "free_y", switch = "y") +
#     scale_color_manual(values = CLASS_COLOR, guide = "none") +
#     xlim(1, 6.2) +
#     theme_void(base_size = 13) +
#     theme(
#       strip.text.y.left = element_blank(),
#       strip.background = element_blank(),
#       plot.margin = margin(6, 8, 6, 0)
#     )

#   p_heat <- ggplot(combined_heat, aes(x = k_min, y = row_id, fill = value)) +
#     geom_tile(color = "white", linewidth = 0.28) +
#     facet_grid(prefix ~ dataset_display, scales = "free_y", space = "free_y", switch = "y") +
#     scale_fill_gradientn(
#       colours = HEAT_COLORS,
#       values = HEAT_VALUES,
#       limits = c(0, 100),
#       breaks = c(0, 25, 50, 75, 100),
#       name = VALUE_COL,
#       oob = squish
#     ) +
#     scale_x_continuous(
#       breaks = seq(KMIN_MIN, KMIN_MAX, by = 1),
#       expand = c(0, 0)
#     ) +
#     labs(
#       x = "k_min",
#       y = NULL,
#       title = NULL
#     ) +
#     theme_minimal(base_size = 14) +
#     theme(
#       plot.title = element_blank(),
#       axis.text.x = element_text(size = 10, colour = "#5A5A5A"),
#       axis.text.y = element_blank(),
#       axis.title.x = element_text(size = 16, face = "bold"),
#       strip.text.x = element_text(size = 15, face = "bold"),
#       strip.text.y.left = element_blank(),
#       strip.background = element_rect(fill = "grey94", color = NA),
#       panel.grid = element_blank(),
#       legend.position = "top",
#       legend.direction = "horizontal",
#       legend.title = element_text(size = 12),
#       legend.text = element_text(size = 11),
#       plot.margin = margin(6, 6, 6, 0)
#     )

#   final_plot <- p_class + p_text + p_heat +
#     plot_layout(widths = c(0.9, 5.2, 16), guides = "collect") &
#     theme(
#       legend.position = "top",
#       legend.box = "horizontal"
#     )

#   n_all_rows <- nrow(combined_support)
#   plot_h <- max(8, 0.62 * n_all_rows + 4.2)

#   out_png <- file.path(
#     outdir,
#     paste0("InEx_combined_kmin_heatmap_", VALUE_COL, "_ggplot2_clean.png")
#   )

#   save_plot_both(
#     final_plot,
#     out_png,
#     width = 22,
#     height = plot_h,
#     save_pdf = SAVE_PDF
#   )

#   write.table(
#     combined_support %>%
#       select(prefix, subtype, stable_class, max_capture, mean_capture, n_ge50, n_total, prop_ge50, row_id),
#     file = file.path(outdir, paste0("InEx_combined_kmin_heatmap_row_summary_", VALUE_COL, "_ggplot2_clean.tsv")),
#     sep = "\t",
#     quote = FALSE,
#     row.names = FALSE
#   )

#   write.table(
#     combined_heat %>%
#       select(prefix, dataset, dataset_display, subtype = row_id, k_min, value),
#     file = file.path(outdir, paste0("InEx_combined_kmin_heatmap_source_", VALUE_COL, "_ggplot2_clean.tsv")),
#     sep = "\t",
#     quote = FALSE,
#     row.names = FALSE
#   )
# }

# # =========================
# # 4. 主程序
# # =========================
# all_prefix_dat <- list()

# for (prefix in PREFIXES) {
#   stable_df <- load_stable_table(STABLE_DIR, prefix)
#   all_tables <- load_all_kmin_tables(RUN_ROOT, prefix, VALUE_COL)

#   prefix_dat <- make_plot_one_prefix(
#     prefix = prefix,
#     stable_df = stable_df,
#     all_tables = all_tables,
#     outdir = OUTDIR,
#     add_top_unstable = ADD_TOP_UNSTABLE,
#     kmin_min = KMIN_MIN,
#     kmin_max = KMIN_MAX
#   )

#   all_prefix_dat[[prefix]] <- prefix_dat
# }

# make_plot_combined(
#   all_prefix_dat = all_prefix_dat,
#   outdir = OUTDIR
# )
#!/usr/bin/env Rscript
#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(patchwork)
  library(scales)
  library(tibble)
  library(grid)
})

# =========================================================
# Global style
# =========================================================

FONT_FAMILY <- "Arial"

# =========================================================
# 1. Command line arguments
# =========================================================

parse_args <- function() {
  defaults <- list(
    "run-root" = NULL,
    "stable-dir" = NULL,
    "outdir" = NULL,
    "value-col" = "capture_rate_any_hit",
    "add-top-unstable" = 0L,
    "kmin-min" = 2L,
    "kmin-max" = 24L,
    "save-pdf" = FALSE
  )

  args <- commandArgs(trailingOnly = TRUE)

  if (length(args) == 0) {
    cat(
      "Usage:\n",
      "  Rscript plot_kmin_heatmap_stability_ggplot2.R \\\n",
      "    --run-root <path> \\\n",
      "    --stable-dir <path> \\\n",
      "    --outdir <path> \\\n",
      "    [--value-col capture_rate_any_hit|capture_rate_main_hit] \\\n",
      "    [--add-top-unstable 0] \\\n",
      "    [--kmin-min 2] \\\n",
      "    [--kmin-max 24] \\\n",
      "    [--save-pdf]\n",
      sep = ""
    )
    quit(save = "no", status = 1)
  }

  i <- 1
  while (i <= length(args)) {
    key <- args[[i]]

    if (!startsWith(key, "--")) {
      stop("Unexpected argument: ", key)
    }

    key2 <- substring(key, 3)

    if (!(key2 %in% names(defaults))) {
      stop("Unknown argument: ", key)
    }

    if (key2 == "save-pdf") {
      defaults[[key2]] <- TRUE
      i <- i + 1
      next
    }

    if (i == length(args)) {
      stop("Missing value for argument: ", key)
    }

    val <- args[[i + 1]]
    defaults[[key2]] <- val
    i <- i + 2
  }

  if (is.null(defaults[["run-root"]])) {
    stop("--run-root is required")
  }

  if (is.null(defaults[["stable-dir"]])) {
    stop("--stable-dir is required")
  }

  if (is.null(defaults[["outdir"]])) {
    stop("--outdir is required")
  }

  defaults[["add-top-unstable"]] <- as.integer(defaults[["add-top-unstable"]])
  defaults[["kmin-min"]] <- as.integer(defaults[["kmin-min"]])
  defaults[["kmin-max"]] <- as.integer(defaults[["kmin-max"]])

  if (!(defaults[["value-col"]] %in% c("capture_rate_any_hit", "capture_rate_main_hit"))) {
    stop("--value-col must be one of: capture_rate_any_hit, capture_rate_main_hit")
  }

  defaults
}

ARGS <- parse_args()

RUN_ROOT <- ARGS[["run-root"]]
STABLE_DIR <- ARGS[["stable-dir"]]
OUTDIR <- ARGS[["outdir"]]
VALUE_COL <- ARGS[["value-col"]]
ADD_TOP_UNSTABLE <- ARGS[["add-top-unstable"]]
KMIN_MIN <- ARGS[["kmin-min"]]
KMIN_MAX <- ARGS[["kmin-max"]]
SAVE_PDF <- isTRUE(ARGS[["save-pdf"]])

if (!dir.exists(OUTDIR)) {
  dir.create(OUTDIR, recursive = TRUE, showWarnings = FALSE)
}

# =========================================================
# 2. Configuration
# =========================================================

DISPLAY_DATASETS <- tribble(
  ~dataset_token, ~dataset_display,
  "FTLD_MCX", "FTLD-MCX",
  "SALS_MCX", "SALS-MCX",
  "FTLD_PFC", "FTLD-PFC",
  "SALS_PFC", "SALS-PFC"
)

CLASS_ORDER_LEGEND <- c(
  "Cross_region_stable",
  "MCX_specific_stable",
  "PFC_specific_stable"
)

CLASS_ORDER_ALL <- c(
  "Cross_region_stable",
  "MCX_specific_stable",
  "PFC_specific_stable",
  "not_stable"
)

CLASS_LABEL <- c(
  "Cross_region_stable" = "Cross-region",
  "MCX_specific_stable" = "MCX-specific",
  "PFC_specific_stable" = "PFC-specific",
  "not_stable" = "Not stable"
)

CLASS_COLOR <- c(
  "Cross_region_stable" = "#11A88C",
  "MCX_specific_stable" = "#E64B35",
  "PFC_specific_stable" = "#4DBBD5",
  "not_stable" = "#D0D0D0"
)

PREFIXES <- c("In", "Ex")

HEAT_COLORS <- c(
  "#08306B",
  "#6BAED6",
  "#F7F3EF",
  "#F4A582",
  "#B2182B"
)

HEAT_VALUES <- scales::rescale(c(0, 25, 50, 75, 100), to = c(0, 1))

# 不显示 24，避免不同 facet 之间出现 “24 2” 粘连
X_BREAKS <- c(2, 6, 10, 14, 18, 22)
X_BREAKS <- X_BREAKS[X_BREAKS >= KMIN_MIN & X_BREAKS <= KMIN_MAX]

# =========================================================
# 3. Helper functions
# =========================================================

find_one_file <- function(run_root, dataset_token, prefix) {
  hits <- list.files(
    run_root,
    pattern = paste0("^", prefix, "_all_subtypes_vulnerability_kmin_summary\\.tsv$"),
    recursive = TRUE,
    full.names = TRUE
  )

  hits <- hits[stringr::str_detect(hits, dataset_token)]

  if (length(hits) == 0) {
    stop(
      "Cannot find file for dataset = ",
      dataset_token,
      ", prefix = ",
      prefix,
      " under ",
      run_root
    )
  }

  hits <- hits[order(nchar(hits), hits)]
  hits[1]
}

read_kmin_summary <- function(fp, dataset_name, prefix, value_col) {
  df <- read.delim(fp, check.names = FALSE)

  need <- c("subtype", "k_min", value_col)
  miss <- setdiff(need, colnames(df))

  if (length(miss) > 0) {
    stop(fp, " missing columns: ", paste(miss, collapse = ", "))
  }

  df %>%
    mutate(
      dataset = dataset_name,
      prefix = prefix,
      subtype = as.character(subtype),
      k_min = suppressWarnings(as.integer(k_min)),
      value = suppressWarnings(as.numeric(.data[[value_col]]))
    ) %>%
    select(dataset, prefix, subtype, k_min, value)
}

load_all_kmin_tables <- function(run_root, prefix, value_col) {
  out <- list()

  for (i in seq_len(nrow(DISPLAY_DATASETS))) {
    dataset_token <- DISPLAY_DATASETS$dataset_token[i]
    fp <- find_one_file(run_root, dataset_token, prefix)
    out[[dataset_token]] <- read_kmin_summary(fp, dataset_token, prefix, value_col)
  }

  out
}

load_stable_table <- function(stable_dir, prefix) {
  fp <- file.path(stable_dir, paste0(prefix, "_stable_classification.tsv"))

  if (!file.exists(fp)) {
    stop("Cannot find stable classification file: ", fp)
  }

  df <- read.delim(fp, check.names = FALSE)

  need <- c("subtype", "stable_class")
  miss <- setdiff(need, colnames(df))

  if (length(miss) > 0) {
    stop(fp, " missing columns: ", paste(miss, collapse = ", "))
  }

  df %>%
    mutate(
      subtype = as.character(subtype),
      stable_class = as.character(stable_class)
    )
}

choose_subtypes <- function(stable_df, all_tables, add_top_unstable = 0) {
  all_df <- bind_rows(all_tables)

  subtype_stat <- all_df %>%
    group_by(subtype) %>%
    summarise(
      global_max = max(value, na.rm = TRUE),
      global_mean = mean(value, na.rm = TRUE),
      .groups = "drop"
    )

  stable_only <- stable_df %>%
    filter(stable_class != "not_stable") %>%
    mutate(class_rank = match(stable_class, CLASS_ORDER_ALL)) %>%
    left_join(subtype_stat, by = "subtype") %>%
    arrange(class_rank, desc(global_max), desc(global_mean), subtype) %>%
    select(subtype, stable_class) %>%
    distinct()

  if (add_top_unstable > 0) {
    unstable_top <- stable_df %>%
      filter(stable_class == "not_stable") %>%
      left_join(subtype_stat, by = "subtype") %>%
      arrange(desc(global_max), desc(global_mean), subtype) %>%
      select(subtype, stable_class) %>%
      distinct() %>%
      slice_head(n = add_top_unstable)

    stable_only <- bind_rows(stable_only, unstable_top) %>%
      distinct(subtype, .keep_all = TRUE)
  }

  stable_only
}

build_support_stats <- function(prefix, chosen_df, all_tables, threshold = 50) {
  all_df <- bind_rows(all_tables) %>%
    filter(subtype %in% chosen_df$subtype)

  grp <- all_df %>%
    group_by(subtype) %>%
    summarise(
      max_capture = max(value, na.rm = TRUE),
      mean_capture = mean(value, na.rm = TRUE),
      .groups = "drop"
    )

  hit <- all_df %>%
    mutate(is_hit = ifelse(value >= threshold, 1, 0)) %>%
    group_by(subtype) %>%
    summarise(
      n_ge50 = sum(is_hit, na.rm = TRUE),
      n_total = n(),
      prop_ge50 = n_ge50 / n_total,
      .groups = "drop"
    )

  chosen_df %>%
    left_join(grp, by = "subtype") %>%
    left_join(hit, by = "subtype") %>%
    mutate(
      prefix = prefix,
      max_capture = replace_na(max_capture, 0),
      mean_capture = replace_na(mean_capture, 0),
      n_ge50 = replace_na(n_ge50, 0),
      n_total = replace_na(n_total, 0),
      prop_ge50 = replace_na(prop_ge50, 0)
    )
}

save_plot_both <- function(p, out_png, width, height, save_pdf = TRUE) {
  ggsave(
    filename = out_png,
    plot = p,
    width = width,
    height = height,
    dpi = 300,
    bg = "white"
  )

  if (save_pdf) {
    out_pdf <- stringr::str_replace(out_png, "\\.png$", ".pdf")

    ggsave(
      filename = out_pdf,
      plot = p,
      width = width,
      height = height,
      bg = "white",
      device = cairo_pdf
    )
  }
}

prepare_one_prefix_data <- function(prefix, stable_df, all_tables, add_top_unstable, kmin_min, kmin_max) {
  chosen_df <- choose_subtypes(
    stable_df = stable_df,
    all_tables = all_tables,
    add_top_unstable = add_top_unstable
  )

  support_df <- build_support_stats(
    prefix = prefix,
    chosen_df = chosen_df,
    all_tables = all_tables,
    threshold = 50
  )

  subtype_order <- chosen_df$subtype
  subtype_order_rev <- rev(subtype_order)

  heat_df <- bind_rows(all_tables) %>%
    filter(subtype %in% subtype_order) %>%
    left_join(DISPLAY_DATASETS, by = c("dataset" = "dataset_token")) %>%
    select(dataset, prefix, dataset_display, subtype, k_min, value) %>%
    group_by(dataset, prefix, dataset_display) %>%
    complete(
      subtype = subtype_order,
      k_min = seq(kmin_min, kmin_max),
      fill = list(value = 0)
    ) %>%
    ungroup() %>%
    mutate(
      subtype = factor(subtype, levels = subtype_order_rev),
      dataset_display = factor(dataset_display, levels = DISPLAY_DATASETS$dataset_display),
      stable_class = support_df$stable_class[match(as.character(subtype), support_df$subtype)]
    )

  annot_df <- support_df %>%
    mutate(
      subtype = factor(subtype, levels = subtype_order_rev),
      x = 1,
      stable_class = factor(stable_class, levels = CLASS_ORDER_ALL)
    )

  label_df <- support_df %>%
    mutate(
      subtype = factor(subtype, levels = subtype_order_rev),
      label = subtype,
      x = 1,
      stable_class = factor(stable_class, levels = CLASS_ORDER_ALL)
    )

  list(
    chosen_df = chosen_df,
    support_df = support_df,
    heat_df = heat_df,
    annot_df = annot_df,
    label_df = label_df
  )
}

# =========================================================
# 4. Plot functions
# =========================================================

build_prefix_plot <- function(prefix_dat) {
  annot_df <- prefix_dat$annot_df
  label_df <- prefix_dat$label_df
  heat_df <- prefix_dat$heat_df

  p_class <- ggplot(annot_df, aes(x = x, y = subtype, fill = stable_class)) +
    geom_tile(width = 0.95, height = 0.95) +
    scale_fill_manual(
      values = CLASS_COLOR,
      breaks = CLASS_ORDER_LEGEND,
      labels = CLASS_LABEL[CLASS_ORDER_LEGEND],
      drop = FALSE,
      name = "Stable class",
      guide = guide_legend(
        title.theme = element_text(size = 18, face = "bold", family = FONT_FAMILY),
        label.theme = element_text(size = 16, family = FONT_FAMILY),
        keywidth = grid::unit(0.65, "cm"),
        keyheight = grid::unit(0.45, "cm")
      )
    ) +
    labs(x = NULL, y = NULL) +
    theme_void(base_size = 13, base_family = FONT_FAMILY) +
    theme(
      legend.position = "top",
      plot.margin = margin(4, 0, 4, 4)
    )

  p_text <- ggplot(label_df, aes(x = x, y = subtype, label = label, color = stable_class)) +
    geom_text(hjust = 0, size = 4.9, fontface = "bold", family = FONT_FAMILY) +
    scale_color_manual(values = CLASS_COLOR, guide = "none") +
    coord_cartesian(xlim = c(1, 5.0), clip = "on") +
    theme_void(base_size = 13, base_family = FONT_FAMILY) +
    theme(
      plot.margin = margin(4, 8, 4, 0)
    )

  p_heat <- ggplot(heat_df, aes(x = k_min, y = subtype, fill = value)) +
    geom_tile(color = "white", linewidth = 0.28) +
    facet_grid(. ~ dataset_display) +
    scale_fill_gradientn(
      colours = HEAT_COLORS,
      values = HEAT_VALUES,
      limits = c(0, 100),
      breaks = c(0, 25, 50, 75, 100),
      name = "capture rate",
      oob = squish,
      guide = guide_colorbar(
        title.position = "top",
        title.hjust = 0.5,
        title.theme = element_text(size = 16, face = "bold", family = FONT_FAMILY),
        label.theme = element_text(size = 14, family = FONT_FAMILY),
        barwidth = grid::unit(3.2, "cm"),
        barheight = grid::unit(0.35, "cm")
      )
    ) +
    scale_x_continuous(
      breaks = X_BREAKS,
      labels = as.character(X_BREAKS),
      expand = expansion(mult = c(0.015, 0.015))
    ) +
    labs(
      x = "Number of clusters",
      y = NULL
    ) +
    theme_minimal(base_size = 14, base_family = FONT_FAMILY) +
    theme(
      axis.text.x = element_text(size = 12, colour = "#5A5A5A", family = FONT_FAMILY),
      axis.text.y = element_blank(),
      axis.title.x = element_text(size = 18, face = "bold", family = FONT_FAMILY),
      strip.text.x = element_text(size = 18, face = "bold", family = FONT_FAMILY),
      strip.background = element_rect(fill = "grey94", color = NA),
      panel.grid = element_blank(),
      panel.spacing.x = grid::unit(0.35, "cm"),
      legend.position = "top",
      legend.direction = "horizontal",
      legend.title = element_text(size = 16, face = "bold", family = FONT_FAMILY),
      legend.text = element_text(size = 14, family = FONT_FAMILY),
      plot.margin = margin(4, 6, 4, 0)
    )

  p_class + p_text + p_heat +
    plot_layout(widths = c(0.45, 4.0, 18), guides = "collect") &
    theme(
      text = element_text(family = FONT_FAMILY),
      legend.position = "top",
      legend.box = "horizontal",
      legend.title = element_text(size = 16, face = "bold", family = FONT_FAMILY),
      legend.text = element_text(size = 14, family = FONT_FAMILY),
      legend.key.width = grid::unit(0.65, "cm"),
      legend.key.height = grid::unit(0.45, "cm")
    )
}

make_plot_one_prefix <- function(prefix, stable_df, all_tables, outdir, add_top_unstable, kmin_min, kmin_max) {
  prefix_dat <- prepare_one_prefix_data(
    prefix = prefix,
    stable_df = stable_df,
    all_tables = all_tables,
    add_top_unstable = add_top_unstable,
    kmin_min = kmin_min,
    kmin_max = kmin_max
  )

  final_plot <- build_prefix_plot(prefix_dat)

  plot_h <- max(4.8, 0.7 * nrow(prefix_dat$chosen_df) + 2.4)

  out_png <- file.path(outdir, paste0(prefix, "_kmin_heatmap_", VALUE_COL, "_ggplot2_clean.png"))

  save_plot_both(
    p = final_plot,
    out_png = out_png,
    width = 22,
    height = plot_h,
    save_pdf = SAVE_PDF
  )

  source_df <- bind_rows(all_tables) %>%
    filter(subtype %in% prefix_dat$chosen_df$subtype) %>%
    left_join(prefix_dat$chosen_df, by = "subtype")

  write.table(
    source_df,
    file = file.path(outdir, paste0(prefix, "_kmin_heatmap_source_ggplot2_clean.tsv")),
    sep = "\t",
    quote = FALSE,
    row.names = FALSE
  )

  write.table(
    prefix_dat$support_df,
    file = file.path(outdir, paste0(prefix, "_kmin_heatmap_row_summary_ggplot2_clean.tsv")),
    sep = "\t",
    quote = FALSE,
    row.names = FALSE
  )

  invisible(prefix_dat)
}

make_plot_combined <- function(all_prefix_dat, outdir) {
  prefix_levels <- c("In", "Ex")

  combined_support <- bind_rows(lapply(prefix_levels, function(px) {
    x <- all_prefix_dat[[px]]$support_df

    if (nrow(x) == 0) {
      return(NULL)
    }

    x %>%
      mutate(
        prefix = factor(prefix, levels = prefix_levels),
        row_id = paste(prefix, subtype, sep = " | "),
        stable_class = factor(stable_class, levels = CLASS_ORDER_ALL)
      )
  }))

  combined_heat <- bind_rows(lapply(prefix_levels, function(px) {
    x <- all_prefix_dat[[px]]$heat_df

    if (nrow(x) == 0) {
      return(NULL)
    }

    x %>%
      mutate(
        prefix = factor(prefix, levels = prefix_levels),
        row_id = paste(prefix, as.character(subtype), sep = " | ")
      )
  }))

  row_levels <- c(
    rev(combined_support$row_id[combined_support$prefix == "Ex"]),
    rev(combined_support$row_id[combined_support$prefix == "In"])
  )

  row_levels <- unique(row_levels)

  combined_support <- combined_support %>%
    mutate(row_id = factor(row_id, levels = row_levels))

  combined_heat <- combined_heat %>%
    mutate(
      row_id = factor(row_id, levels = row_levels),
      dataset_display = factor(dataset_display, levels = DISPLAY_DATASETS$dataset_display)
    )

  annot_df <- combined_support %>%
    mutate(x = 1)

  label_df <- combined_support %>%
    mutate(
      x = 1,
      label = subtype
    )

  p_class <- ggplot(annot_df, aes(x = x, y = row_id, fill = stable_class)) +
    geom_tile(width = 0.95, height = 0.95) +
    facet_grid(prefix ~ ., scales = "free_y", space = "free_y", switch = "y") +
    scale_fill_manual(
      values = CLASS_COLOR,
      breaks = CLASS_ORDER_LEGEND,
      labels = CLASS_LABEL[CLASS_ORDER_LEGEND],
      drop = FALSE,
      name = "Stable class",
      guide = guide_legend(
        title.theme = element_text(size = 18, face = "bold", family = FONT_FAMILY),
        label.theme = element_text(size = 16, family = FONT_FAMILY),
        keywidth = grid::unit(0.65, "cm"),
        keyheight = grid::unit(0.45, "cm")
      )
    ) +
    labs(x = NULL, y = NULL) +
    theme_void(base_size = 13, base_family = FONT_FAMILY) +
    theme(
      strip.text.y.left = element_text(size = 16, face = "bold", angle = 0, family = FONT_FAMILY),
      strip.background = element_rect(fill = "grey94", color = NA),
      legend.position = "top",
      plot.margin = margin(4, 0, 4, 4)
    )

  p_text <- ggplot(label_df, aes(x = x, y = row_id, label = label, color = stable_class)) +
    geom_text(hjust = 0, size = 4.9, fontface = "bold", family = FONT_FAMILY) +
    facet_grid(prefix ~ ., scales = "free_y", space = "free_y", switch = "y") +
    scale_color_manual(values = CLASS_COLOR, guide = "none") +
    coord_cartesian(xlim = c(1, 5.0), clip = "on") +
    theme_void(base_size = 13, base_family = FONT_FAMILY) +
    theme(
      strip.text.y.left = element_blank(),
      strip.background = element_blank(),
      plot.margin = margin(4, 8, 4, 0)
    )

  p_heat <- ggplot(combined_heat, aes(x = k_min, y = row_id, fill = value)) +
    geom_tile(color = "white", linewidth = 0.28) +
    facet_grid(prefix ~ dataset_display, scales = "free_y", space = "free_y", switch = "y") +
    scale_fill_gradientn(
      colours = HEAT_COLORS,
      values = HEAT_VALUES,
      limits = c(0, 100),
      breaks = c(0, 25, 50, 75, 100),
      name = "capture rate",
      oob = squish,
      guide = guide_colorbar(
        title.position = "top",
        title.hjust = 0.5,
        title.theme = element_text(size = 16, face = "bold", family = FONT_FAMILY),
        label.theme = element_text(size = 14, family = FONT_FAMILY),
        barwidth = grid::unit(3.2, "cm"),
        barheight = grid::unit(0.35, "cm")
      )
    ) +
    scale_x_continuous(
      breaks = X_BREAKS,
      labels = as.character(X_BREAKS),
      expand = expansion(mult = c(0.015, 0.015))
    ) +
    labs(
      x = "Number of clusters",
      y = NULL
    ) +
    theme_minimal(base_size = 14, base_family = FONT_FAMILY) +
    theme(
      axis.text.x = element_text(size = 12, colour = "#5A5A5A", family = FONT_FAMILY),
      axis.text.y = element_blank(),
      axis.title.x = element_text(size = 18, face = "bold", family = FONT_FAMILY),
      strip.text.x = element_text(size = 18, face = "bold", family = FONT_FAMILY),
      strip.text.y.left = element_blank(),
      strip.background = element_rect(fill = "grey94", color = NA),
      panel.grid = element_blank(),
      panel.spacing.x = grid::unit(0.35, "cm"),
      legend.position = "top",
      legend.direction = "horizontal",
      legend.title = element_text(size = 16, face = "bold", family = FONT_FAMILY),
      legend.text = element_text(size = 14, family = FONT_FAMILY),
      plot.margin = margin(4, 6, 4, 0)
    )

  final_plot <- p_class + p_text + p_heat +
    plot_layout(widths = c(0.45, 4.0, 18), guides = "collect") &
    theme(
      text = element_text(family = FONT_FAMILY),
      legend.position = "top",
      legend.box = "horizontal",
      legend.title = element_text(size = 16, face = "bold", family = FONT_FAMILY),
      legend.text = element_text(size = 14, family = FONT_FAMILY),
      legend.key.width = grid::unit(0.65, "cm"),
      legend.key.height = grid::unit(0.45, "cm")
    )

  n_all_rows <- nrow(combined_support)
  plot_h <- max(7.5, 0.62 * n_all_rows + 3.8)

  out_png <- file.path(outdir, paste0("InEx_combined_kmin_heatmap_", VALUE_COL, "_ggplot2_clean.png"))

  save_plot_both(
    p = final_plot,
    out_png = out_png,
    width = 22,
    height = plot_h,
    save_pdf = SAVE_PDF
  )

  write.table(
    combined_support %>%
      select(prefix, subtype, stable_class, max_capture, mean_capture, n_ge50, n_total, prop_ge50, row_id),
    file = file.path(outdir, paste0("InEx_combined_kmin_heatmap_row_summary_", VALUE_COL, "_ggplot2_clean.tsv")),
    sep = "\t",
    quote = FALSE,
    row.names = FALSE
  )

  write.table(
    combined_heat %>%
      select(prefix, dataset, dataset_display, subtype = row_id, k_min, value),
    file = file.path(outdir, paste0("InEx_combined_kmin_heatmap_source_", VALUE_COL, "_ggplot2_clean.tsv")),
    sep = "\t",
    quote = FALSE,
    row.names = FALSE
  )
}

# =========================================================
# 5. Main program
# =========================================================

all_prefix_dat <- list()

for (prefix in PREFIXES) {
  message("[INFO] Processing prefix: ", prefix)

  stable_df <- load_stable_table(STABLE_DIR, prefix)
  all_tables <- load_all_kmin_tables(RUN_ROOT, prefix, VALUE_COL)

  prefix_dat <- make_plot_one_prefix(
    prefix = prefix,
    stable_df = stable_df,
    all_tables = all_tables,
    outdir = OUTDIR,
    add_top_unstable = ADD_TOP_UNSTABLE,
    kmin_min = KMIN_MIN,
    kmin_max = KMIN_MAX
  )

  all_prefix_dat[[prefix]] <- prefix_dat
}

message("[INFO] Building In + Ex combined heatmap")

make_plot_combined(
  all_prefix_dat = all_prefix_dat,
  outdir = OUTDIR
)

message("[DONE] k_min heatmap plotting finished.")