# #!/usr/bin/env Rscript

# # ============================================================
# # Panel C
# # MCX-higher structural glia -> vulnerable neuron communication
# # ggplot2 + ggalluvial version
# #
# # THSD4 removed because it only exists in MCX.
# # ============================================================

# suppressPackageStartupMessages({
#   library(readr)
#   library(dplyr)
#   library(stringr)
#   library(ggplot2)
#   library(ggalluvial)
# })

# args <- commandArgs(trailingOnly = TRUE)

# if (length(args) < 4) {
#   stop(
#     "Usage: Rscript mainfig_panelC_mcx_higher_alluvial.R ",
#     "<altered_interactions.tsv> <out.pdf> <out.png> <selected.tsv> ",
#     "[top_classes=7] [min_abs_delta=0]"
#   )
# }

# altered_fp <- args[1]
# out_pdf <- args[2]
# out_png <- args[3]
# out_tsv <- args[4]
# top_classes_n <- ifelse(length(args) >= 5, as.integer(args[5]), 7)
# min_abs_delta <- ifelse(length(args) >= 6, as.numeric(args[6]), 0)

# df <- read_tsv(altered_fp, show_col_types = FALSE)

# required_cols <- c(
#   "source", "target", "interaction_name", "pathway_name",
#   "delta_MCX_minus_PFC", "direction", "abs_delta", "direction_mode"
# )

# missing_cols <- setdiff(required_cols, colnames(df))
# if (length(missing_cols) > 0) {
#   stop(
#     "Missing required columns: ",
#     paste(missing_cols, collapse = ", "),
#     "\nCurrent columns are:\n",
#     paste(colnames(df), collapse = ", ")
#   )
# }

# # ============================================================
# # Helper functions
# # ============================================================

# simplify_source <- function(x) {
#   case_when(
#     str_detect(x, regex("GFAP[-_\\. ]?neg|Astro.*neg", ignore_case = TRUE)) ~ "Astro GFAP-",
#     str_detect(x, regex("GFAP[-_\\. ]?pos|Astro.*pos", ignore_case = TRUE)) ~ "Astro GFAP+",
#     str_detect(x, regex("OPC", ignore_case = TRUE)) ~ "OPC",
#     str_detect(x, regex("Olig|Olg|OL", ignore_case = TRUE)) ~ "Oligo",
#     str_detect(x, regex("Micro|Mic", ignore_case = TRUE)) ~ "Micro",
#     str_detect(x, regex("Astro|Ast", ignore_case = TRUE)) ~ "Astro",
#     TRUE ~ x
#   )
# }

# simplify_target <- function(x) {
#   case_when(
#     str_detect(x, regex("PTHLH", ignore_case = TRUE)) ~ "PTHLH",
#     str_detect(x, regex("CEMIP", ignore_case = TRUE)) ~ "CEMIP",
#     str_detect(x, regex("PCP4|NXPH2", ignore_case = TRUE)) ~ "PCP4_NXPH2",
#     str_detect(x, regex("CDH4|CDH4_plus|CDH4_CCK|CDH4_SCGN", ignore_case = TRUE)) ~ "CDH4+",
#     TRUE ~ x
#   )
# }

# classify_interaction <- function(pathway, interaction) {
#   txt <- paste(pathway, interaction)

#   case_when(
#     str_detect(txt, regex("NRXN|NLGN", ignore_case = TRUE)) ~ "NRXN",
#     str_detect(txt, regex("NRG|ERBB", ignore_case = TRUE)) ~ "NRG",
#     str_detect(txt, regex("NCAM", ignore_case = TRUE)) ~ "NCAM",
#     str_detect(txt, regex("CNTN|NRCAM|CNTNAP", ignore_case = TRUE)) ~ "CNTN",
#     str_detect(txt, regex("NEGR", ignore_case = TRUE)) ~ "NEGR",
#     str_detect(txt, regex("CADM", ignore_case = TRUE)) ~ "CADM",
#     str_detect(txt, regex("NGL|LRRC4|NTNG", ignore_case = TRUE)) ~ "NGL",
#     str_detect(txt, regex("TENASCIN|TNC|TNR", ignore_case = TRUE)) ~ "TENASCIN",
#     str_detect(txt, regex("CDH", ignore_case = TRUE)) ~ "CDH",
#     str_detect(txt, regex("LAMA|LAMININ", ignore_case = TRUE)) ~ "LAMININ",
#     str_detect(txt, regex("PTN|ALK|PTPRZ", ignore_case = TRUE)) ~ "PTN",
#     str_detect(txt, regex("EFN|EPH", ignore_case = TRUE)) ~ "EPHA/EFNA",
#     str_detect(txt, regex("SEMA|PLXN", ignore_case = TRUE)) ~ "SEMA/PLXN",
#     TRUE ~ pathway
#   )
# }

# wrap_source <- function(x) {
#   case_when(
#     x == "Astro GFAP-" ~ "Astro\nGFAP-",
#     x == "Astro GFAP+" ~ "Astro\nGFAP+",
#     TRUE ~ x
#   )
# }

# wrap_target <- function(x) {
#   case_when(
#     x == "PCP4_NXPH2" ~ "PCP4\nNXPH2",
#     TRUE ~ x
#   )
# }

# # ============================================================
# # 1. Filter MCX-higher glia -> shared vulnerable neuron targets
# #    THSD4 intentionally removed.
# # ============================================================

# plot_df <- df %>%
#   filter(direction_mode == "glia_to_neuron") %>%
#   mutate(
#     source_simple = simplify_source(source),
#     target_simple = simplify_target(target),
#     interaction_class = classify_interaction(pathway_name, interaction_name),
#     delta_value = as.numeric(delta_MCX_minus_PFC),
#     abs_delta_value = as.numeric(abs_delta),
#     region_higher = direction
#   ) %>%
#   filter(
#     region_higher == "MCX_higher",
#     abs_delta_value >= min_abs_delta,
#     target_simple %in% c("PTHLH", "CEMIP", "PCP4_NXPH2", "CDH4+")
#   )

# if (nrow(plot_df) == 0) {
#   stop("No MCX_higher glia_to_neuron interactions left after filtering.")
# }

# # ============================================================
# # 2. Select top interaction classes
# # ============================================================

# plot_df_top <- plot_df %>%
#   group_by(target_simple) %>%
#   arrange(desc(abs_delta_value), .by_group = TRUE) %>%
#   slice_head(n = 25) %>%
#   ungroup()

# top_classes <- plot_df_top %>%
#   group_by(interaction_class) %>%
#   summarise(total_delta = sum(abs_delta_value, na.rm = TRUE), .groups = "drop") %>%
#   arrange(desc(total_delta)) %>%
#   slice_head(n = top_classes_n) %>%
#   pull(interaction_class)

# plot_df_final <- plot_df_top %>%
#   filter(interaction_class %in% top_classes) %>%
#   group_by(source_simple, interaction_class, target_simple) %>%
#   summarise(
#     weight = sum(abs_delta_value, na.rm = TRUE),
#     n_interactions = n(),
#     examples = paste(
#       unique(interaction_name)[seq_len(min(6, length(unique(interaction_name))))],
#       collapse = "; "
#     ),
#     .groups = "drop"
#   ) %>%
#   filter(weight > 0)

# if (nrow(plot_df_final) == 0) {
#   stop("No rows left after selecting top interaction classes.")
# }

# # ============================================================
# # 3. Clean labels and ordering
# # ============================================================

# source_order <- c("Astro GFAP-", "Astro GFAP+", "OPC", "Oligo", "Micro")
# target_order <- c("CDH4+", "PTHLH", "CEMIP", "PCP4_NXPH2")

# class_order <- c(
#   "NRXN", "NRG", "NCAM", "CNTN", "NEGR", "CADM", "NGL",
#   "TENASCIN", "CDH", "LAMININ", "PTN", "EPHA/EFNA", "SEMA/PLXN"
# )

# plot_df_final <- plot_df_final %>%
#   mutate(
#     source_simple = factor(source_simple, levels = source_order[source_order %in% unique(source_simple)]),
#     target_simple = factor(target_simple, levels = target_order[target_order %in% unique(target_simple)]),
#     interaction_class = factor(
#       interaction_class,
#       levels = class_order[class_order %in% unique(interaction_class)]
#     ),
#     source_plot = factor(
#       wrap_source(as.character(source_simple)),
#       levels = wrap_source(source_order[source_order %in% as.character(source_simple)])
#     ),
#     target_plot = factor(
#       wrap_target(as.character(target_simple)),
#       levels = wrap_target(target_order[target_order %in% as.character(target_simple)])
#     )
#   )

# write_tsv(plot_df_final, out_tsv)

# message("[INFO] Selected rows: ", nrow(plot_df_final))
# message("[INFO] Targets included: ", paste(unique(as.character(plot_df_final$target_simple)), collapse = ", "))
# message("[INFO] Classes included: ", paste(unique(as.character(plot_df_final$interaction_class)), collapse = ", "))

# # ============================================================
# # 4. Color palette
# # ============================================================

# class_palette <- c(
#   "NRXN" = "#7B68EE",
#   "NRG" = "#00A6D6",
#   "NCAM" = "#66A61E",
#   "CNTN" = "#D8B365",
#   "NEGR" = "#1B9E77",
#   "CADM" = "#F8766D",
#   "NGL" = "#4DBBD5",
#   "TENASCIN" = "#C77CFF",
#   "CDH" = "#E69F00",
#   "LAMININ" = "#999999",
#   "PTN" = "#E7298A",
#   "EPHA/EFNA" = "#A6761D",
#   "SEMA/PLXN" = "#7570B3"
# )

# class_palette <- class_palette[names(class_palette) %in% unique(as.character(plot_df_final$interaction_class))]

# # ============================================================
# # 5. Plot
# # ============================================================

# p <- ggplot(
#   plot_df_final,
#   aes(
#     axis1 = source_plot,
#     axis2 = interaction_class,
#     axis3 = target_plot,
#     y = weight
#   )
# ) +
#   geom_alluvium(
#     aes(fill = interaction_class),
#     width = 0.20,
#     alpha = 0.72,
#     knot.pos = 0.43,
#     color = NA
#   ) +
#   geom_stratum(
#     width = 0.20,
#     fill = "grey97",
#     color = "grey30",
#     linewidth = 0.35
#   ) +
#   geom_text(
#     stat = "stratum",
#     aes(label = after_stat(stratum)),
#     size = 3.6,
#     lineheight = 0.85,
#     color = "black"
#   ) +
#   scale_x_discrete(
#     limits = c("Glia sender", "Interaction class", "Vulnerable target"),
#     expand = c(0.10, 0.06)
#   ) +
#   scale_fill_manual(
#     values = class_palette,
#     name = "Interaction class"
#   ) +
#   labs(
#     title = "MCX-higher structural glia-neuron communication across shared vulnerable targets",
#     x = NULL,
#     y = "Summed MCX - PFC communication difference"
#   ) +
#   theme_classic(base_size = 14) +
#   theme(
#     plot.title = element_text(face = "bold", hjust = 0.5, size = 18),
#     axis.text.x = element_text(size = 14, color = "black"),
#     axis.text.y = element_text(size = 12, color = "black"),
#     axis.title.y = element_text(size = 13, color = "black"),
#     legend.position = "bottom",
#     legend.title = element_text(size = 11),
#     legend.text = element_text(size = 10),
#     legend.key.width = unit(0.8, "cm"),
#     panel.grid = element_blank(),
#     plot.margin = margin(10, 20, 10, 20)
#   ) +
#   guides(
#     fill = guide_legend(
#       nrow = 2,
#       byrow = TRUE,
#       override.aes = list(alpha = 0.85)
#     )
#   ) +
#   coord_cartesian(clip = "off")

# ggsave(out_pdf, p, width = 13.5, height = 6.6, device = "pdf", useDingbats = FALSE)
# ggsave(out_png, p, width = 13.5, height = 6.6, dpi = 300)

# message("[INFO] Saved PDF: ", out_pdf)
# message("[INFO] Saved PNG: ", out_png)
#!/usr/bin/env Rscript

# ============================================================
# Panel C
# MCX-higher structural glia -> vulnerable neuron communication
# ggplot2 + ggalluvial version
#
# THSD4 removed because it only exists in MCX.
#
# Update:
#   - remove y-axis numbers/ticks/line
#   - remove x-axis line and ticks
#   - use caption to explain flow width
# ============================================================

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(stringr)
  library(ggplot2)
  library(ggalluvial)
  library(grid)
})

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 4) {
  stop(
    "Usage: Rscript mainfig_panelC_mcx_higher_alluvial.R ",
    "<altered_interactions.tsv> <out.pdf> <out.png> <selected.tsv> ",
    "[top_classes=7] [min_abs_delta=0]"
  )
}

altered_fp <- args[1]
out_pdf <- args[2]
out_png <- args[3]
out_tsv <- args[4]
top_classes_n <- ifelse(length(args) >= 5, as.integer(args[5]), 7)
min_abs_delta <- ifelse(length(args) >= 6, as.numeric(args[6]), 0)

df <- read_tsv(altered_fp, show_col_types = FALSE)

required_cols <- c(
  "source", "target", "interaction_name", "pathway_name",
  "delta_MCX_minus_PFC", "direction", "abs_delta", "direction_mode"
)

missing_cols <- setdiff(required_cols, colnames(df))
if (length(missing_cols) > 0) {
  stop(
    "Missing required columns: ",
    paste(missing_cols, collapse = ", "),
    "\nCurrent columns are:\n",
    paste(colnames(df), collapse = ", ")
  )
}

# ============================================================
# Helper functions
# ============================================================

simplify_source <- function(x) {
  case_when(
    str_detect(x, regex("GFAP[-_\\. ]?neg|Astro.*neg", ignore_case = TRUE)) ~ "Astro GFAP-",
    str_detect(x, regex("GFAP[-_\\. ]?pos|Astro.*pos", ignore_case = TRUE)) ~ "Astro GFAP+",
    str_detect(x, regex("OPC", ignore_case = TRUE)) ~ "OPC",
    str_detect(x, regex("Olig|Olg|OL", ignore_case = TRUE)) ~ "Oligo",
    str_detect(x, regex("Micro|Mic", ignore_case = TRUE)) ~ "Micro",
    str_detect(x, regex("Astro|Ast", ignore_case = TRUE)) ~ "Astro",
    TRUE ~ x
  )
}

simplify_target <- function(x) {
  case_when(
    str_detect(x, regex("PTHLH", ignore_case = TRUE)) ~ "PTHLH",
    str_detect(x, regex("CEMIP", ignore_case = TRUE)) ~ "CEMIP",
    str_detect(x, regex("PCP4|NXPH2", ignore_case = TRUE)) ~ "PCP4_NXPH2",
    str_detect(x, regex("CDH4|CDH4_plus|CDH4_CCK|CDH4_SCGN", ignore_case = TRUE)) ~ "CDH4+",
    TRUE ~ x
  )
}

classify_interaction <- function(pathway, interaction) {
  txt <- paste(pathway, interaction)

  case_when(
    str_detect(txt, regex("NRXN|NLGN", ignore_case = TRUE)) ~ "NRXN",
    str_detect(txt, regex("NRG|ERBB", ignore_case = TRUE)) ~ "NRG",
    str_detect(txt, regex("NCAM", ignore_case = TRUE)) ~ "NCAM",
    str_detect(txt, regex("CNTN|NRCAM|CNTNAP", ignore_case = TRUE)) ~ "CNTN",
    str_detect(txt, regex("NEGR", ignore_case = TRUE)) ~ "NEGR",
    str_detect(txt, regex("CADM", ignore_case = TRUE)) ~ "CADM",
    str_detect(txt, regex("NGL|LRRC4|NTNG", ignore_case = TRUE)) ~ "NGL",
    str_detect(txt, regex("TENASCIN|TNC|TNR", ignore_case = TRUE)) ~ "TENASCIN",
    str_detect(txt, regex("CDH", ignore_case = TRUE)) ~ "CDH",
    str_detect(txt, regex("LAMA|LAMININ", ignore_case = TRUE)) ~ "LAMININ",
    str_detect(txt, regex("PTN|ALK|PTPRZ", ignore_case = TRUE)) ~ "PTN",
    str_detect(txt, regex("EFN|EPH", ignore_case = TRUE)) ~ "EPHA/EFNA",
    str_detect(txt, regex("SEMA|PLXN", ignore_case = TRUE)) ~ "SEMA/PLXN",
    TRUE ~ pathway
  )
}

wrap_source <- function(x) {
  case_when(
    x == "Astro GFAP-" ~ "Astro\nGFAP-",
    x == "Astro GFAP+" ~ "Astro\nGFAP+",
    TRUE ~ x
  )
}

wrap_target <- function(x) {
  case_when(
    x == "PCP4_NXPH2" ~ "PCP4\nNXPH2",
    TRUE ~ x
  )
}

# ============================================================
# 1. Filter MCX-higher glia -> shared vulnerable neuron targets
#    THSD4 intentionally removed.
# ============================================================

plot_df <- df %>%
  filter(direction_mode == "glia_to_neuron") %>%
  mutate(
    source_simple = simplify_source(source),
    target_simple = simplify_target(target),
    interaction_class = classify_interaction(pathway_name, interaction_name),
    delta_value = as.numeric(delta_MCX_minus_PFC),
    abs_delta_value = as.numeric(abs_delta),
    region_higher = direction
  ) %>%
  filter(
    region_higher == "MCX_higher",
    abs_delta_value >= min_abs_delta,
    target_simple %in% c("PTHLH", "CEMIP", "PCP4_NXPH2", "CDH4+")
  )

if (nrow(plot_df) == 0) {
  stop("No MCX_higher glia_to_neuron interactions left after filtering.")
}

# ============================================================
# 2. Select top interaction classes
# ============================================================

plot_df_top <- plot_df %>%
  group_by(target_simple) %>%
  arrange(desc(abs_delta_value), .by_group = TRUE) %>%
  slice_head(n = 25) %>%
  ungroup()

top_classes <- plot_df_top %>%
  group_by(interaction_class) %>%
  summarise(total_delta = sum(abs_delta_value, na.rm = TRUE), .groups = "drop") %>%
  arrange(desc(total_delta)) %>%
  slice_head(n = top_classes_n) %>%
  pull(interaction_class)

plot_df_final <- plot_df_top %>%
  filter(interaction_class %in% top_classes) %>%
  group_by(source_simple, interaction_class, target_simple) %>%
  summarise(
    weight = sum(abs_delta_value, na.rm = TRUE),
    n_interactions = n(),
    examples = paste(
      unique(interaction_name)[seq_len(min(6, length(unique(interaction_name))))],
      collapse = "; "
    ),
    .groups = "drop"
  ) %>%
  filter(weight > 0)

if (nrow(plot_df_final) == 0) {
  stop("No rows left after selecting top interaction classes.")
}

# ============================================================
# 3. Clean labels and ordering
# ============================================================

source_order <- c("Astro GFAP-", "Astro GFAP+", "OPC", "Oligo", "Micro")
target_order <- c("CDH4+", "PTHLH", "CEMIP", "PCP4_NXPH2")

class_order <- c(
  "NRXN", "NRG", "NCAM", "CNTN", "NEGR", "CADM", "NGL",
  "TENASCIN", "CDH", "LAMININ", "PTN", "EPHA/EFNA", "SEMA/PLXN"
)

plot_df_final <- plot_df_final %>%
  mutate(
    source_simple = factor(
      source_simple,
      levels = source_order[source_order %in% unique(source_simple)]
    ),
    target_simple = factor(
      target_simple,
      levels = target_order[target_order %in% unique(target_simple)]
    ),
    interaction_class = factor(
      interaction_class,
      levels = class_order[class_order %in% unique(interaction_class)]
    ),
    source_plot = factor(
      wrap_source(as.character(source_simple)),
      levels = wrap_source(source_order[source_order %in% as.character(source_simple)])
    ),
    target_plot = factor(
      wrap_target(as.character(target_simple)),
      levels = wrap_target(target_order[target_order %in% as.character(target_simple)])
    )
  )

write_tsv(plot_df_final, out_tsv)

message("[INFO] Selected rows: ", nrow(plot_df_final))
message("[INFO] Targets included: ", paste(unique(as.character(plot_df_final$target_simple)), collapse = ", "))
message("[INFO] Classes included: ", paste(unique(as.character(plot_df_final$interaction_class)), collapse = ", "))

# ============================================================
# 4. Color palette
# ============================================================

class_palette <- c(
  "NRXN" = "#7B68EE",
  "NRG" = "#00A6D6",
  "NCAM" = "#66A61E",
  "CNTN" = "#D8B365",
  "NEGR" = "#1B9E77",
  "CADM" = "#F8766D",
  "NGL" = "#4DBBD5",
  "TENASCIN" = "#C77CFF",
  "CDH" = "#E69F00",
  "LAMININ" = "#999999",
  "PTN" = "#E7298A",
  "EPHA/EFNA" = "#A6761D",
  "SEMA/PLXN" = "#7570B3"
)

class_palette <- class_palette[
  names(class_palette) %in% unique(as.character(plot_df_final$interaction_class))
]

# ============================================================
# 5. Plot
# ============================================================

p <- ggplot(
  plot_df_final,
  aes(
    axis1 = source_plot,
    axis2 = interaction_class,
    axis3 = target_plot,
    y = weight
  )
) +
  geom_alluvium(
    aes(fill = interaction_class),
    width = 0.20,
    alpha = 0.72,
    knot.pos = 0.43,
    color = NA
  ) +
  geom_stratum(
    width = 0.20,
    fill = "grey97",
    color = "grey30",
    linewidth = 0.35
  ) +
  geom_text(
    stat = "stratum",
    aes(label = after_stat(stratum)),
    size = 3.6,
    lineheight = 0.85,
    color = "black"
  ) +
  scale_x_discrete(
    limits = c("Glia sender", "Interaction class", "Vulnerable target"),
    expand = c(0.10, 0.06)
  ) +
  scale_fill_manual(
    values = class_palette,
    name = "Interaction class"
  ) +
  labs(
    title = "MCX-higher glia-neuron communication across vulnerable targets",
    x = NULL,
    y = NULL,
    caption = "Flow width represents the summed MCX-higher CellChat communication difference."
  ) +
  theme_classic(base_size = 14) +
  theme(
    plot.title = element_text(face = "bold", hjust = 0.5, size = 18),
    plot.caption = element_text(size = 10, hjust = 0.5, color = "grey30"),

    axis.text.x = element_text(size = 14, color = "black", margin = margin(t = 6)),
    axis.title.x = element_blank(),

    # Remove x-axis horizontal line and ticks.
    axis.line.x = element_blank(),
    axis.ticks.x = element_blank(),

    # Remove y-axis because flow width already encodes the summed difference.
    axis.text.y = element_blank(),
    axis.ticks.y = element_blank(),
    axis.line.y = element_blank(),
    axis.title.y = element_blank(),

    legend.position = "bottom",
    legend.title = element_text(size = 11),
    legend.text = element_text(size = 10),
    legend.key.width = unit(0.8, "cm"),

    panel.grid = element_blank(),
    plot.margin = margin(10, 20, 12, 20)
  ) +
  guides(
    fill = guide_legend(
      nrow = 2,
      byrow = TRUE,
      override.aes = list(alpha = 0.85)
    )
  ) +
  coord_cartesian(clip = "off")

ggsave(out_pdf, p, width = 13.5, height = 6.6, device = "pdf", useDingbats = FALSE)
ggsave(out_png, p, width = 13.5, height = 6.6, dpi = 300)

message("[INFO] Saved PDF: ", out_pdf)
message("[INFO] Saved PNG: ", out_png)