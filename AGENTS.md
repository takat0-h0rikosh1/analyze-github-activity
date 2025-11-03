# AGENTS.md

## プロジェクト概要
- AI Coding Agent 導入後の GitHub アクティビティを定量評価し、生産効率の変化を可視化する
- QuickSight でダッシュボードを構築するため、CSV などアップロード可能なデータソースを生成する

## 用語定義
- **T0**: AI Coding Agent を正式導入した基準日。2025/06/18（Claude Code 導入日）を用いる。
- **pre_ai**: `period_start` が T0 より前のデータで、過去 1 年分（2024/06/18 〜 2025/06/17）を取得する。
- **post_ai**: `period_start` が T0 当日以降のデータで、T0 から現在日時までを取得する。

## 使用技術・方針
- プログラミング言語は R を採用
- パッケージ管理は `renv` を利用し、依存パッケージをロックする
- 端末依存を避けるため Docker コンテナ上で実行できる構成とする（R 本体＋renv 導入済みイメージ）

## 利用中の AI Coding Agent
| Agent           | Coding | Code Review |
|-----------------|--------|-------------|
| GitHub Copilot  | Yes    | Yes         |
| CodeRabbit AI   | No     | Yes         |
| Claude Code     | Yes    | Yes         |

## 分析対象
- GitHub の Push、Pull Request、Review、Review Comment などの開発活動
- Pull Request 系の指標は Coding Agent と開発メンバーを識別できる形で取得・分類
- Issue 系イベントは使用頻度が低いため分析対象外
- AI 導入日 (`T0`) を境界に `pre_ai` / `post_ai` フェーズを判定

## 成果物
- QuickSight へインポート可能な CSV データセット
- 同 CSV を生成する R スクリプト／ノートブック
- スクリプト実行時に生成する可視化（例: Pull Request 活動の推移グラフ）

## 可視化対象指標
- **開発速度・生産性**
  - コミット数（日次 / 週次 / 月次）
  - PR 数（日次 / 週次 / 月次）
  - コードレビューから承認までの時間
  - PR のリードタイム（作成から完了まで）
  - 1 日あたりのコード変更行数（追加 / 削除）
- **コード品質**
  - PR あたりのコメント数
  - レビューイテレーション回数
  - バグ修正 PR の割合
  - リバートされた PR の数
- **協働効率**
  - レビュー応答時間
  - PR 作成から最初のレビューまでの時間

## データ生成の主な流れ
1. GitHub API (REST/GraphQL, `gh api` など) から対象リポジトリの Push/PR/Review/Review Comment を取得（R スクリプトで実装）
   - 対象 GitHub Organization を環境変数で指定し、その配下のリポジトリを横断的に収集する
2. 生データを正規化し、日次または週次粒度で開発指標を集計（`dplyr` などを活用）
   - 例: コミット数、変更行数、マージ PR 数、レビュー数、レビュー応答時間
   - Bot ユーザーを除外し、欠損や重複をチェック
3. 集計結果に `pre_ai` / `post_ai` を付与した CSV を出力し、QuickSight に取り込む
4. 同集計結果を基に R 内で可視化を作成し、PNG などで出力する

## 直近のタスク
- R プロジェクトおよび `renv` 環境の初期化
- Dockerfile を作成し、R 環境＋renv で再現可能な実行手段を整備
- GitHub API 取得スクリプトの実装 (Issues 系 API は呼び出さない)
- PR 取得処理で Coding Agent／開発メンバーを区別するロジックの実装
- 集計ロジックの実装と QuickSight 用 CSV の生成
- 集計結果を用いた可視化・グラフ生成機能の実装
- 責務に応じてスクリプト・可視化・データ出力ディレクトリを分割し、コードベースの見通しを確保

## 環境変数
| 変数名              | 必須 | 用途・説明                                                                                 |
|---------------------|------|--------------------------------------------------------------------------------------------|
| `GITHUB_TOKEN`      | Yes  | GitHub API 認証用 Personal Access Token（`repo`, `read:org` 権限を推奨）                    |
| `GITHUB_ORG`        | Yes  | データ取得対象となる GitHub Organization 名（例: `example-inc`）                          |
| `GITHUB_API_URL`    | No   | GitHub Enterprise を利用する場合などの API ベース URL（省略時は `https://api.github.com`） |
| `GITHUB_AGENT_USERS`| No   | Coding Agent とみなす GitHub ユーザー名をカンマ区切りで指定（指定がない場合は既定リスト） |
| `OUTPUT_DIR`        | No   | CSV や可視化ファイルを出力するディレクトリパス（省略時は `data/` 配下を使用）             |

- `renv` / Docker 実行時には上記環境変数を `.env` や実行時オプションで設定し、スクリプトから参照する。GitHub 認証情報はリポジトリに含めないこと。

## CSV スキーマ定義
**対象ファイル:** `data/github_activity_metrics.csv`

| フィールド名       | 型        | 説明                                                                 |
|-------------------|-----------|----------------------------------------------------------------------|
| `period_start`    | DATE      | 集計期間の開始日（ISO-8601、日次/週次/月次の基準日）                  |
| `interval`        | STRING    | 集計粒度（`daily` / `weekly` / `monthly`）                           |
| `repo`            | STRING    | リポジトリ名（`owner/name`）。全体集計は `ALL` などで表現             |
| `actor_type`      | STRING    | 活動主体区分（`human` / `agent`）                                    |
| `metric_category` | STRING    | 指標カテゴリ（`productivity` / `quality` / `collaboration`）          |
| `metric_name`     | STRING    | 指標名（例: `commit_count`, `pr_lead_time_hours`）                    |
| `metric_value`    | DOUBLE    | 指標値（件数・平均時間・割合・行数など）                              |
| `value_unit`      | STRING    | 指標の単位（`count` / `hours` / `ratio` / `lines` など）               |
| `sample_size`     | INTEGER   | 指標算出時のサンプル数（平均値の母数など、不要時は NULL）             |
| `ai_phase`        | STRING    | `pre_ai` / `post_ai`（`period_start` と AI 導入日で判定）              |
| `generated_at`    | TIMESTAMP | データ生成時刻（再計算の識別用）                                      |

- 同スキーマにより QuickSight で棒グラフや折れ線グラフへの割り当てが容易（時間軸、主体区分、導入前後比較などを柔軟に可視化可能）。
- 指標別の詳細分析が必要な場合は別 CSV（例: `data/pr_detail.csv`）で PR 単位の情報を保持し、QuickSight のドリルダウンに活用する。
