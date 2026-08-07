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

    # プロジェクト内モジュール
    # import gamedata as g


@app.cell
def intro():
    mo.md("""
    # 🐧 marimoで始めるデータ分析

    このノートでは、南極で観測された **Palmer Penguins** データを使って、
    データの読み込み・絞り込み・集計・可視化を体験します。

    marimoでは、UIを操作したり変数を書き換えたりすると、
    その値に依存するセルが自動的に再実行されます。

    データ: [palmerpenguins](https://allisonhorst.github.io/palmerpenguins/)
    ライセンス: CC0
    """)
    return


@app.cell
def load_data():
    penguins_url = "https://raw.githubusercontent.com/allisonhorst/palmerpenguins/main/inst/extdata/penguins.csv"
    penguins = pl.read_csv(penguins_url, null_values="NA")
    return (penguins,)


@app.cell
def preview_data(penguins):
    mo.vstack(
        [
            mo.md(
                f"""
                ## 1. オンラインのCSVを読み込む

                `pl.read_csv(URL)` で、Web上のCSVを直接読み込めます。
                このデータは **{penguins.height}行 × {penguins.width}列** です。
                """
            ),
            penguins.head(10),
        ]
    )
    return


@app.cell
def controls(penguins):
    species_filter = mo.ui.dropdown(
        options=["すべて", *penguins["species"].unique().sort().to_list()],
        value="すべて",
        label="ペンギンの種類",
    )
    island_filter = mo.ui.dropdown(
        options=["すべて", *penguins["island"].unique().sort().to_list()],
        value="すべて",
        label="島",
    )
    min_mass = mo.ui.slider(
        start=2500,
        stop=6000,
        step=250,
        value=3000,
        show_value=True,
        label="最小体重 (g)",
    )
    mo.vstack(
        [
            mo.md("## 2. UIで表示対象を選ぶ"),
            mo.hstack(
                [species_filter, island_filter, min_mass],
                justify="start",
                gap=2,
            ),
        ]
    )
    return island_filter, min_mass, species_filter


@app.cell
def filter_data(island_filter, min_mass, penguins, species_filter):
    _species_condition = (
        pl.lit(True)
        if species_filter.value == "すべて"
        else pl.col("species") == species_filter.value
    )
    _island_condition = (
        pl.lit(True)
        if island_filter.value == "すべて"
        else pl.col("island") == island_filter.value
    )
    filtered_penguins = penguins.filter(
        _species_condition,
        _island_condition,
        pl.col("body_mass_g").is_not_null(),
        pl.col("body_mass_g") >= min_mass.value,
        pl.col("bill_length_mm").is_not_null(),
        pl.col("bill_depth_mm").is_not_null(),
    )
    return (filtered_penguins,)


@app.cell
def selection_status(
    filtered_penguins,
    island_filter,
    min_mass,
    species_filter,
):
    selected_count = filtered_penguins.height
    selected_avg_mass = filtered_penguins["body_mass_g"].mean()
    _selected_label = species_filter.value
    _selected_island = island_filter.value
    _selected_avg_text = (
        f"{selected_avg_mass:,.0f} g" if selected_avg_mass is not None else "該当データなし"
    )
    mo.md(
        f"""
        ### 選択結果

        - **種類:** {_selected_label}
        - **島:** {_selected_island}
        - **体重:** {min_mass.value:,} g以上
        - **個体数:** {selected_count}羽
        - **平均体重:** {_selected_avg_text}
        """
    )
    return


@app.cell
def summarize_data(filtered_penguins):
    species_summary = (
        filtered_penguins.group_by("species")
        .agg(
            pl.len().alias("count"),
            pl.col("body_mass_g").mean().round(0).alias("avg_body_mass_g"),
            pl.col("flipper_length_mm").mean().round(1).alias("avg_flipper_length_mm"),
        )
        .sort("species")
    )
    mo.vstack([mo.md("## 3. 種類ごとに集計する"), species_summary])
    return


@app.cell
def plot_data(filtered_penguins):
    penguin_chart = (
        alt.Chart(filtered_penguins)
        .mark_circle(size=90, opacity=0.7)
        .encode(
            x=alt.X("bill_length_mm:Q", title="くちばしの長さ (mm)", scale=alt.Scale(zero=False)),
            y=alt.Y("bill_depth_mm:Q", title="くちばしの深さ (mm)", scale=alt.Scale(zero=False)),
            color=alt.Color("species:N", title="種類"),
            tooltip=[
                alt.Tooltip("species:N", title="種類"),
                alt.Tooltip("island:N", title="島"),
                alt.Tooltip("bill_length_mm:Q", title="くちばしの長さ"),
                alt.Tooltip("bill_depth_mm:Q", title="くちばしの深さ"),
                alt.Tooltip("body_mass_g:Q", title="体重 (g)"),
            ],
        )
        .properties(width=650, height=380, title="くちばしの形を種類別に比較")
        .interactive()
    )
    mo.vstack([mo.md("## 4. Altairで可視化する"), penguin_chart])
    return


@app.cell
def exercise():
    mo.md("""
    ## 5. 試してみよう

    - ペンギンの種類、島、最小体重を変更し、表とグラフが同時に変わることを確認する
    - 散布図の横軸を `flipper_length_mm` (翼の長さ) に変えてみる
    - 集計表へ、くちばしの平均的な長さを追加してみる

    marimoではセルの実行順ではなく、**変数の依存関係**に沿って必要なセルが更新されます。
    """)
    return


if __name__ == "__main__":
    app.run()
