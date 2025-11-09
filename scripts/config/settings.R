# 環境設定の共有 -------------------------------------------------
#
# 環境変数から設定値を読み込み、Config クラスで一元管理する。
# `Config$new()` で生成したインスタンスを共通化し、各モジュールが同じ設定を参照できるようにする。

Config <- setRefClass(
  "Config",
  fields = list(
    github = "list",
    ai = "list",
    output = "list"
  ),
  methods = list(
    initialize = function() {
      callSuper()
      .self$reload()
    },

    reload = function() {
      github <<- .self$build_github_settings()
      ai <<- .self$build_ai_settings()
      output <<- .self$build_output_settings()
      invisible(.self)
    },

    build_github_settings = function() {
      token <- .self$read_required_env("GITHUB_TOKEN")
      org <- .self$read_required_env("GITHUB_ORG")

      api_url <- Sys.getenv("GITHUB_API_URL", unset = "https://api.github.com")
      api_url <- .self$normalize_base_url(api_url)

      agent_users <- .self$parse_list_env("GITHUB_AGENT_USERS")
      target_repos <- .self$parse_list_env("GITHUB_TARGET_REPOS")
      approval_thresholds_env <- .self$parse_int_map_env("GITHUB_APPROVAL_THRESHOLDS")
      approval_thresholds_file <- .self$parse_int_map_file(
        Sys.getenv("GITHUB_APPROVAL_THRESHOLDS_FILE", unset = "")
      )
      approval_thresholds <- approval_thresholds_file
      if (is.null(approval_thresholds)) {
        approval_thresholds <- approval_thresholds_env
      } else if (!is.null(approval_thresholds_env)) {
        approval_thresholds <- modifyList(approval_thresholds, approval_thresholds_env)
      }
      if (is.null(approval_thresholds) || !length(approval_thresholds)) {
        approval_thresholds <- NULL
      }
      user_agent <- Sys.getenv("GITHUB_USER_AGENT", unset = "")
      if (!nzchar(user_agent)) {
        user_agent <- "analyze-github-activity/0.1"
      }

      request_pause <- suppressWarnings(as.numeric(Sys.getenv("GITHUB_REQUEST_PAUSE_SEC", unset = "0.25")))
      if (is.na(request_pause) || request_pause < 0) {
        request_pause <- 0
      }

      rate_threshold <- suppressWarnings(as.integer(Sys.getenv("GITHUB_RATE_THRESHOLD", unset = "50")))
      if (is.na(rate_threshold) || rate_threshold < 0) {
        rate_threshold <- 0
      }

      rate_padding <- suppressWarnings(as.numeric(Sys.getenv("GITHUB_RATE_RESET_PADDING_SEC", unset = "5")))
      if (is.na(rate_padding) || rate_padding < 0) {
        rate_padding <- 0
      }

      max_repo_pages <- suppressWarnings(as.integer(Sys.getenv("GITHUB_MAX_REPO_PAGES", unset = "1")))
      if (is.na(max_repo_pages) || max_repo_pages < 1) {
        max_repo_pages <- 1L
      }

      max_pr_pages <- suppressWarnings(as.integer(Sys.getenv("GITHUB_MAX_PR_PAGES", unset = "100")))
      if (is.na(max_pr_pages) || max_pr_pages < 1) {
        max_pr_pages <- 100L
      }

      max_review_pages <- suppressWarnings(as.integer(Sys.getenv("GITHUB_MAX_REVIEW_PAGES", unset = "10")))
      if (is.na(max_review_pages) || max_review_pages < 1) {
        max_review_pages <- 10L
      }

      max_comment_pages <- suppressWarnings(as.integer(Sys.getenv("GITHUB_MAX_COMMENT_PAGES", unset = "10")))
      if (is.na(max_comment_pages) || max_comment_pages < 1) {
        max_comment_pages <- 10L
      }

      max_commit_pages <- suppressWarnings(as.integer(Sys.getenv("GITHUB_MAX_COMMIT_PAGES", unset = "50")))
      if (is.na(max_commit_pages) || max_commit_pages < 1) {
        max_commit_pages <- 50L
      }

      list(
        token = token,
        org = org,
        api_url = api_url,
        agent_users = agent_users,
        target_repos = target_repos,
        approval_thresholds = approval_thresholds,
        user_agent = user_agent,
        request_pause_sec = request_pause,
        rate_limit_threshold = rate_threshold,
        rate_limit_padding_sec = rate_padding,
        max_repo_pages = max_repo_pages,
        max_pr_pages = max_pr_pages,
        max_review_pages = max_review_pages,
        max_comment_pages = max_comment_pages,
        max_commit_pages = max_commit_pages
      )
    },

    build_ai_settings = function() {
      t0_raw <- Sys.getenv("AI_T0", unset = "2025-06-18")
      t0_date <- as.Date(t0_raw)
      if (is.na(t0_date)) {
        cli::cli_abort(c(
          "Environment variable {.envvar AI_T0} must be an ISO date (YYYY-MM-DD).",
          i = "Got: {.val {t0_raw}}"
        ))
      }

      lookback_days_raw <- Sys.getenv("AI_LOOKBACK_DAYS", unset = "180")
      lookback_days <- suppressWarnings(as.integer(lookback_days_raw))
      if (is.na(lookback_days) || lookback_days < 1) {
        cli::cli_abort(c(
          "Environment variable {.envvar AI_LOOKBACK_DAYS} must be a positive integer.",
          i = "Got: {.val {lookback_days_raw}}"
        ))
      }

      list(
        t0 = t0_date,
        pre_start = t0_date - lookback_days,
        lookback_days = lookback_days
      )
    },

    build_output_settings = function() {
      files_dir <- Sys.getenv("OUTPUT_DIR", unset = "output/files")
      viz_dir <- Sys.getenv("OUTPUT_VIZ_DIR", unset = "output/viz")

      list(
        files_dir = files_dir,
        viz_dir = viz_dir
      )
    },

    read_required_env = function(name) {
      value <- Sys.getenv(name, unset = "")
      if (!nzchar(value)) {
        cli::cli_abort("Environment variable {.envvar {name}} must be set.")
      }
      value
    },

    parse_list_env = function(name) {
      value <- Sys.getenv(name, unset = "")
      if (!nzchar(value)) {
        return(character())
      }
      parts <- trimws(strsplit(value, ",", fixed = TRUE)[[1]])
      parts[nzchar(parts)]
    },

    parse_int_map_env = function(name, default = NULL) {
      value <- Sys.getenv(name, unset = NA_character_)
      if (is.na(value) || !nzchar(value)) {
        return(default)
      }
      entries <- trimws(strsplit(value, ",", fixed = TRUE)[[1]])
      parsed <- .self$parse_int_map_entries(entries)
      if (!length(parsed)) default else parsed
    },

    parse_int_map_file = function(path) {
      if (!nzchar(path) || !file.exists(path)) {
        return(NULL)
      }
      lines <- readLines(path, warn = FALSE)
      lines <- trimws(lines)
      lines <- lines[nzchar(lines) & !grepl("^#", lines)]
      if (!length(lines)) {
        return(NULL)
      }
      parsed <- .self$parse_int_map_entries(lines)
      if (!length(parsed)) NULL else parsed
    },

    parse_int_map_entries = function(entries) {
      result <- list()
      for (entry in entries) {
        if (!nzchar(entry) || !grepl("=", entry, fixed = TRUE)) {
          next
        }
        parts <- strsplit(entry, "=", fixed = TRUE)[[1]]
        key <- trimws(parts[1])
        val <- suppressWarnings(as.integer(trimws(parts[2])))
        if (!nzchar(key) || is.na(val)) {
          next
        }
        result[[key]] <- as.integer(val)
      }
      result
    },

    normalize_base_url = function(url) {
      if (!nzchar(url)) {
        return("https://api.github.com")
      }
      cleaned <- sub("/+$", "", url)
      if (!nzchar(cleaned)) "https://api.github.com" else cleaned
    }
  )
)

config_instance <- local({
  instance <- NULL
  function() {
    if (is.null(instance)) {
      instance <<- Config$new()
    }
    instance
  }
})

get_settings <- function() {
  inst <- config_instance()
  list(
    github = inst$github,
    ai = inst$ai,
    output = inst$output
  )
}

reload_settings <- function() {
  inst <- config_instance()
  inst$reload()
  get_settings()
}
