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
    list(metric = "pr_count", file = "pr_trends.png", aggregation = "sum", title = "Pull Request 件数推移", y_label = "PR 件数"),
    list(metric = "commit_count", file = "commit_trends.png", aggregation = "sum", title = "コミット数推移", y_label = "コミット数"),
    list(metric = "lines_added", file = "lines_added.png", aggregation = "sum", title = "コード追加行数推移", y_label = "追加行数"),
    list(metric = "lines_deleted", file = "lines_deleted.png", aggregation = "sum", title = "コード削除行数推移", y_label = "削除行数"),
    list(metric = "pr_lead_time_hours", file = "pr_lead_time.png", aggregation = "mean", title = "PR リードタイム推移", y_label = "平均リードタイム（時間）"),
    list(metric = "review_to_approval_time_hours", file = "review_to_approval_time.png", aggregation = "mean", title = "レビュー承認までの時間推移", y_label = "平均時間（時間）"),
    list(metric = "review_response_time_hours", file = "review_response_time.png", aggregation = "mean", title = "レビュー応答時間推移", y_label = "平均時間（時間）"),
    list(metric = "pr_first_review_time_hours", file = "first_review_time.png", aggregation = "mean", title = "PR 作成から最初のレビューまでの時間推移", y_label = "平均時間（時間）"),
    list(metric = "pr_comment_count", file = "pr_comment_count.png", aggregation = "mean", title = "PR あたりのコメント数推移", y_label = "平均コメント数"),
    list(metric = "review_iteration_count", file = "review_iteration_count.png", aggregation = "mean", title = "レビューイテレーション回数推移", y_label = "平均回数"),
    list(metric = "bug_fix_ratio", file = "bug_fix_ratio.png", aggregation = "mean", title = "バグ修正 PR 割合推移", y_label = "割合", y_limits = c(0, 1)),
    list(metric = "revert_pr_count", file = "revert_pr_count.png", aggregation = "sum", title = "リバートされた PR 数推移", y_label = "PR 数")
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
