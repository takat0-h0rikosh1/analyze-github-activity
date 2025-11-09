# データ出力手順

このドキュメントは GitHub 活動データを再取得し、CSV と可視化 PNG を生成するまでの手順をまとめたものです。Docker 上で動作する R パイプラインを対象としています。

## 前提条件

- Docker / Docker Compose がインストール済みであること
- プロジェクトルートに `.env` ファイルを作成し、少なくとも以下を設定済みであること

```bash
cp .env.template .env
```

### 必須設定

| 変数名           | 必須 | 説明                                                                 |
|------------------|------|----------------------------------------------------------------------|
| `GITHUB_TOKEN`   | ○    | `repo` / `read:org` 権限を持つ PAT。OSS リポジトリに含めないこと    |
| `GITHUB_ORG`     | ○    | 取得対象の GitHub Organization 名                                     |

### 重要な設定

| 変数名           | デフォルト | 説明                                                                 |
|------------------|-----------|----------------------------------------------------------------------|
| `AI_T0`          | `2025-06-18` | AI ツール導入日（T0）。この日付を境に pre_ai / post_ai を分類 |
| `AI_LOOKBACK_DAYS` | `180` | T0 から遡ってデータを取得する日数。試験実行=30-60, 通常=180, 長期=365 |
| `GITHUB_MAX_PR_PAGES` | `100` | 各リポジトリの PR 一覧取得の最大ページ数（100ページ=最大10,000PR）<br>**重要**: この値が小さすぎると古い PR が取得できず、データが欠落します |

### その他のオプション設定

| 変数名           | デフォルト | 説明                                                                 |
|------------------|-----------|----------------------------------------------------------------------|
| `GITHUB_TARGET_REPOS` | - | 対象リポジトリを `owner/name` でカンマ区切り指定（省略時は全リポジトリ） |
| `GITHUB_AGENT_USERS` | - | AI エージェント（Bot）として扱うユーザー名（カンマ区切り） |
| `GITHUB_APPROVAL_THRESHOLDS` | - | リポジトリごとの承認しきい値。`repo=2` 形式で指定 |
| `GITHUB_APPROVAL_THRESHOLDS_FILE` | - | 承認しきい値を外部ファイルから読み込む場合のパス |
| `PLOT_LABEL_LANGUAGE` | `en` | グラフのラベル言語（`en` または `ja`） |

### ページネーション制御

| 変数名           | デフォルト | 説明                                                                 |
|------------------|-----------|----------------------------------------------------------------------|
| `GITHUB_MAX_REPO_PAGES` | `1` | リポジトリ一覧取得の最大ページ数 |
| `GITHUB_MAX_REVIEW_PAGES` | `10` | 各 PR のレビュー一覧取得の最大ページ数 |
| `GITHUB_MAX_COMMENT_PAGES` | `10` | 各 PR のコメント一覧取得の最大ページ数 |
| `GITHUB_MAX_COMMIT_PAGES` | `50` | 各リポジトリのコミット一覧取得の最大ページ数 |

### レート制限・スロットリング制御

| 変数名           | デフォルト | 説明                                                                 |
|------------------|-----------|----------------------------------------------------------------------|
| `GITHUB_REQUEST_PAUSE_SEC` | `0.25` | 各 API リクエスト後の待機時間（秒） |
| `GITHUB_RATE_THRESHOLD` | `50` | レート制限の残り回数がこの値を下回ると待機 |
| `GITHUB_RATE_RESET_PADDING_SEC` | `5` | レート制限リセット時刻に追加する余裕時間（秒） |

詳細な環境変数の説明は [環境変数リファレンス](./environment_variables.md) を参照してください。

## 実行手順

1. **データ取得期間の設定**
   `.env` ファイルで以下を設定します：

   ```bash
   # AI ツール導入日
   AI_T0=2025-06-18

   # T0 から遡る日数（デフォルト: 180日 = 6ヶ月）
   AI_LOOKBACK_DAYS=180
   ```

   これにより、`2024-12-20`（T0 - 180日）以降のデータが取得されます。

2. **ページネーション設定の確認**
   リポジトリの PR 数が多い場合は、`.env` で `GITHUB_MAX_PR_PAGES` を調整してください：

   ```bash
   # 各リポジトリから最大10,000PR取得（デフォルト）
   GITHUB_MAX_PR_PAGES=100

   # 大量のPRがある場合は増やす
   GITHUB_MAX_PR_PAGES=200
   ```

3. **レート制御の設定**
   GitHub API のレートリミットが厳しい場合は `.env` で調整してください：

   ```bash
   GITHUB_REQUEST_PAUSE_SEC=0.5
   GITHUB_RATE_THRESHOLD=100
   ```

   多数のリポジトリを処理する際は、初回のみ `GITHUB_REPO_LIMIT=5` のように制限をかけると安全です。

4. **パイプライン実行**
   プロジェクトルートで以下を実行します。

   ```bash
   docker compose run --rm app Rscript scripts/pipeline/generate_visualizations.R
   ```

   - **引数は不要**になりました。全ての設定は `.env` で制御されます。
   - 実行時間は GitHub API の待ち時間に依存し、複数リポジトリの場合は 20〜40 分程度かかることがあります。
   - レート制限に達した場合、自動的に待機してから再開します。
   - ログ末尾に「There were XX warnings」と表示される場合がありますが、データが存在しない指標で `geom_line` が NA を除外した旨の通知であり、通常は問題ありません。

5. **成果物の確認**
   - **CSV**: `output/files/github_activity_metrics.csv`
     QuickSight などにインポートできる統合データセットです。`interval`（daily / weekly / monthly）や `metric_name` でフィルタして利用します。

   - **可視化（通常版）**: `output/viz/*.png`
     以下の12種類のグラフが生成されます：
     - `pr_trends.png` - PR 件数
     - `commit_trends.png` - コミット数
     - `lines_added.png` - 追加行数
     - `lines_deleted.png` - 削除行数
     - `pr_lead_time.png` - PR リードタイム
     - `review_to_approval_time.png` - レビュー承認時間
     - `review_response_time.png` - レビュー応答時間
     - `first_review_time.png` - 初回レビュー時間
     - `pr_comment_count.png` - PR コメント数
     - `review_iteration_count.png` - レビュー反復回数
     - `bug_fix_ratio.png` - バグ修正率
     - `revert_pr_count.png` - リバート PR 数

   - **可視化（積み上げ版）**: `output/viz/*_stacked.png`
     以下の6種類のリポジトリ別積み上げグラフが生成されます：
     - `pr_trends_stacked.png` - PR 件数（リポジトリ別）
     - `commit_trends_stacked.png` - コミット数（リポジトリ別）
     - `lines_added_stacked.png` - 追加行数（リポジトリ別）
     - `lines_deleted_stacked.png` - 削除行数（リポジトリ別）
     - `pr_lead_time_stacked.png` - PR リードタイム（リポジトリ別）
     - `pr_comment_count_stacked.png` - PR コメント数（リポジトリ別）

   `PLOT_LABEL_LANGUAGE` に応じて英語 / 日本語でラベルが描画されます。

6. **結果の再利用**
   - QuickSight 取り込み、Google Drive 共有など必要な先へ CSV / PNG をアップロードしてください。
   - 新しい期間のデータが必要になった場合は、同じ手順で再実行するだけで最新の `generated_at` 付きデータを得られます。

## トラブルシューティング

| 症状 | 対応 |
|------|------|
| GitHub API が 403 / timeout になる | `GITHUB_REQUEST_PAUSE_SEC` を増やす（例: `0.5`）、`GITHUB_RATE_THRESHOLD` を増やす（例: `100`） |
| レート制限に頻繁に達する | `AI_LOOKBACK_DAYS` を減らす、`GITHUB_REPO_LIMIT` で対象を制限、`GITHUB_TARGET_REPOS` で絞り込む |
| データが欠落している（2025年前半など） | `GITHUB_MAX_PR_PAGES` を増やす（例: `200`）、`AI_LOOKBACK_DAYS` を確認 |
| 実行時間が長すぎる | `AI_LOOKBACK_DAYS` を減らす（例: `90`）、`GITHUB_TARGET_REPOS` で対象を絞る、`GITHUB_REPO_LIMIT` を設定 |
| グラフが文字化けする | `PLOT_LABEL_LANGUAGE=en` に戻すか、日本語フォントを導入した上で `ja` を利用する |
| AI エージェントの分類が機能しない | `GITHUB_AGENT_USERS` のユーザー名を確認、カンマ区切りにスペースが入っていないか確認 |
| 積み上げグラフが生成されない | `*_stacked.png` は自動生成されます。ログで `chart_type = "stacked_with_line"` が使用されているか確認 |

詳細なトラブルシューティングは [環境変数リファレンス](./environment_variables.md#トラブルシューティング) を参照してください。

以上でデータ再出力の手順は完了です。
