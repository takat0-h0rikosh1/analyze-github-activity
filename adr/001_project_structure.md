# 001: scripts 配下への配置と責務分離

- 日付: 2025-02-14
- ステータス: Accepted

## コンテキスト
- データ取得から可視化まで複数の処理ステップがあり、単一ファイルではコードの見通しが悪化する。
- 環境変数の管理や GitHub API への接続など、共通処理を複数のスクリプトから利用する必要がある。

## 決定
- すべての R プログラムは `scripts/` 配下に配置する。
- `scripts/` の直下に役割別サブディレクトリを設ける。
  - `scripts/api/`: GitHub API 連携モジュール
  - `scripts/config/`: 環境設定読み込みと共有オブジェクト
  - `scripts/processing/`: 整形・集計ロジック
  - `scripts/pipeline/`: CLI エントリポイント、ワークフロー制御
  - `scripts/viz/`: 可視化、レポート生成
- 出力結果は `output/files/` や `output/viz/` に格納し、`scripts/config/settings.R` でパスを一元管理する。
- モジュール設計では OOP パラダイムを積極的に採用し、環境設定や API クライアントなどはクラス/オブジェクトとして責務をカプセル化する。

## 影響
- 新しいスクリプトを追加する際は、上記いずれかのサブディレクトリを選択することで責務が明確になる。
- 環境変数は `scripts/config/settings.R` の `Config` クラスで集約管理され、他モジュールは `config_instance()` を通じて参照する。
- `output/` 配下のディレクトリを変更したい場合は環境変数 (`OUTPUT_DIR`, `OUTPUT_VIZ_DIR`) を `.env` で上書きできる。
