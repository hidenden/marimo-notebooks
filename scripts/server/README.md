# marimo サーバーの準備と実行

`scripts/server/marimo_run.sh` は、踏み台サーバー上で利用者ごとの marimo Docker コンテナを起動・停止するためのスクリプトです。利用者はVS Code Remoteで踏み台サーバーへ接続し、リモート側のGitHub Copilot Agentと、VS Codeのポート転送を利用します。

## 前提条件

踏み台サーバーに次の環境が必要です。

- Bash
- Docker
- `sudo docker` を実行できる権限
- `ss` と GNU `stat` コマンド
- 管理者から案内された marimo Docker イメージ
- Notebook リポジトリの clone
- 共有生データディレクトリへの読み取り権限
- PostgreSQL への到達性と、管理者から案内された共通DB設定値

操作スクリプト自体は一般ユーザーとして実行してください。スクリプト内部の `sudo docker` だけがsudoを使用します。

最新のmarimoイメージは `--no-token` で起動するため、marimo自体のトークン認証は無効です。ポートは必ず踏み台サーバーのlocalhostだけに公開し、利用者PCのブラウザーからはVS Code Remoteのポート転送経由で接続してください。

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
| `MARIMO_HOST_PORT` | 必須 | 管理者から割り当てられた利用者固有ポート（1024～65535）。marimo-pairの接続先と、VS Codeで転送するローカル側にも同じ番号を使用 |
| `MARIMO_WORKSPACE` | 必須 | このリポジトリを自分のHOME配下へcloneしたディレクトリの絶対パス。`${HOME}/marimo-notebooks` を推奨 |
| `MARIMO_RAW_DATA_DIR` | 必須 | 共有生データディレクトリの絶対パス |
| `MARIMO_HOST_ADDRESS` | 任意 | 公開アドレス。既定値は安全のため `127.0.0.1` |
| `MARIMO_CONTAINER_PORT` | 任意 | コンテナ内の marimo ポート。既定値は `2718` |
| `MARIMO_WORKDIR` | 任意 | ワークスペースのコンテナ内マウント先。既定値は `/workspace` |
| `MARIMO_RAW_DATA_MOUNT` | 任意 | 生データのコンテナ内マウント先。既定値は `/data/raw` |
| `MARIMO_DNS_SERVER` | 任意 | コンテナで明示的な DNS が必要な場合に指定 |
| `MARIMO_LOG_LEVEL` | 任意 | marimo のログレベル。既定値は `info` |

`MARIMO_CONTAINER_NAME` と `MARIMO_HOST_PORT` は利用者間で重複しない値を管理者に確認してください。`.marimo-user.env` は Git の管理対象外です。

`scripts/server/marimo_setup.sh` には利用者設定の記入例が置かれていますが、現状は設定ファイルを自動生成する処理ではありません。通常は実行せず、上記の `config/marimo-user.env.example` から `.marimo-user.env` を作成してください。

### 2. DB接続設定をリポジトリ直下へ配置する

各利用者は、cloneしたリポジトリの直下に `db.env` を配置します。ファイルは利用者ごとに分かれますが、管理者から案内された同じ参照専用DBユーザーの値を設定します。

```bash
install -m 600 config/db.env.example db.env
${EDITOR:-vi} db.env
```

`BENCHMARK_DB_HOST`、`BENCHMARK_DB_NAME`、`BENCHMARK_DB_USER`、`BENCHMARK_DB_PASSWORD` を実際の共通接続情報へ変更します。`docker run --env-file` では引用符も値の一部になるため、値を `"` で囲まないでください。実際の認証情報はGitへ登録しません。

スクリプトはファイルが実行ユーザー所有かつ `600` でない場合、処理を中止します。スクリプト内部の `sudo docker run --env-file db.env` が設定をコンテナへ渡します。`db.env` は `.gitignore` の対象であり、Gitへ登録しません。

### 3. パスと Docker を確認する

```bash
source .marimo-user.env
test -d "${MARIMO_WORKSPACE}"
test -d "${MARIMO_RAW_DATA_DIR}"
sudo docker image inspect "${MARIMO_IMAGE}"
```

各コマンドが成功することを確認してください。また、`MARIMO_HOST_PORT` が他の利用者に使われていないことを確認してください。起動時にもスクリプトがポートの使用状況を検査します。

## 起動

```bash
./scripts/server/marimo_run.sh start
```

起動時には次の処理が行われます。

- ワークスペースをコンテナの `MARIMO_WORKDIR` へ読み書き可能でマウント
- コンテナをスクリプト実行者と同じ数値UID/GID（補助グループを含む）で実行
- HOME、XDG、uv、TMPDIRの書き込み先を `/workspace/.marimo-runtime` と `/workspace/.venv` に限定
- 実際のコンテナ内ポートとマウント先を `MARIMO_PORT`、`MARIMO_WORKSPACE`、`MARIMO_RAW_DATA_DIR` としてイメージへ通知
- 共有生データを `MARIMO_RAW_DATA_MOUNT` へ読み取り専用でマウント
- DB 接続設定を環境変数としてコンテナへ注入
- 指定ポートを `127.0.0.1` に公開
- コンテナの再起動ポリシーを `unless-stopped` に設定

停止済みの同名コンテナがある場合は削除して作り直します。すでに起動中の場合は新しいコンテナを作らず、接続情報を表示します。

`sudo ./scripts/server/marimo_run.sh start` のようにスクリプト全体をsudoで起動する必要はありません。通常どおり `./scripts/server/marimo_run.sh start` を実行してください。内部で組み立てられる主要なDockerオプションは次の形です。

```text
sudo docker run --user <利用者UID>:<利用者GID> \
  --volume <HOME配下のclone先>:/workspace ...
```

このためNotebook、`.venv`、marimo設定、uvキャッシュはホスト側でも利用者自身の所有となり、root所有のファイルは作られません。共有生データをUnixの補助グループで読める利用者については、そのグループIDも `--group-add` で引き継がれます。

## VS Code Remoteから接続する

利用者PCのVS CodeからRemote SSHで踏み台サーバーへ接続し、このリポジトリを開きます。VS Code Server、ターミナル、GitHub Copilot Agentは踏み台サーバー上で動作します。

リモート側のターミナルでコンテナを起動します。

```text
./scripts/server/marimo_run.sh start
```

### marimo-pairで接続する

リモート側のGitHub Copilot Agentに次のように指示します。`<MARIMO_HOST_PORT>` は `.marimo-user.env` の値へ置き換えてください。

```text
/marimo-pair http://localhost:<MARIMO_HOST_PORT> の既存セッションで
<ノートブックファイル名> を pair してください。
新しい marimo サーバーは起動しないでください。
sandbox 内から接続できない場合は、接続スクリプトを sandbox 外で実行してください。
```

Agentとmarimoコンテナはどちらも踏み台サーバー上にあるため、この接続にポート転送は不要です。marimo-pairは内部でBashスクリプトを実行するため、Windowsクライアント上ではなく、Bashを利用できる踏み台サーバー上のAgentから実行する構成を推奨します。

### クライアントPCのブラウザーで開く

VS Codeのポートビューで「ポートの転送」を実行し、リモートポートに `.marimo-user.env` の `MARIMO_HOST_PORT` を指定します。ローカル側にも同じポート番号を指定してください。

たとえば `MARIMO_HOST_PORT=12718` の場合、リモートポートとローカルポートをどちらも `12718` とし、クライアントPCのブラウザーで次のURLを開きます。

```text
http://localhost:12718
```

ローカル側で割当ポートが使用中の場合、別番号へ安易に変えるとAgentとブラウザーの接続先が分かりにくくなります。競合プロセスを停止するか、管理者に別の利用者固有ポートを確認して `MARIMO_HOST_PORT` も変更してください。

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

## DB設定を別の場所に置く場合

既定のリポジトリ直下以外へ配置する場合は、`MARIMO_DB_ENV` に絶対パスを指定できます。指定ファイルは実行ユーザー所有で、権限を `600` にしてください。

```bash
MARIMO_USER_CONFIG=/path/to/user.env \
MARIMO_DB_ENV=/path/to/db.env \
./scripts/server/marimo_run.sh start
```

## トラブルシューティング

- `利用者設定ファイルがありません`: リポジトリ直下に `.marimo-user.env` を作成したか、`MARIMO_USER_CONFIG` のパスを確認します。
- `DB設定ファイルがありません`: リポジトリ直下に `db.env` を配置したか確認します。
- DB設定ファイルの所有者・権限エラー: `chmod 600 db.env` を実行し、自分が所有者であることを確認します。
- `ポート ... は既に使用されています`: 管理者に未使用ポートを確認し、`MARIMO_HOST_PORT` を変更します。
- コンテナが起動しない: `./scripts/server/marimo_run.sh logs` と `sudo docker ps -a` で状態を確認します。
- Notebookや`.venv`がroot所有になる: スクリプト全体をsudo化した独自ラッパーを使っていないか確認し、コンテナの `Config.User` が自分の `id -u:id -g` になっているか確認します。
- marimo-pairから接続できない: Copilot Agentがリモート側で動作していることと、接続先が `http://localhost:<MARIMO_HOST_PORT>` であることを確認します。
- ブラウザーから接続できない: コンテナの `status`、VS Codeのポートビューに表示されたリモート／ローカルポート、ブラウザーのURLを順に確認します。両方のポート番号は `MARIMO_HOST_PORT` と同じにします。
