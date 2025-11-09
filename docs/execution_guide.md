# データ出力手順

このドキュメントは GitHub 活動データを再取得し、CSV と可視化 PNG を生成するまでの手順をまとめたものです。Docker 上で動作する R パイプラインを対象としています。

## 前提条件

- Docker / Docker Compose がインストール済みであること
- プロジェクトルートに `.env` ファイルを作成し、少なくとも以下を設定済みであること

```bash
cp .env.template .env
```

| 変数名           | 必須 | 説明                                                                 |
|------------------|------|----------------------------------------------------------------------|
| `GITHUB_TOKEN`   | ○    | `repo` / `read:org` 権限を持つ PAT。OSS リポジトリに含めないこと    |
| `GITHUB_ORG`     | ○    | 取得対象の GitHub Organization 名                                     |
| `GITHUB_TARGET_REPOS` | △ | 対象リポジトリを `owner/name` でカンマ区切り指定（省略時は全リポジトリ） |
| `GITHUB_APPROVAL_THRESHOLDS` / `GITHUB_APPROVAL_THRESHOLDS_FILE` | △ | リポジトリごとの承認しきい値。`repo=2` 形式で指定し、機密値はファイル側に置く |
| `PLOT_LABEL_LANGUAGE` | △ | `en`（既定）または `ja`。日本語表示する場合のみ `ja` に設定し、フォントを用意する |

その他、`GITHUB_REQUEST_PAUSE_SEC` などのスロットリング系変数は `.env.template` を参照してください。

## 実行手順

1. **レート制御の確認**  
   GitHub API のレートリミットが厳しい場合は `.env` で `GITHUB_REQUEST_PAUSE_SEC` や `GITHUB_RATE_THRESHOLD` を調整してください。多数のリポジトリを処理する際は、初回のみ `GITHUB_REPO_LIMIT=10` のように制限をかけると安全です。

2. **パイプライン実行**  
   プロジェクトルートで以下を実行します。

   ```bash
   docker compose run --rm app Rscript scripts/pipeline/generate_visualizations.R
   ```

   - `max_repo_pages` や `max_pr_pages` を増やしたい場合は引数で指定可能です（例: `...generate_visualizations.R 2 2`）。
   - 実行時間は GitHub API の待ち時間に依存し、複数リポジトリの場合は 10〜20 分程度かかることがあります。
   - ログ末尾に「There were XX warnings」と表示される場合がありますが、データが存在しない指標で `geom_line` が NA を除外した旨の通知であり、通常は問題ありません。

3. **成果物の確認**  
   - CSV: `output/files/github_activity_metrics.csv`  
     QuickSight などにインポートできる統合データセットです。`interval`（daily / weekly / monthly）や `metric_name` でフィルタして利用します。
   - 可視化: `output/viz/*.png`  
     `pr_trends.png`（PR 件数）, `review_response_time.png`（レビュー応答時間）など 12 種類のグラフが生成されます。`PLOT_LABEL_LANGUAGE` に応じて英語 / 日本語でラベルが描画されます。

4. **結果の再利用**  
   - QuickSight 取り込み、Google Drive 共有など必要な先へ CSV / PNG をアップロードしてください。
   - 新しい期間のデータが必要になった場合は、同じ手順で再実行するだけで最新の `generated_at` 付きデータを得られます。

## トラブルシューティング

| 症状 | 対応 |
|------|------|
| GitHub API が 403 / timeout になる | `GITHUB_REQUEST_PAUSE_SEC` を増やす、対象リポジトリ数を減らして分割実行する |
| グラフが文字化けする | `PLOT_LABEL_LANGUAGE=en` に戻すか、日本語フォントを導入した上で `ja` を利用する |
| `lines_added` / `lines_deleted` が常に 0 | PR 詳細 API 呼び出しを追加する必要があります（現状は未取得）。必要に応じて機能追加してください |

以上でデータ再出力の手順は完了です。
