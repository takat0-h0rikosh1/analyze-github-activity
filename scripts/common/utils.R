# 共通ユーティリティ -------------------------------------------------
#
# 汎用的なヘルパー関数を定義する。特定の API やドメインに依存しない処理は
# ここにまとめ、各モジュールから再利用する。

# NULL や長さ 0 のベクトルを安全に扱うユーティリティ
as_list_safe <- function(x) {
  if (is.null(x)) {
    list()
  } else if (is.list(x)) {
    x
  } else {
    list(x)
  }
}

# URL に含める文字列をエンコードする（`reserved = TRUE` で予約文字もエンコード）
url_encode <- function(x) {
  utils::URLencode(x, reserved = TRUE)
}

# 日付や日時を ISO8601 形式の文字列 (UTC) に変換する
iso_datetime <- function(x) {
  if (is.null(x)) {
    return(NULL)
  }
  if (inherits(x, "Date")) {
    return(sprintf("%sT00:00:00Z", format(x, "%Y-%m-%d")))
  }
  if (!inherits(x, "POSIXt")) {
    cli::cli_abort("ISO 形式に変換できない型です: {class(x)[1]}")
  }
  format(as.POSIXct(x, tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}

# ISO8601 の文字列を POSIXct (UTC) に変換する
parse_iso_datetime <- function(x) {
  if (is.null(x)) {
    return(NULL)
  }
  as.POSIXct(x, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}
