# 使用する共通Dockerイメージ。
# latestは使わず、検証済みバージョンを明示する。
MARIMO_IMAGE="marimo-image:0.1.0"

# 利用者固有のコンテナ名。
MARIMO_CONTAINER_NAME="marimo-jsl-miwa"

# 管理者から割り当てられた利用者固有のポート。
# marimo-pairの接続先と、VS Codeで転送するローカル側にも同じ番号を使う。
MARIMO_HOST_PORT="12718"

# コンテナは踏み台のlocalhostにのみ公開する。
MARIMO_HOST_ADDRESS="127.0.0.1"

# marimoコンテナ内の待受ポート。
MARIMO_CONTAINER_PORT="2718"

# Notebookリポジトリのclone先。通常は自分のHOME配下にcloneする。
MARIMO_WORKSPACE="${HOME}/marimo-notebooks"

# 別チームが管理する生データのトップディレクトリ。
MARIMO_RAW_DATA_DIR="/srv/benchmark/raw-data"

# コンテナ内のマウント先。
MARIMO_WORKDIR="/workspace"
MARIMO_RAW_DATA_MOUNT="/data/raw"

# 現在の環境で必要な場合に指定する。
MARIMO_DNS_SERVER="172.20.1.10"
