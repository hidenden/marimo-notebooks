# /// script
# [tool.marimo.display]
# theme = "system"
# ///

import marimo

__generated_with = "0.23.16"
app = marimo.App(width="medium")

with app.setup:
    # 標準ライブラリ
    from datetime import date, datetime

    # サードパーティライブラリ
    import marimo as mo
    import altair as alt
    import polars as pl
    import polars.selectors as cs


@app.cell
def _():
    from benchmark_analysis.agent_context import get_database_context, hello_sample

    database_context = get_database_context()
    database_context
    return (hello_sample,)


@app.cell
def _(hello_sample):
    # ライブラリ側に新規関数を実装し､即時反映をしたい場合には Restart Kernelを行う必要がある｡

    x  = hello_sample()
    x
    return


if __name__ == "__main__":
    app.run()
