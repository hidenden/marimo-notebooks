#!/usr/bin/env bash
# 踏み台サーバー用 marimo 初期セットアップ

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
USER_CONFIG_FILE="${REPOSITORY_DIR}/.marimo-user.env"
DB_ENV_FILE="${REPOSITORY_DIR}/db.env"
IMAGE_REPOSITORY="marimo-image"
FORCE=false
CHECK_ONLY=false
TEMP_FILES=()

# macOSではDocker Desktop/OrbStackのユーザーソケットを使うためsudoを付けない。
if [[ "$(uname -s)" == "Darwin" ]]; then
    IS_MACOS=true
    DOCKER_COMMAND=(docker)
else
    IS_MACOS=false
    DOCKER_COMMAND=(sudo docker)
fi

log() {
    printf '[marimo-setup] %s\n' "$*"
}

die() {
    printf '[marimo-setup] ERROR: %s\n' "$*" >&2
    exit 1
}

cleanup() {
    local file
    set +u
    for file in "${TEMP_FILES[@]}"; do
        [[ ! -e "${file}" ]] || rm -f -- "${file}"
    done
    set -u
}
trap cleanup EXIT

show_usage() {
    cat <<EOF
Usage:
  $(basename "$0") [--force]
  $(basename "$0") --check

Options:
  --force  既存の設定をバックアップして再作成する
  --check  既存の設定を変更せず検証だけ行う
  --help   このヘルプを表示する
EOF
}

parse_arguments() {
    while (($# > 0)); do
        case "$1" in
            --force)
                FORCE=true
                ;;
            --check)
                CHECK_ONLY=true
                ;;
            --help | -h)
                show_usage
                exit 0
                ;;
            *)
                die "不明なオプションです: $1"
                ;;
        esac
        shift
    done

    if [[ "${FORCE}" == true && "${CHECK_ONLY}" == true ]]; then
        die "--force と --check は同時に指定できません"
    fi
}

require_command() {
    command -v "$1" >/dev/null 2>&1 ||
        die "必要なコマンドが見つかりません: $1"
}

check_prerequisites() {
    [[ "${EUID}" -ne 0 ]] ||
        die "このスクリプトはsudoを付けず、一般ユーザーとして実行してください"

    local command
    for command in docker stat sort grep sed mktemp install cp date id uname; do
        require_command "${command}"
    done

    if [[ "${IS_MACOS}" == true ]]; then
        # macOSにはssがないため、ポート確認には標準搭載のlsofを使用する。
        require_command lsof
        stat -f '%Lp' "${REPOSITORY_DIR}" >/dev/null 2>&1 ||
            die "macOSのstatを実行できません"
    else
        require_command sudo
        require_command ss
        stat -c '%a' "${REPOSITORY_DIR}" >/dev/null 2>&1 ||
            die "GNU statが必要です"
    fi

    log "Dockerへのアクセスを確認します"
    "${DOCKER_COMMAND[@]}" info >/dev/null ||
        die "Dockerを実行できません"
}

file_mode() {
    local file="$1"
    if [[ "${IS_MACOS}" == true ]]; then
        # macOSのBSD statでは-fを使用する。
        stat -f '%Lp' "${file}"
    else
        stat -c '%a' "${file}"
    fi
}

file_owner_uid() {
    local file="$1"
    if [[ "${IS_MACOS}" == true ]]; then
        # macOSのBSD statでは-fを使用する。
        stat -f '%u' "${file}"
    else
        stat -c '%u' "${file}"
    fi
}

prompt_value() {
    local prompt="$1"
    local default_value="${2:-}"
    local value

    if [[ -n "${default_value}" ]]; then
        read -r -p "${prompt} [${default_value}]: " value
        printf '%s' "${value:-${default_value}}"
    else
        read -r -p "${prompt}: " value
        printf '%s' "${value}"
    fi
}

prompt_required() {
    local prompt="$1"
    local default_value="${2:-}"
    local value
    while :; do
        value="$(prompt_value "${prompt}" "${default_value}")"
        if [[ -n "${value}" ]]; then
            printf '%s' "${value}"
            return
        fi
        log "値を入力してください" >&2
    done
}

prompt_secret() {
    local prompt="$1"
    local value
    while :; do
        read -r -s -p "${prompt}: " value
        printf '\n' >&2
        if [[ -n "${value}" ]]; then
            printf '%s' "${value}"
            return
        fi
        log "値を入力してください" >&2
    done
}

reject_newline() {
    local name="$1"
    local value="$2"
    [[ "${value}" != *$'\n'* && "${value}" != *$'\r'* ]] ||
        die "${name} に改行は使用できません"
}

latest_local_image() {
    local tag
    tag="$({
        "${DOCKER_COMMAND[@]}" image ls "${IMAGE_REPOSITORY}" \
            --format '{{.Tag}}' 2>/dev/null || true
    } | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1 || true)"

    [[ -z "${tag}" ]] || printf '%s:%s' "${IMAGE_REPOSITORY}" "${tag}"
}

safe_container_name() {
    local name="marimo-${USER:-$(id -un)}"
    name="$(printf '%s' "${name}" | sed -E 's/[^a-zA-Z0-9_.-]+/-/g')"
    printf '%s' "${name}"
}

write_shell_assignment() {
    local file="$1"
    local name="$2"
    local value="$3"
    printf '%s=' "${name}" >>"${file}"
    printf '%q' "${value}" >>"${file}"
    printf '\n' >>"${file}"
}

backup_if_needed() {
    local file="$1"
    if [[ -e "${file}" ]]; then
        local backup="${file}.$(date '+%Y%m%d%H%M%S').$$.bak"
        cp -p -- "${file}" "${backup}"
        log "既存ファイルをバックアップしました: ${backup}"
    fi
}

create_user_config() {
    local detected_image image container_name host_port workspace raw_data dns_server
    detected_image="$(latest_local_image)"

    if [[ -n "${detected_image}" ]]; then
        log "登録済みの最新バージョンを検出しました: ${detected_image}"
        image="$(prompt_required 'Dockerイメージ' "${detected_image}")"
    else
        log "latest以外のバージョン付きmarimo-imageが見つかりませんでした"
        image="$(prompt_required '管理者から指定されたDockerイメージ')"
    fi

    container_name="$(prompt_required '利用者固有のコンテナ名' "$(safe_container_name)")"
    host_port="$(prompt_required '管理者から割り当てられたポート番号')"
    workspace="$(prompt_required 'Notebookリポジトリの絶対パス' "${REPOSITORY_DIR}")"
    raw_data="$(prompt_required '共有生データディレクトリの絶対パス' '/srv/benchmark/raw-data')"
    dns_server="$(prompt_value 'DNSサーバー（不要なら空欄）')"

    local name value
    while IFS='=' read -r name value; do
        reject_newline "${name}" "${value}"
    done <<EOF
MARIMO_IMAGE=${image}
MARIMO_CONTAINER_NAME=${container_name}
MARIMO_HOST_PORT=${host_port}
MARIMO_WORKSPACE=${workspace}
MARIMO_RAW_DATA_DIR=${raw_data}
MARIMO_DNS_SERVER=${dns_server}
EOF

    local temp_file
    temp_file="$(mktemp "${REPOSITORY_DIR}/.marimo-user.env.tmp.XXXXXX")"
    TEMP_FILES+=("${temp_file}")
    chmod 600 "${temp_file}"

    {
        printf '# marimo_setup.sh により生成された利用者設定\n'
        printf '# 秘密情報はdb.envに保存すること\n'
    } >"${temp_file}"
    write_shell_assignment "${temp_file}" MARIMO_IMAGE "${image}"
    write_shell_assignment "${temp_file}" MARIMO_CONTAINER_NAME "${container_name}"
    write_shell_assignment "${temp_file}" MARIMO_HOST_PORT "${host_port}"
    write_shell_assignment "${temp_file}" MARIMO_HOST_ADDRESS "127.0.0.1"
    write_shell_assignment "${temp_file}" MARIMO_CONTAINER_PORT "2718"
    write_shell_assignment "${temp_file}" MARIMO_WORKSPACE "${workspace}"
    write_shell_assignment "${temp_file}" MARIMO_RAW_DATA_DIR "${raw_data}"
    write_shell_assignment "${temp_file}" MARIMO_WORKDIR "/workspace"
    write_shell_assignment "${temp_file}" MARIMO_RAW_DATA_MOUNT "/data/raw"
    write_shell_assignment "${temp_file}" MARIMO_DNS_SERVER "${dns_server}"
    write_shell_assignment "${temp_file}" MARIMO_LOG_LEVEL "info"

    backup_if_needed "${USER_CONFIG_FILE}"
    install -m 600 "${temp_file}" "${USER_CONFIG_FILE}"
    rm -f -- "${temp_file}"
    log "作成しました: ${USER_CONFIG_FILE}"
}

create_db_config() {
    local host port database user password sslmode timeout application_name
    host="$(prompt_required 'PostgreSQLホスト')"
    port="$(prompt_required 'PostgreSQLポート' '5432')"
    database="$(prompt_required 'データベース名')"
    user="$(prompt_required '共通の参照専用DBユーザー')"
    password="$(prompt_secret 'DBパスワード（入力内容は表示されません）')"
    sslmode="$(prompt_required 'SSLモード' 'prefer')"
    timeout="$(prompt_required '接続タイムアウト（秒）' '10')"
    application_name="$(prompt_required 'application_name' 'marimo-analysis')"

    local name value
    while IFS='=' read -r name value; do
        reject_newline "${name}" "${value}"
    done <<EOF
BENCHMARK_DB_HOST=${host}
BENCHMARK_DB_PORT=${port}
BENCHMARK_DB_NAME=${database}
BENCHMARK_DB_USER=${user}
BENCHMARK_DB_PASSWORD=${password}
BENCHMARK_DB_SSLMODE=${sslmode}
BENCHMARK_DB_CONNECT_TIMEOUT=${timeout}
BENCHMARK_DB_APPLICATION_NAME=${application_name}
EOF

    local temp_file
    temp_file="$(mktemp "${REPOSITORY_DIR}/db.env.tmp.XXXXXX")"
    TEMP_FILES+=("${temp_file}")
    chmod 600 "${temp_file}"
    {
        printf 'BENCHMARK_DB_HOST=%s\n' "${host}"
        printf 'BENCHMARK_DB_PORT=%s\n' "${port}"
        printf 'BENCHMARK_DB_NAME=%s\n' "${database}"
        printf 'BENCHMARK_DB_USER=%s\n' "${user}"
        printf 'BENCHMARK_DB_PASSWORD=%s\n' "${password}"
        printf 'BENCHMARK_DB_SSLMODE=%s\n' "${sslmode}"
        printf 'BENCHMARK_DB_CONNECT_TIMEOUT=%s\n' "${timeout}"
        printf 'BENCHMARK_DB_APPLICATION_NAME=%s\n' "${application_name}"
    } >"${temp_file}"

    backup_if_needed "${DB_ENV_FILE}"
    install -m 600 "${temp_file}" "${DB_ENV_FILE}"
    rm -f -- "${temp_file}"
    log "作成しました: ${DB_ENV_FILE}"
}

validate_port() {
    [[ "${MARIMO_HOST_PORT}" =~ ^[0-9]+$ ]] ||
        die "MARIMO_HOST_PORTは数値で指定してください"
    ((MARIMO_HOST_PORT >= 1024 && MARIMO_HOST_PORT <= 65535)) ||
        die "MARIMO_HOST_PORTは1024～65535の範囲で指定してください"

    if port_is_listening "${MARIMO_HOST_PORT}"; then
        local container_port="${MARIMO_CONTAINER_PORT:-2718}"
        if "${DOCKER_COMMAND[@]}" container inspect "${MARIMO_CONTAINER_NAME}" \
            --format '{{.State.Running}}' 2>/dev/null | grep -qx true &&
            "${DOCKER_COMMAND[@]}" port "${MARIMO_CONTAINER_NAME}" "${container_port}/tcp" \
                2>/dev/null | grep -qE ":${MARIMO_HOST_PORT}$"; then
            log "設定済みコンテナがポート${MARIMO_HOST_PORT}を使用中です"
        else
            die "ポート${MARIMO_HOST_PORT}は既に使用されています"
        fi
    fi
}

port_is_listening() {
    local port="$1"
    if [[ "${IS_MACOS}" == true ]]; then
        # macOSにはssがないためlsofでTCPのLISTENソケットを確認する。
        lsof -nP -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null | grep -q .
    else
        ss -H -ltn "sport = :${port}" 2>/dev/null | grep -q .
    fi
}

validate_configuration() {
    [[ -f "${USER_CONFIG_FILE}" ]] || die "設定ファイルがありません: ${USER_CONFIG_FILE}"
    [[ -f "${DB_ENV_FILE}" ]] || die "DB設定ファイルがありません: ${DB_ENV_FILE}"

    # shellcheck disable=SC1090
    source "${USER_CONFIG_FILE}"
    : "${MARIMO_IMAGE:?MARIMO_IMAGEが設定されていません}"
    : "${MARIMO_CONTAINER_NAME:?MARIMO_CONTAINER_NAMEが設定されていません}"
    : "${MARIMO_HOST_PORT:?MARIMO_HOST_PORTが設定されていません}"
    : "${MARIMO_WORKSPACE:?MARIMO_WORKSPACEが設定されていません}"
    : "${MARIMO_RAW_DATA_DIR:?MARIMO_RAW_DATA_DIRが設定されていません}"

    [[ "${MARIMO_HOST_ADDRESS:-127.0.0.1}" == "127.0.0.1" ]] ||
        die "MARIMO_HOST_ADDRESSは127.0.0.1にしてください"
    [[ "${MARIMO_CONTAINER_NAME}" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]+$ ]] ||
        die "MARIMO_CONTAINER_NAMEの形式が不正です"
    validate_port
    [[ -d "${MARIMO_WORKSPACE}" && -w "${MARIMO_WORKSPACE}" ]] ||
        die "ワークスペースが存在しないか、書き込めません: ${MARIMO_WORKSPACE}"
    [[ -d "${MARIMO_RAW_DATA_DIR}" && -r "${MARIMO_RAW_DATA_DIR}" ]] ||
        die "共有生データディレクトリが存在しないか、読めません: ${MARIMO_RAW_DATA_DIR}"

    local db_mode db_owner
    db_mode="$(file_mode "${DB_ENV_FILE}")"
    db_owner="$(file_owner_uid "${DB_ENV_FILE}")"
    [[ "${db_mode}" == "600" ]] || die "db.envの権限は600にしてください"
    [[ "${db_owner}" == "$(id -u)" ]] || die "db.envは実行ユーザー所有にしてください"

    local required_key
    for required_key in \
        BENCHMARK_DB_HOST BENCHMARK_DB_PORT BENCHMARK_DB_NAME \
        BENCHMARK_DB_USER BENCHMARK_DB_PASSWORD; do
        grep -qE "^${required_key}=.+$" "${DB_ENV_FILE}" ||
            die "db.envに${required_key}が設定されていません"
    done

    log "Dockerイメージを確認します: ${MARIMO_IMAGE}"
    "${DOCKER_COMMAND[@]}" image inspect "${MARIMO_IMAGE}" >/dev/null ||
        die "Dockerイメージが見つかりません: ${MARIMO_IMAGE}"

    if "${DOCKER_COMMAND[@]}" container inspect "${MARIMO_CONTAINER_NAME}" >/dev/null 2>&1; then
        log "同名のコンテナが既に存在します: ${MARIMO_CONTAINER_NAME}"
    fi

    if command -v git >/dev/null 2>&1; then
        git -C "${REPOSITORY_DIR}" check-ignore -q "${USER_CONFIG_FILE}" ||
            die ".marimo-user.envが.gitignoreの対象ではありません"
        git -C "${REPOSITORY_DIR}" check-ignore -q "${DB_ENV_FILE}" ||
            die "db.envが.gitignoreの対象ではありません"
    fi
}

print_summary() {
    cat <<EOF

セットアップが完了しました。

コンテナ名:
  ${MARIMO_CONTAINER_NAME}

marimo-pair接続先:
  http://localhost:${MARIMO_HOST_PORT}

VS Codeポート転送:
  remote: ${MARIMO_HOST_PORT}
  local:  ${MARIMO_HOST_PORT}

次のコマンド:
  ./scripts/server/marimo_run.sh start
EOF
}

main() {
    parse_arguments "$@"
    check_prerequisites

    if [[ "${CHECK_ONLY}" == true ]]; then
        validate_configuration
        print_summary
        return
    fi

    if [[ ! -e "${USER_CONFIG_FILE}" || "${FORCE}" == true ]]; then
        create_user_config
    else
        log "既存の設定を使用します: ${USER_CONFIG_FILE}"
    fi

    if [[ ! -e "${DB_ENV_FILE}" || "${FORCE}" == true ]]; then
        create_db_config
    else
        log "既存のDB設定を使用します: ${DB_ENV_FILE}"
    fi

    validate_configuration
    print_summary
}

main "$@"
