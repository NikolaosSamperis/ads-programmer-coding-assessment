# ------------------------------------------------------------------------------
# Question 4.2 - Adverse Event Visualisations
#
# Description : Two ggplot2 figures for the AE TLG package:
#                 Plot 1 - Stacked bar of AE severity (AESEV) by treatment arm
#                 Plot 2 - Top 10 most frequent AEs (AETERM) with 95%
#                          Clopper-Pearson exact CIs for incidence rate
# Inputs      : pharmaverseadam::adae, pharmaverseadam::adsl
# Outputs     : ae_severity_distribution.png
#               top10_ae_frequency.png
# ------------------------------------------------------------------------------

# 1. Setup ---------------------------------------------------------------------
suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(pharmaverseadam)
})

out_dir <- file.path(dirname(rstudioapi::getSourceEditorContext()$path), "output")
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

adae <- pharmaverseadam::adae
adsl <- pharmaverseadam::adsl

# 2. Plot 1 - AE severity distribution by treatment ----------------------------
# Stacked bar of *all AE events* (not de-duplicated by subject) coloured by
# AESEV. Severity factor levels are fixed so the legend and stacking order
# stay consistent regardless of which categories appear.
sev_levels <- c("MILD", "MODERATE", "SEVERE")
sev_colours <- c(
  MILD     = "#F8766D",  # salmon
  MODERATE = "#00BA38",  # green
  SEVERE   = "#619CFF"   # blue
)

ae_sev <- adae %>%
  filter(!is.na(AESEV)) %>%
  mutate(AESEV = factor(AESEV, levels = sev_levels))

p_sev <- ggplot(ae_sev, aes(x = ACTARM, fill = AESEV)) +
  geom_bar() +
  scale_fill_manual(values = sev_colours, drop = FALSE) +
  labs(
    title = "AE severity distribution by treatment",
    x     = "Treatment Arm",
    y     = "Count of AEs",
    fill  = "Severity/Intensity"
  ) +
  theme_gray(base_size = 12)

ggsave(
  filename = file.path(out_dir, "ae_severity_distribution.png"),
  plot     = p_sev,
  width    = 8,
  height   = 5,
  dpi      = 300
)

# 3. Plot 2 - Top 10 most frequent AEs with 95% CI -----------------------------
# Incidence is calculated per *subject* (count distinct USUBJID per AETERM),
# divided by the total number of subjects in ADSL. Clopper-Pearson exact
# confidence intervals come from binom.test().
n_total <- dplyr::n_distinct(adsl$USUBJID)

clopper_pearson <- function(x, n, conf = 0.95) {
  ci <- stats::binom.test(x, n, conf.level = conf)$conf.int
  tibble::tibble(lower = ci[1], upper = ci[2])
}

top10 <- adae %>%
  filter(!is.na(AETERM)) %>%
  group_by(AETERM) %>%
  summarise(n_subj = dplyr::n_distinct(USUBJID), .groups = "drop") %>%
  slice_max(n_subj, n = 10, with_ties = FALSE) %>%
  rowwise() %>%
  mutate(ci = list(clopper_pearson(n_subj, n_total))) %>%
  tidyr::unnest(ci) %>%
  ungroup() %>%
  mutate(
    pct       = 100 * n_subj / n_total,
    lower_pct = 100 * lower,
    upper_pct = 100 * upper,
    AETERM    = forcats::fct_reorder(AETERM, pct)
  )

p_top10 <- ggplot(top10, aes(x = pct, y = AETERM)) +
  geom_point(size = 2.2) +
  geom_errorbar(aes(xmin = lower_pct, xmax = upper_pct), width = 0.25,
                orientation = "y") +
  scale_x_continuous(labels = function(x) paste0(x, "%")) +
  labs(
    title    = "Top 10 Most Frequent Adverse Events",
    subtitle = paste0("n = ", n_total, " subjects; 95% Clopper-Pearson CIs"),
    x        = "Percentage of Patients (%)",
    y        = NULL
  ) +
  theme_minimal(base_size = 12) +
  theme(panel.grid.minor = element_blank())

ggsave(
  filename = file.path(out_dir, "top10_ae_frequency.png"),
  plot     = p_top10,
  width    = 9,
  height   = 6,
  dpi      = 300
)

message("Saved: ", file.path(out_dir, "ae_severity_distribution.png"))
message("Saved: ", file.path(out_dir, "top10_ae_frequency.png"))
