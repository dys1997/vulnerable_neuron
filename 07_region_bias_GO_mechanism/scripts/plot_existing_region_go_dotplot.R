#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(ggplot2)
  library(stringr)
})

# =========================================================
# Direct visualization of existing GO results.
# This script does NOT run DEG or GO enrichment.
# It only reads four existing GO tables:
#   pfc_up, pfc_down, mcx_up, mcx_down
# from config/existing_go_plot_config.tsv, merges them, and plots.
# =========================================================

parse_args_simple <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  out <- list()
  i <- 1
  while (i <= length(args)) {
    key <- args[i]
    if (startsWith(key, "--")) {
      key2 <- sub("^--", "", key)
      if (i == length(args) || startsWith(args[i + 1], "--")) {
        out[[key2]] <- TRUE
        i <- i + 1
      } else {
        out[[key2]] <- args[i + 1]
        i <- i + 2
      }
    } else {
      i <- i + 1
    }
  }
  out
}

opt <- parse_args_simple()
required_args <- c("config", "contrast", "outdir")
missing_args <- required_args[!required_args %in% names(opt)]
if (length(missing_args) > 0) {
  stop("Missing required arguments: ", paste(missing_args, collapse = ", "))
}

config_fp <- opt[["config"]]
contrast_name <- opt[["contrast"]]
outdir <- opt[["outdir"]]
width <- ifelse("width" %in% names(opt), as.numeric(opt[["width"]]), 12)
height <- ifelse("height" %in% names(opt), as.numeric(opt[["height"]]), 6.5)
auto_top_n <- ifelse("auto-top-n" %in% names(opt), as.integer(opt[["auto-top-n"]]), 6)
dir.create(outdir, recursive = TRUE, showWarnings = FALSE)

split_semicolon <- function(x) {
  if (length(x) == 0 || is.na(x) || trimws(x) == "") return(character(0))
  y <- unlist(strsplit(x, ";", fixed = TRUE))
  y <- trimws(y)
  y[y != ""]
}

parse_gene_ratio <- function(x) {
  out <- sapply(x, function(z) {
    if (is.na(z)) return(NA_real_)
    z <- as.character(z)
    if (grepl("/", z, fixed = TRUE)) {
      a <- strsplit(z, "/", fixed = TRUE)[[1]]
      if (length(a) != 2) return(NA_real_)
      num <- suppressWarnings(as.numeric(a[1]))
      den <- suppressWarnings(as.numeric(a[2]))
      if (is.na(num) || is.na(den) || den == 0) return(NA_real_)
      return(num / den)
    }
    zz <- suppressWarnings(as.numeric(z))
    if (!is.na(zz)) return(zz)
    return(NA_real_)
  })
  as.numeric(out)
}

make_term_label <- function(x) {
  x <- as.character(x)
  x <- str_replace_all(x, "_", " ")
  x <- str_to_sentence(x)
  x <- str_wrap(x, width = 28)
  x
}

read_config <- function(config_fp, contrast_name) {
  if (!file.exists(config_fp)) stop("Config file not found: ", config_fp)
  cfg <- readr::read_tsv(
    config_fp,
    show_col_types = FALSE,
    col_types = readr::cols(.default = readr::col_character())
  )
  if (!"contrast" %in% colnames(cfg)) {
    stop("Config file must contain column 'contrast'. Columns: ", paste(colnames(cfg), collapse = ", "))
  }
  cfg$contrast <- trimws(cfg$contrast)
  contrast_name <- trimws(contrast_name)
  row <- cfg[cfg$contrast == contrast_name, , drop = FALSE]
  if (nrow(row) != 1) {
    message("[debug] contrast_name = ", contrast_name)
    message("[debug] matched rows = ", nrow(row))
    message("[debug] available contrasts:")
    print(cfg$contrast)
    stop("Cannot find exactly one config row for contrast: ", contrast_name)
  }
  row
}

read_go_one <- function(fp, region, direction, short_label) {
  if (is.na(fp) || trimws(fp) == "") {
    message("[warn] Empty path for ", region, " ", direction)
    return(data.frame())
  }
  if (!file.exists(fp)) {
    message("[warn] GO file not found: ", fp)
    return(data.frame())
  }
  if (file.info(fp)$size == 0) {
    message("[warn] Empty GO file: ", fp)
    return(data.frame())
  }
  x <- suppressMessages(readr::read_tsv(fp, show_col_types = FALSE))
  if (nrow(x) == 0) {
    message("[warn] No rows in GO file: ", fp)
    return(data.frame())
  }
  required_cols <- c("Description", "p.adjust", "GeneRatio")
  missing_cols <- setdiff(required_cols, colnames(x))
  if (length(missing_cols) > 0) {
    stop("GO file missing required columns: ", paste(missing_cols, collapse = ", "), " in ", fp)
  }
  x %>%
    mutate(
      Description = as.character(.data$Description),
      p.adjust = suppressWarnings(as.numeric(.data$p.adjust)),
      GeneRatio = as.character(.data$GeneRatio),
      Region = region,
      direction_raw = direction,
      Direction = paste0(short_label, " ", direction),
      source_file = fp
    ) %>%
    filter(!is.na(.data$Description), .data$Description != "", !is.na(.data$p.adjust))
}

pick_selected_terms <- function(go_all, terms_up, terms_down, auto_top_n) {
  selected_up <- data.frame()
  selected_down <- data.frame()

  if (length(terms_up) > 0) {
    selected_up <- go_all %>%
      filter(.data$direction_raw == "up", .data$Description %in% terms_up)
  }
  if (length(terms_down) > 0) {
    selected_down <- go_all %>%
      filter(.data$direction_raw == "down", .data$Description %in% terms_down)
  }

  if (nrow(selected_up) == 0) {
    message("[warn] No configured UP terms found. Fallback to top UP GO terms.")
    selected_up <- go_all %>%
      filter(.data$direction_raw == "up") %>%
      group_by(.data$Region) %>%
      arrange(.data$p.adjust, .by_group = TRUE) %>%
      slice_head(n = auto_top_n) %>%
      ungroup()
  }

  if (nrow(selected_down) == 0) {
    message("[warn] No configured DOWN terms found. Fallback to top DOWN GO terms.")
    selected_down <- go_all %>%
      filter(.data$direction_raw == "down") %>%
      group_by(.data$Region) %>%
      arrange(.data$p.adjust, .by_group = TRUE) %>%
      slice_head(n = auto_top_n) %>%
      ungroup()
  }

  bind_rows(selected_down, selected_up)
}

save_empty_plot <- function(pdf_fp, png_fp, tsv_fp, title, label) {
  write_tsv(data.frame(), tsv_fp)
  p <- ggplot() +
    annotate("text", x = 0, y = 0, label = label, size = 6) +
    theme_void() +
    labs(title = title)
  ggsave(pdf_fp, plot = p, width = width, height = height)
  ggsave(png_fp, plot = p, width = width, height = height, dpi = 300)
}

cfg_row <- read_config(config_fp, contrast_name)
short_label <- cfg_row$short_label[[1]]
if (is.na(short_label) || trimws(short_label) == "") short_label <- contrast_name
plot_title <- cfg_row$plot_title[[1]]
if (is.na(plot_title) || trimws(plot_title) == "") {
  plot_title <- paste0("PFC vs MCX: representative GO terms in ", short_label)
}
terms_up <- split_semicolon(cfg_row$up_terms[[1]])
terms_down <- split_semicolon(cfg_row$down_terms[[1]])

pfc_up_fp <- cfg_row$pfc_up[[1]]
pfc_down_fp <- cfg_row$pfc_down[[1]]
mcx_up_fp <- cfg_row$mcx_up[[1]]
mcx_down_fp <- cfg_row$mcx_down[[1]]

message("[info] contrast: ", contrast_name)
message("[info] short_label: ", short_label)
message("[info] phenotype_region_bias: ", cfg_row$phenotype_region_bias[[1]])
message("[info] up terms: ", paste(terms_up, collapse = " | "))
message("[info] down terms: ", paste(terms_down, collapse = " | "))
message("[info] Reading GO files:")
message("  PFC up:   ", pfc_up_fp)
message("  PFC down: ", pfc_down_fp)
message("  MCX up:   ", mcx_up_fp)
message("  MCX down: ", mcx_down_fp)

go_all <- bind_rows(
  read_go_one(pfc_up_fp, "PFC", "up", short_label),
  read_go_one(pfc_down_fp, "PFC", "down", short_label),
  read_go_one(mcx_up_fp, "MCX", "up", short_label),
  read_go_one(mcx_down_fp, "MCX", "down", short_label)
)

pdf_fp <- file.path(outdir, paste0(contrast_name, "_PFC_vs_MCX_GO_bias_dotplot.pdf"))
png_fp <- file.path(outdir, paste0(contrast_name, "_PFC_vs_MCX_GO_bias_dotplot.png"))
tsv_fp <- file.path(outdir, paste0(contrast_name, "_PFC_vs_MCX_GO_bias_dotplot_data.tsv"))

if (nrow(go_all) == 0) {
  message("[warn] No GO results found for contrast: ", contrast_name)
  save_empty_plot(pdf_fp, png_fp, tsv_fp, plot_title, "No GO terms found")
  quit(save = "no", status = 0)
}

selected <- pick_selected_terms(go_all, terms_up, terms_down, auto_top_n)
if (nrow(selected) == 0) {
  message("[warn] No selected GO terms after fallback.")
  save_empty_plot(pdf_fp, png_fp, tsv_fp, plot_title, "No selected GO terms")
  quit(save = "no", status = 0)
}

selected <- selected %>%
  mutate(
    log10_padj = -log10(pmax(.data$p.adjust, .Machine$double.xmin)),
    GeneRatio_num = parse_gene_ratio(.data$GeneRatio),
    term_show = make_term_label(.data$Description),
    Region = factor(.data$Region, levels = c("MCX", "PFC")),
    Direction = factor(.data$Direction, levels = c(paste0(short_label, " down"), paste0(short_label, " up")))
  )

if (all(is.na(selected$GeneRatio_num))) {
  message("[warn] All GeneRatio values are NA. Use fixed point size.")
  selected$GeneRatio_num <- 0.05
}
selected$GeneRatio_num[is.na(selected$GeneRatio_num)] <- median(selected$GeneRatio_num, na.rm = TRUE)

configured_down_labels <- make_term_label(terms_down)
configured_up_labels <- make_term_label(terms_up)

down_present <- selected %>%
  filter(.data$direction_raw == "down") %>%
  arrange(.data$p.adjust) %>%
  pull(.data$term_show) %>%
  unique()
up_present <- selected %>%
  filter(.data$direction_raw == "up") %>%
  arrange(.data$p.adjust) %>%
  pull(.data$term_show) %>%
  unique()

down_levels <- unique(c(configured_down_labels[configured_down_labels %in% down_present], down_present))
up_levels <- unique(c(configured_up_labels[configured_up_labels %in% up_present], up_present))
all_levels <- unique(c(down_levels, up_levels))
selected$term_show <- factor(selected$term_show, levels = all_levels)

p <- ggplot(selected, aes(x = .data$log10_padj, y = .data$term_show)) +
  geom_point(aes(size = .data$GeneRatio_num, color = .data$Region), alpha = 0.9) +
  facet_wrap(~Direction, scales = "free_y", ncol = 2, drop = TRUE) +
  scale_color_manual(values = c(MCX = "#F8766D", PFC = "#00BFC4"), drop = FALSE) +
  scale_size_continuous(name = "GeneRatio", range = c(3, 9)) +
  labs(
    x = expression(-log[10](adjusted~P)),
    y = NULL,
    color = "Region",
    title = plot_title
  ) +
  theme_bw(base_size = 13) +
  theme(
    strip.background = element_rect(fill = "grey90", color = "black"),
    strip.text = element_text(face = "bold", size = 12),
    axis.text.y = element_text(color = "black", size = 11),
    axis.text.x = element_text(color = "black"),
    axis.title.x = element_text(face = "bold"),
    legend.position = "right",
    panel.grid.minor = element_blank(),
    plot.title = element_text(face = "bold", hjust = 0.5)
  )

ggsave(pdf_fp, plot = p, width = width, height = height)
ggsave(png_fp, plot = p, width = width, height = height, dpi = 300)
write_tsv(selected, tsv_fp)

message("[done] Saved:")
message("  ", pdf_fp)
message("  ", png_fp)
message("  ", tsv_fp)
