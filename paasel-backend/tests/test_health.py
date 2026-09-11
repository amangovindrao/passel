"""Health endpoint tests."""


async def test_health_returns_200(client, mock_db):
    response = await client.get("/health")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["database"] == "connected"
    mock_db.execute.assert_awaited_once()
