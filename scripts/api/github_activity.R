# GitHub 開発活動取得モジュール --------------------------------------------
#
# GitHub REST API へのアクセスを `GitHubClient` に委譲し、リポジトリや PR、
# コミットなどの取得をまとめて扱うサービスクラスを提供する。
#
# このモジュールを経由することで、他のレイヤーは API パスやパラメータの
# 詳細を意識せずに利用できるようになる。

GitHubActivityService <- setRefClass(
  "GitHubActivityService",
  fields = list(
    client = "ANY"
  ),
  methods = list(
    initialize = function() {
      client <<- github_client()
      callSuper()
    },

    list_org_repositories = function(type = "all", per_page = 100, max_pages = Inf) {
      org <- client$org()
      endpoint <- sprintf("orgs/%s/repos", org)
      query <- list(type = type, per_page = per_page)
      client$get(endpoint, query = query, paginate = TRUE, max_pages = max_pages)
    },

    list_pull_requests = function(repo, state = "all", per_page = 100, max_pages = Inf) {
      endpoint <- sprintf("repos/%s/pulls", repo)
      query <- list(state = state, per_page = per_page)
      client$get(endpoint, query = query, paginate = TRUE, max_pages = max_pages)
    },

    list_pull_request_reviews = function(repo, number, per_page = 100, max_pages = Inf) {
      endpoint <- sprintf("repos/%s/pulls/%s/reviews", repo, number)
      query <- list(per_page = per_page)
      client$get(endpoint, query = query, paginate = TRUE, max_pages = max_pages)
    },

    list_pull_request_comments = function(repo, number, per_page = 100, max_pages = Inf) {
      endpoint <- sprintf("repos/%s/pulls/%s/comments", repo, number)
      query <- list(per_page = per_page)
      client$get(endpoint, query = query, paginate = TRUE, max_pages = max_pages)
    },

    list_commits = function(repo, since = NULL, until = NULL, per_page = 100, max_pages = Inf) {
      endpoint <- sprintf("repos/%s/commits", repo)
      query <- list(per_page = per_page)
      if (!is.null(since)) {
        query$since <- client$iso_time(since)
      }
      if (!is.null(until)) {
        query$until <- client$iso_time(until)
      }
      client$get(endpoint, query = query, paginate = TRUE, max_pages = max_pages)
    }
  )
)

get_activity_service <- local({
  instance <- NULL
  function() {
    if (is.null(instance)) {
      instance <<- GitHubActivityService$new()
    }
    instance
  }
})
