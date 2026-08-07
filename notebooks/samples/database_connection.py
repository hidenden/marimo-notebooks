# /// script
# [tool.marimo.display]
# theme = "system"
# ///

import marimo

__generated_with = "0.23.16"
app = marimo.App(width="medium")

with app.setup:
    import os

    import marimo as mo
    import psycopg
    from psycopg.rows import dict_row


@app.cell
def intro():
    mo.md("""
    # PostgreSQL 接続サンプル

    `marimo_run.sh` は `docker run --env-file db.env` を使い、DB接続情報を
    **コンテナの環境変数**として注入します。Notebookから呼び出す接続ライブラリは、
    `db.env` を直接読む必要はありません。

    このサンプルでは次の流れで接続します。

    1. `os.environ` から `BENCHMARK_DB_*` を取得する
    2. `psycopg.connect()` のキーワード引数へ変換する
    3. 接続を `with` ブロック内だけで使用し、処理後に必ず閉じる

    > パスワードはNotebookの出力やログへ表示しないでください。
    """)
    return


@app.cell
def load_connection_settings():
    required_environment_variables = (
        "BENCHMARK_DB_HOST",
        "BENCHMARK_DB_PORT",
        "BENCHMARK_DB_NAME",
        "BENCHMARK_DB_USER",
        "BENCHMARK_DB_PASSWORD",
    )
    missing_environment_variables = [
        _name for _name in required_environment_variables if not os.getenv(_name)
    ]

    db_connection_kwargs = {
        "host": os.getenv("BENCHMARK_DB_HOST", ""),
        "port": int(os.getenv("BENCHMARK_DB_PORT", "5432")),
        "dbname": os.getenv("BENCHMARK_DB_NAME", ""),
        "user": os.getenv("BENCHMARK_DB_USER", ""),
        "password": os.getenv("BENCHMARK_DB_PASSWORD", ""),
        "sslmode": os.getenv("BENCHMARK_DB_SSLMODE", "prefer"),
        "connect_timeout": int(os.getenv("BENCHMARK_DB_CONNECT_TIMEOUT", "10")),
        "application_name": os.getenv("BENCHMARK_DB_APPLICATION_NAME", "marimo-analysis"),
    }
    return db_connection_kwargs, missing_environment_variables


@app.cell
def show_connection_settings(db_connection_kwargs, missing_environment_variables):
    _safe_settings = {
        _key: ("********" if _key == "password" else _value)
        for _key, _value in db_connection_kwargs.items()
    }
    _status = (
        mo.callout(
            "不足している環境変数: " + ", ".join(missing_environment_variables),
            kind="danger",
        )
        if missing_environment_variables
        else mo.callout("必須のDB接続情報が環境変数に設定されています。", kind="success")
    )
    mo.vstack(
        [
            mo.md("## 接続設定の確認"),
            _status,
            mo.md("パスワードをマスクした、`psycopg.connect()` への引数です。"),
            mo.json(_safe_settings),
        ]
    )
    return


@app.cell
def connection_control(missing_environment_variables):
    connect_button = mo.ui.run_button(
        label="PostgreSQLへの接続を確認",
        disabled=bool(missing_environment_variables),
        tooltip="SELECT current_database() などを実行します。",
    )
    mo.vstack([mo.md("## 疎通確認"), connect_button])
    return (connect_button,)


@app.cell
def test_connection(connect_button, db_connection_kwargs):
    mo.stop(
        not connect_button.value,
        mo.md("ボタンを押すまでDB接続は行いません。"),
    )

    try:
        with psycopg.connect(**db_connection_kwargs, row_factory=dict_row) as _connection:
            with _connection.cursor() as _cursor:
                _cursor.execute(
                    """
                    SELECT
                        current_database() AS database_name,
                        current_user AS user_name,
                        inet_server_addr()::text AS server_address,
                        inet_server_port() AS server_port,
                        version() AS postgres_version
                    """
                )
                connection_result = _cursor.fetchone()
    except psycopg.Error as _error:
        connection_output = mo.callout(
            f"DB接続に失敗しました: {type(_error).__name__}: {_error}",
            kind="danger",
        )
    else:
        connection_output = mo.vstack(
            [
                mo.callout("PostgreSQLへ接続できました。", kind="success"),
                mo.json(connection_result),
            ]
        )

    connection_output
    return


@app.cell
def usage_notes():
    mo.md("""
    ## 共通ライブラリから使う場合

    共通DB接続ライブラリでも同じ考え方です。設定を引数で受け取るAPIなら、
    このNotebookの `db_connection_kwargs` を渡します。

    ```python
    with psycopg.connect(**db_connection_kwargs) as connection:
        ...
    ```

    ライブラリ自身が環境変数を読む設計にする場合も、参照する名前を
    `BENCHMARK_DB_*` に統一してください。テストしやすさを重視するなら、
    「環境変数を引数へ変換する処理」と「接続する処理」を分けるのがおすすめです。

    ローカルでNotebookを直接起動する場合は、Dockerによる環境変数注入がないため、
    起動前のシェルで同じ環境変数を設定する必要があります。
    """)
    return


if __name__ == "__main__":
    app.run()
