# marimo サーバーの準備と実行

`scripts/server/marimo_run.sh` は、踏み台サーバー上で利用者ごとの marimo Docker コンテナを起動・停止するためのスクリプトです。コンテナのポートは踏み台サーバーの localhost にだけ公開されるため、利用者の PC からは SSH トンネルを経由して接続します。

## 前提条件

踏み台サーバーに次の環境が必要です。

- Bash
- Docker
- `sudo docker` を実行できる権限
- `ss` と GNU `stat` コマンド
- 管理者から案内された marimo Docker イメージ
- Notebook リポジトリの clone
- 共有生データディレクトリへの読み取り権限
- PostgreSQL を利用する場合は、接続先ネットワークへの到達性と認証情報

以降のコマンドは、特記がない限りリポジトリのルートで実行します。

## 初回準備

### 1. 利用者設定を作成する

設定例をリポジトリ直下の `.marimo-user.env` にコピーします。

```bash
cp config/marimo-user.env.example .marimo-user.env
```

`.marimo-user.env` を開き、少なくとも次の値を利用環境に合わせて変更してください。

| 変数 | 必須 | 説明 |
| --- | --- | --- |
| `MARIMO_IMAGE` | 必須 | 管理者から指定された Docker イメージ。`latest` ではなく検証済みバージョンを指定します。 |
| `MARIMO_CONTAINER_NAME` | 必須 | 他の利用者と重複しないコンテナ名 |
| `MARIMO_HOST_PORT` | 必須 | 踏み台サーバー側の利用者固有ポート（1024～65535） |
| `MARIMO_WORKSPACE` | 必須 | このリポジトリを clone したディレクトリの絶対パス |
| `MARIMO_RAW_DATA_DIR` | 必須 | 共有生データディレクトリの絶対パス |
| `MARIMO_HOST_ADDRESS` | 任意 | 公開アドレス。既定値は安全のため `127.0.0.1` |
| `MARIMO_CONTAINER_PORT` | 任意 | コンテナ内の marimo ポート。既定値は `2718` |
| `MARIMO_WORKDIR` | 任意 | ワークスペースのコンテナ内マウント先。既定値は `/workspace` |
| `MARIMO_RAW_DATA_MOUNT` | 任意 | 生データのコンテナ内マウント先。既定値は `/data/raw` |
| `MARIMO_DNS_SERVER` | 任意 | コンテナで明示的な DNS が必要な場合に指定 |
| `MARIMO_LOG_LEVEL` | 任意 | marimo のログレベル。既定値は `info` |

`MARIMO_CONTAINER_NAME` と `MARIMO_HOST_PORT` は利用者間で重複しない値を管理者に確認してください。`.marimo-user.env` は Git の管理対象外です。

`scripts/server/marimo_setup.sh` には利用者設定の記入例が置かれていますが、現状は設定ファイルを自動生成する処理ではありません。通常は実行せず、上記の `config/marimo-user.env.example` から `.marimo-user.env` を作成してください。

### 2. DB 接続設定を作成する

DB 接続設定はリポジトリ外の `~/.config/marimo/db.env` に配置します。

```bash
mkdir -p ~/.config/marimo
cp config/db.env.example ~/.config/marimo/db.env
chmod 600 ~/.config/marimo/db.env
```

`~/.config/marimo/db.env` を開き、管理者から案内された接続情報を設定してください。特に `BENCHMARK_DB_HOST`、`BENCHMARK_DB_NAME`、`BENCHMARK_DB_USER`、`BENCHMARK_DB_PASSWORD` を確認します。認証情報は Git に登録しないでください。

スクリプトは DB 設定ファイルの権限が厳密に `600` でない場合、処理を中止します。

### 3. パスと Docker を確認する

```bash
test -d "$(pwd)"
test -d /設定した/MARIMO_RAW_DATA_DIR
sudo docker image inspect marimo-poc:0.1.0
```

最後の2つは `.marimo-user.env` に設定したディレクトリとイメージ名に置き換えてください。また、`MARIMO_HOST_PORT` が他の利用者に使われていないことを確認してください。起動時にもスクリプトがポートの使用状況を検査します。

## 起動

```bash
./scripts/server/marimo_run.sh start
```

起動時には次の処理が行われます。

- ワークスペースをコンテナの `MARIMO_WORKDIR` へ読み書き可能でマウント
- 共有生データを `MARIMO_RAW_DATA_MOUNT` へ読み取り専用でマウント
- DB 接続設定を環境変数としてコンテナへ注入
- 指定ポートを `127.0.0.1` に公開
- コンテナの再起動ポリシーを `unless-stopped` に設定

停止済みの同名コンテナがある場合は削除して作り直します。すでに起動中の場合は新しいコンテナを作らず、接続情報を表示します。

## PC から接続する

利用者の PC で SSH トンネルを開始します。次の例の最初の `2718` は PC 側のポート、2つ目は `.marimo-user.env` の `MARIMO_HOST_PORT` です。

```bash
ssh -N -L 2718:127.0.0.1:<MARIMO_HOST_PORT> <ユーザー名>@<踏み台ホスト>
```

トンネルを実行しているターミナルを開いたまま、ブラウザーで次の URL にアクセスします。

```text
http://localhost:2718
```

PC 側の `2718` が使用中の場合は、未使用のポート（例: `12718`）に変更し、ブラウザーでも同じポートを使います。

## 日常の操作

| コマンド | 動作 |
| --- | --- |
| `./scripts/server/marimo_run.sh start` | コンテナを起動 |
| `./scripts/server/marimo_run.sh stop` | コンテナを停止 |
| `./scripts/server/marimo_run.sh restart` | コンテナを停止して作り直し |
| `./scripts/server/marimo_run.sh status` | コンテナの状態、イメージ、ポートを表示 |
| `./scripts/server/marimo_run.sh logs` | 直近100行からログを追跡。終了は `Ctrl+C` |
| `./scripts/server/marimo_run.sh version` | 設定されたイメージ名と既存コンテナのイメージ ID を表示 |
| `./scripts/server/marimo_run.sh remove` | コンテナを停止して削除。Notebook はホスト側に残る |

`stop` と `remove` は異なります。`stop` はコンテナを残し、`remove` はコンテナ自体を削除します。どちらの場合も、Notebook は `MARIMO_WORKSPACE` に保存されているため削除されません。

## 設定ファイルを別の場所に置く場合

既定のパスを使えない場合は、実行時にファイルの絶対パスを指定できます。

```bash
MARIMO_USER_CONFIG=/path/to/user.env \
MARIMO_DB_ENV=/path/to/db.env \
./scripts/server/marimo_run.sh start
```

## トラブルシューティング

- `利用者設定ファイルがありません`: リポジトリ直下に `.marimo-user.env` を作成したか、`MARIMO_USER_CONFIG` のパスを確認します。
- `DB設定ファイルがありません`: `~/.config/marimo/db.env` を作成したか、`MARIMO_DB_ENV` のパスを確認します。
- `DB設定ファイルの権限を600にしてください`: `chmod 600 ~/.config/marimo/db.env` を実行します。
- `ポート ... は既に使用されています`: 管理者に未使用ポートを確認し、`MARIMO_HOST_PORT` を変更します。
- コンテナが起動しない: `./scripts/server/marimo_run.sh logs` と `sudo docker ps -a` で状態を確認します。
- ブラウザーから接続できない: コンテナの `status`、SSH トンネルの接続先ポート、ブラウザーの URL を順に確認します。踏み台サーバーのポートへ直接アクセスする構成ではありません。
