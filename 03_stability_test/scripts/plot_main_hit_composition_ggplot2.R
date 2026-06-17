
# suppressPackageStartupMessages({
#   library(ggplot2)
#   library(dplyr)
#   library(tidyr)
#   library(stringr)
#   library(forcats)
#   library(patchwork)
#   library(scales)
#   library(jsonlite)
# })

# parse_args <- function() {
#   args <- commandArgs(trailingOnly = TRUE)

#   defaults <- list(
#     "structure-dir" = NULL,
#     "outdir" = NULL,
#     "save-pdf" = FALSE
#   )

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

#     defaults[[key2]] <- args[[i + 1]]
#     i <- i + 2
#   }

#   if (is.null(defaults[["structure-dir"]])) stop("--structure-dir is required")
#   if (is.null(defaults[["outdir"]])) stop("--outdir is required")

#   defaults
# }

# ARGS <- parse_args()
# STRUCTURE_DIR <- ARGS[["structure-dir"]]
# OUTDIR <- ARGS[["outdir"]]
# SAVE_PDF <- isTRUE(ARGS[["save-pdf"]])

# if (!dir.exists(OUTDIR)) {
#   dir.create(OUTDIR, recursive = TRUE, showWarnings = FALSE)
# }

# PREFIXES <- c("In", "Ex")
# REGION_ORDER <- c("MCX", "PFC")
# REP_ORDER <- c(
#   "FTLD_MCX_Control_Concat_QC_harmony_filted",
#   "SALS_MCX_control_concat_QC_harmony",
#   "FTLD_PFC_Ctrl_Concat_QC_harmony_filted",
#   "SALS_PFC_control_concat_QC_harmony"
# )

# REP_LABEL <- c(
#   "FTLD_MCX_Control_Concat_QC_harmony_filted" = "FTLD-MCX",
#   "SALS_MCX_control_concat_QC_harmony" = "SALS-MCX",
#   "FTLD_PFC_Ctrl_Concat_QC_harmony_filted" = "FTLD-PFC",
#   "SALS_PFC_control_concat_QC_harmony" = "SALS-PFC"
# )

# CAPTURE_COLORS <- c(
#   "#08306B",
#   "#6BAED6",
#   "#F7F3EF",
#   "#F4A582",
#   "#B2182B"
# )
# CAPTURE_VALUES <- scales::rescale(c(0, 25, 50, 75, 100), to = c(0, 1))

# save_plot_both <- function(p, out_png, width, height, save_pdf = FALSE) {
#   ggsave(out_png, p, width = width, height = height, dpi = 300, bg = "white")
#   if (save_pdf) {
#     ggsave(str_replace(out_png, "\\.png$", ".pdf"), p, width = width, height = height, bg = "white")
#   }
# }

# normalize_cluster_label <- function(x) {
#   if (is.na(x)) return("")
#   s <- str_trim(as.character(x))
#   if (s == "" || tolower(s) == "nan") return("")

#   num <- suppressWarnings(as.numeric(s))
#   if (!is.na(num)) {
#     if (abs(num - round(num)) < 1e-8) {
#       return(as.character(as.integer(round(num))))
#     } else {
#       return(as.character(num))
#     }
#   }
#   s
# }

# parse_top_subtypes <- function(x) {
#   if (is.na(x) || x == "") {
#     return(data.frame(component_subtype = character(), percent = numeric()))
#   }

#   parts <- unlist(strsplit(x, ";", fixed = TRUE))
#   parts <- parts[nzchar(parts)]

#   out <- lapply(parts, function(p) {
#     m <- str_match(p, "^(.*?):\\s*\\d+\\(([-0-9.]+)%\\)$")
#     if (all(is.na(m))) return(NULL)

#     data.frame(
#       component_subtype = str_trim(m[2]),
#       percent = as.numeric(m[3]),
#       stringsAsFactors = FALSE
#     )
#   })

#   out <- out[!vapply(out, is.null, logical(1))]
#   if (length(out) == 0) {
#     return(data.frame(component_subtype = character(), percent = numeric()))
#   }

#   out <- bind_rows(out)

#   s <- sum(out$percent, na.rm = TRUE)
#   if (s < 99.5) {
#     out <- bind_rows(
#       out,
#       data.frame(
#         component_subtype = "Other",
#         percent = max(0, 100 - s),
#         stringsAsFactors = FALSE
#       )
#     )
#   }

#   out
# }

# parse_json_counts_to_pct <- function(x) {
#   if (is.na(x) || x == "" || x == "{}") {
#     return(data.frame(component_subtype = character(), percent = numeric()))
#   }

#   obj <- tryCatch(jsonlite::fromJSON(x), error = function(e) NULL)
#   if (is.null(obj) || length(obj) == 0) {
#     return(data.frame(component_subtype = character(), percent = numeric()))
#   }

#   vals <- as.numeric(obj)
#   nms <- names(obj)

#   keep <- !is.na(vals) & vals > 0
#   vals <- vals[keep]
#   nms <- nms[keep]

#   if (length(vals) == 0) {
#     return(data.frame(component_subtype = character(), percent = numeric()))
#   }

#   pct <- 100 * vals / sum(vals)

#   data.frame(
#     component_subtype = nms,
#     percent = pct,
#     stringsAsFactors = FALSE
#   ) %>%
#     arrange(desc(percent), component_subtype)
# }

# parse_composition <- function(top_subtypes, subtype_count_json = NA_character_) {
#   out <- parse_json_counts_to_pct(subtype_count_json)
#   if (nrow(out) > 0) return(out)
#   parse_top_subtypes(top_subtypes)
# }

# save_empty_plot <- function(title, out_png, save_pdf = FALSE) {
#   p <- ggplot() +
#     annotate("text", x = 0.5, y = 0.5, label = "No data", size = 6) +
#     xlim(0, 1) + ylim(0, 1) +
#     labs(title = title) +
#     theme_void(base_size = 14) +
#     theme(plot.title = element_text(size = 18, face = "bold", hjust = 0.5))
#   save_plot_both(p, out_png, width = 8, height = 4, save_pdf = save_pdf)
# }

# write_debug_tsv <- function(df, fp) {
#   write.table(df, file = fp, sep = "\t", quote = FALSE, row.names = FALSE)
# }

# # ---------- input ----------
# kmin_fp <- file.path(STRUCTURE_DIR, "stable_subtype_kmin_structure.tsv")
# hit_fp <- file.path(STRUCTURE_DIR, "stable_hit_cluster_summary.tsv")

# if (!file.exists(kmin_fp)) stop("Cannot find: ", kmin_fp)
# if (!file.exists(hit_fp)) stop("Cannot find: ", hit_fp)

# kmin_df <- read.delim(kmin_fp, check.names = FALSE)
# hit_df <- read.delim(hit_fp, check.names = FALSE)

# if (!("subtype_count_json" %in% colnames(hit_df))) {
#   hit_df$subtype_count_json <- NA_character_
# }

# kmin_df <- kmin_df %>%
#   mutate(
#     prefix = as.character(prefix),
#     region = factor(as.character(region), levels = REGION_ORDER),
#     rep = factor(as.character(rep), levels = REP_ORDER),
#     rep_label = factor(REP_LABEL[as.character(rep)], levels = unname(REP_LABEL)),
#     subtype = as.character(subtype),
#     row_label = paste0(as.character(region), " | ", subtype),
#     k_min = as.integer(k_min),
#     main_hit_cluster = as.character(main_hit_cluster),
#     main_hit_cluster_norm = vapply(main_hit_cluster, normalize_cluster_label, character(1)),
#     capture_rate_main_hit = as.numeric(capture_rate_main_hit),
#     capture_rate_any_hit = as.numeric(capture_rate_any_hit)
#   )

# hit_df <- hit_df %>%
#   mutate(
#     prefix = as.character(prefix),
#     region = factor(as.character(region), levels = REGION_ORDER),
#     rep = factor(as.character(rep), levels = REP_ORDER),
#     rep_label = factor(REP_LABEL[as.character(rep)], levels = unname(REP_LABEL)),
#     k_min = as.integer(k_min),
#     cluster = as.character(cluster),
#     cluster_norm = vapply(cluster, normalize_cluster_label, character(1)),
#     top_subtypes = as.character(top_subtypes),
#     subtype_count_json = as.character(subtype_count_json)
#   )

# row_order_df <- kmin_df %>%
#   group_by(prefix, region, subtype, row_label) %>%
#   summarise(
#     mean_capture_any = mean(capture_rate_any_hit, na.rm = TRUE),
#     mean_capture_main = mean(capture_rate_main_hit, na.rm = TRUE),
#     .groups = "drop"
#   ) %>%
#   arrange(prefix, region, desc(mean_capture_any), desc(mean_capture_main), subtype)

# for (prefix_now in PREFIXES) {

#   row_levels <- row_order_df %>%
#     filter(prefix == prefix_now) %>%
#     pull(row_label)

#   row_levels_rev <- rev(unique(row_levels))

#   one_kmin <- kmin_df %>%
#     filter(prefix == prefix_now) %>%
#     mutate(
#       row_label = factor(row_label, levels = row_levels_rev),
#       region = factor(region, levels = REGION_ORDER)
#     )

#   if (nrow(one_kmin) == 0) {
#     save_empty_plot(
#       paste0(prefix_now, ": main-hit capture + composition"),
#       file.path(OUTDIR, paste0(prefix_now, "_capture_plus_mainhit_composition_ggplot2.png")),
#       save_pdf = SAVE_PDF
#     )
#     next
#   }

#   # ---------- left panel ----------
#   capture_df <- one_kmin %>%
#     group_by(region, row_label, k_min) %>%
#     summarise(
#       capture_rate_main_hit = mean(capture_rate_main_hit, na.rm = TRUE),
#       .groups = "drop"
#     ) %>%
#     mutate(
#       row_label = factor(row_label, levels = row_levels_rev),
#       region = factor(region, levels = REGION_ORDER)
#     ) %>%
#     filter(!is.na(region))

#   p_capture <- ggplot(capture_df, aes(x = factor(k_min), y = 1, fill = capture_rate_main_hit)) +
#     geom_tile(color = "white", linewidth = 0.25, height = 0.95, width = 0.95) +
#     facet_grid(region + row_label ~ ., scales = "free_y", space = "free_y", switch = "y") +
#     scale_fill_gradientn(
#       colours = CAPTURE_COLORS,
#       values = CAPTURE_VALUES,
#       limits = c(0, 100),
#       breaks = c(0, 25, 50, 75, 100),
#       oob = squish,
#       name = "Main-hit capture (%)",
#       na.value = "grey85"
#     ) +
#     labs(title = "Main-hit capture", x = "k_min", y = NULL) +
#     theme_minimal(base_size = 12) +
#     theme(
#       plot.title = element_text(size = 16, face = "bold", hjust = 0.5),
#       axis.text.x = element_text(size = 8),
#       axis.text.y = element_blank(),
#       axis.title.x = element_text(face = "bold"),
#       strip.text.y.left = element_text(size = 10, face = "bold", angle = 0),
#       strip.background = element_rect(fill = "grey95", color = NA),
#       panel.grid = element_blank(),
#       legend.position = "top"
#     )

#   # ---------- right panel source ----------
#   focal_df <- one_kmin %>%
#     filter(!is.na(main_hit_cluster_norm), main_hit_cluster_norm != "") %>%
#     select(
#       rep, rep_label, region, prefix, subtype, row_label, k_min,
#       main_hit_cluster, main_hit_cluster_norm, capture_rate_main_hit
#     )

#   hit_main_df <- hit_df %>%
#     select(
#       rep, rep_label, region, prefix, k_min,
#       cluster, cluster_norm, top_subtypes, subtype_count_json
#     )

#   merged_df <- focal_df %>%
#     left_join(
#       hit_main_df,
#       by = c(
#         "rep", "rep_label", "region", "prefix", "k_min",
#         "main_hit_cluster_norm" = "cluster_norm"
#       )
#     ) %>%
#     mutate(
#       join_ok = !is.na(cluster),
#       has_json = !is.na(subtype_count_json) & subtype_count_json != "" & subtype_count_json != "{}",
#       has_top = !is.na(top_subtypes) & top_subtypes != ""
#     )

#   write_debug_tsv(
#     merged_df,
#     file.path(OUTDIR, paste0(prefix_now, "_merged_debug.tsv"))
#   )

#   bad_join_df <- merged_df %>%
#     filter(capture_rate_main_hit > 0) %>%
#     filter(!join_ok)

#   if (nrow(bad_join_df) > 0) {
#     bad_fp <- file.path(OUTDIR, paste0(prefix_now, "_bad_join.tsv"))
#     write_debug_tsv(bad_join_df, bad_fp)
#     stop(
#       paste0(
#         "[ERROR] Found rows with capture_rate_main_hit > 0 but failed cluster join.\n",
#         "See: ", bad_fp
#       )
#     )
#   }

#   # ---------- parse composition row by row ----------
#   comp_rows <- lapply(seq_len(nrow(merged_df)), function(i) {
#     rr <- merged_df[i, ]

#     parsed <- parse_composition(
#       top_subtypes = rr$top_subtypes,
#       subtype_count_json = rr$subtype_count_json
#     )

#     if (nrow(parsed) == 0) {
#       return(data.frame(
#         rep = rr$rep,
#         rep_label = rr$rep_label,
#         region = rr$region,
#         prefix = rr$prefix,
#         subtype = rr$subtype,
#         row_label = rr$row_label,
#         k_min = rr$k_min,
#         main_hit_cluster = rr$main_hit_cluster,
#         capture_rate_main_hit = rr$capture_rate_main_hit,
#         component_subtype = "__PARSE_FAILED__",
#         percent = NA_real_,
#         stringsAsFactors = FALSE
#       ))
#     }

#     parsed %>%
#       mutate(
#         rep = rr$rep,
#         rep_label = rr$rep_label,
#         region = rr$region,
#         prefix = rr$prefix,
#         subtype = rr$subtype,
#         row_label = rr$row_label,
#         k_min = rr$k_min,
#         main_hit_cluster = rr$main_hit_cluster,
#         capture_rate_main_hit = rr$capture_rate_main_hit
#       ) %>%
#       select(
#         rep, rep_label, region, prefix, subtype, row_label, k_min,
#         main_hit_cluster, capture_rate_main_hit, component_subtype, percent
#       )
#   })

#   comp_long <- bind_rows(comp_rows)

#   bad_parse_df <- comp_long %>%
#     filter(component_subtype == "__PARSE_FAILED__" | is.na(percent))

#   if (nrow(bad_parse_df) > 0) {
#     bad_fp <- file.path(OUTDIR, paste0(prefix_now, "_bad_parse.tsv"))
#     write_debug_tsv(bad_parse_df, bad_fp)
#     stop(
#       paste0(
#         "[ERROR] Found rows where composition parsing failed.\n",
#         "See: ", bad_fp
#       )
#     )
#   }

#   if (nrow(comp_long) > 0) {

#     all_components <- sort(unique(comp_long$component_subtype))

#     rep_keys <- focal_df %>%
#       select(rep, region, row_label, k_min, subtype, capture_rate_main_hit) %>%
#       distinct() %>%
#       mutate(
#         region = factor(region, levels = REGION_ORDER),
#         row_label = factor(row_label, levels = row_levels_rev),
#         rep = factor(rep, levels = REP_ORDER)
#       )

#     # rep-level full grid
#     comp_plot_df <- rep_keys %>%
#       tidyr::crossing(component_subtype = all_components) %>%
#       left_join(
#         comp_long %>%
#           mutate(
#             region = factor(region, levels = REGION_ORDER),
#             row_label = factor(row_label, levels = row_levels_rev),
#             rep = factor(rep, levels = REP_ORDER)
#           ) %>%
#           select(rep, region, row_label, k_min, subtype, component_subtype, percent),
#         by = c("rep", "region", "row_label", "k_min", "subtype", "component_subtype")
#       ) %>%
#       mutate(percent = ifelse(is.na(percent), 0, percent))

#     # focal check
#     focal_check_df <- comp_plot_df %>%
#       mutate(is_focal = component_subtype == subtype) %>%
#       group_by(rep, region, row_label, k_min, subtype, capture_rate_main_hit) %>%
#       summarise(
#         focal_percent = sum(percent[is_focal], na.rm = TRUE),
#         .groups = "drop"
#       )

#     write_debug_tsv(
#       focal_check_df,
#       file.path(OUTDIR, paste0(prefix_now, "_focal_check.tsv"))
#     )

#     bad_focal_df <- focal_check_df %>%
#       filter(capture_rate_main_hit > 0) %>%
#       filter(focal_percent <= 0)

#     if (nrow(bad_focal_df) > 0) {
#       bad_fp <- file.path(OUTDIR, paste0(prefix_now, "_bad_focal_zero.tsv"))
#       write_debug_tsv(bad_focal_df, bad_fp)
#       stop(
#         paste0(
#           "[ERROR] Found rows with capture_rate_main_hit > 0 but focal subtype percent == 0.\n",
#           "See: ", bad_fp
#         )
#       )
#     }

#     # region-level aggregation
#     comp_plot_df <- comp_plot_df %>%
#       group_by(region, row_label, k_min, subtype, component_subtype) %>%
#       summarise(percent = mean(percent, na.rm = TRUE), .groups = "drop") %>%
#       group_by(region, row_label, k_min, subtype) %>%
#       mutate(
#         total_percent = sum(percent, na.rm = TRUE),
#         percent = ifelse(total_percent > 0, 100 * percent / total_percent, 0)
#       ) %>%
#       ungroup() %>%
#       select(-total_percent) %>%
#       mutate(
#         row_label = factor(row_label, levels = row_levels_rev),
#         region = factor(region, levels = REGION_ORDER),
#         k_min = as.integer(k_min)
#       ) %>%
#       filter(!is.na(region))

#     # -------- manual stacking with geom_rect --------
#     comp_plot_df2 <- comp_plot_df %>%
#       filter(percent > 0) %>%
#       mutate(
#         is_focal = component_subtype == subtype
#       ) %>%
#       group_by(region, row_label, k_min, subtype) %>%
#       arrange(desc(is_focal), desc(percent), component_subtype, .by_group = TRUE) %>%
#       mutate(
#         ymin = lag(cumsum(percent), default = 0),
#         ymax = cumsum(percent)
#       ) %>%
#       ungroup()

#     # total check
#     bar_total_check <- comp_plot_df2 %>%
#       group_by(region, row_label, k_min, subtype) %>%
#       summarise(
#         sum_percent = max(ymax),
#         .groups = "drop"
#       )

#     write_debug_tsv(
#       bar_total_check,
#       file.path(OUTDIR, paste0(prefix_now, "_bar_total_check.tsv"))
#     )

#     bad_total_df <- bar_total_check %>%
#       filter(abs(sum_percent - 100) > 1e-6)

#     if (nrow(bad_total_df) > 0) {
#       bad_fp <- file.path(OUTDIR, paste0(prefix_now, "_bad_bar_total.tsv"))
#       write_debug_tsv(bad_total_df, bad_fp)
#       stop(
#         paste0(
#           "[ERROR] Found bars whose stacked total is not 100.\n",
#           "See: ", bad_fp
#         )
#       )
#     }

#     # x positions
#     k_levels <- sort(unique(one_kmin$k_min))

#     comp_plot_df2 <- comp_plot_df2 %>%
#       mutate(
#         x = match(k_min, k_levels),
#         xmin = x - 0.495,
#         xmax = x + 0.495
#       )

#     # 恢复原来的动态配色风格
#     fill_order <- comp_plot_df2 %>%
#       group_by(component_subtype) %>%
#       summarise(
#         total_pct = sum(ymax - ymin, na.rm = TRUE),
#         .groups = "drop"
#       ) %>%
#       arrange(desc(total_pct), component_subtype) %>%
#       pull(component_subtype)

#     comp_plot_df2 <- comp_plot_df2 %>%
#       mutate(component_subtype = factor(component_subtype, levels = fill_order))

#     fill_cols <- setNames(
#       hcl.colors(length(fill_order), palette = "Dynamic"),
#       fill_order
#     )

#     legend_breaks <- fill_order
#     legend_labels <- fill_order

#     p_comp <- ggplot() +
#       geom_hline(
#         yintercept = c(0, 25, 50, 75, 100),
#         color = "grey90",
#         linewidth = 0.35
#       ) +
#       geom_rect(
#         data = comp_plot_df2,
#         aes(
#           xmin = xmin,
#           xmax = xmax,
#           ymin = ymin,
#           ymax = ymax,
#           fill = component_subtype
#         ),
#         color = NA
#       ) +
#       facet_grid(region + row_label ~ ., scales = "free_y", space = "free_y", switch = "y") +
#       scale_fill_manual(
#         values = fill_cols,
#         breaks = legend_breaks,
#         labels = legend_labels,
#         name = "Cell type in main-hit cluster",
#         drop = FALSE
#       ) +
#       scale_x_continuous(
#         breaks = seq_along(k_levels),
#         labels = k_levels,
#         expand = expansion(mult = c(0, 0))
#       ) +
#       scale_y_continuous(
#         limits = c(0, 100),
#         breaks = c(0, 25, 50, 75, 100),
#         expand = c(0, 0)
#       ) +
#       labs(title = "Main-hit cluster composition", x = "k_min", y = NULL) +
#       theme_minimal(base_size = 12) +
#       theme(
#         plot.title = element_text(size = 16, face = "bold", hjust = 0.5),
#         axis.text.x = element_text(size = 8),
#         axis.text.y = element_blank(),
#         axis.title.x = element_text(face = "bold"),
#         strip.text.y.left = element_blank(),
#         strip.background = element_blank(),
#         panel.grid = element_blank(),
#         legend.position = "right"
#       )

#     final_plot <- p_capture + p_comp +
#       plot_layout(widths = c(1.0, 1.2), guides = "collect") &
#       theme(legend.position = "top")

#     out_png <- file.path(OUTDIR, paste0(prefix_now, "_capture_plus_mainhit_composition_ggplot2.png"))
#     save_plot_both(
#       final_plot,
#       out_png,
#       width = 18,
#       height = max(6, 0.45 * length(row_levels_rev) + 3.5),
#       save_pdf = SAVE_PDF
#     )
#   } else {
#     out_png <- file.path(OUTDIR, paste0(prefix_now, "_capture_plus_mainhit_composition_ggplot2.png"))
#     save_plot_both(
#       p_capture,
#       out_png,
#       width = 9,
#       height = max(6, 0.45 * length(row_levels_rev) + 3.5),
#       save_pdf = SAVE_PDF
#     )
#   }
# }

# cat("[DONE] plots written to: ", OUTDIR, "\n", sep = "")

# suppressPackageStartupMessages({
#   library(ggplot2)
#   library(dplyr)
#   library(tidyr)
#   library(stringr)
#   library(patchwork)
#   library(jsonlite)
# })

# # =========================
# # args
# # =========================
# parse_args <- function() {
#   args <- commandArgs(trailingOnly = TRUE)

#   defaults <- list(
#     "structure-dir" = NULL,
#     "outdir" = NULL,
#     "save-pdf" = FALSE
#   )

#   i <- 1
#   while (i <= length(args)) {
#     key <- args[[i]]

#     if (!startsWith(key, "--")) stop("Unexpected argument: ", key)
#     key2 <- substring(key, 3)

#     if (!(key2 %in% names(defaults))) stop("Unknown argument: ", key)

#     if (key2 == "save-pdf") {
#       defaults[[key2]] <- TRUE
#       i <- i + 1
#       next
#     }

#     if (i == length(args)) stop("Missing value for argument: ", key)

#     defaults[[key2]] <- args[[i + 1]]
#     i <- i + 2
#   }

#   if (is.null(defaults[["structure-dir"]])) stop("--structure-dir is required")
#   if (is.null(defaults[["outdir"]])) stop("--outdir is required")

#   defaults
# }

# ARGS <- parse_args()
# STRUCTURE_DIR <- ARGS[["structure-dir"]]
# OUTDIR <- ARGS[["outdir"]]
# SAVE_PDF <- isTRUE(ARGS[["save-pdf"]])

# if (!dir.exists(OUTDIR)) dir.create(OUTDIR, recursive = TRUE, showWarnings = FALSE)

# # =========================
# # constants
# # =========================
# REP_ORDER <- c(
#   "FTLD_MCX_Control_Concat_QC_harmony_filted",
#   "SALS_MCX_control_concat_QC_harmony",
#   "FTLD_PFC_Ctrl_Concat_QC_harmony_filted",
#   "SALS_PFC_control_concat_QC_harmony"
# )

# REP_LABEL <- c(
#   "FTLD_MCX_Control_Concat_QC_harmony_filted" = "FTLD-MCX",
#   "SALS_MCX_control_concat_QC_harmony" = "SALS-MCX",
#   "FTLD_PFC_Ctrl_Concat_QC_harmony_filted" = "FTLD-PFC",
#   "SALS_PFC_control_concat_QC_harmony" = "SALS-PFC"
# )

# PREFIX_ORDER <- c("In", "Ex")
# KMIN_RANGE <- 2:24

# STABLE_CLASS_MAP <- c(
#   "Cross_region_stable" = "Cross-region",
#   "MCX_specific_stable" = "MCX-specific",
#   "PFC_specific_stable" = "PFC-specific"
# )

# STABLE_CLASS_COLORS <- c(
#   "Cross-region" = "#20A486",
#   "MCX-specific" = "#E94F37",
#   "PFC-specific" = "#56B1C7"
# )

# save_plot_both <- function(p, out_png, width, height, save_pdf = FALSE) {
#   ggsave(out_png, p, width = width, height = height, dpi = 300, bg = "white")
#   if (save_pdf) {
#     ggsave(
#       sub("\\.png$", ".pdf", out_png),
#       p, width = width, height = height, bg = "white"
#     )
#   }
# }

# normalize_cluster_label <- function(x) {
#   if (is.na(x)) return("")
#   s <- str_trim(as.character(x))
#   if (s == "" || tolower(s) == "nan") return("")

#   num <- suppressWarnings(as.numeric(s))
#   if (!is.na(num)) {
#     if (abs(num - round(num)) < 1e-8) {
#       return(as.character(as.integer(round(num))))
#     } else {
#       return(as.character(num))
#     }
#   }
#   s
# }

# parse_top_subtypes <- function(x) {
#   if (is.na(x) || x == "") {
#     return(data.frame(component_subtype = character(), percent = numeric()))
#   }

#   parts <- unlist(strsplit(x, ";", fixed = TRUE))
#   parts <- parts[nzchar(parts)]

#   out <- lapply(parts, function(p) {
#     m <- str_match(p, "^(.*?):\\s*\\d+\\(([-0-9.]+)%\\)$")
#     if (all(is.na(m))) return(NULL)

#     data.frame(
#       component_subtype = str_trim(m[2]),
#       percent = as.numeric(m[3]),
#       stringsAsFactors = FALSE
#     )
#   })

#   out <- out[!vapply(out, is.null, logical(1))]
#   if (length(out) == 0) {
#     return(data.frame(component_subtype = character(), percent = numeric()))
#   }

#   out <- bind_rows(out)
#   s <- sum(out$percent, na.rm = TRUE)

#   if (s < 99.5) {
#     out <- bind_rows(
#       out,
#       data.frame(
#         component_subtype = "Other",
#         percent = max(0, 100 - s),
#         stringsAsFactors = FALSE
#       )
#     )
#   }

#   out
# }

# parse_json_counts_to_pct <- function(x) {
#   if (is.na(x) || x == "" || x == "{}") {
#     return(data.frame(component_subtype = character(), percent = numeric()))
#   }

#   obj <- tryCatch(jsonlite::fromJSON(x), error = function(e) NULL)
#   if (is.null(obj) || length(obj) == 0) {
#     return(data.frame(component_subtype = character(), percent = numeric()))
#   }

#   vals <- as.numeric(obj)
#   nms <- names(obj)

#   keep <- !is.na(vals) & vals > 0
#   vals <- vals[keep]
#   nms <- nms[keep]

#   if (length(vals) == 0) {
#     return(data.frame(component_subtype = character(), percent = numeric()))
#   }

#   pct <- 100 * vals / sum(vals)

#   data.frame(
#     component_subtype = nms,
#     percent = pct,
#     stringsAsFactors = FALSE
#   ) %>%
#     arrange(desc(percent), component_subtype)
# }

# parse_composition <- function(top_subtypes, subtype_count_json = NA_character_) {
#   out <- parse_json_counts_to_pct(subtype_count_json)
#   if (nrow(out) > 0) return(out)
#   parse_top_subtypes(top_subtypes)
# }

# # =========================
# # input
# # =========================
# kmin_fp <- file.path(STRUCTURE_DIR, "stable_subtype_kmin_structure.tsv")
# hit_fp  <- file.path(STRUCTURE_DIR, "stable_hit_cluster_summary.tsv")

# if (!file.exists(kmin_fp)) stop("Cannot find: ", kmin_fp)
# if (!file.exists(hit_fp)) stop("Cannot find: ", hit_fp)

# kmin_df <- read.delim(kmin_fp, check.names = FALSE)
# hit_df  <- read.delim(hit_fp,  check.names = FALSE)

# if (!("subtype_count_json" %in% colnames(hit_df))) {
#   hit_df$subtype_count_json <- NA_character_
# }

# kmin_df <- kmin_df %>%
#   mutate(
#     rep = as.character(rep),
#     prefix = as.character(prefix),
#     subtype = as.character(subtype),
#     stable_class = as.character(stable_class),
#     k_min = as.integer(k_min),
#     capture_rate_any_hit = as.numeric(capture_rate_any_hit),
#     main_hit_cluster = as.character(main_hit_cluster),
#     main_hit_cluster_norm = vapply(main_hit_cluster, normalize_cluster_label, character(1)),
#     rep_label = factor(REP_LABEL[rep], levels = unname(REP_LABEL))
#   )

# hit_df <- hit_df %>%
#   mutate(
#     rep = as.character(rep),
#     prefix = as.character(prefix),
#     k_min = as.integer(k_min),
#     cluster = as.character(cluster),
#     cluster_norm = vapply(cluster, normalize_cluster_label, character(1)),
#     rep_label = factor(REP_LABEL[rep], levels = unname(REP_LABEL)),
#     top_subtypes = as.character(top_subtypes),
#     subtype_count_json = as.character(subtype_count_json)
#   )

# # =========================
# # row order
# # =========================
# row_info <- kmin_df %>%
#   filter(stable_class %in% names(STABLE_CLASS_MAP)) %>%
#   group_by(prefix, subtype, stable_class) %>%
#   summarise(
#     mean_capture_any = mean(capture_rate_any_hit, na.rm = TRUE),
#     .groups = "drop"
#   ) %>%
#   mutate(
#     prefix = factor(prefix, levels = PREFIX_ORDER),
#     stable_class_disp = STABLE_CLASS_MAP[stable_class],
#     text_color = STABLE_CLASS_COLORS[stable_class_disp]
#   ) %>%
#   arrange(prefix, desc(mean_capture_any), subtype) %>%
#   mutate(
#     row_id = row_number(),
#     subtype_label = subtype
#   )

# if (nrow(row_info) == 0) stop("No stable subtype rows found.")

# n_rows <- nrow(row_info)

# prefix_blocks <- row_info %>%
#   mutate(prefix = as.character(prefix)) %>%
#   group_by(prefix) %>%
#   summarise(
#     y_mid = mean(row_id),
#     y_min = min(row_id) - 0.5,
#     y_max = max(row_id) + 0.5,
#     .groups = "drop"
#   )

# # =========================
# # join main-hit composition
# # =========================
# focal_df <- kmin_df %>%
#   filter(stable_class %in% names(STABLE_CLASS_MAP)) %>%
#   select(rep, rep_label, prefix, subtype, stable_class, k_min,
#          main_hit_cluster, main_hit_cluster_norm) %>%
#   left_join(
#     row_info %>% select(prefix, subtype, stable_class, row_id, subtype_label, stable_class_disp, text_color),
#     by = c("prefix", "subtype", "stable_class")
#   )

# hit_main_df <- hit_df %>%
#   select(rep, rep_label, prefix, k_min, cluster, cluster_norm, top_subtypes, subtype_count_json)

# merged_df <- focal_df %>%
#   left_join(
#     hit_main_df,
#     by = c("rep", "rep_label", "prefix", "k_min", "main_hit_cluster_norm" = "cluster_norm")
#   ) %>%
#   mutate(join_ok = !is.na(cluster))

# write.table(
#   merged_df,
#   file = file.path(OUTDIR, "composition_combined_merged_debug.tsv"),
#   sep = "\t", quote = FALSE, row.names = FALSE
# )

# # =========================
# # parse composition
# # =========================
# comp_rows <- lapply(seq_len(nrow(merged_df)), function(i) {
#   rr <- merged_df[i, ]

#   if (is.na(rr$main_hit_cluster_norm) || rr$main_hit_cluster_norm == "") return(NULL)
#   if (!isTRUE(rr$join_ok)) return(NULL)

#   parsed <- parse_composition(
#     top_subtypes = rr$top_subtypes,
#     subtype_count_json = rr$subtype_count_json
#   )

#   if (nrow(parsed) == 0) return(NULL)

#   parsed %>%
#     mutate(
#       rep = rr$rep,
#       rep_label = rr$rep_label,
#       prefix = rr$prefix,
#       subtype = rr$subtype,
#       stable_class = rr$stable_class,
#       stable_class_disp = rr$stable_class_disp,
#       row_id = rr$row_id,
#       subtype_label = rr$subtype_label,
#       text_color = rr$text_color,
#       k_min = rr$k_min
#     )
# })

# comp_long <- bind_rows(comp_rows)

# if (nrow(comp_long) == 0) stop("No composition data parsed.")

# # =========================
# # manual stacking
# # =========================
# comp_plot_df <- comp_long %>%
#   filter(percent > 0) %>%
#   mutate(
#     rep_label = factor(as.character(rep_label), levels = unname(REP_LABEL)),
#     component_subtype = as.character(component_subtype),
#     is_focal = component_subtype == subtype
#   ) %>%
#   group_by(rep_label, row_id, subtype, k_min) %>%
#   arrange(desc(is_focal), desc(percent), component_subtype, .by_group = TRUE) %>%
#   mutate(
#     pct_prev = lag(cumsum(percent), default = 0),
#     pct_now  = cumsum(percent),
#     ymin = row_id - 0.45 + 0.9 * (pct_prev / 100),
#     ymax = row_id - 0.45 + 0.9 * (pct_now  / 100),
#     xmin = k_min - 0.48,
#     xmax = k_min + 0.48
#   ) %>%
#   ungroup()

# bar_total_check <- comp_plot_df %>%
#   group_by(rep_label, row_id, subtype, k_min) %>%
#   summarise(
#     sum_percent = max(pct_now),
#     .groups = "drop"
#   )

# write.table(
#   bar_total_check,
#   file = file.path(OUTDIR, "composition_combined_bar_total_check.tsv"),
#   sep = "\t", quote = FALSE, row.names = FALSE
# )

# # =========================
# # background cells to remove ugly white gaps
# # =========================
# bg_grid <- expand.grid(
#   row_id = row_info$row_id,
#   rep_label = factor(unname(REP_LABEL), levels = unname(REP_LABEL)),
#   k_min = KMIN_RANGE,
#   stringsAsFactors = FALSE
# ) %>%
#   mutate(
#     xmin = k_min - 0.48,
#     xmax = k_min + 0.48,
#     ymin = row_id - 0.45,
#     ymax = row_id + 0.45
#   )

# # =========================
# # colors for composition
# # =========================
# fill_order <- comp_plot_df %>%
#   group_by(component_subtype) %>%
#   summarise(total_pct = sum(percent, na.rm = TRUE), .groups = "drop") %>%
#   arrange(desc(total_pct), component_subtype) %>%
#   pull(component_subtype)

# comp_plot_df <- comp_plot_df %>%
#   mutate(component_subtype = factor(component_subtype, levels = fill_order))

# fill_cols <- setNames(
#   hcl.colors(length(fill_order), palette = "Dynamic"),
#   fill_order
# )

# # =========================
# # left class plot
# # =========================
# p_class <- ggplot() +
#   geom_rect(
#     data = prefix_blocks,
#     aes(xmin = 0.00, xmax = 0.22, ymin = y_min, ymax = y_max),
#     fill = "grey92", color = NA
#   ) +
#   geom_text(
#     data = prefix_blocks,
#     aes(x = 0.11, y = y_mid, label = prefix),
#     fontface = "bold", size = 6
#   ) +
#   geom_rect(
#     data = row_info,
#     aes(
#       xmin = 0.28, xmax = 0.96,
#       ymin = row_id - 0.48,
#       ymax = row_id + 0.48,
#       fill = stable_class_disp
#     ),
#     color = NA
#   ) +
#   scale_fill_manual(
#     values = STABLE_CLASS_COLORS,
#     name = "Stable class",
#     drop = FALSE
#   ) +
#   scale_y_reverse(limits = c(n_rows + 0.5, 0.5), expand = c(0, 0)) +
#   xlim(0, 1) +
#   labs(title = "Class") +
#   theme_void(base_size = 12) +
#   theme(
#     plot.title = element_text(size = 18, face = "bold", hjust = 0.5)
#   )

# # =========================
# # left subtype label plot
# # =========================
# p_label <- ggplot(row_info, aes(x = 0, y = row_id, label = subtype_label)) +
#   geom_text(
#     aes(color = stable_class_disp),
#     hjust = 0, fontface = "bold", size = 6, show.legend = FALSE
#   ) +
#   scale_color_manual(values = STABLE_CLASS_COLORS, drop = FALSE) +
#   scale_y_reverse(limits = c(n_rows + 0.5, 0.5), expand = c(0, 0)) +
#   xlim(0, 1.05) +
#   theme_void(base_size = 12)

# # =========================
# # main composition plot
# # =========================
# p_comp <- ggplot() +
#   geom_rect(
#     data = bg_grid,
#     aes(
#       xmin = xmin, xmax = xmax,
#       ymin = ymin, ymax = ymax
#     ),
#     fill = "grey96",
#     color = NA
#   ) +
#   geom_hline(
#     yintercept = seq(0.5, n_rows + 0.5, by = 1),
#     color = "white",
#     linewidth = 0.7
#   ) +
#   geom_rect(
#     data = comp_plot_df,
#     aes(
#       xmin = xmin, xmax = xmax,
#       ymin = ymin, ymax = ymax,
#       fill = component_subtype
#     ),
#     color = NA
#   ) +
#   facet_grid(. ~ rep_label) +
#   scale_fill_manual(
#     values = fill_cols,
#     breaks = fill_order,
#     labels = fill_order,
#     name = "Cell type in main-hit cluster",
#     drop = FALSE
#   ) +
#   scale_x_continuous(
#     breaks = KMIN_RANGE,
#     labels = KMIN_RANGE,
#     limits = c(min(KMIN_RANGE) - 0.5, max(KMIN_RANGE) + 0.5),
#     expand = c(0, 0)
#   ) +
#   scale_y_reverse(
#     limits = c(n_rows + 0.5, 0.5),
#     expand = c(0, 0)
#   ) +
#   labs(
#     title = "In + Ex combined: main-hit cluster composition by rep",
#     x = "k_min",
#     y = NULL
#   ) +
#   theme_minimal(base_size = 12) +
#   theme(
#     plot.title = element_text(size = 22, face = "bold", hjust = 0.5),
#     axis.text.x = element_text(size = 11),
#     axis.text.y = element_blank(),
#     axis.title.x = element_text(size = 16, face = "bold"),
#     panel.grid = element_blank(),
#     panel.background = element_rect(fill = "grey98", color = NA),
#     strip.text.x = element_text(size = 16, face = "bold"),
#     strip.background = element_rect(fill = "grey95", color = NA),
#     legend.position = "top",
#     legend.title = element_text(size = 14),
#     legend.text = element_text(size = 12)
#   )

# # =========================
# # combine
# # =========================
# final_plot <- p_class + p_label + p_comp +
#   plot_layout(widths = c(0.55, 2.3, 8.7), guides = "collect") &
#   theme(legend.position = "top")

# out_png <- file.path(OUTDIR, "In_Ex_combined_mainhit_composition_by_rep_improved.png")
# save_plot_both(
#   final_plot,
#   out_png,
#   width = 24,
#   height = max(8, 0.9 * n_rows + 2.5),
#   save_pdf = SAVE_PDF
# )

# cat("[DONE] plot written to: ", out_png, "\n", sep = "")
# suppressPackageStartupMessages({
#   library(ggplot2)
#   library(dplyr)
#   library(tidyr)
#   library(stringr)
#   library(patchwork)
#   library(jsonlite)
# })

# # =========================
# # args
# # =========================
# parse_args <- function() {
#   args <- commandArgs(trailingOnly = TRUE)

#   defaults <- list(
#     "structure-dir" = NULL,
#     "outdir" = NULL,
#     "save-pdf" = FALSE
#   )

#   i <- 1
#   while (i <= length(args)) {
#     key <- args[[i]]

#     if (!startsWith(key, "--")) stop("Unexpected argument: ", key)
#     key2 <- substring(key, 3)

#     if (!(key2 %in% names(defaults))) stop("Unknown argument: ", key)

#     if (key2 == "save-pdf") {
#       defaults[[key2]] <- TRUE
#       i <- i + 1
#       next
#     }

#     if (i == length(args)) stop("Missing value for argument: ", key)

#     defaults[[key2]] <- args[[i + 1]]
#     i <- i + 2
#   }

#   if (is.null(defaults[["structure-dir"]])) stop("--structure-dir is required")
#   if (is.null(defaults[["outdir"]])) stop("--outdir is required")

#   defaults
# }

# ARGS <- parse_args()
# STRUCTURE_DIR <- ARGS[["structure-dir"]]
# OUTDIR <- ARGS[["outdir"]]
# SAVE_PDF <- isTRUE(ARGS[["save-pdf"]])

# if (!dir.exists(OUTDIR)) dir.create(OUTDIR, recursive = TRUE, showWarnings = FALSE)

# # =========================
# # constants
# # =========================
# REP_ORDER <- c(
#   "FTLD_MCX_Control_Concat_QC_harmony_filted",
#   "SALS_MCX_control_concat_QC_harmony",
#   "FTLD_PFC_Ctrl_Concat_QC_harmony_filted",
#   "SALS_PFC_control_concat_QC_harmony"
# )

# REP_LABEL <- c(
#   "FTLD_MCX_Control_Concat_QC_harmony_filted" = "FTLD-MCX",
#   "SALS_MCX_control_concat_QC_harmony" = "SALS-MCX",
#   "FTLD_PFC_Ctrl_Concat_QC_harmony_filted" = "FTLD-PFC",
#   "SALS_PFC_control_concat_QC_harmony" = "SALS-PFC"
# )

# PREFIX_ORDER <- c("In", "Ex")
# KMIN_RANGE <- 2:24

# STABLE_CLASS_MAP <- c(
#   "Cross_region_stable" = "Cross-region",
#   "MCX_specific_stable" = "MCX-specific",
#   "PFC_specific_stable" = "PFC-specific"
# )

# STABLE_CLASS_COLORS <- c(
#   "Cross-region" = "#20A486",
#   "MCX-specific" = "#E94F37",
#   "PFC-specific" = "#56B1C7"
# )

# save_plot_both <- function(p, out_png, width, height, save_pdf = FALSE) {
#   ggsave(out_png, p, width = width, height = height, dpi = 300, bg = "white")
#   if (save_pdf) {
#     ggsave(
#       sub("\\.png$", ".pdf", out_png),
#       p, width = width, height = height, bg = "white"
#     )
#   }
# }

# normalize_cluster_label <- function(x) {
#   if (is.na(x)) return("")
#   s <- str_trim(as.character(x))
#   if (s == "" || tolower(s) == "nan") return("")

#   num <- suppressWarnings(as.numeric(s))
#   if (!is.na(num)) {
#     if (abs(num - round(num)) < 1e-8) {
#       return(as.character(as.integer(round(num))))
#     } else {
#       return(as.character(num))
#     }
#   }
#   s
# }

# parse_top_subtypes <- function(x) {
#   if (is.na(x) || x == "") {
#     return(data.frame(component_subtype = character(), percent = numeric()))
#   }

#   parts <- unlist(strsplit(x, ";", fixed = TRUE))
#   parts <- parts[nzchar(parts)]

#   out <- lapply(parts, function(p) {
#     m <- str_match(p, "^(.*?):\\s*\\d+\\(([-0-9.]+)%\\)$")
#     if (all(is.na(m))) return(NULL)

#     data.frame(
#       component_subtype = str_trim(m[2]),
#       percent = as.numeric(m[3]),
#       stringsAsFactors = FALSE
#     )
#   })

#   out <- out[!vapply(out, is.null, logical(1))]
#   if (length(out) == 0) {
#     return(data.frame(component_subtype = character(), percent = numeric()))
#   }

#   out <- bind_rows(out)
#   s <- sum(out$percent, na.rm = TRUE)

#   if (s < 99.5) {
#     out <- bind_rows(
#       out,
#       data.frame(
#         component_subtype = "Other",
#         percent = max(0, 100 - s),
#         stringsAsFactors = FALSE
#       )
#     )
#   }

#   out
# }

# parse_json_counts_to_pct <- function(x) {
#   if (is.na(x) || x == "" || x == "{}") {
#     return(data.frame(component_subtype = character(), percent = numeric()))
#   }

#   obj <- tryCatch(jsonlite::fromJSON(x), error = function(e) NULL)
#   if (is.null(obj) || length(obj) == 0) {
#     return(data.frame(component_subtype = character(), percent = numeric()))
#   }

#   vals <- as.numeric(obj)
#   nms <- names(obj)

#   keep <- !is.na(vals) & vals > 0
#   vals <- vals[keep]
#   nms <- nms[keep]

#   if (length(vals) == 0) {
#     return(data.frame(component_subtype = character(), percent = numeric()))
#   }

#   pct <- 100 * vals / sum(vals)

#   data.frame(
#     component_subtype = nms,
#     percent = pct,
#     stringsAsFactors = FALSE
#   ) %>%
#     arrange(desc(percent), component_subtype)
# }

# parse_composition <- function(top_subtypes, subtype_count_json = NA_character_) {
#   out <- parse_json_counts_to_pct(subtype_count_json)
#   if (nrow(out) > 0) return(out)
#   parse_top_subtypes(top_subtypes)
# }

# # =========================
# # input
# # =========================
# kmin_fp <- file.path(STRUCTURE_DIR, "stable_subtype_kmin_structure.tsv")
# hit_fp  <- file.path(STRUCTURE_DIR, "stable_hit_cluster_summary.tsv")

# if (!file.exists(kmin_fp)) stop("Cannot find: ", kmin_fp)
# if (!file.exists(hit_fp)) stop("Cannot find: ", hit_fp)

# kmin_df <- read.delim(kmin_fp, check.names = FALSE)
# hit_df  <- read.delim(hit_fp, check.names = FALSE)

# if (!("subtype_count_json" %in% colnames(hit_df))) {
#   hit_df$subtype_count_json <- NA_character_
# }

# kmin_df <- kmin_df %>%
#   mutate(
#     rep = as.character(rep),
#     prefix = as.character(prefix),
#     subtype = as.character(subtype),
#     stable_class = as.character(stable_class),
#     k_min = as.integer(k_min),
#     capture_rate_any_hit = as.numeric(capture_rate_any_hit),
#     main_hit_cluster = as.character(main_hit_cluster),
#     main_hit_cluster_norm = vapply(main_hit_cluster, normalize_cluster_label, character(1)),
#     rep_label = factor(REP_LABEL[rep], levels = unname(REP_LABEL))
#   )

# hit_df <- hit_df %>%
#   mutate(
#     rep = as.character(rep),
#     prefix = as.character(prefix),
#     k_min = as.integer(k_min),
#     cluster = as.character(cluster),
#     cluster_norm = vapply(cluster, normalize_cluster_label, character(1)),
#     rep_label = factor(REP_LABEL[rep], levels = unname(REP_LABEL)),
#     top_subtypes = as.character(top_subtypes),
#     subtype_count_json = as.character(subtype_count_json)
#   )

# # =========================
# # overall row info
# # =========================
# row_info_all <- kmin_df %>%
#   filter(stable_class %in% names(STABLE_CLASS_MAP)) %>%
#   group_by(prefix, subtype, stable_class) %>%
#   summarise(
#     mean_capture_any = mean(capture_rate_any_hit, na.rm = TRUE),
#     .groups = "drop"
#   ) %>%
#   mutate(
#     prefix = factor(prefix, levels = PREFIX_ORDER),
#     stable_class_disp = STABLE_CLASS_MAP[stable_class]
#   )

# if (nrow(row_info_all) == 0) stop("No stable subtype rows found.")

# # =========================
# # join main-hit composition for all stable rows
# # =========================
# focal_df <- kmin_df %>%
#   filter(stable_class %in% names(STABLE_CLASS_MAP)) %>%
#   select(rep, rep_label, prefix, subtype, stable_class, k_min,
#          main_hit_cluster, main_hit_cluster_norm)

# hit_main_df <- hit_df %>%
#   select(rep, rep_label, prefix, k_min, cluster, cluster_norm, top_subtypes, subtype_count_json)

# merged_df <- focal_df %>%
#   left_join(
#     hit_main_df,
#     by = c("rep", "rep_label", "prefix", "k_min", "main_hit_cluster_norm" = "cluster_norm")
#   ) %>%
#   mutate(join_ok = !is.na(cluster))

# write.table(
#   merged_df,
#   file = file.path(OUTDIR, "composition_by_stable_class_merged_debug.tsv"),
#   sep = "\t", quote = FALSE, row.names = FALSE
# )

# # =========================
# # parse composition for all stable rows
# # =========================
# comp_rows <- lapply(seq_len(nrow(merged_df)), function(i) {
#   rr <- merged_df[i, ]

#   if (is.na(rr$main_hit_cluster_norm) || rr$main_hit_cluster_norm == "") return(NULL)
#   if (!isTRUE(rr$join_ok)) return(NULL)

#   parsed <- parse_composition(
#     top_subtypes = rr$top_subtypes,
#     subtype_count_json = rr$subtype_count_json
#   )

#   if (nrow(parsed) == 0) return(NULL)

#   parsed %>%
#     mutate(
#       rep = rr$rep,
#       rep_label = rr$rep_label,
#       prefix = rr$prefix,
#       subtype = rr$subtype,
#       stable_class = rr$stable_class,
#       stable_class_disp = STABLE_CLASS_MAP[rr$stable_class],
#       k_min = rr$k_min
#     )
# })

# comp_long_all <- bind_rows(comp_rows)
# if (nrow(comp_long_all) == 0) stop("No composition data parsed.")

# # 只保留真正用到的 component_subtype
# fill_order_global <- comp_long_all %>%
#   filter(percent > 0) %>%
#   group_by(component_subtype) %>%
#   summarise(total_pct = sum(percent, na.rm = TRUE), .groups = "drop") %>%
#   arrange(desc(total_pct), component_subtype) %>%
#   pull(component_subtype)

# # 改成区分度更强的配色
# fill_cols_global <- setNames(
#   grDevices::hcl.colors(length(fill_order_global), palette = "Dark 3"),
#   fill_order_global
# )

# # =========================
# # helper to build one block
# # =========================
# build_block_plot <- function(
#   block_title,
#   stable_class_keys,
#   rep_labels_keep,
#   show_comp_legend = FALSE
# ) {
#   row_info_block <- row_info_all %>%
#     filter(stable_class %in% stable_class_keys) %>%
#     arrange(prefix, desc(mean_capture_any), subtype) %>%
#     mutate(
#       row_id = row_number(),
#       subtype_label = subtype
#     )

#   if (nrow(row_info_block) == 0) return(NULL)

#   n_rows <- nrow(row_info_block)

#   prefix_blocks <- row_info_block %>%
#     mutate(prefix = as.character(prefix)) %>%
#     group_by(prefix) %>%
#     summarise(
#       y_mid = mean(row_id),
#       y_min = min(row_id) - 0.5,
#       y_max = max(row_id) + 0.5,
#       .groups = "drop"
#     )

#   comp_block <- comp_long_all %>%
#     filter(rep_label %in% rep_labels_keep, stable_class %in% stable_class_keys) %>%
#     inner_join(
#       row_info_block %>%
#         select(prefix, subtype, stable_class, stable_class_disp, row_id, subtype_label),
#       by = c("prefix", "subtype", "stable_class", "stable_class_disp")
#     )

#   # hand stacking
#   comp_plot_df <- comp_block %>%
#     filter(percent > 0, component_subtype %in% fill_order_global) %>%
#     mutate(
#       rep_label = factor(as.character(rep_label), levels = rep_labels_keep),
#       component_subtype = factor(as.character(component_subtype), levels = fill_order_global),
#       is_focal = as.character(component_subtype) == subtype
#     ) %>%
#     group_by(rep_label, row_id, subtype, k_min) %>%
#     arrange(desc(is_focal), desc(percent), component_subtype, .by_group = TRUE) %>%
#     mutate(
#       pct_prev = lag(cumsum(percent), default = 0),
#       pct_now  = cumsum(percent),
#       ymin = row_id - 0.45 + 0.9 * (pct_prev / 100),
#       ymax = row_id - 0.45 + 0.9 * (pct_now / 100),
#       xmin = k_min - 0.48,
#       xmax = k_min + 0.48
#     ) %>%
#     ungroup()

#   bar_total_check <- comp_plot_df %>%
#     group_by(rep_label, row_id, subtype, k_min) %>%
#     summarise(sum_percent = max(pct_now), .groups = "drop")

#   write.table(
#     bar_total_check,
#     file = file.path(
#       OUTDIR,
#       paste0("bar_total_check_", gsub("[^A-Za-z0-9]+", "_", block_title), ".tsv")
#     ),
#     sep = "\t", quote = FALSE, row.names = FALSE
#   )

#   # class panel
#   p_class <- ggplot() +
#     geom_rect(
#       data = prefix_blocks,
#       aes(xmin = 0.00, xmax = 0.22, ymin = y_min, ymax = y_max),
#       fill = "grey92", color = NA
#     ) +
#     geom_text(
#       data = prefix_blocks,
#       aes(x = 0.11, y = y_mid, label = prefix),
#       fontface = "bold", size = 6
#     ) +
#     geom_rect(
#       data = row_info_block,
#       aes(
#         xmin = 0.28, xmax = 0.96,
#         ymin = row_id - 0.48,
#         ymax = row_id + 0.48,
#         fill = stable_class_disp
#       ),
#       color = NA
#     ) +
#     scale_fill_manual(
#       values = STABLE_CLASS_COLORS,
#       drop = FALSE
#     ) +
#     scale_y_reverse(limits = c(n_rows + 0.5, 0.5), expand = c(0, 0)) +
#     xlim(0, 1) +
#     labs(title = if (show_comp_legend) "Class" else NULL) +
#     theme_void(base_size = 12) +
#     theme(
#       plot.title = element_text(size = 18, face = "bold", hjust = 0.5),
#       legend.position = "none"
#     )

#   # subtype labels
#   p_label <- ggplot(row_info_block, aes(x = 0, y = row_id, label = subtype_label)) +
#     geom_text(
#       aes(color = stable_class_disp),
#       hjust = 0, fontface = "bold", size = 6, show.legend = FALSE
#     ) +
#     scale_color_manual(values = STABLE_CLASS_COLORS, drop = FALSE) +
#     scale_y_reverse(limits = c(n_rows + 0.5, 0.5), expand = c(0, 0)) +
#     xlim(0, 1.05) +
#     theme_void(base_size = 12)

#   # composition panel
#   p_comp <- ggplot() +
#     geom_hline(
#       yintercept = seq(0.5, n_rows + 0.5, by = 1),
#       color = "white",
#       linewidth = 0.7
#     ) +
#     geom_rect(
#       data = comp_plot_df,
#       aes(
#         xmin = xmin, xmax = xmax,
#         ymin = ymin, ymax = ymax,
#         fill = component_subtype
#       ),
#       color = NA
#     ) +
#     facet_grid(. ~ rep_label) +
#     scale_fill_manual(
#       values = fill_cols_global,
#       breaks = fill_order_global,
#       labels = fill_order_global,
#       name = NULL,
#       drop = TRUE
#     ) +
#     scale_x_continuous(
#       breaks = KMIN_RANGE,
#       labels = KMIN_RANGE,
#       limits = c(min(KMIN_RANGE) - 0.5, max(KMIN_RANGE) + 0.5),
#       expand = c(0, 0)
#     ) +
#     scale_y_reverse(
#       limits = c(n_rows + 0.5, 0.5),
#       expand = c(0, 0)
#     ) +
#     labs(x = "k_min", y = NULL) +
#     guides(
#       fill = guide_legend(
#         title = NULL,
#         nrow = 4,
#         byrow = TRUE,
#         keywidth = grid::unit(0.45, "cm"),
#         keyheight = grid::unit(0.45, "cm"),
#         override.aes = list(alpha = 1)
#       )
#     ) +
#     theme_minimal(base_size = 12) +
#     theme(
#       axis.text.x = element_text(size = 11),
#       axis.text.y = element_blank(),
#       axis.title.x = element_text(size = 16, face = "bold"),
#       panel.grid = element_blank(),
#       panel.background = element_rect(fill = "grey98", color = NA),
#       strip.text.x = element_text(size = 16, face = "bold"),
#       strip.background = element_rect(fill = "grey95", color = NA),
#       legend.position = if (show_comp_legend) "top" else "none",
#       legend.text = element_text(size = 12),
#       legend.key.width = grid::unit(0.45, "cm"),
#       legend.key.height = grid::unit(0.45, "cm"),
#       legend.box = "vertical"
#     )

#   block_plot <- p_class + p_label + p_comp +
#     plot_layout(widths = c(0.55, 2.3, 8.7)) +
#     plot_annotation(
#       title = block_title,
#       theme = theme(
#         plot.title = element_text(size = 18, face = "bold", hjust = 0.5)
#       )
#     )

#   list(plot = block_plot, nrows = n_rows)
# }

# # =========================
# # build three blocks
# # =========================
# block_mcx <- build_block_plot(
#   block_title = "MCX-specific stable",
#   stable_class_keys = "MCX_specific_stable",
#   rep_labels_keep = c("FTLD-MCX", "SALS-MCX"),
#   show_comp_legend = TRUE
# )

# block_pfc <- build_block_plot(
#   block_title = "PFC-specific stable",
#   stable_class_keys = "PFC_specific_stable",
#   rep_labels_keep = c("FTLD-PFC", "SALS-PFC"),
#   show_comp_legend = FALSE
# )

# block_cross <- build_block_plot(
#   block_title = "Cross-region stable",
#   stable_class_keys = "Cross_region_stable",
#   rep_labels_keep = c("FTLD-MCX", "SALS-MCX", "FTLD-PFC", "SALS-PFC"),
#   show_comp_legend = FALSE
# )

# blocks <- list(block_mcx, block_pfc, block_cross)
# blocks <- blocks[!vapply(blocks, is.null, logical(1))]

# if (length(blocks) == 0) stop("No non-empty blocks to plot.")

# block_plots <- lapply(blocks, `[[`, "plot")
# block_heights <- vapply(blocks, `[[`, numeric(1), "nrows")

# final_plot <- wrap_plots(block_plots, ncol = 1, heights = block_heights) +
#   plot_layout(guides = "collect") +
#   plot_annotation(
#     title = "In + Ex combined: main-hit cluster composition by stable class and disease",
#     theme = theme(
#       plot.title = element_text(size = 24, face = "bold", hjust = 0.5)
#     )
#   ) &
#   theme(legend.position = "top")

# out_png <- file.path(OUTDIR, "In_Ex_mainhit_composition_by_stable_class_blocks_cleanlegend_usedonly.png")
# save_plot_both(
#   final_plot,
#   out_png,
#   width = 24,
#   height = max(10, 1.1 * sum(block_heights) + 5),
#   save_pdf = SAVE_PDF
# )

# cat("[DONE] plot written to: ", out_png, "\n", sep = "")
# suppressPackageStartupMessages({
#   library(ggplot2)
#   library(dplyr)
#   library(tidyr)
#   library(stringr)
#   library(patchwork)
#   library(jsonlite)
# })

# # =========================
# # args
# # =========================
# parse_args <- function() {
#   args <- commandArgs(trailingOnly = TRUE)

#   defaults <- list(
#     "structure-dir" = NULL,
#     "outdir" = NULL,
#     "save-pdf" = FALSE
#   )

#   i <- 1
#   while (i <= length(args)) {
#     key <- args[[i]]

#     if (!startsWith(key, "--")) stop("Unexpected argument: ", key)
#     key2 <- substring(key, 3)

#     if (!(key2 %in% names(defaults))) stop("Unknown argument: ", key)

#     if (key2 == "save-pdf") {
#       defaults[[key2]] <- TRUE
#       i <- i + 1
#       next
#     }

#     if (i == length(args)) stop("Missing value for argument: ", key)

#     defaults[[key2]] <- args[[i + 1]]
#     i <- i + 2
#   }

#   if (is.null(defaults[["structure-dir"]])) stop("--structure-dir is required")
#   if (is.null(defaults[["outdir"]])) stop("--outdir is required")

#   defaults
# }

# ARGS <- parse_args()
# STRUCTURE_DIR <- ARGS[["structure-dir"]]
# OUTDIR <- ARGS[["outdir"]]
# SAVE_PDF <- isTRUE(ARGS[["save-pdf"]])

# if (!dir.exists(OUTDIR)) dir.create(OUTDIR, recursive = TRUE, showWarnings = FALSE)

# # =========================
# # constants
# # =========================
# REP_ORDER <- c(
#   "FTLD_MCX_Control_Concat_QC_harmony_filted",
#   "SALS_MCX_control_concat_QC_harmony",
#   "FTLD_PFC_Ctrl_Concat_QC_harmony_filted",
#   "SALS_PFC_control_concat_QC_harmony"
# )

# REP_LABEL <- c(
#   "FTLD_MCX_Control_Concat_QC_harmony_filted" = "FTLD-MCX",
#   "SALS_MCX_control_concat_QC_harmony" = "SALS-MCX",
#   "FTLD_PFC_Ctrl_Concat_QC_harmony_filted" = "FTLD-PFC",
#   "SALS_PFC_control_concat_QC_harmony" = "SALS-PFC"
# )

# PREFIX_ORDER <- c("In", "Ex")
# KMIN_RANGE <- 2:24

# STABLE_CLASS_MAP <- c(
#   "Cross_region_stable" = "Cross-region",
#   "MCX_specific_stable" = "MCX-specific",
#   "PFC_specific_stable" = "PFC-specific"
# )

# STABLE_CLASS_COLORS <- c(
#   "Cross-region" = "#20A486",
#   "MCX-specific" = "#E94F37",
#   "PFC-specific" = "#56B1C7"
# )

# save_plot_both <- function(p, out_png, width, height, save_pdf = FALSE) {
#   ggsave(out_png, p, width = width, height = height, dpi = 300, bg = "white")
#   if (save_pdf) {
#     ggsave(
#       sub("\\.png$", ".pdf", out_png),
#       p, width = width, height = height, bg = "white"
#     )
#   }
# }

# normalize_cluster_label <- function(x) {
#   if (is.na(x)) return("")
#   s <- str_trim(as.character(x))
#   if (s == "" || tolower(s) == "nan") return("")

#   num <- suppressWarnings(as.numeric(s))
#   if (!is.na(num)) {
#     if (abs(num - round(num)) < 1e-8) {
#       return(as.character(as.integer(round(num))))
#     } else {
#       return(as.character(num))
#     }
#   }
#   s
# }

# parse_top_subtypes <- function(x) {
#   if (is.na(x) || x == "") {
#     return(data.frame(component_subtype = character(), percent = numeric()))
#   }

#   parts <- unlist(strsplit(x, ";", fixed = TRUE))
#   parts <- parts[nzchar(parts)]

#   out <- lapply(parts, function(p) {
#     m <- str_match(p, "^(.*?):\\s*\\d+\\(([-0-9.]+)%\\)$")
#     if (all(is.na(m))) return(NULL)

#     data.frame(
#       component_subtype = str_trim(m[2]),
#       percent = as.numeric(m[3]),
#       stringsAsFactors = FALSE
#     )
#   })

#   out <- out[!vapply(out, is.null, logical(1))]
#   if (length(out) == 0) {
#     return(data.frame(component_subtype = character(), percent = numeric()))
#   }

#   out <- bind_rows(out)
#   s <- sum(out$percent, na.rm = TRUE)

#   if (s < 99.5) {
#     out <- bind_rows(
#       out,
#       data.frame(
#         component_subtype = "Other",
#         percent = max(0, 100 - s),
#         stringsAsFactors = FALSE
#       )
#     )
#   }

#   out
# }

# parse_json_counts_to_pct <- function(x) {
#   if (is.na(x) || x == "" || x == "{}") {
#     return(data.frame(component_subtype = character(), percent = numeric()))
#   }

#   obj <- tryCatch(jsonlite::fromJSON(x), error = function(e) NULL)
#   if (is.null(obj) || length(obj) == 0) {
#     return(data.frame(component_subtype = character(), percent = numeric()))
#   }

#   vals <- as.numeric(obj)
#   nms <- names(obj)

#   keep <- !is.na(vals) & vals > 0
#   vals <- vals[keep]
#   nms <- nms[keep]

#   if (length(vals) == 0) {
#     return(data.frame(component_subtype = character(), percent = numeric()))
#   }

#   pct <- 100 * vals / sum(vals)

#   data.frame(
#     component_subtype = nms,
#     percent = pct,
#     stringsAsFactors = FALSE
#   ) %>%
#     arrange(desc(percent), component_subtype)
# }

# parse_composition <- function(top_subtypes, subtype_count_json = NA_character_) {
#   out <- parse_json_counts_to_pct(subtype_count_json)
#   if (nrow(out) > 0) return(out)
#   parse_top_subtypes(top_subtypes)
# }

# # =========================
# # input
# # =========================
# kmin_fp <- file.path(STRUCTURE_DIR, "stable_subtype_kmin_structure.tsv")
# hit_fp  <- file.path(STRUCTURE_DIR, "stable_hit_cluster_summary.tsv")

# if (!file.exists(kmin_fp)) stop("Cannot find: ", kmin_fp)
# if (!file.exists(hit_fp)) stop("Cannot find: ", hit_fp)

# kmin_df <- read.delim(kmin_fp, check.names = FALSE)
# hit_df  <- read.delim(hit_fp, check.names = FALSE)

# if (!("subtype_count_json" %in% colnames(hit_df))) {
#   hit_df$subtype_count_json <- NA_character_
# }

# kmin_df <- kmin_df %>%
#   mutate(
#     rep = as.character(rep),
#     prefix = as.character(prefix),
#     subtype = as.character(subtype),
#     stable_class = as.character(stable_class),
#     k_min = as.integer(k_min),
#     capture_rate_any_hit = as.numeric(capture_rate_any_hit),
#     main_hit_cluster = as.character(main_hit_cluster),
#     main_hit_cluster_norm = vapply(main_hit_cluster, normalize_cluster_label, character(1)),
#     rep_label = factor(REP_LABEL[rep], levels = unname(REP_LABEL))
#   )

# hit_df <- hit_df %>%
#   mutate(
#     rep = as.character(rep),
#     prefix = as.character(prefix),
#     k_min = as.integer(k_min),
#     cluster = as.character(cluster),
#     cluster_norm = vapply(cluster, normalize_cluster_label, character(1)),
#     rep_label = factor(REP_LABEL[rep], levels = unname(REP_LABEL)),
#     top_subtypes = as.character(top_subtypes),
#     subtype_count_json = as.character(subtype_count_json)
#   )

# # =========================
# # overall row info
# # =========================
# row_info_all <- kmin_df %>%
#   filter(stable_class %in% names(STABLE_CLASS_MAP)) %>%
#   group_by(prefix, subtype, stable_class) %>%
#   summarise(
#     mean_capture_any = mean(capture_rate_any_hit, na.rm = TRUE),
#     .groups = "drop"
#   ) %>%
#   mutate(
#     prefix = factor(prefix, levels = PREFIX_ORDER),
#     stable_class_disp = STABLE_CLASS_MAP[stable_class]
#   )

# if (nrow(row_info_all) == 0) stop("No stable subtype rows found.")

# # =========================
# # join main-hit composition for all stable rows
# # =========================
# focal_df <- kmin_df %>%
#   filter(stable_class %in% names(STABLE_CLASS_MAP)) %>%
#   select(rep, rep_label, prefix, subtype, stable_class, k_min,
#          main_hit_cluster, main_hit_cluster_norm)

# hit_main_df <- hit_df %>%
#   select(rep, rep_label, prefix, k_min, cluster, cluster_norm, top_subtypes, subtype_count_json)

# merged_df <- focal_df %>%
#   left_join(
#     hit_main_df,
#     by = c("rep", "rep_label", "prefix", "k_min", "main_hit_cluster_norm" = "cluster_norm")
#   ) %>%
#   mutate(join_ok = !is.na(cluster))

# write.table(
#   merged_df,
#   file = file.path(OUTDIR, "composition_by_stable_class_merged_debug.tsv"),
#   sep = "\t", quote = FALSE, row.names = FALSE
# )

# # =========================
# # parse composition for all stable rows
# # =========================
# comp_rows <- lapply(seq_len(nrow(merged_df)), function(i) {
#   rr <- merged_df[i, ]

#   if (is.na(rr$main_hit_cluster_norm) || rr$main_hit_cluster_norm == "") return(NULL)
#   if (!isTRUE(rr$join_ok)) return(NULL)

#   parsed <- parse_composition(
#     top_subtypes = rr$top_subtypes,
#     subtype_count_json = rr$subtype_count_json
#   )

#   if (nrow(parsed) == 0) return(NULL)

#   parsed %>%
#     mutate(
#       rep = rr$rep,
#       rep_label = rr$rep_label,
#       prefix = rr$prefix,
#       subtype = rr$subtype,
#       stable_class = rr$stable_class,
#       stable_class_disp = STABLE_CLASS_MAP[rr$stable_class],
#       k_min = rr$k_min
#     )
# })

# comp_long_all <- bind_rows(comp_rows)
# if (nrow(comp_long_all) == 0) stop("No composition data parsed.")

# # 只保留真正用到的 component_subtype
# fill_order_global <- comp_long_all %>%
#   filter(percent > 0) %>%
#   group_by(component_subtype) %>%
#   summarise(total_pct = sum(percent, na.rm = TRUE), .groups = "drop") %>%
#   arrange(desc(total_pct), component_subtype) %>%
#   pull(component_subtype)

# # 改成区分度更强的配色
# fill_cols_global <- setNames(
#   grDevices::hcl.colors(length(fill_order_global), palette = "Dark 3"),
#   fill_order_global
# )

# # =========================
# # helper to build one block
# # =========================
# build_block_plot <- function(
#   block_title,
#   stable_class_keys,
#   rep_labels_keep,
#   show_comp_legend = FALSE
# ) {
#   row_info_block <- row_info_all %>%
#     filter(stable_class %in% stable_class_keys) %>%
#     arrange(prefix, desc(mean_capture_any), subtype) %>%
#     mutate(
#       row_id = row_number(),
#       subtype_label = subtype
#     )

#   if (nrow(row_info_block) == 0) return(NULL)

#   n_rows <- nrow(row_info_block)

#   prefix_blocks <- row_info_block %>%
#     mutate(prefix = as.character(prefix)) %>%
#     group_by(prefix) %>%
#     summarise(
#       y_mid = mean(row_id),
#       y_min = min(row_id) - 0.5,
#       y_max = max(row_id) + 0.5,
#       .groups = "drop"
#     )

#   comp_block <- comp_long_all %>%
#     filter(rep_label %in% rep_labels_keep, stable_class %in% stable_class_keys) %>%
#     inner_join(
#       row_info_block %>%
#         select(prefix, subtype, stable_class, stable_class_disp, row_id, subtype_label),
#       by = c("prefix", "subtype", "stable_class", "stable_class_disp")
#     )

#   # hand stacking
#   comp_plot_df <- comp_block %>%
#     filter(percent > 0, component_subtype %in% fill_order_global) %>%
#     mutate(
#       rep_label = factor(as.character(rep_label), levels = rep_labels_keep),
#       component_subtype = factor(as.character(component_subtype), levels = fill_order_global),
#       is_focal = as.character(component_subtype) == subtype
#     ) %>%
#     group_by(rep_label, row_id, subtype, k_min) %>%
#     arrange(desc(is_focal), desc(percent), component_subtype, .by_group = TRUE) %>%
#     mutate(
#       pct_prev = lag(cumsum(percent), default = 0),
#       pct_now  = cumsum(percent),
#       ymin = row_id - 0.45 + 0.9 * (pct_prev / 100),
#       ymax = row_id - 0.45 + 0.9 * (pct_now / 100),
#       xmin = k_min - 0.48,
#       xmax = k_min + 0.48
#     ) %>%
#     ungroup()

#   bar_total_check <- comp_plot_df %>%
#     group_by(rep_label, row_id, subtype, k_min) %>%
#     summarise(sum_percent = max(pct_now), .groups = "drop")

#   write.table(
#     bar_total_check,
#     file = file.path(
#       OUTDIR,
#       paste0("bar_total_check_", gsub("[^A-Za-z0-9]+", "_", block_title), ".tsv")
#     ),
#     sep = "\t", quote = FALSE, row.names = FALSE
#   )

#   # class panel
#   p_class <- ggplot() +
#     geom_rect(
#       data = prefix_blocks,
#       aes(xmin = 0.00, xmax = 0.22, ymin = y_min, ymax = y_max),
#       fill = "grey92", color = NA
#     ) +
#     geom_text(
#       data = prefix_blocks,
#       aes(x = 0.11, y = y_mid, label = prefix),
#       fontface = "bold", size = 6
#     ) +
#     geom_rect(
#       data = row_info_block,
#       aes(
#         xmin = 0.28, xmax = 0.96,
#         ymin = row_id - 0.48,
#         ymax = row_id + 0.48,
#         fill = stable_class_disp
#       ),
#       color = NA
#     ) +
#     scale_fill_manual(
#       values = STABLE_CLASS_COLORS,
#       drop = FALSE
#     ) +
#     scale_y_reverse(limits = c(n_rows + 0.5, 0.5), expand = c(0, 0)) +
#     xlim(0, 1) +
#     labs(title = if (show_comp_legend) "Class" else NULL) +
#     theme_void(base_size = 12) +
#     theme(
#       plot.title = element_text(size = 18, face = "bold", hjust = 0.5),
#       legend.position = "none"
#     )

#   # subtype labels
#   p_label <- ggplot(row_info_block, aes(x = 0, y = row_id, label = subtype_label)) +
#     geom_text(
#       aes(color = stable_class_disp),
#       hjust = 0, fontface = "bold", size = 6, show.legend = FALSE
#     ) +
#     scale_color_manual(values = STABLE_CLASS_COLORS, drop = FALSE) +
#     scale_y_reverse(limits = c(n_rows + 0.5, 0.5), expand = c(0, 0)) +
#     xlim(0, 1.05) +
#     theme_void(base_size = 12)

#   # composition panel
#   p_comp <- ggplot() +
#     geom_hline(
#       yintercept = seq(0.5, n_rows + 0.5, by = 1),
#       color = "white",
#       linewidth = 0.7
#     ) +
#     geom_rect(
#       data = comp_plot_df,
#       aes(
#         xmin = xmin, xmax = xmax,
#         ymin = ymin, ymax = ymax,
#         fill = component_subtype
#       ),
#       color = NA
#     ) +
#     facet_grid(. ~ rep_label) +
#     scale_fill_manual(
#       values = fill_cols_global,
#       breaks = fill_order_global,
#       labels = fill_order_global,
#       name = NULL,
#       drop = TRUE
#     ) +
#     scale_x_continuous(
#       breaks = KMIN_RANGE,
#       labels = KMIN_RANGE,
#       limits = c(min(KMIN_RANGE) - 0.5, max(KMIN_RANGE) + 0.5),
#       expand = c(0, 0)
#     ) +
#     scale_y_reverse(
#       limits = c(n_rows + 0.5, 0.5),
#       expand = c(0, 0)
#     ) +
#     labs(x = "k_min", y = NULL) +
#     guides(
#       fill = guide_legend(
#         title = NULL,
#         nrow = 4,
#         byrow = TRUE,
#         keywidth = grid::unit(0.45, "cm"),
#         keyheight = grid::unit(0.45, "cm"),
#         override.aes = list(alpha = 1)
#       )
#     ) +
#     theme_minimal(base_size = 12) +
#     theme(
#       axis.text.x = element_text(size = 11),
#       axis.text.y = element_blank(),
#       axis.title.x = element_text(size = 16, face = "bold"),
#       panel.grid = element_blank(),
#       panel.background = element_rect(fill = "grey98", color = NA),
#       strip.text.x = element_text(size = 16, face = "bold"),
#       strip.background = element_rect(fill = "grey95", color = NA),
#       legend.position = if (show_comp_legend) "top" else "none",
#       legend.text = element_text(size = 12),
#       legend.key.width = grid::unit(0.45, "cm"),
#       legend.key.height = grid::unit(0.45, "cm"),
#       legend.box = "vertical"
#     )

#   block_plot <- p_class + p_label + p_comp +
#     plot_layout(widths = c(0.55, 2.3, 8.7)) +
#     plot_annotation(
#       title = block_title,
#       theme = theme(
#         plot.title = element_text(size = 18, face = "bold", hjust = 0.5)
#       )
#     )

#   list(plot = block_plot, nrows = n_rows)
# }

# # =========================
# # build three blocks
# # =========================
# block_mcx <- build_block_plot(
#   block_title = "MCX-specific stable",
#   stable_class_keys = "MCX_specific_stable",
#   rep_labels_keep = c("FTLD-MCX", "SALS-MCX"),
#   show_comp_legend = TRUE
# )

# block_pfc <- build_block_plot(
#   block_title = "PFC-specific stable",
#   stable_class_keys = "PFC_specific_stable",
#   rep_labels_keep = c("FTLD-PFC", "SALS-PFC"),
#   show_comp_legend = FALSE
# )

# block_cross <- build_block_plot(
#   block_title = "Cross-region stable",
#   stable_class_keys = "Cross_region_stable",
#   rep_labels_keep = c("FTLD-MCX", "SALS-MCX", "FTLD-PFC", "SALS-PFC"),
#   show_comp_legend = FALSE
# )

# blocks <- list(block_mcx, block_pfc, block_cross)
# blocks <- blocks[!vapply(blocks, is.null, logical(1))]

# if (length(blocks) == 0) stop("No non-empty blocks to plot.")

# block_plots <- lapply(blocks, `[[`, "plot")
# block_heights <- vapply(blocks, `[[`, numeric(1), "nrows")

# final_plot <- wrap_plots(block_plots, ncol = 1, heights = block_heights) +
#   plot_layout(guides = "collect") +
#   plot_annotation(
#     title = "In + Ex combined: main-hit cluster composition by stable class and disease",
#     theme = theme(
#       plot.title = element_text(size = 24, face = "bold", hjust = 0.5)
#     )
#   ) &
#   theme(legend.position = "top")

# out_png <- file.path(OUTDIR, "In_Ex_mainhit_composition_by_stable_class_blocks_cleanlegend_usedonly.png")
# save_plot_both(
#   final_plot,
#   out_png,
#   width = 24,
#   height = max(10, 1.1 * sum(block_heights) + 5),
#   save_pdf = SAVE_PDF
# )

# cat("[DONE] plot written to: ", out_png, "\n", sep = "")
# ============================================================
# Snakefile for vulnerable neuron stability analysis
# plus barcode-level stable vulnerable / non-vulnerable PV states
# ============================================================

# suppressPackageStartupMessages({
#   library(ggplot2)
#   library(dplyr)
#   library(tidyr)
#   library(stringr)
#   library(patchwork)
#   library(jsonlite)
# })

# # =========================
# # args
# # =========================
# parse_args <- function() {
#   args <- commandArgs(trailingOnly = TRUE)

#   defaults <- list(
#     "structure-dir" = NULL,
#     "outdir" = NULL,
#     "save-pdf" = FALSE
#   )

#   i <- 1
#   while (i <= length(args)) {
#     key <- args[[i]]

#     if (!startsWith(key, "--")) stop("Unexpected argument: ", key)
#     key2 <- substring(key, 3)

#     if (!(key2 %in% names(defaults))) stop("Unknown argument: ", key)

#     if (key2 == "save-pdf") {
#       defaults[[key2]] <- TRUE
#       i <- i + 1
#       next
#     }

#     if (i == length(args)) stop("Missing value for argument: ", key)

#     defaults[[key2]] <- args[[i + 1]]
#     i <- i + 2
#   }

#   if (is.null(defaults[["structure-dir"]])) stop("--structure-dir is required")
#   if (is.null(defaults[["outdir"]])) stop("--outdir is required")

#   defaults
# }

# ARGS <- parse_args()
# STRUCTURE_DIR <- ARGS[["structure-dir"]]
# OUTDIR <- ARGS[["outdir"]]
# SAVE_PDF <- isTRUE(ARGS[["save-pdf"]])

# if (!dir.exists(OUTDIR)) dir.create(OUTDIR, recursive = TRUE, showWarnings = FALSE)

# # =========================
# # constants
# # =========================
# REP_ORDER <- c(
#   "FTLD_MCX_Control_Concat_QC_harmony_filted",
#   "SALS_MCX_control_concat_QC_harmony",
#   "FTLD_PFC_Ctrl_Concat_QC_harmony_filted",
#   "SALS_PFC_control_concat_QC_harmony"
# )

# REP_LABEL <- c(
#   "FTLD_MCX_Control_Concat_QC_harmony_filted" = "FTLD-MCX",
#   "SALS_MCX_control_concat_QC_harmony" = "SALS-MCX",
#   "FTLD_PFC_Ctrl_Concat_QC_harmony_filted" = "FTLD-PFC",
#   "SALS_PFC_control_concat_QC_harmony" = "SALS-PFC"
# )

# PREFIX_ORDER <- c("In", "Ex")
# KMIN_RANGE <- 2:24

# STABLE_CLASS_MAP <- c(
#   "Cross_region_stable" = "Cross-region",
#   "MCX_specific_stable" = "MCX-specific",
#   "PFC_specific_stable" = "PFC-specific"
# )

# STABLE_CLASS_COLORS <- c(
#   "Cross-region" = "#20A486",
#   "MCX-specific" = "#E94F37",
#   "PFC-specific" = "#56B1C7"
# )

# save_plot_both <- function(p, out_png, width, height, save_pdf = FALSE) {
#   ggsave(out_png, p, width = width, height = height, dpi = 300, bg = "white")
#   if (save_pdf) {
#     ggsave(
#       sub("\\.png$", ".pdf", out_png),
#       p, width = width, height = height, bg = "white"
#     )
#   }
# }

# normalize_cluster_label <- function(x) {
#   if (is.na(x)) return("")
#   s <- str_trim(as.character(x))
#   if (s == "" || tolower(s) == "nan") return("")

#   num <- suppressWarnings(as.numeric(s))
#   if (!is.na(num)) {
#     if (abs(num - round(num)) < 1e-8) {
#       return(as.character(as.integer(round(num))))
#     } else {
#       return(as.character(num))
#     }
#   }
#   s
# }

# parse_top_subtypes <- function(x) {
#   if (is.na(x) || x == "") {
#     return(data.frame(component_subtype = character(), percent = numeric()))
#   }

#   parts <- unlist(strsplit(x, ";", fixed = TRUE))
#   parts <- parts[nzchar(parts)]

#   out <- lapply(parts, function(p) {
#     m <- str_match(p, "^(.*?):\\s*\\d+\\(([-0-9.]+)%\\)$")
#     if (all(is.na(m))) return(NULL)

#     data.frame(
#       component_subtype = str_trim(m[2]),
#       percent = as.numeric(m[3]),
#       stringsAsFactors = FALSE
#     )
#   })

#   out <- out[!vapply(out, is.null, logical(1))]
#   if (length(out) == 0) {
#     return(data.frame(component_subtype = character(), percent = numeric()))
#   }

#   out <- bind_rows(out)
#   s <- sum(out$percent, na.rm = TRUE)

#   if (s < 99.5) {
#     out <- bind_rows(
#       out,
#       data.frame(
#         component_subtype = "Other",
#         percent = max(0, 100 - s),
#         stringsAsFactors = FALSE
#       )
#     )
#   }

#   out
# }

# parse_json_counts_to_pct <- function(x) {
#   if (is.na(x) || x == "" || x == "{}") {
#     return(data.frame(component_subtype = character(), percent = numeric()))
#   }

#   obj <- tryCatch(jsonlite::fromJSON(x), error = function(e) NULL)
#   if (is.null(obj) || length(obj) == 0) {
#     return(data.frame(component_subtype = character(), percent = numeric()))
#   }

#   vals <- as.numeric(obj)
#   nms <- names(obj)

#   keep <- !is.na(vals) & vals > 0
#   vals <- vals[keep]
#   nms <- nms[keep]

#   if (length(vals) == 0) {
#     return(data.frame(component_subtype = character(), percent = numeric()))
#   }

#   pct <- 100 * vals / sum(vals)

#   data.frame(
#     component_subtype = nms,
#     percent = pct,
#     stringsAsFactors = FALSE
#   ) %>%
#     arrange(desc(percent), component_subtype)
# }

# parse_composition <- function(top_subtypes, subtype_count_json = NA_character_) {
#   out <- parse_json_counts_to_pct(subtype_count_json)
#   if (nrow(out) > 0) return(out)
#   parse_top_subtypes(top_subtypes)
# }

# # =========================
# # input
# # =========================
# kmin_fp <- file.path(STRUCTURE_DIR, "stable_subtype_kmin_structure.tsv")
# hit_fp  <- file.path(STRUCTURE_DIR, "stable_hit_cluster_summary.tsv")

# if (!file.exists(kmin_fp)) stop("Cannot find: ", kmin_fp)
# if (!file.exists(hit_fp)) stop("Cannot find: ", hit_fp)

# kmin_df <- read.delim(kmin_fp, check.names = FALSE)
# hit_df  <- read.delim(hit_fp, check.names = FALSE)

# if (!("subtype_count_json" %in% colnames(hit_df))) {
#   hit_df$subtype_count_json <- NA_character_
# }

# kmin_df <- kmin_df %>%
#   mutate(
#     rep = as.character(rep),
#     prefix = as.character(prefix),
#     subtype = as.character(subtype),
#     stable_class = as.character(stable_class),
#     k_min = as.integer(k_min),
#     capture_rate_any_hit = as.numeric(capture_rate_any_hit),
#     main_hit_cluster = as.character(main_hit_cluster),
#     main_hit_cluster_norm = vapply(main_hit_cluster, normalize_cluster_label, character(1)),
#     rep_label = factor(REP_LABEL[rep], levels = unname(REP_LABEL))
#   )

# hit_df <- hit_df %>%
#   mutate(
#     rep = as.character(rep),
#     prefix = as.character(prefix),
#     k_min = as.integer(k_min),
#     cluster = as.character(cluster),
#     cluster_norm = vapply(cluster, normalize_cluster_label, character(1)),
#     rep_label = factor(REP_LABEL[rep], levels = unname(REP_LABEL)),
#     top_subtypes = as.character(top_subtypes),
#     subtype_count_json = as.character(subtype_count_json)
#   )

# # =========================
# # overall row info
# # =========================
# row_info_all <- kmin_df %>%
#   filter(stable_class %in% names(STABLE_CLASS_MAP)) %>%
#   group_by(prefix, subtype, stable_class) %>%
#   summarise(
#     mean_capture_any = mean(capture_rate_any_hit, na.rm = TRUE),
#     .groups = "drop"
#   ) %>%
#   mutate(
#     prefix = factor(prefix, levels = PREFIX_ORDER),
#     stable_class_disp = STABLE_CLASS_MAP[stable_class]
#   )

# if (nrow(row_info_all) == 0) stop("No stable subtype rows found.")

# # =========================
# # join main-hit composition for all stable rows
# # =========================
# focal_df <- kmin_df %>%
#   filter(stable_class %in% names(STABLE_CLASS_MAP)) %>%
#   select(rep, rep_label, prefix, subtype, stable_class, k_min,
#          main_hit_cluster, main_hit_cluster_norm)

# hit_main_df <- hit_df %>%
#   select(rep, rep_label, prefix, k_min, cluster, cluster_norm, top_subtypes, subtype_count_json)

# merged_df <- focal_df %>%
#   left_join(
#     hit_main_df,
#     by = c("rep", "rep_label", "prefix", "k_min", "main_hit_cluster_norm" = "cluster_norm")
#   ) %>%
#   mutate(join_ok = !is.na(cluster))

# write.table(
#   merged_df,
#   file = file.path(OUTDIR, "composition_by_stable_class_merged_debug.tsv"),
#   sep = "\t", quote = FALSE, row.names = FALSE
# )

# # =========================
# # parse composition for all stable rows
# # =========================
# comp_rows <- lapply(seq_len(nrow(merged_df)), function(i) {
#   rr <- merged_df[i, ]

#   if (is.na(rr$main_hit_cluster_norm) || rr$main_hit_cluster_norm == "") return(NULL)
#   if (!isTRUE(rr$join_ok)) return(NULL)

#   parsed <- parse_composition(
#     top_subtypes = rr$top_subtypes,
#     subtype_count_json = rr$subtype_count_json
#   )

#   if (nrow(parsed) == 0) return(NULL)

#   parsed %>%
#     mutate(
#       rep = rr$rep,
#       rep_label = rr$rep_label,
#       prefix = rr$prefix,
#       subtype = rr$subtype,
#       stable_class = rr$stable_class,
#       stable_class_disp = STABLE_CLASS_MAP[rr$stable_class],
#       k_min = rr$k_min
#     )
# })

# comp_long_all <- bind_rows(comp_rows)
# if (nrow(comp_long_all) == 0) stop("No composition data parsed.")

# # 只保留真正用到的 component_subtype
# fill_order_global <- comp_long_all %>%
#   filter(percent > 0) %>%
#   group_by(component_subtype) %>%
#   summarise(total_pct = sum(percent, na.rm = TRUE), .groups = "drop") %>%
#   arrange(desc(total_pct), component_subtype) %>%
#   pull(component_subtype)

# # 改成区分度更强的配色
# fill_cols_global <- setNames(
#   grDevices::hcl.colors(length(fill_order_global), palette = "Dark 3"),
#   fill_order_global
# )

# # =========================
# # helper to build one block
# # =========================
# build_block_plot <- function(
#   block_title,
#   stable_class_keys,
#   rep_labels_keep,
#   show_comp_legend = FALSE
# ) {
#   row_info_block <- row_info_all %>%
#     filter(stable_class %in% stable_class_keys) %>%
#     arrange(prefix, desc(mean_capture_any), subtype) %>%
#     mutate(
#       row_id = row_number(),
#       subtype_label = subtype
#     )

#   if (nrow(row_info_block) == 0) return(NULL)

#   n_rows <- nrow(row_info_block)

#   prefix_blocks <- row_info_block %>%
#     mutate(prefix = as.character(prefix)) %>%
#     group_by(prefix) %>%
#     summarise(
#       y_mid = mean(row_id),
#       y_min = min(row_id) - 0.5,
#       y_max = max(row_id) + 0.5,
#       .groups = "drop"
#     )

#   comp_block <- comp_long_all %>%
#     filter(rep_label %in% rep_labels_keep, stable_class %in% stable_class_keys) %>%
#     inner_join(
#       row_info_block %>%
#         select(prefix, subtype, stable_class, stable_class_disp, row_id, subtype_label),
#       by = c("prefix", "subtype", "stable_class", "stable_class_disp")
#     )

#   # hand stacking
#   comp_plot_df <- comp_block %>%
#     filter(percent > 0, component_subtype %in% fill_order_global) %>%
#     mutate(
#       rep_label = factor(as.character(rep_label), levels = rep_labels_keep),
#       component_subtype = factor(as.character(component_subtype), levels = fill_order_global),
#       is_focal = as.character(component_subtype) == subtype
#     ) %>%
#     group_by(rep_label, row_id, subtype, k_min) %>%
#     arrange(desc(is_focal), desc(percent), component_subtype, .by_group = TRUE) %>%
#     mutate(
#       pct_prev = lag(cumsum(percent), default = 0),
#       pct_now  = cumsum(percent),
#       ymin = row_id - 0.45 + 0.9 * (pct_prev / 100),
#       ymax = row_id - 0.45 + 0.9 * (pct_now / 100),
#       xmin = k_min - 0.48,
#       xmax = k_min + 0.48
#     ) %>%
#     ungroup()

#   bar_total_check <- comp_plot_df %>%
#     group_by(rep_label, row_id, subtype, k_min) %>%
#     summarise(sum_percent = max(pct_now), .groups = "drop")

#   write.table(
#     bar_total_check,
#     file = file.path(
#       OUTDIR,
#       paste0("bar_total_check_", gsub("[^A-Za-z0-9]+", "_", block_title), ".tsv")
#     ),
#     sep = "\t", quote = FALSE, row.names = FALSE
#   )

#   # class panel
#   p_class <- ggplot() +
#     geom_rect(
#       data = prefix_blocks,
#       aes(xmin = 0.00, xmax = 0.22, ymin = y_min, ymax = y_max),
#       fill = "grey92", color = NA
#     ) +
#     geom_text(
#       data = prefix_blocks,
#       aes(x = 0.11, y = y_mid, label = prefix),
#       fontface = "bold", size = 6
#     ) +
#     geom_rect(
#       data = row_info_block,
#       aes(
#         xmin = 0.28, xmax = 0.96,
#         ymin = row_id - 0.48,
#         ymax = row_id + 0.48,
#         fill = stable_class_disp
#       ),
#       color = NA
#     ) +
#     scale_fill_manual(
#       values = STABLE_CLASS_COLORS,
#       drop = FALSE
#     ) +
#     scale_y_reverse(limits = c(n_rows + 0.5, 0.5), expand = c(0, 0)) +
#     xlim(0, 1) +
#     labs(title = if (show_comp_legend) "Class" else NULL) +
#     theme_void(base_size = 12) +
#     theme(
#       plot.title = element_text(size = 18, face = "bold", hjust = 0.5),
#       legend.position = "none"
#     )

#   # subtype labels
#   p_label <- ggplot(row_info_block, aes(x = 0, y = row_id, label = subtype_label)) +
#     geom_text(
#       aes(color = stable_class_disp),
#       hjust = 0, fontface = "bold", size = 6, show.legend = FALSE
#     ) +
#     scale_color_manual(values = STABLE_CLASS_COLORS, drop = FALSE) +
#     scale_y_reverse(limits = c(n_rows + 0.5, 0.5), expand = c(0, 0)) +
#     xlim(0, 1.05) +
#     theme_void(base_size = 12)

#   # composition panel
#   p_comp <- ggplot() +
#     geom_hline(
#       yintercept = seq(0.5, n_rows + 0.5, by = 1),
#       color = "white",
#       linewidth = 0.7
#     ) +
#     geom_rect(
#       data = comp_plot_df,
#       aes(
#         xmin = xmin, xmax = xmax,
#         ymin = ymin, ymax = ymax,
#         fill = component_subtype
#       ),
#       color = NA
#     ) +
#     facet_grid(. ~ rep_label) +
#     scale_fill_manual(
#       values = fill_cols_global,
#       breaks = fill_order_global,
#       labels = fill_order_global,
#       name = NULL,
#       drop = TRUE
#     ) +
#     scale_x_continuous(
#       breaks = KMIN_RANGE,
#       labels = KMIN_RANGE,
#       limits = c(min(KMIN_RANGE) - 0.5, max(KMIN_RANGE) + 0.5),
#       expand = c(0, 0)
#     ) +
#     scale_y_reverse(
#       limits = c(n_rows + 0.5, 0.5),
#       expand = c(0, 0)
#     ) +
#     labs(x = "k_min", y = NULL) +
#     guides(
#       fill = guide_legend(
#         title = NULL,
#         nrow = 4,
#         byrow = TRUE,
#         keywidth = grid::unit(0.45, "cm"),
#         keyheight = grid::unit(0.45, "cm"),
#         override.aes = list(alpha = 1)
#       )
#     ) +
#     theme_minimal(base_size = 12) +
#     theme(
#       axis.text.x = element_text(size = 11),
#       axis.text.y = element_blank(),
#       axis.title.x = element_text(size = 16, face = "bold"),
#       panel.grid = element_blank(),
#       panel.background = element_rect(fill = "grey98", color = NA),
#       strip.text.x = element_text(size = 16, face = "bold"),
#       strip.background = element_rect(fill = "grey95", color = NA),
#       legend.position = if (show_comp_legend) "top" else "none",
#       legend.text = element_text(size = 12),
#       legend.key.width = grid::unit(0.45, "cm"),
#       legend.key.height = grid::unit(0.45, "cm"),
#       legend.box = "vertical"
#     )

#   block_plot <- p_class + p_label + p_comp +
#     plot_layout(widths = c(0.55, 2.3, 8.7)) +
#     plot_annotation(
#       title = block_title,
#       theme = theme(
#         plot.title = element_text(size = 18, face = "bold", hjust = 0.5)
#       )
#     )

#   list(plot = block_plot, nrows = n_rows)
# }

# # =========================
# # build three blocks
# # =========================
# block_mcx <- build_block_plot(
#   block_title = "MCX-specific stable",
#   stable_class_keys = "MCX_specific_stable",
#   rep_labels_keep = c("FTLD-MCX", "SALS-MCX"),
#   show_comp_legend = TRUE
# )

# block_pfc <- build_block_plot(
#   block_title = "PFC-specific stable",
#   stable_class_keys = "PFC_specific_stable",
#   rep_labels_keep = c("FTLD-PFC", "SALS-PFC"),
#   show_comp_legend = FALSE
# )

# block_cross <- build_block_plot(
#   block_title = "Cross-region stable",
#   stable_class_keys = "Cross_region_stable",
#   rep_labels_keep = c("FTLD-MCX", "SALS-MCX", "FTLD-PFC", "SALS-PFC"),
#   show_comp_legend = FALSE
# )

# blocks <- list(block_mcx, block_pfc, block_cross)
# blocks <- blocks[!vapply(blocks, is.null, logical(1))]

# if (length(blocks) == 0) stop("No non-empty blocks to plot.")

# block_plots <- lapply(blocks, `[[`, "plot")
# block_heights <- vapply(blocks, `[[`, numeric(1), "nrows")

# final_plot <- wrap_plots(block_plots, ncol = 1, heights = block_heights) +
#   plot_layout(guides = "collect") +
#   plot_annotation(
#     title = "In + Ex combined: main-hit cluster composition by stable class and disease",
#     theme = theme(
#       plot.title = element_text(size = 24, face = "bold", hjust = 0.5)
#     )
#   ) &
#   theme(legend.position = "top")

# out_png <- file.path(OUTDIR, "In_Ex_mainhit_composition_by_stable_class_blocks_cleanlegend_usedonly.png")
# save_plot_both(
#   final_plot,
#   out_png,
#   width = 24,
#   height = max(10, 1.1 * sum(block_heights) + 5),
#   save_pdf = SAVE_PDF
# )

# cat("[DONE] plot written to: ", out_png, "\n", sep = "")
suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(patchwork)
  library(jsonlite)
})

parse_args <- function() {
  args <- commandArgs(trailingOnly = TRUE)

  defaults <- list(
    "structure-dir" = NULL,
    "outdir" = NULL,
    "save-pdf" = FALSE
  )

  i <- 1
  while (i <= length(args)) {
    key <- args[[i]]

    if (!startsWith(key, "--")) stop("Unexpected argument: ", key)
    key2 <- substring(key, 3)

    if (!(key2 %in% names(defaults))) stop("Unknown argument: ", key)

    if (key2 == "save-pdf") {
      defaults[[key2]] <- TRUE
      i <- i + 1
      next
    }

    if (i == length(args)) stop("Missing value for argument: ", key)

    defaults[[key2]] <- args[[i + 1]]
    i <- i + 2
  }

  if (is.null(defaults[["structure-dir"]])) stop("--structure-dir is required")
  if (is.null(defaults[["outdir"]])) stop("--outdir is required")

  defaults
}

ARGS <- parse_args()
STRUCTURE_DIR <- ARGS[["structure-dir"]]
OUTDIR <- ARGS[["outdir"]]
SAVE_PDF <- isTRUE(ARGS[["save-pdf"]])

if (!dir.exists(OUTDIR)) dir.create(OUTDIR, recursive = TRUE, showWarnings = FALSE)

REP_LABEL <- c(
  "FTLD_MCX_Control_Concat_QC_harmony_filted" = "FTLD-MCX",
  "SALS_MCX_control_concat_QC_harmony" = "SALS-MCX",
  "FTLD_PFC_Ctrl_Concat_QC_harmony_filted" = "FTLD-DLPFC",
  "SALS_PFC_control_concat_QC_harmony" = "SALS-DLPFC"
)

PREFIX_ORDER <- c("In", "Ex")
KMIN_RANGE <- 2:24

STABLE_CLASS_MAP <- c(
  "Cross_region_stable" = "Cross-region",
  "MCX_specific_stable" = "MCX-specific",
  "PFC_specific_stable" = "DLPFC-specific"
)

STABLE_CLASS_COLORS <- c(
  "Cross-region" = "#20A486",
  "MCX-specific" = "#E94F37",
  "DLPFC-specific" = "#56B1C7"
)

save_plot_both <- function(p, out_png, width, height, save_pdf = FALSE) {
  ggsave(out_png, p, width = width, height = height, dpi = 300, bg = "white")
  if (save_pdf) {
    ggsave(
      sub("\\.png$", ".pdf", out_png),
      p, width = width, height = height, bg = "white"
    )
  }
}

normalize_cluster_label <- function(x) {
  if (is.na(x)) return("")
  s <- str_trim(as.character(x))
  if (s == "" || tolower(s) == "nan") return("")

  num <- suppressWarnings(as.numeric(s))
  if (!is.na(num)) {
    if (abs(num - round(num)) < 1e-8) {
      return(as.character(as.integer(round(num))))
    } else {
      return(as.character(num))
    }
  }
  s
}

parse_top_subtypes <- function(x) {
  if (is.na(x) || x == "") {
    return(data.frame(component_subtype = character(), percent = numeric()))
  }

  parts <- unlist(strsplit(x, ";", fixed = TRUE))
  parts <- parts[nzchar(parts)]

  out <- lapply(parts, function(p) {
    m <- str_match(p, "^(.*?):\\s*\\d+\\(([-0-9.]+)%\\)$")
    if (all(is.na(m))) return(NULL)

    data.frame(
      component_subtype = str_trim(m[2]),
      percent = as.numeric(m[3]),
      stringsAsFactors = FALSE
    )
  })

  out <- out[!vapply(out, is.null, logical(1))]
  if (length(out) == 0) {
    return(data.frame(component_subtype = character(), percent = numeric()))
  }

  out <- bind_rows(out)
  s <- sum(out$percent, na.rm = TRUE)

  if (s < 99.5) {
    out <- bind_rows(
      out,
      data.frame(
        component_subtype = "Other",
        percent = max(0, 100 - s),
        stringsAsFactors = FALSE
      )
    )
  }

  out
}

parse_json_counts_to_pct <- function(x) {
  if (is.na(x) || x == "" || x == "{}") {
    return(data.frame(component_subtype = character(), percent = numeric()))
  }

  obj <- tryCatch(jsonlite::fromJSON(x), error = function(e) NULL)
  if (is.null(obj) || length(obj) == 0) {
    return(data.frame(component_subtype = character(), percent = numeric()))
  }

  vals <- as.numeric(obj)
  nms <- names(obj)

  keep <- !is.na(vals) & vals > 0
  vals <- vals[keep]
  nms <- nms[keep]

  if (length(vals) == 0) {
    return(data.frame(component_subtype = character(), percent = numeric()))
  }

  pct <- 100 * vals / sum(vals)

  data.frame(
    component_subtype = nms,
    percent = pct,
    stringsAsFactors = FALSE
  ) %>%
    arrange(desc(percent), component_subtype)
}

parse_composition <- function(top_subtypes, subtype_count_json = NA_character_) {
  out <- parse_json_counts_to_pct(subtype_count_json)
  if (nrow(out) > 0) return(out)
  parse_top_subtypes(top_subtypes)
}

kmin_fp <- file.path(STRUCTURE_DIR, "stable_subtype_kmin_structure.tsv")
hit_fp  <- file.path(STRUCTURE_DIR, "stable_hit_cluster_summary.tsv")

if (!file.exists(kmin_fp)) stop("Cannot find: ", kmin_fp)
if (!file.exists(hit_fp)) stop("Cannot find: ", hit_fp)

kmin_df <- read.delim(kmin_fp, check.names = FALSE)
hit_df  <- read.delim(hit_fp, check.names = FALSE)

if (!("subtype_count_json" %in% colnames(hit_df))) {
  hit_df$subtype_count_json <- NA_character_
}

kmin_df <- kmin_df %>%
  mutate(
    rep = as.character(rep),
    prefix = as.character(prefix),
    subtype = as.character(subtype),
    stable_class = as.character(stable_class),
    k_min = as.integer(k_min),
    capture_rate_any_hit = as.numeric(capture_rate_any_hit),
    main_hit_cluster = as.character(main_hit_cluster),
    main_hit_cluster_norm = vapply(main_hit_cluster, normalize_cluster_label, character(1)),
    rep_label = factor(REP_LABEL[rep], levels = unname(REP_LABEL))
  )

hit_df <- hit_df %>%
  mutate(
    rep = as.character(rep),
    prefix = as.character(prefix),
    k_min = as.integer(k_min),
    cluster = as.character(cluster),
    cluster_norm = vapply(cluster, normalize_cluster_label, character(1)),
    rep_label = factor(REP_LABEL[rep], levels = unname(REP_LABEL)),
    top_subtypes = as.character(top_subtypes),
    subtype_count_json = as.character(subtype_count_json)
  )

row_info_all <- kmin_df %>%
  filter(stable_class %in% names(STABLE_CLASS_MAP)) %>%
  group_by(prefix, subtype, stable_class) %>%
  summarise(
    mean_capture_any = mean(capture_rate_any_hit, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(
    prefix = factor(prefix, levels = PREFIX_ORDER),
    stable_class_disp = STABLE_CLASS_MAP[stable_class]
  )

if (nrow(row_info_all) == 0) stop("No stable subtype rows found.")

focal_df <- kmin_df %>%
  filter(stable_class %in% names(STABLE_CLASS_MAP)) %>%
  select(rep, rep_label, prefix, subtype, stable_class, k_min,
         main_hit_cluster, main_hit_cluster_norm)

hit_main_df <- hit_df %>%
  select(rep, rep_label, prefix, k_min, cluster, cluster_norm, top_subtypes, subtype_count_json)

merged_df <- focal_df %>%
  left_join(
    hit_main_df,
    by = c("rep", "rep_label", "prefix", "k_min", "main_hit_cluster_norm" = "cluster_norm")
  ) %>%
  mutate(join_ok = !is.na(cluster))

write.table(
  merged_df,
  file = file.path(OUTDIR, "composition_by_stable_class_merged_debug.tsv"),
  sep = "\t", quote = FALSE, row.names = FALSE
)

comp_rows <- lapply(seq_len(nrow(merged_df)), function(i) {
  rr <- merged_df[i, ]

  if (is.na(rr$main_hit_cluster_norm) || rr$main_hit_cluster_norm == "") return(NULL)
  if (!isTRUE(rr$join_ok)) return(NULL)

  parsed <- parse_composition(
    top_subtypes = rr$top_subtypes,
    subtype_count_json = rr$subtype_count_json
  )

  if (nrow(parsed) == 0) return(NULL)

  parsed %>%
    mutate(
      rep = rr$rep,
      rep_label = rr$rep_label,
      prefix = rr$prefix,
      subtype = rr$subtype,
      stable_class = rr$stable_class,
      stable_class_disp = STABLE_CLASS_MAP[rr$stable_class],
      k_min = rr$k_min
    )
})

comp_long_all <- bind_rows(comp_rows)
if (nrow(comp_long_all) == 0) stop("No composition data parsed.")

fill_order_global <- comp_long_all %>%
  filter(percent > 0) %>%
  group_by(component_subtype) %>%
  summarise(total_pct = sum(percent, na.rm = TRUE), .groups = "drop") %>%
  arrange(desc(total_pct), component_subtype) %>%
  pull(component_subtype)

fill_cols_global <- setNames(
  grDevices::hcl.colors(length(fill_order_global), palette = "Dark 3"),
  fill_order_global
)

make_combined_legend <- function(fill_order_global, fill_cols_global) {
  class_df <- data.frame(
    group = "Stable class",
    label = c("MCX-specific", "DLPFC-specific", "Cross-region"),
    color = STABLE_CLASS_COLORS[c("MCX-specific", "DLPFC-specific", "Cross-region")],
    x = 0.20,
    y = c(2.40, 1.88, 1.36),
    stringsAsFactors = FALSE
  )

  cell_df <- data.frame(
    group = "Cell type",
    label = fill_order_global,
    color = fill_cols_global[fill_order_global],
    stringsAsFactors = FALSE
  ) %>%
    mutate(
      col = ifelse(row_number() <= ceiling(n() / 2), 1, 2),
      row = ifelse(col == 1, row_number(), row_number() - ceiling(n() / 2)),
      x = ifelse(col == 1, 2.10, 3.0),
      y = 2.40 - (row - 1) * 0.52
    )

  legend_df <- bind_rows(class_df, cell_df)

  title_df <- data.frame(
    title = c("Stable class", "Cell type"),
    x = c(0.20, 2.10),
    y = c(3.05, 3.05),
    stringsAsFactors = FALSE
  )

  ggplot() +
    geom_text(
      data = title_df,
      aes(x = x, y = y, label = title),
      hjust = 0,
      fontface = "bold",
      size = 6
    ) +
    geom_point(
      data = legend_df,
      aes(x = x, y = y, color = label),
      shape = 15,
      size = 7
    ) +
    geom_text(
      data = legend_df,
      aes(x = x + 0.22, y = y, label = label),
      hjust = 0,
      vjust = 0.5,
      size = 5.5
    ) +
    scale_color_manual(values = c(STABLE_CLASS_COLORS, fill_cols_global), guide = "none") +
    coord_cartesian(xlim = c(0, 5.2), ylim = c(0.7, 3.35), clip = "off") +
    theme_void() +
    theme(
      plot.margin = margin(2, 2, 2, 2)
    )
}

build_block_plot <- function(
  block_title,
  stable_class_keys,
  rep_labels_keep
) {
  row_info_block <- row_info_all %>%
    filter(stable_class %in% stable_class_keys) %>%
    arrange(prefix, desc(mean_capture_any), subtype) %>%
    mutate(
      row_id = row_number(),
      subtype_label = subtype,
      stable_class_disp = as.character(stable_class_disp),
      class_fill = STABLE_CLASS_COLORS[stable_class_disp]
    )

  if (nrow(row_info_block) == 0) return(NULL)

  n_rows <- nrow(row_info_block)

  prefix_blocks <- row_info_block %>%
    mutate(prefix = as.character(prefix)) %>%
    group_by(prefix) %>%
    summarise(
      y_mid = mean(row_id),
      y_min = min(row_id) - 0.5,
      y_max = max(row_id) + 0.5,
      .groups = "drop"
    )

  comp_block <- comp_long_all %>%
    filter(rep_label %in% rep_labels_keep, stable_class %in% stable_class_keys) %>%
    inner_join(
      row_info_block %>%
        select(prefix, subtype, stable_class, stable_class_disp, row_id, subtype_label),
      by = c("prefix", "subtype", "stable_class", "stable_class_disp")
    )

  comp_plot_df <- comp_block %>%
    filter(percent > 0, component_subtype %in% fill_order_global) %>%
    mutate(
      rep_label = factor(as.character(rep_label), levels = rep_labels_keep),
      component_subtype = factor(as.character(component_subtype), levels = fill_order_global),
      is_focal = as.character(component_subtype) == subtype
    ) %>%
    group_by(rep_label, row_id, subtype, k_min) %>%
    arrange(desc(is_focal), desc(percent), component_subtype, .by_group = TRUE) %>%
    mutate(
      pct_prev = lag(cumsum(percent), default = 0),
      pct_now  = cumsum(percent),
      ymin = row_id - 0.45 + 0.9 * (pct_prev / 100),
      ymax = row_id - 0.45 + 0.9 * (pct_now / 100),
      xmin = k_min - 0.48,
      xmax = k_min + 0.48
    ) %>%
    ungroup()

  bar_total_check <- comp_plot_df %>%
    group_by(rep_label, row_id, subtype, k_min) %>%
    summarise(sum_percent = max(pct_now), .groups = "drop")

  write.table(
    bar_total_check,
    file = file.path(
      OUTDIR,
      paste0("bar_total_check_", gsub("[^A-Za-z0-9]+", "_", block_title), ".tsv")
    ),
    sep = "\t", quote = FALSE, row.names = FALSE
  )

  p_class <- ggplot() +
    geom_rect(
      data = prefix_blocks,
      aes(xmin = 0.00, xmax = 0.22, ymin = y_min, ymax = y_max),
      fill = "grey92", color = NA
    ) +
    geom_text(
      data = prefix_blocks,
      aes(x = 0.11, y = y_mid, label = prefix),
      fontface = "bold", size = 6
    ) +
    geom_rect(
      data = row_info_block,
      aes(
        xmin = 0.28, xmax = 0.96,
        ymin = row_id - 0.48,
        ymax = row_id + 0.48
      ),
      fill = row_info_block$class_fill,
      color = NA
    ) +
    scale_y_reverse(limits = c(n_rows + 0.5, 0.5), expand = c(0, 0)) +
    xlim(0, 1) +
    theme_void(base_size = 12) +
    theme(legend.position = "none")

  p_label <- ggplot(row_info_block, aes(x = 0, y = row_id, label = subtype_label)) +
    geom_text(
      aes(color = stable_class_disp),
      hjust = 0, fontface = "bold", size = 6, show.legend = FALSE
    ) +
    scale_color_manual(values = STABLE_CLASS_COLORS, drop = FALSE) +
    scale_y_reverse(limits = c(n_rows + 0.5, 0.5), expand = c(0, 0)) +
    xlim(0, 1.05) +
    theme_void(base_size = 12)

  p_comp <- ggplot() +
    geom_hline(
      yintercept = seq(0.5, n_rows + 0.5, by = 1),
      color = "white",
      linewidth = 0.7
    ) +
    geom_rect(
      data = comp_plot_df,
      aes(
        xmin = xmin, xmax = xmax,
        ymin = ymin, ymax = ymax,
        fill = component_subtype
      ),
      color = NA
    ) +
    facet_grid(. ~ rep_label) +
    scale_fill_manual(
      values = fill_cols_global,
      breaks = fill_order_global,
      labels = fill_order_global,
      name = NULL,
      drop = TRUE
    ) +
    scale_x_continuous(
      breaks = KMIN_RANGE,
      labels = KMIN_RANGE,
      limits = c(min(KMIN_RANGE) - 0.5, max(KMIN_RANGE) + 0.5),
      expand = c(0, 0)
    ) +
    scale_y_reverse(
      limits = c(n_rows + 0.5, 0.5),
      expand = c(0, 0)
    ) +
    labs(x = "k_min", y = NULL) +
    theme_minimal(base_size = 12) +
    theme(
      axis.text.x = element_text(size = 11),
      axis.text.y = element_blank(),
      axis.title.x = element_text(size = 16, face = "bold"),
      panel.grid = element_blank(),
      panel.background = element_rect(fill = "grey98", color = NA),
      strip.text.x = element_text(size = 16, face = "bold"),
      strip.background = element_rect(fill = "grey95", color = NA),
      legend.position = "none"
    )

  block_plot <- p_class + p_label + p_comp +
    plot_layout(widths = c(0.55, 2.3, 8.7)) +
    plot_annotation(
      title = block_title,
      theme = theme(
        plot.title = element_text(size = 18, face = "bold", hjust = 0.5)
      )
    )

  list(plot = block_plot, nrows = n_rows)
}

block_mcx <- build_block_plot(
  block_title = "MCX-specific stable",
  stable_class_keys = "MCX_specific_stable",
  rep_labels_keep = c("FTLD-MCX", "SALS-MCX")
)

block_pfc <- build_block_plot(
  block_title = "DLPFC-specific stable",
  stable_class_keys = "PFC_specific_stable",
  rep_labels_keep = c("FTLD-DLPFC", "SALS-DLPFC")
)

block_cross <- build_block_plot(
  block_title = "Cross-region stable",
  stable_class_keys = "Cross_region_stable",
  rep_labels_keep = c("FTLD-MCX", "SALS-MCX", "FTLD-DLPFC", "SALS-DLPFC")
)

blocks <- list(block_mcx, block_pfc, block_cross)
blocks <- blocks[!vapply(blocks, is.null, logical(1))]

if (length(blocks) == 0) stop("No non-empty blocks to plot.")

block_plots <- lapply(blocks, `[[`, "plot")
block_heights <- vapply(blocks, `[[`, numeric(1), "nrows")

legend_plot <- make_combined_legend(fill_order_global, fill_cols_global)
body_plot <- wrap_plots(block_plots, ncol = 1, heights = block_heights)

final_plot <- legend_plot / body_plot +
  plot_layout(heights = c(1.25, sum(block_heights)))

out_png <- file.path(OUTDIR, "In_Ex_mainhit_composition_by_stable_class_blocks_cleanlegend_usedonly.png")

save_plot_both(
  final_plot,
  out_png,
  width = 24,
  height = max(11.5, 1.1 * sum(block_heights) + 6.5),
  save_pdf = SAVE_PDF
)

cat("[DONE] plot written to: ", out_png, "\n", sep = "")
