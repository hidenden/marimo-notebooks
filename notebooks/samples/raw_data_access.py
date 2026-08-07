# /// script
# [tool.marimo.display]
# theme = "system"
# ///

import marimo

__generated_with = "0.23.16"
app = marimo.App(width="medium")

with app.setup:
    import os
    from datetime import datetime
    from pathlib import Path

    import marimo as mo
    import polars as pl


@app.cell
def raw_data_location():
    raw_data_root = Path(os.environ.get("MARIMO_RAW_DATA_DIR", "/data/raw"))
    return (raw_data_root,)


@app.cell
def intro(raw_data_root):
    mo.md(
        f"""
        # 生データ格納域へのファイルアクセス

        `marimo_run.sh` は、ホスト側の `MARIMO_RAW_DATA_DIR` をコンテナの
        `MARIMO_RAW_DATA_MOUNT` へマウントします。既定のマウント先は `/data/raw` です。

        そのうえで、コンテナ内の環境変数 `MARIMO_RAW_DATA_DIR` には
        **コンテナ内のマウント先**が設定されます。このNotebookから見えている
        生データ格納域のトップは次のパスです。

        ```text
        {raw_data_root}
        ```

        例えば、ホスト上の `/srv/benchmark/raw-data/example.csv` は、既定設定なら
        Notebookから `/data/raw/example.csv` に見えます。ホスト側のパスをNotebookへ
        ハードコードせず、必ず `MARIMO_RAW_DATA_DIR` を起点にしてください。

        生データ格納域は `:ro` オプションで**読み取り専用**マウントされています。
        Notebookから読み取りはできますが、作成・更新・削除はできません。
        """
    )
    return


@app.cell
def check_raw_data_root(raw_data_root):
    if not raw_data_root.exists():
        raw_data_root_status = mo.callout(
            f"生データ格納域が見つかりません: {raw_data_root}。"
            "marimo_run.shで起動したコンテナ内で実行してください。",
            kind="danger",
        )
    elif not raw_data_root.is_dir():
        raw_data_root_status = mo.callout(
            f"生データ格納域がディレクトリではありません: {raw_data_root}",
            kind="danger",
        )
    else:
        raw_data_root_status = mo.callout(
            f"生データ格納域を読み取れます: {raw_data_root}",
            kind="success",
        )
    raw_data_root_status
    return


@app.cell
def list_top_level_entries(raw_data_root):
    def _describe_entry(_path: Path) -> dict[str, object]:
        _stat = _path.stat()
        return {
            "name": _path.name,
            "type": "directory" if _path.is_dir() else "file",
            "size_bytes": None if _path.is_dir() else _stat.st_size,
            "modified_at": datetime.fromtimestamp(_stat.st_mtime).isoformat(timespec="seconds"),
        }

    if raw_data_root.is_dir():
        _entries = sorted(raw_data_root.iterdir(), key=lambda _path: _path.name)
        raw_data_entries = pl.DataFrame([_describe_entry(_path) for _path in _entries])
    else:
        raw_data_entries = pl.DataFrame(
            schema={
                "name": pl.String,
                "type": pl.String,
                "size_bytes": pl.Int64,
                "modified_at": pl.String,
            }
        )
    return (raw_data_entries,)


@app.cell
def show_top_level_entries(raw_data_entries):
    mo.vstack(
        [
            mo.md(
                f"""
                ## トップディレクトリの一覧

                `Path.iterdir()` を使ってトップ直下を一覧にしています。
                現在 **{raw_data_entries.height}件**あります。
                """
            ),
            raw_data_entries,
        ]
    )
    return


@app.cell
def file_selection():
    relative_file_path = mo.ui.text(
        label="生データ格納域のトップからの相対ファイルパス",
        placeholder="例: measurements/benchmark.csv",
        full_width=True,
    )
    preview_button = mo.ui.run_button(label="ファイルを読み込む")
    mo.vstack(
        [
            mo.md("## ファイルの読み込み"),
            relative_file_path,
            preview_button,
        ]
    )
    return preview_button, relative_file_path


@app.cell
def preview_file(preview_button, raw_data_root, relative_file_path):
    mo.stop(
        not preview_button.value,
        mo.md("相対パスを入力し、「ファイルを読み込む」を押してください。"),
    )

    _relative_path = relative_file_path.value.strip()
    mo.stop(not _relative_path, mo.callout("相対パスを入力してください。", kind="warn"))

    _root = raw_data_root.resolve()
    _target = (_root / _relative_path).resolve()
    mo.stop(
        not _target.is_relative_to(_root),
        mo.callout(
            "生データ格納域の外を指すパスは読み込めません。",
            kind="danger",
        ),
    )
    mo.stop(
        not _target.is_file(),
        mo.callout(f"ファイルが見つかりません: {_target}", kind="danger"),
    )

    try:
        if _target.suffix.lower() == ".csv":
            _preview = pl.read_csv(_target, n_rows=100)
        elif _target.suffix.lower() in {".parquet", ".pq"}:
            _preview = pl.scan_parquet(_target).head(100).collect()
        elif _target.suffix.lower() in {".json", ".ndjson", ".jsonl"}:
            _preview = pl.read_ndjson(_target, n_rows=100)
        else:
            _preview = _target.read_text(encoding="utf-8", errors="replace")[:10_000]
    except (OSError, pl.exceptions.PolarsError) as _error:
        file_preview_output = mo.callout(
            f"ファイルの読み込みに失敗しました: {type(_error).__name__}: {_error}",
            kind="danger",
        )
    else:
        file_preview_output = mo.vstack(
            [
                mo.callout(f"読み込みました: {_target}", kind="success"),
                mo.md(
                    "CSV、Parquet、NDJSONは先頭100行、それ以外はUTF-8テキストとして"
                    "先頭10,000文字を表示します。"
                ),
                _preview,
            ]
        )

    file_preview_output
    return


@app.cell
def code_examples(raw_data_root):
    mo.md(
        f"""
        ## Notebookコードでの利用例

        ```python
        import os
        from pathlib import Path
        import polars as pl

        raw_data_root = Path(os.environ["MARIMO_RAW_DATA_DIR"])
        csv_path = raw_data_root / "measurements" / "benchmark.csv"
        data = pl.read_csv(csv_path)
        ```

        現在の環境では `raw_data_root` は `{raw_data_root}` です。ファイルを指定するときは、
        このトップパスに相対パスを `/` 演算子で追加します。

        書き込み結果は、生データ格納域ではなくNotebookワークスペース側へ保存してください。
        """
    )
    return


if __name__ == "__main__":
    app.run()
