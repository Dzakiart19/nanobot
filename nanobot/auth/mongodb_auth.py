"""MongoDB-backed user authentication for Dzeck."""

from __future__ import annotations

import datetime
import os
from typing import Any


_COLLECTION = "users"


def _get_db() -> Any:
    import pymongo

    uri = os.environ.get("MONGODB_URI", "")
    db_name = os.environ.get("MONGODB_DATABASE", "dzeckbot")
    if not uri:
        raise RuntimeError("MONGODB_URI environment variable not set")
    client = pymongo.MongoClient(uri, serverSelectionTimeoutMS=5000)
    return client[db_name]


def _hash_password(password: str) -> str:
    import bcrypt

    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def _verify_password(password: str, hashed: str) -> bool:
    import bcrypt

    try:
        return bcrypt.checkpw(password.encode("utf-8"), hashed.encode("utf-8"))
    except Exception:
        return False


def signup_user(name: str, email: str, password: str) -> dict[str, Any]:
    """Create a new user. Returns user dict on success, raises ValueError on failure."""
    email = email.strip().lower()
    name = name.strip()

    if not name:
        raise ValueError("Name is required")
    if not email or "@" not in email:
        raise ValueError("Valid email address is required")
    if not password or len(password) < 6:
        raise ValueError("Password must be at least 6 characters")

    db = _get_db()
    collection = db[_COLLECTION]
    collection.create_index("email", unique=True)

    if collection.find_one({"email": email}):
        raise ValueError("Email already registered")

    hashed = _hash_password(password)
    user: dict[str, Any] = {
        "name": name,
        "email": email,
        "password_hash": hashed,
        "created_at": datetime.datetime.utcnow(),
    }
    collection.insert_one(user)
    return {"email": email, "name": name}


def login_user(email: str, password: str) -> dict[str, Any]:
    """Verify credentials. Returns user dict on success, raises ValueError on failure."""
    email = email.strip().lower()

    if not email or not password:
        raise ValueError("Email and password are required")

    db = _get_db()
    collection = db[_COLLECTION]

    user = collection.find_one({"email": email})
    if not user:
        raise ValueError("Invalid email or password")

    if not _verify_password(password, user.get("password_hash", "")):
        raise ValueError("Invalid email or password")

    return {"email": user["email"], "name": user.get("name", "")}
