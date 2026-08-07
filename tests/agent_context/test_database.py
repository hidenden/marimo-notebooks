from benchmark_analysis.agent_context import get_database_context


def test_get_database_context_returns_placeholder_information() -> None:
    context = get_database_context()

    assert context["database_type"] == "PostgreSQL"
    assert context["tables"]
    assert "password" not in context
