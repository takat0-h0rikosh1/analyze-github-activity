# GitHub API クライアント -------------------------------------------------
#
# GitHub REST API を操作するためのクラスベースのラッパーを提供する。
# 認証情報や実行環境に依存する設定は `scripts/config/settings.R` の Config で集中管理する。

ensure_config_loaded <- function() {
  if (!exists("config_instance", mode = "function")) {
    cfg_path <- file.path("scripts", "config", "settings.R")
    if (!file.exists(cfg_path)) {
      cli::cli_abort("Configuration module not found at {cfg_path}.")
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
      resp <- tryCatch(
        httr2::req_perform(req),
        error = function(err) {
          cli::cli_abort(
            "GitHub API request failed to execute: {err$message}",
            parent = err
          )
        }
      )

      tryCatch(
        httr2::resp_check_status(resp),
        error = function(err) {
          details <- github_error_details(resp)
          cli::cli_abort(
            c(
              "GitHub API returned an error.",
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

      results <- as_list(httr2::resp_body_json(resp, simplifyVector = FALSE))
      next_link <- github_next_link(resp)

      page <- 1L
      while (!is.null(next_link) && page < max_pages) {
        req <- request_from_url(next_link)
        resp <- perform(req)
        chunk <- as_list(httr2::resp_body_json(resp, simplifyVector = FALSE))
        results <- c(results, chunk)
        next_link <- github_next_link(resp)
        page <- page + 1L
      }

      results
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

# 便利関数 -------------------------------------------------------------

github_agent_users <- function() {
  github_client()$agent_users()
}

github_org <- function() {
  github_client()$org()
}

github_get <- function(endpoint,
                        query = list(),
                        paginate = TRUE,
                        per_page = 100,
                        max_pages = Inf) {
  github_client()$get(endpoint, query, paginate, per_page, max_pages)
}

github_request <- function(endpoint,
                            query = list(),
                            method = "GET",
                            body = NULL) {
  github_client()$request(endpoint, query, method, body)
}

github_request_from_url <- function(url) {
  github_client()$request_from_url(url)
}

github_perform <- function(req) {
  github_client()$perform(req)
}

# 補助関数 -------------------------------------------------------------

github_error_details <- function(resp) {
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
}

github_next_link <- function(resp) {
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
}

as_list <- function(x) {
  if (is.null(x)) {
    list()
  } else if (is.list(x)) {
    x
  } else {
    list(x)
  }
}

github_encode <- function(x) {
  utils::URLencode(x, reserved = TRUE)
}

github_repo_path <- function(repo) {
  parts <- strsplit(repo, "/", fixed = TRUE)[[1]]
  parts <- trimws(parts)
  if (length(parts) != 2L || any(!nzchar(parts))) {
    cli::cli_abort("Repository must be supplied as `owner/name`. Got: {repo}")
  }
  paste(github_encode(parts), collapse = "/")
}

github_iso_time <- function(x) {
  if (is.null(x)) {
    return(NULL)
  }
  if (inherits(x, "Date")) {
    return(sprintf("%sT00:00:00Z", format(x, "%Y-%m-%d")))
  }
  if (!inherits(x, "POSIXt")) {
    cli::cli_abort("Time value must be Date or POSIXt. Got: {class(x)[1]}")
  }
  format(as.POSIXct(x, tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}

github_parse_timestamp <- function(x) {
  if (is.null(x)) {
    return(NULL)
  }
  as.POSIXct(x, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0) {
    y
  } else {
    x
  }
}
