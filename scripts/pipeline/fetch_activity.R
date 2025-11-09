#!/usr/bin/env Rscript

# GitHub から開発活動を取得し、後続処理に渡すためのパイプラインひな型。
# 取得・加工の責務を役割別モジュールに委譲し、このスクリプトでは実行順序と
# 出力先の制御のみを行う。

suppressMessages(source("scripts/api/github_client.R"))
suppressMessages(source("scripts/api/github_activity.R"))
suppressMessages(source("scripts/processing/activity_transform.R"))

run_fetch_pipeline <- function(max_repo_pages = 1,
                               max_pr_pages = 1,
                               max_review_pages = 1,
                               max_comment_pages = 1,
                               max_commit_pages = 1) {
  svc <- get_activity_service()
  settings <- config_instance()

  repos <- svc$list_org_repositories(per_page = 100, max_pages = max_repo_pages)
  target_repos <- settings$github$target_repos %||% character()

  if (length(target_repos)) {
    repo_names <- vapply(repos, function(repo) repo$full_name %||% repo$name, character(1))
    selected_idx <- match(target_repos, repo_names, nomatch = 0)

    valid_idx <- selected_idx[selected_idx > 0]
    selected <- if (length(valid_idx)) repos[valid_idx] else list()

    missing <- target_repos[selected_idx == 0 | is.na(selected_idx)]
    if (length(missing)) {
      cli::cli_alert_warning("設定されたリポジトリの一部が一覧に存在しません: {paste(missing, collapse = \", \")}")
    }

    repos <- selected

    if (length(repos)) {
      current_names <- vapply(repos, function(repo) repo$full_name %||% repo$name, character(1))
      order_idx <- match(target_repos, current_names, nomatch = 0)
      repos <- repos[order_idx[order_idx > 0]]
    }
  }

  repo_limit_env <- suppressWarnings(as.integer(Sys.getenv("GITHUB_REPO_LIMIT", unset = "")))
  if (!is.na(repo_limit_env) && repo_limit_env > 0 && length(repos) > repo_limit_env) {
    repos <- repos[seq_len(repo_limit_env)]
  }

  cli::cli_inform("取得リポジトリ数: {length(repos)}")

  agent_users <- settings$github$agent_users
  commit_since <- as.POSIXct(settings$ai$pre_start)
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
        ai_phase = label_ai_phase(as.Date(pr$created_at)),
        additions = pr$additions %||% NA_real_,
        deletions = pr$deletions %||% NA_real_,
        changed_files = pr$changed_files %||% NA_integer_,
        merged_by = pr$merged_by$login %||% NA_character_,
        is_bug_fix = detect_bug_fix(pr),
        is_revert = detect_revert(pr),
        labels = list(extract_label_names(pr))
      )
    })

    reviews_norm <- list()
    review_comments_norm <- list()

    if (length(pulls)) {
      for (pr in pulls) {
        number <- pr$number
        raw_reviews <- tryCatch(
          svc$list_pull_request_reviews(
            repo = repo_name,
            number = number,
            per_page = 100,
            max_pages = max_review_pages
          ),
          error = function(err) {
            cli::cli_warn("レビュー取得に失敗しました ({repo_name}#{number}): {err$message}")
            list()
          }
        )

        if (length(raw_reviews)) {
          reviews_norm <- c(
            reviews_norm,
            lapply(raw_reviews, function(rv) {
              submitted <- rv$submitted_at %||% rv$created_at %||% NA_character_
              list(
                repo = repo_name,
                number = number,
                reviewer = rv$user$login %||% NA_character_,
                actor_type = label_actor_type(rv$user$login, agent_users),
                state = rv$state %||% NA_character_,
                submitted_at = submitted
              )
            })
          )
        }

        raw_comments <- tryCatch(
          svc$list_pull_request_comments(
            repo = repo_name,
            number = number,
            per_page = 100,
            max_pages = max_comment_pages
          ),
          error = function(err) {
            cli::cli_warn("レビューコメント取得に失敗しました ({repo_name}#{number}): {err$message}")
            list()
          }
        )

        if (length(raw_comments)) {
          review_comments_norm <- c(
            review_comments_norm,
            lapply(raw_comments, function(cm) {
              list(
                repo = repo_name,
                number = number,
                commenter = cm$user$login %||% NA_character_,
                actor_type = label_actor_type(cm$user$login, agent_users),
                created_at = cm$created_at %||% NA_character_
              )
            })
          )
        }
      }
    }

    commits_norm <- list()
    commits <- tryCatch(
      svc$list_commits(
        repo = repo_name,
        since = commit_since,
        per_page = 100,
        max_pages = max_commit_pages
      ),
      error = function(err) {
        cli::cli_warn("コミット取得に失敗しました ({repo_name}): {err$message}")
        list()
      }
    )

    if (length(commits)) {
      commits_norm <- lapply(commits, function(cm) {
        author_login <- cm$author$login %||% cm$committer$login %||% NA_character_
        committed_at <- cm$commit$author$date %||% cm$commit$committer$date %||% NA_character_
        list(
          repo = repo_name,
          sha = cm$sha,
          author = author_login,
          actor_type = label_actor_type(author_login, agent_users),
          committed_at = committed_at
        )
      })
    }

    results[[repo_name]] <- list(
      pulls = pulls_norm,
      reviews = reviews_norm,
      review_comments = review_comments_norm,
      commits = commits_norm
    )
  }

  results
}

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  max_repo_pages <- 1
  max_pr_pages <- 1
  max_review_pages <- 1
  max_comment_pages <- 1
  max_commit_pages <- 1

  if (length(args) >= 1) {
    max_repo_pages <- as.integer(args[[1]])
  }
  if (length(args) >= 2) {
    max_pr_pages <- as.integer(args[[2]])
  }
  if (length(args) >= 3) {
    max_review_pages <- as.integer(args[[3]])
  }
  if (length(args) >= 4) {
    max_comment_pages <- as.integer(args[[4]])
  }
  if (length(args) >= 5) {
    max_commit_pages <- as.integer(args[[5]])
  }

  data <- run_fetch_pipeline(
    max_repo_pages,
    max_pr_pages,
    max_review_pages,
    max_comment_pages,
    max_commit_pages
  )
  cli::cli_inform("取得完了。リポジトリ数: {length(data)}")
}

if (identical(environment(), globalenv())) {
  main()
}

# 内部ユーティリティ -----------------------------------------------------------

extract_label_names <- function(pr) {
  if (is.null(pr$labels) || !length(pr$labels)) {
    return(character())
  }
  labels <- vapply(pr$labels, function(lbl) lbl$name %||% NA_character_, character(1))
  labels[nzchar(labels)]
}

detect_bug_fix <- function(pr) {
  labels <- tolower(extract_label_names(pr))
  title <- tolower(pr$title %||% "")

  if (length(labels) && any(grepl("bug|fix", labels, perl = TRUE))) {
    return(TRUE)
  }

  grepl("\\b(fix|bug|hotfix)\\b", title, perl = TRUE)
}

detect_revert <- function(pr) {
  title <- pr$title %||% ""
  grepl("^revert", title, ignore.case = TRUE)
}
