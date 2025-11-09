# 環境変数リファレンス

本ドキュメントでは、`analyze-github-activity` で使用可能な環境変数の詳細を説明します。

## 目次

- [必須環境変数](#必須環境変数)
- [GitHub API 設定](#github-api-設定)
- [AI/データ分析設定](#aiデータ分析設定)
- [ページネーション制御](#ページネーション制御)
- [レート制限・スロットリング制御](#レート制限スロットリング制御)
- [出力設定](#出力設定)
- [可視化設定](#可視化設定)
- [設定例](#設定例)

---

## 必須環境変数

これらの環境変数は必ず設定する必要があります。未設定の場合、スクリプト実行時にエラーが発生します。

### `GITHUB_TOKEN`

**説明**: GitHub Personal Access Token (PAT)。GitHub API へのアクセスに使用されます。

**必要なスコープ**:
- `repo` - プライベートリポジトリを含むリポジトリ情報へのアクセス
- `read:org` - Organization のリポジトリ一覧取得

**取得方法**:
1. GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
2. "Generate new token (classic)" をクリック
3. 必要なスコープを選択して生成

**例**:
```bash
GITHUB_TOKEN=github_pat_11AXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
```

**セキュリティ上の注意**:
- `.env` ファイルを `.gitignore` に追加し、Git にコミットしないこと
- トークンを共有しないこと
- 定期的にトークンをローテーションすること

---

### `GITHUB_ORG`

**説明**: 分析対象の GitHub Organization 名。

**形式**: Organization の名前（URL の `github.com/<org-name>` 部分）

**例**:
```bash
GITHUB_ORG=your-company
```

---

## GitHub API 設定

### `GITHUB_API_URL`

**説明**: GitHub API のベース URL。GitHub Enterprise Server を使用している場合に指定します。

**デフォルト値**: `https://api.github.com`

**例**:
```bash
# GitHub Enterprise Server の場合
GITHUB_API_URL=https://github.example.com/api/v3
```

---

### `GITHUB_AGENT_USERS`

**説明**: AI エージェント（Bot）として扱う GitHub ユーザー名のリスト。カンマ区切りで複数指定可能。

**デフォルト値**: 空（全てのユーザーを human として扱う）

**用途**:
- human vs agent の活動を分類
- AI 導入前後の効果測定に使用

**例**:
```bash
# GitHub Copilot, CodeRabbit, Claude Code を agent として分類
GITHUB_AGENT_USERS=github-copilot,coderabbit-ai,claude-code

# Dependabot も含める場合
GITHUB_AGENT_USERS=github-copilot,coderabbit-ai,claude-code,dependabot
```

---

### `GITHUB_TARGET_REPOS`

**説明**: 分析対象リポジトリを限定する場合に指定。カンマ区切りで複数指定可能。

**デフォルト値**: 空（Organization 内の全リポジトリを対象）

**形式**: `owner/repo-name` 形式

**例**:
```bash
# 特定の 3 つのリポジトリのみを分析
GITHUB_TARGET_REPOS=your-company/backend-api,your-company/frontend-app,your-company/mobile-app
```

**補足**:
- 指定された順序でリポジトリが処理されます
- 存在しないリポジトリ名を指定した場合、警告が出力されますが処理は継続します

---

### `GITHUB_USER_AGENT`

**説明**: GitHub API リクエスト時の User-Agent ヘッダー。

**デフォルト値**: `analyze-github-activity/0.1`

**例**:
```bash
GITHUB_USER_AGENT=my-company-analytics/1.0
```

---

### `GITHUB_APPROVAL_THRESHOLDS`

**説明**: リポジトリごとの承認数しきい値。カンマ区切りで `repo=threshold` 形式で指定。

**デフォルト値**: 全リポジトリで `1`

**用途**: 承認数が基準に達したかどうかの判定に使用（metrics に影響）

**例**:
```bash
# backend-api は 2 承認必要、frontend は 1 承認でOK
GITHUB_APPROVAL_THRESHOLDS=your-company/backend-api=2,your-company/frontend-app=1
```

---

### `GITHUB_APPROVAL_THRESHOLDS_FILE`

**説明**: 承認数しきい値をファイルから読み込む場合のパスを指定。

**デフォルト値**: 空

**ファイル形式**:
```
# コメント行は無視される
your-company/backend-api=2
your-company/frontend-app=1
your-company/mobile-app=2
```

**例**:
```bash
GITHUB_APPROVAL_THRESHOLDS_FILE=config/approval_thresholds.txt
```

**優先順位**: ファイルで指定された値が `GITHUB_APPROVAL_THRESHOLDS` よりも優先されますが、両方指定した場合は環境変数の値でファイルの値が上書きされます。

---

### `GITHUB_REPO_LIMIT`

**説明**: 処理するリポジトリ数の上限。テスト実行時や大規模 Organization での試験実行に有用。

**デフォルト値**: 無制限

**例**:
```bash
# 最初の 5 リポジトリのみ処理
GITHUB_REPO_LIMIT=5
```

---

## AI/データ分析設定

### `AI_T0`

**説明**: AI ツール導入日（T0: Time Zero）。この日付を境に pre_ai / post_ai 期間を分類します。

**デフォルト値**: `2025-06-18`

**形式**: ISO 8601 形式 (`YYYY-MM-DD`)

**用途**:
- AI 導入前後の効果測定
- グラフ上の T0 マーカー表示
- `ai_phase` フィールドの分類基準

**例**:
```bash
# 2024年1月1日から AI ツールを導入した場合
AI_T0=2024-01-01
```

---

### `AI_LOOKBACK_DAYS`

**説明**: T0 から遡ってデータを取得する日数。

**デフォルト値**: `180`（6ヶ月）

**用途**:
- データ取得範囲の制限
- API コール数の削減
- 分析に必要な期間のみを効率的に取得

**計算式**: `データ取得開始日 = AI_T0 - AI_LOOKBACK_DAYS`

**例**:
```bash
# 1年間のデータを取得
AI_LOOKBACK_DAYS=365

# 3ヶ月間のデータを取得
AI_LOOKBACK_DAYS=90
```

**推奨値**:
- **試験実行**: `30`～`60`（1～2ヶ月）
- **通常分析**: `180`（6ヶ月）
- **長期分析**: `365`（1年）

**注意**: 日数を増やすほど API コール数が増加し、レート制限に達する可能性が高まります。

---

## ページネーション制御

GitHub API は 1 リクエストあたり最大 100 件のアイテムを返します。大量のデータを取得する場合、複数ページに分けて取得する必要があります。これらの環境変数で最大ページ数を制御できます。

### `GITHUB_MAX_REPO_PAGES`

**説明**: リポジトリ一覧取得の最大ページ数。

**デフォルト値**: `1`

**取得可能件数**: `GITHUB_MAX_REPO_PAGES × 100` 件のリポジトリ

**例**:
```bash
# 最大 100 リポジトリ（1ページ）
GITHUB_MAX_REPO_PAGES=1

# 最大 500 リポジトリ（5ページ）
GITHUB_MAX_REPO_PAGES=5
```

**推奨値**:
- `GITHUB_TARGET_REPOS` で対象を絞っている場合: `1` で十分
- 大規模 Organization（100+ リポジトリ）: 必要に応じて増やす

---

### `GITHUB_MAX_PR_PAGES`

**説明**: 各リポジトリの PR 一覧取得の最大ページ数。

**デフォルト値**: `100`

**取得可能件数**: `GITHUB_MAX_PR_PAGES × 100` 件の PR

**重要**: この値が小さすぎると、古い PR が取得できず、データが欠落します。

**例**:
```bash
# 最大 10,000 PR（100ページ）- デフォルト
GITHUB_MAX_PR_PAGES=100

# 最大 5,000 PR（50ページ）
GITHUB_MAX_PR_PAGES=50

# 最大 20,000 PR（200ページ）
GITHUB_MAX_PR_PAGES=200
```

**推奨値**:
- **小～中規模リポジトリ**（年間 < 1,000 PR）: `50`
- **中～大規模リポジトリ**（年間 1,000～5,000 PR）: `100`（デフォルト）
- **大規模リポジトリ**（年間 > 5,000 PR）: `200`

**補足**:
- `AI_LOOKBACK_DAYS` で期間を制限しているため、実際に処理される PR 数はフィルタリング後の件数になります
- ページ数が多いほど API コール数が増加しますが、日付フィルタリングにより早期に取得が完了する場合もあります

---

### `GITHUB_MAX_REVIEW_PAGES`

**説明**: 各 PR のレビュー一覧取得の最大ページ数。

**デフォルト値**: `10`

**取得可能件数**: `GITHUB_MAX_REVIEW_PAGES × 100` 件のレビュー

**例**:
```bash
# 最大 1,000 レビュー（10ページ）- デフォルト
GITHUB_MAX_REVIEW_PAGES=10

# 最大 500 レビュー（5ページ）
GITHUB_MAX_REVIEW_PAGES=5
```

**推奨値**: `10`（通常の PR では十分）

---

### `GITHUB_MAX_COMMENT_PAGES`

**説明**: 各 PR のコメント一覧取得の最大ページ数。

**デフォルト値**: `10`

**取得可能件数**: `GITHUB_MAX_COMMENT_PAGES × 100` 件のコメント

**例**:
```bash
# 最大 1,000 コメント（10ページ）- デフォルト
GITHUB_MAX_COMMENT_PAGES=10

# 最大 2,000 コメント（20ページ）
GITHUB_MAX_COMMENT_PAGES=20
```

**推奨値**: `10`～`20`

---

### `GITHUB_MAX_COMMIT_PAGES`

**説明**: 各リポジトリのコミット一覧取得の最大ページ数。

**デフォルト値**: `50`

**取得可能件数**: `GITHUB_MAX_COMMIT_PAGES × 100` 件のコミット

**例**:
```bash
# 最大 5,000 コミット（50ページ）- デフォルト
GITHUB_MAX_COMMIT_PAGES=50

# 最大 10,000 コミット（100ページ）
GITHUB_MAX_COMMIT_PAGES=100
```

**推奨値**: `50`～`100`

**補足**: コミット取得は `AI_LOOKBACK_DAYS` に基づいた `since` パラメータで制限されるため、実際の取得件数は期間内のコミット数になります。

---

## レート制限・スロットリング制御

GitHub API にはレート制限があります（通常 5,000 リクエスト/時間）。これらの設定でレート制限への対応を調整できます。

### `GITHUB_REQUEST_PAUSE_SEC`

**説明**: 各 API リクエスト後の待機時間（秒）。

**デフォルト値**: `0.25`（250ミリ秒）

**用途**: API リクエスト間隔を調整してレート制限を回避

**例**:
```bash
# 500ミリ秒待機（より慎重）
GITHUB_REQUEST_PAUSE_SEC=0.5

# 待機なし（高速だがレート制限のリスク増）
GITHUB_REQUEST_PAUSE_SEC=0
```

**推奨値**:
- **通常**: `0.25`
- **レート制限に頻繁に達する場合**: `0.5`～`1.0`
- **小規模データセット**: `0`

---

### `GITHUB_RATE_THRESHOLD`

**説明**: レート制限の残り回数がこの値を下回った場合、リセット時刻まで待機します。

**デフォルト値**: `50`

**例**:
```bash
# 残り 100 リクエストで待機（より慎重）
GITHUB_RATE_THRESHOLD=100

# 残り 10 リクエストまで使い切る（積極的）
GITHUB_RATE_THRESHOLD=10
```

**推奨値**: `50`～`100`

---

### `GITHUB_RATE_RESET_PADDING_SEC`

**説明**: レート制限リセット時刻に追加する余裕時間（秒）。

**デフォルト値**: `5`

**用途**: リセット時刻直後のリクエスト失敗を回避

**例**:
```bash
# リセット後 10 秒待機（より安全）
GITHUB_RATE_RESET_PADDING_SEC=10
```

**推奨値**: `5`～`10`

---

## 出力設定

### `OUTPUT_DIR`

**説明**: CSV ファイルなどのデータファイル出力ディレクトリ。

**デフォルト値**: `output/files`

**例**:
```bash
OUTPUT_DIR=data/exports
```

---

### `OUTPUT_VIZ_DIR`

**説明**: 可視化ファイル（PNG グラフ）の出力ディレクトリ。

**デフォルト値**: `output/viz`

**例**:
```bash
OUTPUT_VIZ_DIR=output/visualizations
```

---

## 可視化設定

### `PLOT_LABEL_LANGUAGE`

**説明**: グラフのラベル言語。

**デフォルト値**: `en`（英語）

**利用可能な値**:
- `en` - English
- `ja` - 日本語

**例**:
```bash
# 日本語でグラフラベルを表示
PLOT_LABEL_LANGUAGE=ja
```

**影響範囲**:
- グラフタイトル
- 軸ラベル
- 凡例

---

## 設定例

### 例1: 最小構成（必須項目のみ）

```bash
# 必須
GITHUB_TOKEN=github_pat_XXXXXXXXXXXXXXXXXXXXX
GITHUB_ORG=your-company
```

### 例2: 基本的な分析設定

```bash
# 必須
GITHUB_TOKEN=github_pat_XXXXXXXXXXXXXXXXXXXXX
GITHUB_ORG=your-company

# AI設定
AI_T0=2024-06-01
AI_LOOKBACK_DAYS=180

# エージェント分類
GITHUB_AGENT_USERS=github-copilot,coderabbit-ai

# 対象リポジトリ
GITHUB_TARGET_REPOS=your-company/backend,your-company/frontend,your-company/mobile

# ページネーション
GITHUB_MAX_PR_PAGES=100

# 可視化
PLOT_LABEL_LANGUAGE=ja
```

### 例3: 大規模 Organization 向け設定

```bash
# 必須
GITHUB_TOKEN=github_pat_XXXXXXXXXXXXXXXXXXXXX
GITHUB_ORG=large-company

# AI設定
AI_T0=2023-01-01
AI_LOOKBACK_DAYS=730  # 2年間

# ページネーション（大量データ対応）
GITHUB_MAX_REPO_PAGES=5
GITHUB_MAX_PR_PAGES=200
GITHUB_MAX_REVIEW_PAGES=20
GITHUB_MAX_COMMENT_PAGES=20
GITHUB_MAX_COMMIT_PAGES=100

# レート制限対策（慎重）
GITHUB_REQUEST_PAUSE_SEC=0.5
GITHUB_RATE_THRESHOLD=100
GITHUB_RATE_RESET_PADDING_SEC=10
```

### 例4: テスト・開発環境向け設定

```bash
# 必須
GITHUB_TOKEN=github_pat_XXXXXXXXXXXXXXXXXXXXX
GITHUB_ORG=test-org

# データ取得を最小限に
AI_LOOKBACK_DAYS=30
GITHUB_REPO_LIMIT=2
GITHUB_MAX_PR_PAGES=10

# 高速実行
GITHUB_REQUEST_PAUSE_SEC=0
```

### 例5: GitHub Enterprise Server 向け設定

```bash
# 必須
GITHUB_TOKEN=github_pat_XXXXXXXXXXXXXXXXXXXXX
GITHUB_ORG=enterprise-org

# Enterprise Server 設定
GITHUB_API_URL=https://github.example.com/api/v3
GITHUB_USER_AGENT=company-analytics/1.0

# その他は通常通り
AI_T0=2024-01-01
AI_LOOKBACK_DAYS=180
GITHUB_MAX_PR_PAGES=100
```

---

## トラブルシューティング

### レート制限に頻繁に達する

**解決策**:
1. `GITHUB_REQUEST_PAUSE_SEC` を増やす（例: `0.5`）
2. `GITHUB_RATE_THRESHOLD` を増やす（例: `100`）
3. `AI_LOOKBACK_DAYS` を減らす
4. `GITHUB_MAX_PR_PAGES` を減らす

### データが欠落している

**チェック項目**:
1. `GITHUB_MAX_PR_PAGES` が十分か確認
   - リポジトリの総 PR 数を確認: `curl -H "Authorization: Bearer $GITHUB_TOKEN" https://api.github.com/repos/{org}/{repo}/pulls?state=all&per_page=1`
   - 必要なページ数 = 総PR数 ÷ 100（切り上げ）
2. `AI_LOOKBACK_DAYS` が適切か確認
3. `GITHUB_TARGET_REPOS` で除外していないか確認

### 実行時間が長すぎる

**解決策**:
1. `AI_LOOKBACK_DAYS` を減らす
2. `GITHUB_TARGET_REPOS` で対象を絞る
3. `GITHUB_REPO_LIMIT` でテスト実行
4. `GITHUB_REQUEST_PAUSE_SEC` を減らす（レート制限に注意）

### エージェント分類が機能しない

**チェック項目**:
1. `GITHUB_AGENT_USERS` のユーザー名が正確か確認
2. カンマの前後にスペースが入っていないか確認
3. ユーザー名の大文字小文字が一致しているか確認

---

## 参考資料

- [GitHub REST API ドキュメント](https://docs.github.com/en/rest)
- [GitHub API レート制限](https://docs.github.com/en/rest/overview/resources-in-the-rest-api#rate-limiting)
- [Personal Access Token 作成方法](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token)
