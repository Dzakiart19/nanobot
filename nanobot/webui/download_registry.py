"""Temporary file download registry for the deliver_file tool."""
from __future__ import annotations

import secrets
import time
from pathlib import Path
from typing import NamedTuple

_TTL_SECONDS = 3600

class _DownloadEntry(NamedTuple):
    path: Path
    filename: str
    content_type: str
    created_at: float


_registry: dict[str, _DownloadEntry] = {}


def register_download(path: Path, filename: str, content_type: str) -> str:
    _purge_expired()
    token = secrets.token_urlsafe(24)
    _registry[token] = _DownloadEntry(
        path=path,
        filename=filename,
        content_type=content_type,
        created_at=time.monotonic(),
    )
    return token


def get_download(token: str) -> _DownloadEntry | None:
    entry = _registry.get(token)
    if entry is None:
        return None
    if time.monotonic() - entry.created_at > _TTL_SECONDS:
        _registry.pop(token, None)
        return None
    return entry


def _purge_expired() -> None:
    now = time.monotonic()
    expired = [k for k, v in _registry.items() if now - v.created_at > _TTL_SECONDS]
    for k in expired:
        _registry.pop(k, None)
