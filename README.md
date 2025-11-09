# analyze-github-activity

GitHub Organization の開発活動を分析し、AI ツール導入前後の効果を測定するためのツールです。

## 概要

このツールは GitHub REST API を使用して、以下のデータを取得・分析します：

- Pull Request の件数、リードタイム、レビュー時間
- コミット数、コード変更量（追加/削除行数）
- レビューの反復回数、コメント数
- バグ修正率、リバート率

取得したデータを QuickSight などのBI ツールで分析可能な CSV 形式で出力し、さらに月次推移グラフを自動生成します。

## 主な機能

### データ取得

- ✅ **期間指定**: AI 導入日（T0）から遡った期間のデータを取得
- ✅ **リポジトリ絞り込み**: 対象リポジトリを指定可能
- ✅ **AI エージェント分類**: human / agent を自動分類
- ✅ **日付フィルタリング**: 不要な古いデータを除外して効率化

### 可視化

- ✅ **通常版グラフ**: 12種類の時系列グラフ（折れ線）
- ✅ **積み上げ版グラフ**: 6種類のリポジトリ別積み上げグラフ
- ✅ **T0 マーカー**: AI 導入日を明示
- ✅ **多言語対応**: 英語/日本語のラベル切り替え

### 出力形式

- **CSV**: `output/files/github_activity_metrics.csv`
  - QuickSight, Tableau, Google Sheets などで利用可能
  - daily / weekly / monthly の集計粒度

- **PNG グラフ**: `output/viz/*.png`
  - 通常版: `pr_trends.png`, `lines_added.png` など12種類
  - 積み上げ版: `pr_trends_stacked.png` など6種類

## クイックスタート

### 1. 前提条件

- Docker / Docker Compose
- GitHub Personal Access Token（`repo`, `read:org` スコープ）

### 2. 環境設定

```bash
# .env ファイルを作成
cp .env.template .env

# 必須項目を設定
vim .env
```

最低限必要な設定：

```bash
GITHUB_TOKEN=github_pat_XXXXXXXXXXXXXXXXXXXXX
GITHUB_ORG=your-organization
```

### 3. データ取得・可視化

```bash
# パイプライン実行
docker compose run --rm app Rscript scripts/pipeline/generate_visualizations.R
```

実行後、以下が生成されます：

- `output/files/github_activity_metrics.csv` - メトリクスデータ
- `output/viz/*.png` - 可視化グラフ（18枚）

### 4. 出力の確認

```bash
# CSV確認
head -20 output/files/github_activity_metrics.csv

# グラフ確認
open output/viz/pr_trends_stacked.png
```

## 主要な環境変数

| 変数名 | デフォルト | 説明 |
|--------|-----------|------|
| `GITHUB_TOKEN` | - | **必須**: GitHub Personal Access Token |
| `GITHUB_ORG` | - | **必須**: 分析対象の Organization 名 |
| `AI_T0` | `2025-06-18` | AI ツール導入日（この日付を境に pre_ai / post_ai を分類） |
| `AI_LOOKBACK_DAYS` | `180` | T0 から遡る日数（データ取得期間） |
| `GITHUB_MAX_PR_PAGES` | `100` | PR 一覧取得の最大ページ数（100ページ=10,000PR） |
| `GITHUB_TARGET_REPOS` | - | 対象リポジトリ（カンマ区切り） |
| `GITHUB_AGENT_USERS` | - | AI エージェントとして扱うユーザー名 |
| `PLOT_LABEL_LANGUAGE` | `en` | グラフラベル言語（`en` または `ja`） |

詳細は [環境変数リファレンス](./docs/environment_variables.md) を参照してください。

## ドキュメント

- 📖 [実行手順ガイド](./docs/execution_guide.md) - 詳しい実行手順とトラブルシューティング
- 📖 [環境変数リファレンス](./docs/environment_variables.md) - 全20項目の環境変数の詳細説明
- 📊 [分析インサイト例](./docs/analysis_insights_20251109.md) - 実際の分析結果サンプル

## 使用例

### 基本的な使い方

```bash
# 6ヶ月間のデータを取得（デフォルト）
docker compose run --rm app Rscript scripts/pipeline/generate_visualizations.R
```

### 期間を変更

```bash
# .env で設定
AI_LOOKBACK_DAYS=90  # 3ヶ月間に変更
```

### 対象リポジトリを絞る

```bash
# .env で設定
GITHUB_TARGET_REPOS=your-org/repo1,your-org/repo2,your-org/repo3
```

### AI エージェントを分類

```bash
# .env で設定
GITHUB_AGENT_USERS=github-copilot,coderabbit-ai,dependabot
```

## アーキテクチャ

```
scripts/
├── api/                      # GitHub API クライアント
│   ├── github_client.R       # 汎用 API クライアント
│   └── github_activity.R     # 活動データ取得サービス
├── config/
│   └── settings.R            # 環境変数管理
├── processing/
│   ├── activity_transform.R  # データ変換
│   └── metrics_summary.R     # メトリクス集計
├── viz/
│   ├── pr_trends.R           # グラフ生成
│   └── regenerate_plots.R    # グラフ再生成ユーティリティ
└── pipeline/
    ├── fetch_activity.R      # データ取得パイプライン
    └── generate_visualizations.R  # 統合パイプライン
```

## 技術スタック

- **言語**: R 4.3.3
- **主要パッケージ**:
  - `httr2` - HTTP クライアント
  - `dplyr` - データ変換
  - `ggplot2` - グラフ生成
  - `cli` - ログ出力
- **コンテナ**: Docker (rocker/r-ver:4.3.3)
- **パッケージ管理**: renv

## トラブルシューティング

### レート制限に頻繁に達する

```bash
# リクエスト間隔を増やす
GITHUB_REQUEST_PAUSE_SEC=0.5

# 取得期間を短縮
AI_LOOKBACK_DAYS=60

# 対象リポジトリを絞る
GITHUB_TARGET_REPOS=your-org/repo1,your-org/repo2
```

### データが欠落している

```bash
# PR取得ページ数を増やす
GITHUB_MAX_PR_PAGES=200

# 取得期間を確認
AI_LOOKBACK_DAYS=180
```

### 実行時間が長すぎる

- **原因**: PR 詳細取得（additions/deletions）が多い
- **対処**: `AI_LOOKBACK_DAYS` を減らす、`GITHUB_TARGET_REPOS` で絞る

詳細は [実行手順ガイド](./docs/execution_guide.md#トラブルシューティング) を参照してください。

## ライセンス

このプロジェクトのライセンスについては、プロジェクト管理者にお問い合わせください。

## 貢献

バグ報告や機能要望は Issue でお知らせください。

## 参考資料

- [GitHub REST API ドキュメント](https://docs.github.com/en/rest)
- [GitHub API レート制限](https://docs.github.com/en/rest/overview/resources-in-the-rest-api#rate-limiting)
