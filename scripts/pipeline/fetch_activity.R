#!/usr/bin/env Rscript

# GitHub から開発活動を取得し、後続処理に渡すためのパイプラインひな型。
# 取得・加工の責務を役割別モジュールに委譲し、このスクリプトでは実行順序と
# 出力先の制御のみを行う。

suppressMessages(source("scripts/api/github_client.R"))
suppressMessages(source("scripts/api/github_activity.R"))
suppressMessages(source("scripts/processing/activity_transform.R"))

run_fetch_pipeline <- function(max_repo_pages = 1, max_pr_pages = 1) {
  svc <- get_activity_service()
  settings <- config_instance()

  repos <- svc$list_org_repositories(per_page = 100, max_pages = max_repo_pages)
  cli::cli_inform("取得リポジトリ数: {length(repos)}")

  agent_users <- settings$github$agent_users
  results <- list()

  for (repo in repos) {
    repo_name <- repo$full_name %||% repo$name
    cli::cli_inform("リポジトリ処理中: {repo_name}")

    pulls <- svc$list_pull_requests(
      repo = repo_name,
      state = "all",
      per_page = 100,
      max_pages = max_pr_pages
    )

    pulls_norm <- lapply(pulls, function(pr) {
      list(
        repo = repo_name,
        number = pr$number,
        title = pr$title,
        state = pr$state,
        created_at = pr$created_at,
        merged_at = pr$merged_at,
        closed_at = pr$closed_at,
        author = pr$user$login,
        actor_type = label_actor_type(pr$user$login, agent_users),
        ai_phase = label_ai_phase(as.Date(pr$created_at))
      )
    })

    results[[repo_name]] <- pulls_norm
  }

  results
}

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  max_repo_pages <- 1
  max_pr_pages <- 1

  if (length(args) >= 1) {
    max_repo_pages <- as.integer(args[[1]])
  }
  if (length(args) >= 2) {
    max_pr_pages <- as.integer(args[[2]])
  }

  data <- run_fetch_pipeline(max_repo_pages, max_pr_pages)
  cli::cli_inform("取得完了。リポジトリ数: {length(data)}")
}

if (identical(environment(), globalenv())) {
  main()
}
