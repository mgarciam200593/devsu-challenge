from src.app import app

def test_api():
    response = app.test_client().post("/DevOps", json={
        "message": "This is a test",
        "to": "Juan Perez",
        "from": "Rita Asturia",
        "timeToLifeSec": 45
    })
    assert response.json["message"] == "Hello Juan Perez your message will be send"