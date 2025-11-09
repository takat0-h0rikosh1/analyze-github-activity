# GitHub API クライアント -------------------------------------------------
#
# GitHub REST API を操作するためのクラスベースのラッパー。認証情報や環境設定は
# `scripts/config/settings.R` の Config インスタンスから取得し、ここで集約利用する。

source_common_utils <- local({
  loaded <- FALSE
  function() {
    if (!loaded) {
      utils_path <- file.path("scripts", "common", "utils.R")
      if (!file.exists(utils_path)) {
        cli::cli_abort("共通ユーティリティが見つかりません: {utils_path}")
      }
      source(utils_path, local = FALSE)
      loaded <<- TRUE
    }
  }
})

source_common_utils()

ensure_config_loaded <- function() {
  if (!exists("config_instance", mode = "function")) {
    cfg_path <- file.path("scripts", "config", "settings.R")
    if (!file.exists(cfg_path)) {
      cli::cli_abort("設定モジュールが見つかりません: {cfg_path}")
    }
    sys.source(cfg_path, envir = topenv())
  }
}

GitHubClient <- setRefClass(
  "GitHubClient",
  fields = list(
    config = "ANY"
  ),
  methods = list(
    initialize = function() {
      ensure_config_loaded()
      config <<- config_instance()
      callSuper()
    },

    settings = function() {
      config$github
    },

    agent_users = function() {
      settings()$agent_users
    },

    org = function() {
      settings()$org
    },

    headers = function() {
      gh <- settings()
      list(
        Accept = "application/vnd.github+json",
        Authorization = sprintf("Bearer %s", gh$token),
        `X-GitHub-Api-Version` = "2022-11-28",
        `User-Agent` = gh$user_agent
      )
    },

    request = function(endpoint,
                       query = list(),
                       method = "GET",
                       body = NULL) {
      gh <- settings()
      endpoint <- sub("^/", "", endpoint)

      req <- httr2::request(gh$api_url)
      if (nzchar(endpoint)) {
        req <- httr2::req_url_path_append(req, endpoint)
      }

      req <- do.call(httr2::req_headers, c(list(req), headers()))

      if (length(query)) {
        req <- do.call(httr2::req_url_query, c(list(req), query))
      }

      if (!identical(method, "GET")) {
        req <- httr2::req_method(req, method)
      }

      if (!is.null(body)) {
        req <- httr2::req_body_json(req, body = body, auto_unbox = TRUE)
      }

      req
    },

    request_from_url = function(url) {
      req <- httr2::request(url)
      do.call(httr2::req_headers, c(list(req), headers()))
    },

    perform = function(req) {
      pause <- settings()$request_pause_sec %||% 0
      if (!is.null(pause) && pause > 0) {
        Sys.sleep(pause)
      }

      resp <- tryCatch(
        httr2::req_perform(req),
        error = function(err) {
          cli::cli_abort(
            "GitHub API の呼び出しに失敗しました: {err$message}",
            parent = err
          )
        }
      )

      .self$rate_limit_backoff(resp)

      tryCatch(
        httr2::resp_check_status(resp),
        error = function(err) {
          details <- .error_details(resp)
          cli::cli_abort(
            c(
              "GitHub API からエラーが返りました。",
              i = details$message,
              if (!is.null(details$documentation_url)) {
                c("i" = details$documentation_url)
              }
            ),
            parent = err
          )
        }
      )

      resp
    },

    get = function(endpoint,
                   query = list(),
                   paginate = TRUE,
                   per_page = 100,
                   max_pages = Inf) {
      if (paginate) {
        query$per_page <- per_page
      }

      req <- request(endpoint, query = query)
      resp <- perform(req)

      if (!paginate) {
        return(httr2::resp_body_json(resp, simplifyVector = FALSE))
      }

      results <- .as_list(httr2::resp_body_json(resp, simplifyVector = FALSE))
      next_link <- .next_link(resp)

      page <- 1L
      while (!is.null(next_link) && page < max_pages) {
        req <- request_from_url(next_link)
        resp <- perform(req)
        chunk <- .as_list(httr2::resp_body_json(resp, simplifyVector = FALSE))
        results <- c(results, chunk)
        next_link <- .next_link(resp)
        page <- page + 1L
      }

      results
    },

    repo_path = function(repo) {
      parts <- trimws(strsplit(repo, "/", fixed = TRUE)[[1]])
      if (length(parts) != 2L || any(!nzchar(parts))) {
        cli::cli_abort("リポジトリは `owner/name` 形式で指定してください: {repo}")
      }
      paste(vapply(parts, url_encode, character(1)), collapse = "/")
    },

    iso_time = function(x) {
      iso_datetime(x)
    },

    parse_timestamp = function(x) {
      parse_iso_datetime(x)
    },

    .error_details = function(resp) {
      message <- NULL
      docs <- NULL

      content <- tryCatch(
        httr2::resp_body_json(resp, simplifyVector = TRUE),
        error = function(...) NULL
      )

      if (is.list(content)) {
        message <- content$message %||% content$error %||% "Unknown error response."
        docs <- content$documentation_url %||% NULL
      }

      list(
        message = message %||% sprintf("HTTP %s", httr2::resp_status_desc(resp)),
        documentation_url = docs
      )
    },

    .next_link = function(resp) {
      link <- httr2::resp_headers(resp)[["link"]]
      if (is.null(link) || !nzchar(link)) {
        return(NULL)
      }

      parts <- strsplit(link, ",")[[1]]
      for (part in parts) {
        part <- trimws(part)
        if (grepl('rel="next"', part, fixed = TRUE)) {
          matches <- sub("^.*<([^>]+)>.*$", "\\1", part)
          if (!identical(matches, part)) {
            return(matches)
          }
        }
      }

      NULL
    },

    rate_limit_backoff = function(resp) {
      headers <- httr2::resp_headers(resp)
      remaining_raw <- headers[["x-ratelimit-remaining"]] %||% NA_character_
      remaining <- suppressWarnings(as.integer(remaining_raw))
      threshold <- settings()$rate_limit_threshold %||% 0

      if (is.na(remaining) || remaining > threshold || threshold <= 0) {
        return(invisible(NULL))
      }

      reset_raw <- headers[["x-ratelimit-reset"]] %||% NA_character_
      reset_epoch <- suppressWarnings(as.numeric(reset_raw))
      padding <- settings()$rate_limit_padding_sec %||% 0

      if (is.na(reset_epoch)) {
        return(invisible(NULL))
      }

      wait_sec <- max(reset_epoch - as.numeric(Sys.time()) + padding, padding, 0)
      if (wait_sec > 0) {
        cli::cli_alert_info("GitHub API rate limit 残り {remaining}; {round(wait_sec, 1)} 秒待機します。")
        Sys.sleep(wait_sec)
      }
    },

    .as_list = function(x) {
      as_list_safe(x)
    }
  )
)

.github_client_singleton <- local({
  instance <- NULL
  function() {
    if (is.null(instance)) {
      instance <<- GitHubClient$new()
    }
    instance
  }
})

github_client <- function() {
  .github_client_singleton()
}

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0) {
    y
  } else {
    x
  }
}
