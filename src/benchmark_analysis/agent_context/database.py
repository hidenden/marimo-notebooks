"""データベースについてAIへ渡す情報を組み立てる。"""


def get_database_context() -> dict[str, object]:
    """データベースの概要をJSON化可能な辞書として返す。

    現時点ではライブラリ実装例として固定の仮情報を返す。
    今後、実際のスキーマ情報などを安全に取得する処理へ置き換える。
    認証情報や接続文字列は戻り値に含めない。
    """
    return {
        "database_type": "PostgreSQL",
        "description": "ベンチマーク結果を格納するデータベース (仮情報)",
        "tables": [
            {
                "name": "benchmark_results",
                "description": "ベンチマーク実行結果 (仮テーブル)",
                "columns": [
                    {"name": "executed_at", "type": "timestamp"},
                    {"name": "score", "type": "numeric"},
                ],
            }
        ],
        "notes": [
            "現在は例示用の固定情報です。",
            "データベースは参照専用として扱ってください。",
        ],
    }


def hello_sample() -> str:
    """サンプル関数。"""
    return "Hello, sample!"
