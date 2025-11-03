# GitHub API client helpers -------------------------------------------------
#
# Provides authenticated requests, pagination handling, and convenience
# wrappers for the GitHub REST API. Relies on the shared Config instance
# defined in `config/settings.R` to resolve environment variables.

ensure_config_loaded <- function() {
  if (!exists("config_instance", mode = "function")) {
    cfg_path <- file.path("scripts", "config", "settings.R")
    if (!file.exists(cfg_path)) {
      cli::cli_abort("Configuration module not found at {cfg_path}.")
    }
    sys.source(cfg_path, envir = topenv())
  }
}

ensure_config_loaded()

config_instance()

github_settings <- function() {
  config_instance()$github
}

github_user_agent <- function() {
  github_settings()$user_agent
}

github_agent_users <- function() {
  github_settings()$agent_users
}

github_org <- function() {
  github_settings()$org
}

github_headers <- function() {
  gh <- github_settings()
  list(
    Accept = "application/vnd.github+json",
    Authorization = sprintf("Bearer %s", gh$token),
    `X-GitHub-Api-Version` = "2022-11-28",
    `User-Agent` = gh$user_agent
  )
}

github_request <- function(endpoint,
                           query = list(),
                           method = "GET",
                           body = NULL) {
  gh <- github_settings()
  endpoint <- sub("^/", "", endpoint)

  req <- httr2::request(gh$api_url)
  if (nzchar(endpoint)) {
    req <- httr2::req_url_path_append(req, endpoint)
  }

  req <- do.call(httr2::req_headers, c(list(req), github_headers()))

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
}

github_request_from_url <- function(url) {
  req <- httr2::request(url)
  do.call(httr2::req_headers, c(list(req), github_headers()))
}

github_perform <- function(req) {
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
}

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

github_get <- function(endpoint,
                       query = list(),
                       paginate = TRUE,
                       per_page = 100,
                       max_pages = Inf) {
  if (paginate) {
    query$per_page <- per_page
  }

  req <- github_request(endpoint, query = query)
  resp <- github_perform(req)

  if (!paginate) {
    return(httr2::resp_body_json(resp, simplifyVector = FALSE))
  }

  results <- as_list(httr2::resp_body_json(resp, simplifyVector = FALSE))
  next_link <- github_next_link(resp)

  page <- 1L
  while (!is.null(next_link) && page < max_pages) {
    req <- github_request_from_url(next_link)
    resp <- github_perform(req)
    chunk <- as_list(httr2::resp_body_json(resp, simplifyVector = FALSE))
    results <- c(results, chunk)
    next_link <- github_next_link(resp)
    page <- page + 1L
  }

  results
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
