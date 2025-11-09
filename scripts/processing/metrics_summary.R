# メトリクス集計ユーティリティ ------------------------------------------------
#
# 取得した GitHub 活動データを QuickSight 取込用のメトリクス形式へ集計する。

suppressWarnings({
  suppressPackageStartupMessages({
    library(dplyr)
    library(purrr)
    library(tibble)
    library(lubridate)
    library(tidyr)
  })
})

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0) {
    y
  } else {
    x
  }
}

parse_datetime_col <- function(x) {
  if (inherits(x, "POSIXct")) {
    return(x)
  }
  suppressWarnings(lubridate::ymd_hms(x, quiet = TRUE, tz = "UTC"))
}

earliest_time <- function(a, b) {
  len <- max(length(a), length(b))
  if (!length(len) || len == 0) {
    return(as.POSIXct(numeric(), origin = "1970-01-01", tz = "UTC"))
  }
  res <- as.POSIXct(rep(NA_real_, len), origin = "1970-01-01", tz = "UTC")
  a <- suppressWarnings(as.POSIXct(a, origin = "1970-01-01", tz = "UTC"))
  b <- suppressWarnings(as.POSIXct(b, origin = "1970-01-01", tz = "UTC"))
  valid_a <- !is.na(a)
  valid_b <- !is.na(b)
  res[valid_a & !valid_b] <- a[valid_a & !valid_b]
  res[!valid_a & valid_b] <- b[!valid_a & valid_b]
  both <- valid_a & valid_b
  if (any(both)) {
    res[both] <- ifelse(a[both] <= b[both], a[both], b[both])
  }
  res
}

time_diff_hours <- function(end, start) {
  if (!length(end) || !length(start)) {
    return(numeric())
  }
  end <- suppressWarnings(as.POSIXct(end, origin = "1970-01-01", tz = "UTC"))
  start <- suppressWarnings(as.POSIXct(start, origin = "1970-01-01", tz = "UTC"))
  res <- rep(NA_real_, length(start))
  valid <- !is.na(end) & !is.na(start) & end >= start
  if (any(valid)) {
    res[valid] <- as.numeric(difftime(end[valid], start[valid], units = "hours"))
  }
  res
}

repo_threshold_values <- function(repos, thresholds_map, default = 1L) {
  if (!is.null(thresholds_map) && !is.list(thresholds_map)) {
    thresholds_map <- as.list(thresholds_map)
  }
  if (is.null(thresholds_map)) {
    return(rep(default, length(repos)))
  }
  vapply(
    repos,
    function(repo) {
      val <- thresholds_map[[repo]]
      if (is.null(val) || is.na(val) || val < 1L) {
        default
      } else {
        as.integer(val)
      }
    },
    integer(1)
  )
}

nth_approval_numeric <- function(times_list, thresholds) {
  n <- length(times_list)
  if (n == 0) {
    return(numeric())
  }
  vapply(
    seq_len(n),
    function(i) {
      times <- times_list[[i]]
      threshold <- thresholds[[i]]
      if (is.null(times) || length(times) < threshold) {
        NA_real_
      } else {
        sorted <- sort(times)
        as.numeric(sorted[threshold])
      }
    },
    numeric(1)
  )
}

schema_cols <- c(
  "period_start",
  "interval",
  "repo",
  "actor_type",
  "metric_category",
  "metric_name",
  "metric_value",
  "value_unit",
  "sample_size",
  "ai_phase",
  "generated_at"
)

empty_metrics_tibble <- function() {
  tibble(
    period_start = as.Date(character()),
    interval = character(),
    repo = character(),
    actor_type = character(),
    metric_category = character(),
    metric_name = character(),
    metric_value = double(),
    value_unit = character(),
    sample_size = integer(),
    ai_phase = character(),
    generated_at = character()
  )
}

compute_period_start <- function(datetime, interval) {
  interval <- match.arg(interval, c("daily", "weekly", "monthly"))
  if (interval == "daily") {
    as.Date(datetime)
  } else if (interval == "weekly") {
    as.Date(lubridate::floor_date(datetime, unit = "week", week_start = 1))
  } else {
    as.Date(lubridate::floor_date(datetime, unit = "month"))
  }
}

assign_ai_phase <- function(dates, settings) {
  t0 <- settings$ai$t0
  ifelse(as.Date(dates) < t0, "pre_ai", "post_ai")
}

safe_min <- function(x) {
  x <- x[!is.na(x)]
  if (!length(x)) {
    return(NA)
  }
  suppressWarnings(min(x))
}

as_pr_dataframe <- function(activity_data) {
  pulls <- purrr::map(activity_data, "pulls")
  pulls <- pulls[lengths(pulls) > 0]
  if (!length(pulls)) {
    return(tibble())
  }

  dplyr::bind_rows(lapply(pulls, dplyr::bind_rows)) %>%
    dplyr::mutate(
      created_at = lubridate::ymd_hms(created_at, quiet = TRUE, tz = "UTC"),
      merged_at = lubridate::ymd_hms(merged_at, quiet = TRUE, tz = "UTC"),
      closed_at = lubridate::ymd_hms(closed_at, quiet = TRUE, tz = "UTC"),
      additions = as.numeric(additions),
      deletions = as.numeric(deletions),
      changed_files = as.numeric(changed_files),
      is_bug_fix = as.logical(is_bug_fix),
      is_revert = as.logical(is_revert)
    )
}

as_review_dataframe <- function(activity_data) {
  reviews <- purrr::map(activity_data, "reviews")
  reviews <- reviews[lengths(reviews) > 0]
  if (!length(reviews)) {
    return(tibble())
  }

  dplyr::bind_rows(lapply(reviews, dplyr::bind_rows)) %>%
    dplyr::mutate(
      submitted_at = lubridate::ymd_hms(submitted_at, quiet = TRUE, tz = "UTC"),
      state = toupper(state %||% NA_character_)
    )
}

as_review_comment_dataframe <- function(activity_data) {
  comments <- purrr::map(activity_data, "review_comments")
  comments <- comments[lengths(comments) > 0]
  if (!length(comments)) {
    return(tibble())
  }

  dplyr::bind_rows(lapply(comments, dplyr::bind_rows)) %>%
    dplyr::mutate(
      created_at = lubridate::ymd_hms(created_at, quiet = TRUE, tz = "UTC")
    )
}

as_commit_dataframe <- function(activity_data) {
  commits <- purrr::map(activity_data, "commits")
  commits <- commits[lengths(commits) > 0]
  if (!length(commits)) {
    return(tibble())
  }

  dplyr::bind_rows(lapply(commits, dplyr::bind_rows)) %>%
    dplyr::mutate(
      committed_at = lubridate::ymd_hms(committed_at, quiet = TRUE, tz = "UTC")
    )
}

prepare_pr_stats <- function(pr_df, review_df, comment_df, settings) {
  if (!nrow(pr_df)) {
    return(tibble())
  }

  thresholds_map <- settings$github$approval_thresholds %||% NULL

  review_summary <- tibble()
  if (nrow(review_df)) {
    review_summary <- review_df %>%
      dplyr::group_by(repo, number) %>%
      dplyr::summarise(
        first_review_time = safe_min(submitted_at),
        first_approval_time = safe_min(submitted_at[state == "APPROVED"]),
        review_count = dplyr::n(),
        review_iterations = sum(state %in% c("CHANGES_REQUESTED", "APPROVED"), na.rm = TRUE),
        approval_times = list(sort(submitted_at[state == "APPROVED"])),
        .groups = "drop"
      )
  }

  comment_summary <- tibble()
  if (nrow(comment_df)) {
    comment_summary <- comment_df %>%
      dplyr::group_by(repo, number) %>%
      dplyr::summarise(
        comment_count = dplyr::n(),
        first_comment_time = safe_min(created_at),
        .groups = "drop"
      )
  }

  joined <- pr_df %>%
    dplyr::left_join(review_summary, by = c("repo", "number")) %>%
    dplyr::left_join(comment_summary, by = c("repo", "number"))

  if (!"approval_times" %in% names(joined)) {
    joined$approval_times <- vector("list", nrow(joined))
  } else {
    joined$approval_times <- lapply(joined$approval_times %||% vector("list", length.out = nrow(joined)), function(x) {
      if (is.null(x) || all(is.na(x))) {
        numeric()
      } else {
        x
      }
    })
  }

  repo_threshold_vec <- repo_threshold_values(joined$repo, thresholds_map, default = 1L)
  approval_time_numeric <- nth_approval_numeric(joined$approval_times, repo_threshold_vec)
  target_approval_time <- as.POSIXct(approval_time_numeric, origin = "1970-01-01", tz = "UTC")

  joined %>%
    dplyr::mutate(
      comment_count = dplyr::coalesce(comment_count, 0),
      review_count = dplyr::coalesce(review_count, 0),
      review_iterations = dplyr::coalesce(review_iterations, 0),
      first_review_time = parse_datetime_col(first_review_time),
      first_comment_time = parse_datetime_col(first_comment_time),
      first_approval_time = parse_datetime_col(first_approval_time),
      response_event_time = earliest_time(first_review_time, first_comment_time),
      approval_threshold = repo_threshold_vec,
      approval_target_time = target_approval_time,
      completion_time = dplyr::coalesce(approval_target_time, merged_at, closed_at),
      lead_time_hours = time_diff_hours(completion_time, created_at),
      review_to_approval_hours = time_diff_hours(approval_target_time, first_review_time),
      pr_first_review_time_hours = time_diff_hours(first_review_time, created_at),
      review_response_time_hours = time_diff_hours(response_event_time, created_at),
      lines_added = coalesce(additions, 0),
      lines_deleted = coalesce(deletions, 0),
      bug_fix_flag = !is.na(is_bug_fix) & is_bug_fix,
      revert_flag = !is.na(is_revert) & is_revert
    ) %>%
    dplyr::select(-response_event_time, -completion_time, -approval_times)
}

finalize_sum_metric <- function(repo_df,
                                interval,
                                metric_name,
                                metric_category,
                                value_unit,
                                generated_at,
                                settings) {
  if (!nrow(repo_df)) {
    return(empty_metrics_tibble())
  }

  repo_df <- repo_df %>%
    dplyr::mutate(
      ai_phase = assign_ai_phase(period_start, settings),
      interval = interval,
      metric_category = metric_category,
      metric_name = metric_name,
      value_unit = value_unit,
      generated_at = format(generated_at, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      sample_size = as.integer(sample_size),
      metric_value = as.numeric(metric_value)
    ) %>%
    dplyr::select(dplyr::all_of(schema_cols))

  overall <- repo_df %>%
    dplyr::group_by(actor_type, ai_phase, period_start) %>%
    dplyr::summarise(
      metric_value = sum(metric_value, na.rm = TRUE),
      sample_size = sum(sample_size, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    dplyr::mutate(
      repo = "ALL",
      interval = interval,
      metric_category = metric_category,
      metric_name = metric_name,
      value_unit = value_unit,
      generated_at = format(generated_at, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    ) %>%
    dplyr::mutate(ai_phase = assign_ai_phase(period_start, settings)) %>%
    dplyr::select(dplyr::all_of(schema_cols))

  dplyr::bind_rows(repo_df, overall) %>%
    dplyr::arrange(period_start, repo, actor_type)
}

finalize_mean_metric <- function(repo_df,
                                 interval,
                                 metric_name,
                                 metric_category,
                                 value_unit,
                                 generated_at,
                                 settings) {
  if (!nrow(repo_df)) {
    return(empty_metrics_tibble())
  }

  repo_df_raw <- repo_df
  repo_df <- repo_df %>%
    dplyr::mutate(
      metric_value = ifelse(sample_size > 0, sum_value / sample_size, NA_real_)
    )

  repo_prepared <- repo_df %>%
    dplyr::mutate(
      ai_phase = assign_ai_phase(period_start, settings),
      interval = interval,
      metric_category = metric_category,
      metric_name = metric_name,
      value_unit = value_unit,
      generated_at = format(generated_at, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      sample_size = as.integer(sample_size)
    ) %>%
    dplyr::select(-sum_value) %>%
    dplyr::select(dplyr::all_of(schema_cols))

  overall <- repo_df_raw %>%
    dplyr::group_by(actor_type, period_start) %>%
    dplyr::summarise(
      sum_value = sum(sum_value, na.rm = TRUE),
      sample_size = sum(sample_size, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    dplyr::mutate(
      metric_value = ifelse(sample_size > 0, sum_value / sample_size, NA_real_),
      repo = "ALL",
      ai_phase = assign_ai_phase(period_start, settings),
      interval = interval,
      metric_category = metric_category,
      metric_name = metric_name,
      value_unit = value_unit,
      generated_at = format(generated_at, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    ) %>%
    dplyr::select(-sum_value) %>%
    dplyr::select(dplyr::all_of(schema_cols))

  dplyr::bind_rows(repo_prepared, overall) %>%
    dplyr::arrange(period_start, repo, actor_type)
}

finalize_ratio_metric <- function(repo_df,
                                  interval,
                                  metric_name,
                                  metric_category,
                                  value_unit,
                                  generated_at,
                                  settings) {
  if (!nrow(repo_df)) {
    return(empty_metrics_tibble())
  }

  repo_df <- repo_df %>%
    dplyr::mutate(
      metric_value = ifelse(denominator > 0, numerator / denominator, NA_real_),
      sample_size = as.integer(denominator)
    )

  repo_prepared <- repo_df %>%
    dplyr::mutate(
      ai_phase = assign_ai_phase(period_start, settings),
      interval = interval,
      metric_category = metric_category,
      metric_name = metric_name,
      value_unit = value_unit,
      generated_at = format(generated_at, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    ) %>%
    dplyr::select(-numerator, -denominator) %>%
    dplyr::select(dplyr::all_of(schema_cols))

  overall <- repo_df %>%
    dplyr::group_by(actor_type, period_start) %>%
    dplyr::summarise(
      numerator = sum(numerator, na.rm = TRUE),
      denominator = sum(denominator, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    dplyr::mutate(
      metric_value = ifelse(denominator > 0, numerator / denominator, NA_real_),
      sample_size = as.integer(denominator),
      repo = "ALL",
      ai_phase = assign_ai_phase(period_start, settings),
      interval = interval,
      metric_category = metric_category,
      metric_name = metric_name,
      value_unit = value_unit,
      generated_at = format(generated_at, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    ) %>%
    dplyr::select(-numerator, -denominator) %>%
    dplyr::select(dplyr::all_of(schema_cols))

  dplyr::bind_rows(repo_prepared, overall) %>%
    dplyr::arrange(period_start, repo, actor_type)
}

metric_pr_counts <- function(pr_df, interval, generated_at, settings) {
  if (!nrow(pr_df)) {
    return(empty_metrics_tibble())
  }

  data <- pr_df %>%
    dplyr::filter(!is.na(created_at)) %>%
    dplyr::mutate(period_start = compute_period_start(created_at, interval))

  if (!nrow(data)) {
    return(empty_metrics_tibble())
  }

  repo_level <- data %>%
    dplyr::group_by(repo, actor_type, period_start) %>%
    dplyr::summarise(
      metric_value = dplyr::n(),
      sample_size = dplyr::n(),
      .groups = "drop"
    )

  finalize_sum_metric(
    repo_level,
    interval,
    "pr_count",
    "productivity",
    "count",
    generated_at,
    settings
  )
}

metric_commit_counts <- function(commit_df, interval, generated_at, settings) {
  if (!nrow(commit_df)) {
    return(empty_metrics_tibble())
  }

  data <- commit_df %>%
    dplyr::filter(!is.na(committed_at)) %>%
    dplyr::mutate(period_start = compute_period_start(committed_at, interval))

  if (!nrow(data)) {
    return(empty_metrics_tibble())
  }

  repo_level <- data %>%
    dplyr::group_by(repo, actor_type, period_start) %>%
    dplyr::summarise(
      metric_value = dplyr::n(),
      sample_size = dplyr::n(),
      .groups = "drop"
    )

  finalize_sum_metric(
    repo_level,
    interval,
    "commit_count",
    "productivity",
    "count",
    generated_at,
    settings
  )
}

metric_line_changes <- function(pr_stats,
                                interval,
                                generated_at,
                                settings,
                                field,
                                metric_name) {
  if (!nrow(pr_stats)) {
    return(empty_metrics_tibble())
  }

  data <- pr_stats %>%
    dplyr::filter(!is.na(created_at)) %>%
    dplyr::mutate(
      value = coalesce(.data[[field]], 0),
      period_start = compute_period_start(created_at, interval)
    )

  if (!nrow(data)) {
    return(empty_metrics_tibble())
  }

  repo_level <- data %>%
    dplyr::group_by(repo, actor_type, period_start) %>%
    dplyr::summarise(
      metric_value = sum(value, na.rm = TRUE),
      sample_size = sum(!is.na(value)),
      .groups = "drop"
    )

  finalize_sum_metric(
    repo_level,
    interval,
    metric_name,
    "productivity",
    "lines",
    generated_at,
    settings
  )
}

metric_mean_from_pr <- function(pr_stats,
                                interval,
                                generated_at,
                                settings,
                                value_col,
                                metric_name,
                                metric_category,
                                value_unit) {
  if (!nrow(pr_stats)) {
    return(empty_metrics_tibble())
  }

  data <- pr_stats %>%
    dplyr::filter(!is.na(created_at)) %>%
    dplyr::mutate(
      value = .data[[value_col]],
      period_start = compute_period_start(created_at, interval)
    )

  data <- data %>%
    dplyr::filter(!is.na(period_start))

  if (!nrow(data)) {
    return(empty_metrics_tibble())
  }

  repo_level <- data %>%
    dplyr::group_by(repo, actor_type, period_start) %>%
    dplyr::summarise(
      sum_value = sum(value, na.rm = TRUE),
      sample_size = sum(!is.na(value)),
      .groups = "drop"
    )

  finalize_mean_metric(
    repo_level,
    interval,
    metric_name,
    metric_category,
    value_unit,
    generated_at,
    settings
  )
}

metric_ratio_from_pr <- function(pr_stats,
                                 interval,
                                 generated_at,
                                 settings,
                                 flag_col,
                                 metric_name,
                                 metric_category) {
  if (!nrow(pr_stats)) {
    return(empty_metrics_tibble())
  }

  data <- pr_stats %>%
    dplyr::filter(!is.na(created_at)) %>%
    dplyr::mutate(
      flag = ifelse(isTRUE(.data[[flag_col]]), 1L, 0L),
      period_start = compute_period_start(created_at, interval)
    )

  if (!nrow(data)) {
    return(empty_metrics_tibble())
  }

  repo_level <- data %>%
    dplyr::group_by(repo, actor_type, period_start) %>%
    dplyr::summarise(
      numerator = sum(flag, na.rm = TRUE),
      denominator = dplyr::n(),
      .groups = "drop"
    )

  finalize_ratio_metric(
    repo_level,
    interval,
    metric_name,
    metric_category,
    "ratio",
    generated_at,
    settings
  )
}

metric_revert_counts <- function(pr_stats,
                                 interval,
                                 generated_at,
                                 settings) {
  if (!nrow(pr_stats)) {
    return(empty_metrics_tibble())
  }

  data <- pr_stats %>%
    dplyr::filter(!is.na(created_at)) %>%
    dplyr::mutate(
      flag = ifelse(isTRUE(revert_flag), 1L, 0L),
      period_start = compute_period_start(created_at, interval)
    )

  repo_level <- data %>%
    dplyr::group_by(repo, actor_type, period_start) %>%
    dplyr::summarise(
      metric_value = sum(flag, na.rm = TRUE),
      sample_size = dplyr::n(),
      .groups = "drop"
    )

  finalize_sum_metric(
    repo_level,
    interval,
    "revert_pr_count",
    "quality",
    "count",
    generated_at,
    settings
  )
}

build_metrics_dataset <- function(activity_data,
                                  intervals = c("daily", "weekly", "monthly")) {
  pr_df <- as_pr_dataframe(activity_data)
  review_df <- as_review_dataframe(activity_data)
  comment_df <- as_review_comment_dataframe(activity_data)
  commit_df <- as_commit_dataframe(activity_data)
  settings <- config_instance()
  pr_stats <- prepare_pr_stats(pr_df, review_df, comment_df, settings)

  generated_at <- Sys.time()

  interval_metrics <- purrr::map(
    intervals,
    function(interval) {
      dplyr::bind_rows(
        metric_pr_counts(pr_df, interval, generated_at, settings),
        metric_commit_counts(commit_df, interval, generated_at, settings),
        metric_line_changes(pr_stats, interval, generated_at, settings, "lines_added", "lines_added"),
        metric_line_changes(pr_stats, interval, generated_at, settings, "lines_deleted", "lines_deleted"),
        metric_mean_from_pr(
          pr_stats,
          interval,
          generated_at,
          settings,
          "lead_time_hours",
          "pr_lead_time_hours",
          "productivity",
          "hours"
        ),
        metric_mean_from_pr(
          pr_stats,
          interval,
          generated_at,
          settings,
          "review_response_time_hours",
          "review_response_time_hours",
          "collaboration",
          "hours"
        ),
        metric_mean_from_pr(
          pr_stats,
          interval,
          generated_at,
          settings,
          "pr_first_review_time_hours",
          "pr_first_review_time_hours",
          "collaboration",
          "hours"
        ),
        metric_mean_from_pr(
          pr_stats,
          interval,
          generated_at,
          settings,
          "review_to_approval_hours",
          "review_to_approval_time_hours",
          "productivity",
          "hours"
        ),
        metric_mean_from_pr(
          pr_stats,
          interval,
          generated_at,
          settings,
          "comment_count",
          "pr_comment_count",
          "quality",
          "count"
        ),
        metric_mean_from_pr(
          pr_stats,
          interval,
          generated_at,
          settings,
          "review_iterations",
          "review_iteration_count",
          "quality",
          "count"
        ),
        metric_ratio_from_pr(
          pr_stats,
          interval,
          generated_at,
          settings,
          "bug_fix_flag",
          "bug_fix_ratio",
          "quality"
        ),
        metric_revert_counts(
          pr_stats,
          interval,
          generated_at,
          settings
        )
      )
    }
  )

  dplyr::bind_rows(interval_metrics) %>%
    dplyr::distinct()
}
