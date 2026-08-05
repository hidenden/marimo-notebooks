#!/usr/bin/env bash
#
# 利用者用 marimo コンテナ操作スクリプト
#
# 使用例:
#   ./scripts/server/marimo_run.sh start
#   ./scripts/server/marimo_run.sh stop
#   ./scripts/server/marimo_run.sh status
#   ./scripts/server/marimo_run.sh logs
#   ./scripts/server/marimo_run.sh restart
#
# 前提:
#   - Dockerをsudo経由で実行できる
#   - リポジトリ直下に .marimo-user.env が存在する
#   - DB認証情報は .marimo-db.env からコンテナへ注入する
#

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

USER_CONFIG_FILE="${MARIMO_USER_CONFIG:-${REPOSITORY_DIR}/.marimo-user.env}"
DB_ENV_FILE="${MARIMO_DB_ENV:-${HOME}/.config/marimo/db.env}"

DOCKER_COMMAND=(sudo docker)

log() {
    printf '[marimo] %s\n' "$*"
}

error() {
    printf '[marimo] ERROR: %s\n' "$*" >&2
}

die() {
    error "$*"
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 ||
        die "必要なコマンドが見つかりません: $1"
}

load_user_config() {
    [[ -f "${USER_CONFIG_FILE}" ]] ||
        die "利用者設定ファイルがありません: ${USER_CONFIG_FILE}"

    # shellcheck disable=SC1090
    source "${USER_CONFIG_FILE}"

    : "${MARIMO_IMAGE:?MARIMO_IMAGE が設定されていません}"
    : "${MARIMO_CONTAINER_NAME:?MARIMO_CONTAINER_NAME が設定されていません}"
    : "${MARIMO_HOST_PORT:?MARIMO_HOST_PORT が設定されていません}"
    : "${MARIMO_WORKSPACE:?MARIMO_WORKSPACE が設定されていません}"
    : "${MARIMO_RAW_DATA_DIR:?MARIMO_RAW_DATA_DIR が設定されていません}"

    MARIMO_CONTAINER_PORT="${MARIMO_CONTAINER_PORT:-2718}"
    MARIMO_HOST_ADDRESS="${MARIMO_HOST_ADDRESS:-127.0.0.1}"
    MARIMO_DNS_SERVER="${MARIMO_DNS_SERVER:-}"
    MARIMO_WORKDIR="${MARIMO_WORKDIR:-/workspace}"
    MARIMO_RAW_DATA_MOUNT="${MARIMO_RAW_DATA_MOUNT:-/data/raw}"
    MARIMO_LOG_LEVEL="${MARIMO_LOG_LEVEL:-info}"
}

validate_configuration() {
    [[ "${MARIMO_HOST_PORT}" =~ ^[0-9]+$ ]] ||
        die "MARIMO_HOST_PORT は数値で指定してください"

    ((MARIMO_HOST_PORT >= 1024 && MARIMO_HOST_PORT <= 65535)) ||
        die "MARIMO_HOST_PORT は1024～65535の範囲で指定してください"

    [[ -d "${MARIMO_WORKSPACE}" ]] ||
        die "Notebookワークスペースがありません: ${MARIMO_WORKSPACE}"

    [[ -d "${MARIMO_RAW_DATA_DIR}" ]] ||
        die "生データディレクトリがありません: ${MARIMO_RAW_DATA_DIR}"

    [[ -f "${DB_ENV_FILE}" ]] ||
        die "DB設定ファイルがありません: ${DB_ENV_FILE}"

    # DB認証情報を他利用者から読まれにくくする。
    local mode
    mode="$(stat -c '%a' "${DB_ENV_FILE}")"

    if [[ "${mode}" != "600" ]]; then
        die "DB設定ファイルの権限を600にしてください: chmod 600 ${DB_ENV_FILE}"
    fi
}

container_exists() {
    "${DOCKER_COMMAND[@]}" container inspect \
        "${MARIMO_CONTAINER_NAME}" >/dev/null 2>&1
}

container_running() {
    [[ "$(
        "${DOCKER_COMMAND[@]}" inspect \
            --format '{{.State.Running}}' \
            "${MARIMO_CONTAINER_NAME}" 2>/dev/null || true
    )" == "true" ]]
}

port_is_listening() {
    # ssが利用できることを前提とする。
    ss -H -ltn "sport = :${MARIMO_HOST_PORT}" 2>/dev/null |
        grep -q .
}

print_connection_info() {
    cat <<EOF

marimo is available through an SSH tunnel.

Remote endpoint:
  ${MARIMO_HOST_ADDRESS}:${MARIMO_HOST_PORT}

Example SSH tunnel from the client PC:
  ssh -N -L 2718:${MARIMO_HOST_ADDRESS}:${MARIMO_HOST_PORT} $(whoami)@<jump-host>

Browser URL:
  http://localhost:2718

Copilot Agentへの指示例:
  localhost:2718 で動作している marimo-pair に接続し、
  現在開いているNotebookの状態を確認してください。

EOF
}

start_container() {
    if container_running; then
        log "既に起動しています: ${MARIMO_CONTAINER_NAME}"
        print_connection_info
        return 0
    fi

    if container_exists; then
        log "停止中の既存コンテナを削除します: ${MARIMO_CONTAINER_NAME}"
        "${DOCKER_COMMAND[@]}" rm "${MARIMO_CONTAINER_NAME}" >/dev/null
    fi

    if port_is_listening; then
        die "ポート ${MARIMO_HOST_PORT} は既に使用されています"
    fi

    local -a docker_args=(
        run
        --detach
        --name "${MARIMO_CONTAINER_NAME}"
        --restart unless-stopped

        # localhostだけに公開する。
        # PCからはSSHトンネル経由で接続する。
        --publish
        "${MARIMO_HOST_ADDRESS}:${MARIMO_HOST_PORT}:${MARIMO_CONTAINER_PORT}"

        # 利用者ごとのNotebookワークスペース。
        --volume
        "${MARIMO_WORKSPACE}:${MARIMO_WORKDIR}"

        # 共有の生データ領域。誤更新防止のためread-only。
        --volume
        "${MARIMO_RAW_DATA_DIR}:${MARIMO_RAW_DATA_MOUNT}:ro"

        # DB接続設定を実行時に注入する。
        --env-file
        "${DB_ENV_FILE}"

        --env
        "MARIMO_LOG_LEVEL=${MARIMO_LOG_LEVEL}"

        --workdir
        "${MARIMO_WORKDIR}"

        "${MARIMO_IMAGE}"
    )

    if [[ -n "${MARIMO_DNS_SERVER}" ]]; then
        # イメージ名の前にDockerオプションを挿入する。
        docker_args=(
            "${docker_args[@]:0:${#docker_args[@]}-1}"
            --dns "${MARIMO_DNS_SERVER}"
            "${MARIMO_IMAGE}"
        )
    fi

    log "コンテナを起動します"
    log "  name      : ${MARIMO_CONTAINER_NAME}"
    log "  image     : ${MARIMO_IMAGE}"
    log "  port      : ${MARIMO_HOST_ADDRESS}:${MARIMO_HOST_PORT}"
    log "  workspace : ${MARIMO_WORKSPACE}"
    log "  raw data  : ${MARIMO_RAW_DATA_DIR}"

    "${DOCKER_COMMAND[@]}" "${docker_args[@]}" >/dev/null

    sleep 2

    if ! container_running; then
        error "コンテナの起動に失敗しました"
        "${DOCKER_COMMAND[@]}" logs "${MARIMO_CONTAINER_NAME}" >&2 || true
        exit 1
    fi

    log "起動しました"
    print_connection_info
}

stop_container() {
    if ! container_exists; then
        log "コンテナは存在しません: ${MARIMO_CONTAINER_NAME}"
        return 0
    fi

    if container_running; then
        log "コンテナを停止します: ${MARIMO_CONTAINER_NAME}"
        "${DOCKER_COMMAND[@]}" stop "${MARIMO_CONTAINER_NAME}" >/dev/null
    else
        log "コンテナは既に停止しています: ${MARIMO_CONTAINER_NAME}"
    fi
}

remove_container() {
    if ! container_exists; then
        log "コンテナは存在しません: ${MARIMO_CONTAINER_NAME}"
        return 0
    fi

    if container_running; then
        "${DOCKER_COMMAND[@]}" stop "${MARIMO_CONTAINER_NAME}" >/dev/null
    fi

    log "コンテナを削除します: ${MARIMO_CONTAINER_NAME}"
    "${DOCKER_COMMAND[@]}" rm "${MARIMO_CONTAINER_NAME}" >/dev/null
}

show_status() {
    if ! container_exists; then
        log "状態: 未作成"
        log "コンテナ名: ${MARIMO_CONTAINER_NAME}"
        return 1
    fi

    "${DOCKER_COMMAND[@]}" ps \
        --all \
        --filter "name=^/${MARIMO_CONTAINER_NAME}$" \
        --format \
        'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
}

show_logs() {
    container_exists ||
        die "コンテナが存在しません: ${MARIMO_CONTAINER_NAME}"

    "${DOCKER_COMMAND[@]}" logs \
        --follow \
        --tail 100 \
        "${MARIMO_CONTAINER_NAME}"
}

show_version() {
    log "設定済みイメージ: ${MARIMO_IMAGE}"

    if container_exists; then
        "${DOCKER_COMMAND[@]}" inspect \
            --format 'コンテナイメージID: {{.Image}}' \
            "${MARIMO_CONTAINER_NAME}"
    fi
}

show_usage() {
    cat <<EOF
Usage:
  $(basename "$0") start
  $(basename "$0") stop
  $(basename "$0") restart
  $(basename "$0") status
  $(basename "$0") logs
  $(basename "$0") remove
  $(basename "$0") version

Environment:
  MARIMO_USER_CONFIG  利用者設定ファイル
                      default: ${REPOSITORY_DIR}/.marimo-user.env

  MARIMO_DB_ENV       DB接続設定ファイル
                      default: ${HOME}/.config/marimo/db.env
EOF
}

main() {
    require_command sudo
    require_command docker
    require_command ss
    require_command stat

    load_user_config
    validate_configuration

    local action="${1:-}"

    case "${action}" in
        start)
            start_container
            ;;
        stop)
            stop_container
            ;;
        restart)
            stop_container
            start_container
            ;;
        status)
            show_status
            ;;
        logs)
            show_logs
            ;;
        remove)
            remove_container
            ;;
        version)
            show_version
            ;;
        *)
            show_usage
            exit 2
            ;;
    esac
}

main "$@"
