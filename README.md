# marimo-notebooks

ベンチマークデータの探索・分析・可視化を、[marimo](https://marimo.io/) Notebook で行うためのリポジトリです。Notebook に加えて、データアクセスや前処理を共通化する Python パッケージ、設定例、踏み台サーバー上で marimo を起動するスクリプトを管理します。

## リポジトリ構成

| パス | 内容 |
| --- | --- |
| `notebooks/samples/` | 参照用のサンプル Notebook |
| `notebooks/templates/` | 新しい Notebook のひな型 |
| `notebooks/shared/` | 複数利用者で共有する Notebook |
| `notebooks/users/` | 利用者ごとの Notebook |
| `src/benchmark_analysis/` | データアクセス、前処理、分析、可視化の共通 Python パッケージ |
| `tests/` | 共通パッケージなどのテスト |
| `config/` | 利用者設定・DB 接続設定のサンプル |
| `scripts/server/` | 踏み台サーバー上の marimo コンテナ管理スクリプト |
| `scripts/client/` | クライアント側スクリプト用ディレクトリ |
| `docs/` | プロジェクト文書 |

Notebook の配置ルールについては、[`notebooks/samples/README.md`](notebooks/samples/README.md) と [`notebooks/users/README.md`](notebooks/users/README.md) も参照してください。

## ローカル開発環境

### 前提

- Python 3.12
- [uv](https://docs.astral.sh/uv/)
- Git

### セットアップ

リポジトリのルートで依存関係を同期します。通常の依存関係に加えて、テスト・Lint・型チェック用の開発依存関係も導入されます。

```bash
uv sync
```

外部の PostgreSQL や共有データ領域を使う結合テストも実行する場合は、`integration` グループを追加します。

```bash
uv sync --group integration
```

### Notebook の起動

既存の Notebook を編集する場合は次のように起動します。

```bash
uv run marimo edit notebooks/<対象のNotebook>.py
```

新規作成時は、用途に応じて `notebooks/templates/` または `notebooks/users/` 配下に配置してください。

### 品質チェック

```bash
uv run pytest
uv run ruff check .
uv run ruff format --check .
uv run pyright
```

## 踏み台サーバーでの利用

踏み台サーバーでは Docker コンテナとして marimo を起動し、サーバーの localhost にだけポートを公開します。利用者の PC からは SSH トンネル経由で接続します。

Dockerイメージ内のmarimoはトークン認証を無効にして起動するため、踏み台サーバーのポートを外部へ直接公開せず、必ずSSHトンネル経由で利用します。

コンテナはホスト利用者と同じUID/GIDで動作し、Notebook、uv仮想環境、marimo設定、キャッシュなどの書き込みは、cloneしたリポジトリの `/workspace` マウント内で完結します。操作スクリプトは一般ユーザーとして起動し、Docker操作だけを内部でsudo実行します。

設定ファイルの作成、コンテナの起動・停止、SSH トンネル、ログ確認などの手順は [`scripts/server/README.md`](scripts/server/README.md) を参照してください。

## marimo pair での Agent 接続

marimo サーバーを起動し、必要に応じて SSH トンネルを確立したあと、Agent に次のように指示します。ポート番号と Notebook 名は利用環境に合わせて変更してください。

```text
/marimo-pair http://localhost:2718 の既存セッションで
<ノートブックファイル名> を pair してください。
新しい marimo サーバーは起動しないでください。
sandbox 内から接続できない場合は、接続スクリプトを sandbox 外で実行してください。
```

## 設定・認証情報の扱い

- 実際の DB パスワードや利用者固有の設定は Git に登録しないでください。
- `.marimo-user.env` と `~/.config/marimo-notebooks/db.env` は利用者ごとに作成します。DB設定値には管理者から案内された共通の参照専用ユーザーを使用します。
- 共有の生データ領域は、サーバー用スクリプトによりコンテナへ読み取り専用でマウントされます。
