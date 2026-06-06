"""deliver_file tool — package workspace files and offer a download link."""
from __future__ import annotations

import mimetypes
import tempfile
import zipfile
from pathlib import Path
from typing import Any

from dzeck.agent.tools.base import Tool


class DeliverFileTool(Tool):
    """Package a file or directory and give the user a download link."""

    @property
    def name(self) -> str:
        return "deliver_file"

    @property
    def description(self) -> str:
        return (
            "Package a file or directory and deliver it to the user as a downloadable link. "
            "Use this when you've finished creating code, documents, presentations, or any "
            "files the user should download. "
            "Directories are automatically zipped. Single files are delivered as-is. "
            "Returns a markdown download link to include in your response."
        )

    @property
    def parameters(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "path": {
                    "type": "string",
                    "description": (
                        "Absolute or workspace-relative path to the file or directory to deliver."
                    ),
                },
                "filename": {
                    "type": "string",
                    "description": (
                        "Output filename shown to the user (e.g. 'my-project.zip'). "
                        "Inferred from the path when omitted."
                    ),
                },
            },
            "required": ["path"],
        }

    @classmethod
    def create(cls, ctx: Any) -> "DeliverFileTool":
        return cls(workspace=Path(ctx.workspace))

    def __init__(self, workspace: Path | None = None) -> None:
        self._workspace = workspace

    def _resolve(self, path: str) -> Path:
        p = Path(path)
        if p.is_absolute():
            return p
        if self._workspace:
            return (self._workspace / p).resolve()
        return p.resolve()

    async def execute(self, path: str, filename: str = "") -> str:
        from dzeck.webui.download_registry import register_download

        resolved = self._resolve(path)

        if not resolved.exists():
            return f"Error: path does not exist: {path}"

        if resolved.is_file():
            out_name = filename or resolved.name
            content_type, _ = mimetypes.guess_type(out_name)
            if not content_type:
                content_type = "application/octet-stream"
            token = register_download(resolved, out_name, content_type)
        else:
            out_name = filename or f"{resolved.name}.zip"
            if not out_name.endswith(".zip"):
                out_name += ".zip"
            zip_path = _zip_directory(resolved, out_name)
            token = register_download(zip_path, out_name, "application/zip")

        return f"[📦 Download {out_name}](/webui/download/{token})"


def _zip_directory(source: Path, out_name: str) -> Path:
    tmp = tempfile.mktemp(suffix=".zip")
    out = Path(tmp)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
        for item in source.rglob("*"):
            if item.is_file():
                zf.write(item, item.relative_to(source.parent))
    return out
