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
      user_agent <- Sys.getenv("GITHUB_USER_AGENT", unset = "")
      if (!nzchar(user_agent)) {
        user_agent <- "analyze-github-activity/0.1"
      }

      list(
        token = token,
        org = org,
        api_url = api_url,
        agent_users = agent_users,
        user_agent = user_agent
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

      lookback_days <- 365L
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

    normalize_base_url = function(url) {
      if (!nzchar(url)) {
        return("https://api.github.com")
      }
      cleaned <- sub("/+\Z", "", url)
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
