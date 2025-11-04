# 開発活動データの正規化・整形 ----------------------------------------------
#
# GitHub API から取得した生データを分析用の形へ変換するユーティリティを提供する。
# ここでは主にアクターの種別付与や時期区分などの共通処理をまとめておく。

# アクターがコーディングエージェントか人間かを判定する
label_actor_type <- function(login, agent_users = NULL) {
  agent_users <- agent_users %||% github_client()$agent_users()
  if (is.null(login) || !nzchar(login)) {
    return("unknown")
  }
  if (login %in% agent_users) {
    "agent"
  } else {
    "human"
  }
}

# T0 と比較して pre/post を付与する
label_ai_phase <- function(date, settings = NULL) {
  settings <- settings %||% config_instance()
  t0 <- settings$ai$t0
  if (is.null(date)) {
    return("unknown")
  }
  if (as.Date(date) < t0) {
    "pre_ai"
  } else {
    "post_ai"
  }
}

# %||% ヘルパー（念のためこのモジュール内にも定義しておく）
`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0) {
    y
  } else {
    x
  }
}
