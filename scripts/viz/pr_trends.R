# Pull Request 活動の可視化 ---------------------------------------------------
#
# QuickSight 向けに集計したデータセットを基に、月次の PR 件数推移をプロットする。

suppressWarnings({
  suppressPackageStartupMessages({
    library(dplyr)
    library(ggplot2)
    library(cli)
    library(scales)
  })
})

`%||%` <- function(x, y) {
  if (is.null(x) || (is.character(x) && length(x) == 1L && !nzchar(x)) || length(x) == 0) {
    y
  } else {
    x
  }
}

build_plot_labels <- function(metric_name, interval, repos) {
  lang <- tolower(Sys.getenv("PLOT_LABEL_LANGUAGE", unset = "en"))
  repo_label <- if (length(repos) > 3) {
    if (lang == "ja") {
      sprintf("%s など %d 件", repos[1], length(repos))
    } else {
      sprintf("%s and %d more", repos[1], length(repos) - 1)
    }
  } else if (identical(repos, "ALL")) {
    "ALL"
  } else {
    paste(repos, collapse = ", ")
  }

  if (lang == "ja") {
    list(
      title = sprintf("%s 指標推移", metric_name),
      subtitle = sprintf("粒度: %s / リポジトリ: %s", interval, repo_label),
      x_label = sprintf("集計期間（%s）", interval),
      color_label = "アクター種別"
    )
  } else {
    list(
      title = sprintf("%s Trend", metric_name),
      subtitle = sprintf("Interval: %s / Repos: %s", interval, repo_label),
      x_label = sprintf("Period (%s)", interval),
      color_label = "Actor Type"
    )
  }
}

ensure_settings_loaded <- function() {
  if (!exists("config_instance", mode = "function")) {
    cfg <- file.path("scripts", "config", "settings.R")
    if (!file.exists(cfg)) {
      cli::cli_abort("設定モジュールが見つかりません: {cfg}")
    }
    sys.source(cfg, envir = topenv())
  }
}

plot_metric_trend <- function(metrics,
                              metric_name,
                              output_path,
                              interval = "monthly",
                              repos = "ALL",
                              aggregation = c("sum", "mean"),
                              title = NULL,
                              y_label = NULL,
                              y_limits = NULL) {
  aggregation <- match.arg(aggregation)

  filtered <- metrics %>%
    dplyr::filter(
      metric_name == .env$metric_name,
      interval == .env$interval,
      repo %in% repos
    )

  if (nrow(filtered) == 0) {
    cli::cli_warn("[{metric_name}] 可視化対象データが存在しないため、グラフをスキップします。")
    return(invisible(NULL))
  }

  filtered <- filtered %>%
    dplyr::arrange(period_start, actor_type) %>%
    dplyr::mutate(sample_size = tidyr::replace_na(sample_size, 0L))

  aggregated <- switch(
    aggregation,
    sum = filtered %>%
      dplyr::group_by(period_start, actor_type) %>%
      dplyr::summarise(metric_value = sum(metric_value, na.rm = TRUE), .groups = "drop"),
    mean = filtered %>%
      dplyr::group_by(period_start, actor_type) %>%
      dplyr::summarise(
        total_weight = sum(metric_value * sample_size, na.rm = TRUE),
        total_sample = sum(sample_size, na.rm = TRUE),
        metric_value = ifelse(total_sample > 0, total_weight / total_sample, NA_real_),
        .groups = "drop"
      ) %>%
      dplyr::select(-total_weight, -total_sample)
  )

  if (!nrow(aggregated) || all(is.na(aggregated$metric_value))) {
    cli::cli_warn("[{metric_name}] 指標値が NA のため、グラフをスキップします。")
    return(invisible(NULL))
  }

  ensure_settings_loaded()
  settings <- config_instance()
  t0 <- settings$ai$t0

  value_unit <- filtered$value_unit[which(nzchar(filtered$value_unit))[1]] %||% filtered$value_unit[1] %||% ""
  if (is.null(y_label)) {
    y_label <- if (nzchar(value_unit)) {
      sprintf("%s (%s)", metric_name, value_unit)
    } else {
      metric_name
    }
  }

  if (is.null(y_limits) && (identical(value_unit, "count") || metric_name == "pr_count")) {
    upper <- suppressWarnings(max(aggregated$metric_value, na.rm = TRUE))
    if (!is.finite(upper) || upper <= 0) {
      upper <- 1
    }
    y_limits <- c(0, upper * 1.1)
  }

  labels <- build_plot_labels(metric_name, interval, repos)
  title <- title %||% labels$title
  subtitle <- labels$subtitle
  date_breaks <- switch(
    interval,
    daily = "1 week",
    weekly = "1 month",
    monthly = "2 month",
    "1 month"
  )

  y_formatter <- switch(
    value_unit,
    ratio = scales::label_percent(accuracy = 0.1),
    hours = scales::label_number(accuracy = 0.1),
    scales::label_number(big.mark = ",", accuracy = 1)
  )

  y_limits <- y_limits %||% if (identical(value_unit, "ratio")) c(0, 1) else NULL
  y_max <- suppressWarnings(max(aggregated$metric_value, na.rm = TRUE))

  g <- ggplot(aggregated, aes(x = period_start, y = metric_value, color = actor_type)) +
    geom_line(linewidth = 0.8) +
    geom_point(size = 2) +
    geom_vline(xintercept = as.numeric(t0), linetype = "dashed", color = "#999999") +
    scale_x_date(
      date_labels = "%Y-%m",
      date_breaks = date_breaks,
      expand = expansion(mult = c(0.01, 0.05))
    ) +
    scale_y_continuous(labels = y_formatter, limits = y_limits, expand = expansion(mult = c(0.02, 0.1))) +
    labs(
      title = title,
      subtitle = subtitle,
      x = labels$x_label,
      y = y_label,
      color = labels$color_label
    ) +
    theme_minimal(base_size = 12) +
    theme(
      plot.title = element_text(face = "bold"),
      axis.text.x = element_text(angle = 45, hjust = 1)
    )

  if (is.finite(y_max)) {
    g <- g + annotate(
      "text",
      x = t0,
      y = y_max,
      label = "T0",
      vjust = -0.5,
      size = 3,
      color = "#666666"
    )
  }

  ggplot2::ggsave(filename = output_path, plot = g, width = 10, height = 6, dpi = 300, bg = "white")
  cli::cli_inform("[{metric_name}] グラフを出力しました: {output_path}")

  invisible(output_path)
}

# 既存の PR 件数推移グラフとの互換 API
plot_pr_trends <- function(metrics,
                           output_path,
                           interval = "monthly",
                           repos = "ALL") {
  plot_metric_trend(
    metrics = metrics,
    metric_name = "pr_count",
    output_path = output_path,
    interval = interval,
    repos = repos,
    aggregation = "sum",
    title = sprintf("Pull Request 件数推移（%s, %s）", interval, paste(repos, collapse = ", ")),
    y_label = "PR 件数"
  )
}
