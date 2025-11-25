# tests/test_app.py
import jwt
from app import verify_token, SECRET_KEY

def test_verify_token_valid():
    payload = {"username": "alice"}
    token = jwt.encode(payload, SECRET_KEY, algorithm="HS256")
    # your verify_token expects "Bearer <token>"
    username = verify_token(f"Bearer {token}")
    assert username == "alice"

def test_verify_token_invalid():
    username = verify_token("Bearer not-a-real-token")
    assert username is None