#!/usr/bin/env Rscript

# 既存のメトリクスCSVから可視化のみを再生成するスクリプト

suppressMessages(source("scripts/config/settings.R"))
suppressMessages(source("scripts/viz/pr_trends.R"))

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0) {
    y
  } else {
    x
  }
}

main <- function() {
  settings <- config_instance()
  files_dir <- settings$output$files_dir
  viz_dir <- settings$output$viz_dir

  data_path <- file.path(files_dir, "github_activity_metrics.csv")

  if (!file.exists(data_path)) {
    cli::cli_abort("メトリクスCSVが見つかりません: {data_path}")
  }

  cli::cli_inform("メトリクスCSVを読み込みます: {data_path}")
  metrics <- utils::read.csv(data_path, stringsAsFactors = FALSE)
  metrics$period_start <- as.Date(metrics$period_start)

  dir.create(viz_dir, recursive = TRUE, showWarnings = FALSE)

  plot_specs <- list(
    # 積み上げグラフのみ（折れ線グラフは削除）
    list(metric = "pr_count", file = "pr_trends_stacked.png", aggregation = "sum", y_label = "PR Count", chart_type = "stacked_with_line"),
    list(metric = "commit_count", file = "commit_trends_stacked.png", aggregation = "sum", y_label = "Commit Count", chart_type = "stacked_with_line"),
    list(metric = "lines_added", file = "lines_added_stacked.png", aggregation = "sum", y_label = "Lines Added", chart_type = "stacked_with_line"),
    list(metric = "lines_deleted", file = "lines_deleted_stacked.png", aggregation = "sum", y_label = "Lines Deleted", chart_type = "stacked_with_line"),
    list(metric = "pr_lead_time_hours", file = "pr_lead_time_stacked.png", aggregation = "mean", y_label = "Average Lead Time (hours)", chart_type = "stacked_with_line"),
    list(metric = "pr_comment_count", file = "pr_comment_count_stacked.png", aggregation = "mean", y_label = "Comments per PR", chart_type = "stacked_with_line"),
    # 折れ線グラフのみ（積み上げグラフがない指標）
    list(metric = "review_to_approval_time_hours", file = "review_to_approval_time.png", aggregation = "mean", y_label = "Review to Approval (hours)"),
    list(metric = "review_response_time_hours", file = "review_response_time.png", aggregation = "mean", y_label = "Review Response Time (hours)"),
    list(metric = "pr_first_review_time_hours", file = "first_review_time.png", aggregation = "mean", y_label = "Time to First Review (hours)"),
    list(metric = "review_iteration_count", file = "review_iteration_count.png", aggregation = "mean", y_label = "Review Iterations"),
    list(metric = "bug_fix_ratio", file = "bug_fix_ratio.png", aggregation = "mean", y_label = "Bug Fix Ratio", y_limits = c(0, 1)),
    list(metric = "revert_pr_count", file = "revert_pr_count.png", aggregation = "sum", y_label = "Reverted PRs")
  )

  purrr::walk(
    plot_specs,
    function(spec) {
      output_path <- file.path(viz_dir, spec$file)
      plot_metric_trend(
        metrics = metrics,
        metric_name = spec$metric,
        output_path = output_path,
        interval = "monthly",
        repos = "ALL",
        aggregation = spec$aggregation,
        title = spec$title,
        y_label = spec$y_label,
        y_limits = spec$y_limits %||% NULL,
        chart_type = spec$chart_type %||% "line"
      )
    }
  )

  cli::cli_inform("グラフ再生成が完了しました。")
}

if (identical(environment(), globalenv())) {
  main()
}
