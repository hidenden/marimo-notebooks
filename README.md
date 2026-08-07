# marimo-notebooks

ベンチマークデータの探索・分析・可視化を、[marimo](https://marimo.io/) Notebook で行うためのリポジトリです。主な利用環境は踏み台サーバー上のDockerコンテナです。Notebookに加えて、データアクセスや前処理を共通化するPythonパッケージ、設定例、コンテナ管理スクリプトを管理します。

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
| `docs/` | プロジェクト文書 |

Notebook の配置ルールについては、[`notebooks/samples/README.md`](notebooks/samples/README.md) と [`notebooks/users/README.md`](notebooks/users/README.md) も参照してください。

## 踏み台サーバーでの利用（推奨）

通常のNotebook編集は、踏み台サーバー上でDockerコンテナとしてmarimoを起動して行います。利用者のPCからVS Code Remoteで踏み台サーバーへ接続し、踏み台サーバー上で動作するVS Code Serverからリポジトリとコンテナを操作します。

Dockerイメージ内のmarimoはトークン認証を無効にして起動するため、踏み台サーバーのポートを外部へ直接公開しません。ブラウザーからの接続には、VS Code Remoteのポート転送機能を使用します。

コンテナはホスト利用者と同じUID/GIDで動作し、Notebook、uv仮想環境、marimo設定、キャッシュなどの書き込みは、cloneしたリポジトリの `/workspace` マウント内で完結します。操作スクリプトは一般ユーザーとして起動し、Docker操作だけを内部でsudo実行します。

設定ファイルの作成、コンテナの起動・停止、VS Code Remoteでの接続、ポート転送、ログ確認などの手順は [`scripts/server/README.md`](scripts/server/README.md) を参照してください。

## marimo pair での Agent 接続

VS Code Remoteで踏み台サーバーへ接続した状態で、リモート側のGitHub Copilot Agentからmarimo-pair skillを実行します。`<MARIMO_HOST_PORT>` は `.marimo-user.env` に設定した利用者固有のポート、Notebook名は対象ファイルに置き換えてください。

```text
/marimo-pair http://localhost:<MARIMO_HOST_PORT> の既存セッションで
<ノートブックファイル名> を pair してください。
新しい marimo サーバーは起動しないでください。
sandbox 内から接続できない場合は、接続スクリプトを sandbox 外で実行してください。
```

Agentとmarimoコンテナの通信は踏み台サーバー内で完結するため、Agent接続用のポート転送は不要です。クライアントPCのブラウザーでNotebookを開く場合だけ、VS Codeのポートビューからリモートの `<MARIMO_HOST_PORT>` を転送し、ローカル側にも同じ番号を指定します。ブラウザーのURLは `http://localhost:<MARIMO_HOST_PORT>` です。

marimo-pairは内部でBashスクリプトを実行します。WindowsクライアントにはBash環境が標準で用意されていないため、Copilot Agentも踏み台サーバー側で実行するこの構成を推奨します。

## 設定・認証情報の扱い

- 実際の DB パスワードや利用者固有の設定は Git に登録しないでください。
- `.marimo-user.env` とリポジトリ直下の `db.env` は利用者ごとに作成します。DB設定値には管理者から案内された共通の参照専用ユーザーを使用します。
- 共有の生データ領域は、サーバー用スクリプトによりコンテナへ読み取り専用でマウントされます。

## ローカル環境でのライブラリ開発

ローカル環境は、`src/benchmark_analysis/` の共通ライブラリ開発、単体テスト、Lint、型チェックを行うための開発環境です。通常のNotebook編集には踏み台サーバー上のDocker環境を使用してください。

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

### Notebook編集の代替手段（非推奨）

踏み台サーバーを利用できない場合に限り、ローカルでも既存Notebookを起動できます。ただし、共有データ、DB接続、Dockerイメージとの環境差が生じるため、通常の編集手段としては推奨しません。

```bash
uv run marimo edit notebooks/<対象のNotebook>.py
```

ローカルで新規作成する場合も、用途に応じて `notebooks/templates/` または `notebooks/users/` 配下に配置し、最終的な動作は踏み台サーバー上のDocker環境で確認してください。

### 品質チェック

```bash
uv run pytest
uv run ruff check .
uv run ruff format --check .
uv run pyright
```
