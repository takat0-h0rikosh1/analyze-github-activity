#!/usr/bin/env Rscript

# Pull Request データを取得し、QuickSight 用 CSV と可視化を生成するパイプライン。

suppressMessages(source("scripts/config/settings.R"))
suppressMessages(source("scripts/processing/metrics_summary.R"))
suppressMessages(source("scripts/viz/pr_trends.R"))

fetch_env <- new.env(parent = globalenv())
sys.source("scripts/pipeline/fetch_activity.R", envir = fetch_env)

run_fetch_pipeline <- fetch_env$run_fetch_pipeline

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0) {
    y
  } else {
    x
  }
}

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  max_repo_pages <- 1L
  max_pr_pages <- 1L

  if (length(args) >= 1 && nzchar(args[[1]])) {
    max_repo_pages <- as.integer(args[[1]])
  }
  if (length(args) >= 2 && nzchar(args[[2]])) {
    max_pr_pages <- as.integer(args[[2]])
  }

  cli::cli_inform("PR データ取得を開始します。max_repo_pages={max_repo_pages}, max_pr_pages={max_pr_pages}")
  pr_data <- run_fetch_pipeline(max_repo_pages, max_pr_pages)

  cli::cli_inform("メトリクスデータセットを構築します。")
  metrics <- build_metrics_dataset(pr_data)

  settings <- config_instance()
  files_dir <- settings$output$files_dir
  viz_dir <- settings$output$viz_dir

  dir.create(files_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(viz_dir, recursive = TRUE, showWarnings = FALSE)

  data_path <- file.path(files_dir, "github_activity_metrics.csv")
  utils::write.csv(metrics, data_path, row.names = FALSE, na = "")
  cli::cli_inform("メトリクス CSV を出力しました: {data_path}")

  plot_specs <- list(
    list(metric = "pr_count", file = "pr_trends.png", aggregation = "sum", y_label = "PR Count"),
    list(metric = "commit_count", file = "commit_trends.png", aggregation = "sum", y_label = "Commit Count"),
    list(metric = "lines_added", file = "lines_added.png", aggregation = "sum", y_label = "Lines Added"),
    list(metric = "lines_deleted", file = "lines_deleted.png", aggregation = "sum", y_label = "Lines Deleted"),
    list(metric = "pr_lead_time_hours", file = "pr_lead_time.png", aggregation = "mean", y_label = "Average Lead Time (hours)"),
    list(metric = "review_to_approval_time_hours", file = "review_to_approval_time.png", aggregation = "mean", y_label = "Review to Approval (hours)"),
    list(metric = "review_response_time_hours", file = "review_response_time.png", aggregation = "mean", y_label = "Review Response Time (hours)"),
    list(metric = "pr_first_review_time_hours", file = "first_review_time.png", aggregation = "mean", y_label = "Time to First Review (hours)"),
    list(metric = "pr_comment_count", file = "pr_comment_count.png", aggregation = "mean", y_label = "Comments per PR"),
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
        y_limits = spec$y_limits %||% NULL
      )
    }
  )

  cli::cli_inform("パイプライン処理が完了しました。")
}

if (identical(environment(), globalenv())) {
  main()
}
