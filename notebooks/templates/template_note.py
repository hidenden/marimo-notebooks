# /// script
# [tool.marimo.display]
# theme = "system"
# ///

import marimo

__generated_with = "0.23.6"
app = marimo.App(width="medium")

with app.setup:
    # 標準ライブラリ
    from datetime import date, datetime

    # サードパーティライブラリ
    import marimo as mo
    import altair as alt
    import polars as pl
    import polars.selectors as cs
    
    # プロジェクト内モジュール
    # import gamedata as g

@app.cell
def _():
    return

if __name__ == "__main__":
    app.run()
