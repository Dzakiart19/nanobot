"""HTTP API handler extracted from WebSocketChannel.

Handles all non-WebSocket HTTP routes: bootstrap, sessions, settings,
media, commands, sidebar state, static file serving, and token management.

Also houses shared HTTP utility functions used by both this module and
``websocket.py`` to avoid circular imports.
"""

from __future__ import annotations

import asyncio
import json
import mimetypes
import re
from collections.abc import Callable
from pathlib import Path
from typing import TYPE_CHECKING, Any

from loguru import logger
from websockets.http11 import Request as WsRequest
from websockets.http11 import Response

from nanobot.command.builtin import builtin_command_palette
from nanobot.utils.subagent_channel_display import scrub_subagent_messages_for_channel
from nanobot.webui.gateway_tokens import GatewayTokenStore, token_response_payload
from nanobot.webui.http_utils import (
    case_insensitive_header as _case_insensitive_header,
)
from nanobot.webui.http_utils import (
    host_for_url as _host_for_url,
)
from nanobot.webui.http_utils import (
    http_error as _http_error,
)
from nanobot.webui.http_utils import (
    http_json_response as _http_json_response,
)
from nanobot.webui.http_utils import (
    http_response as _http_response,
)
from nanobot.webui.http_utils import (
    is_localhost as _is_localhost,
)
from nanobot.webui.http_utils import (
    issue_route_secret_matches as _issue_route_secret_matches,
)
from nanobot.webui.http_utils import (
    normalize_config_path as _normalize_config_path,
)
from nanobot.webui.http_utils import (
    parse_query as _parse_query,
)
from nanobot.webui.http_utils import (
    parse_request_path as _parse_request_path,
)
from nanobot.webui.http_utils import (
    query_first as _query_first,
)
from nanobot.webui.http_utils import (
    safe_host_header as _safe_host_header,
)
from nanobot.webui.media_gateway import WebUIMediaGateway
from nanobot.webui.sidebar_state import (
    read_webui_sidebar_state,
    write_webui_sidebar_state,
)
from nanobot.webui.thread_disk import delete_webui_thread
from nanobot.webui.transcript import build_webui_thread_response
from nanobot.webui.workspaces import WebUIWorkspaceController

if TYPE_CHECKING:
    from nanobot.bus.queue import MessageBus
    from nanobot.session.manager import SessionManager


def _decode_api_key(raw_key: str) -> str | None:
    from urllib.parse import unquote

    key = unquote(raw_key)
    _api_key_re = re.compile(r"^[A-Za-z0-9_:.-]{1,128}$")
    if _api_key_re.match(key) is None:
        return None
    return key


def _default_model_name_from_config() -> str | None:
    try:
        from nanobot.config.loader import load_config
        model = load_config().resolve_preset().model.strip()
        return model or None
    except Exception as e:
        logger.debug("bootstrap model_name could not load from config: {}", e)
        return None


def _resolve_bootstrap_model_name(
    runtime_name: Callable[[], str | None] | None,
) -> str | None:
    if runtime_name is not None:
        try:
            raw = runtime_name()
        except Exception as e:
            logger.debug("bootstrap runtime model resolver failed: {}", e)
        else:
            if isinstance(raw, str):
                stripped = raw.strip()
                if stripped:
                    return stripped
    return _default_model_name_from_config()


# ---------------------------------------------------------------------------
# GatewayHTTPHandler
# ---------------------------------------------------------------------------


class GatewayHTTPHandler:
    """Handles all HTTP routes served alongside the WebSocket endpoint.

    Routes HTTP requests and delegates stateful work to explicit gateway
    services owned by the composition layer.
    """

    def __init__(
        self,
        *,
        config: Any,  # WebSocketConfig
        session_manager: SessionManager | None,
        static_dist_path: Path | None,
        runtime_model_name: Callable[[], str | None] | None,
        runtime_surface: str,
        runtime_capabilities_overrides: dict[str, Any] | None,
        bus: MessageBus,
        tokens: GatewayTokenStore,
        media: WebUIMediaGateway,
        workspaces: WebUIWorkspaceController,
        log: Any = logger,
    ) -> None:
        self.config = config
        self.session_manager = session_manager
        self.static_dist_path = static_dist_path
        self.runtime_model_name = runtime_model_name
        self.bus = bus
        self.tokens = tokens
        self.media = media
        self.workspaces = workspaces
        self._log = log
        self._runtime_surface = runtime_surface

        from nanobot.webui.settings_api import runtime_capabilities as _rc
        from nanobot.webui.settings_routes import WebUISettingsRouter

        self._capabilities = _rc(runtime_surface, runtime_capabilities_overrides or {})
        self.settings_routes = WebUISettingsRouter(
            bus=bus,
            logger=self._log,
            check_api_token=self.check_api_token,
            parse_query=_parse_query,
            json_response=_http_json_response,
            error_response=_http_error,
            runtime_surface=runtime_surface,
            runtime_capabilities=self._capabilities,
        )

    # -- Token management ---------------------------------------------------

    def check_api_token(self, request: WsRequest) -> bool:
        return self.tokens.check_api_token(request)

    # -- Main dispatch ------------------------------------------------------

    async def dispatch(self, connection: Any, request: WsRequest) -> Any | None:
        """Route an HTTP request. Returns Response or None."""
        got, _ = _parse_request_path(request.path)

        # Token issue endpoint
        if self.config.token_issue_path:
            issue_expected = _normalize_config_path(self.config.token_issue_path)
            if got == issue_expected:
                return self._handle_token_issue(connection, request)

        # Auth routes (public — no token required)
        if got == "/api/auth/login":
            return await self._handle_auth_login(request)
        if got == "/api/auth/signup":
            return await self._handle_auth_signup(request)

        # Bootstrap + signup (auth is handled inside these handlers)
        if got == "/webui/bootstrap":
            return self._handle_bootstrap(connection, request)
        if got == "/webui/signup":
            return self._handle_signup(request)

        # Settings routes (delegated)
        response = await self.settings_routes.dispatch(request, got)
        if response is not None:
            return response

        # Session routes
        response = self._dispatch_session_routes(request, got)
        if response is not None:
            return response

        # Media routes
        response = self._dispatch_media_routes(request, got)
        if response is not None:
            return response

        # Misc routes
        response = self._dispatch_misc_routes(connection, request, got)
        if response is not None:
            return response

        # Image generation route
        if got == "/api/generate-image":
            return await self._handle_generate_image(request)

        # API 404 (never serve SPA for /api/ routes)
        if got.startswith("/api/"):
            return _http_error(404, "API route not found")

        # Static SPA serving
        if self.static_dist_path is not None:
            response = self._serve_static(got)
            if response is not None:
                return response

        return connection.respond(404, "Not Found")

    # -- Token issue --------------------------------------------------------

    def _handle_token_issue(self, connection: Any, request: Any) -> Any:
        secret = self.config.token_issue_secret.strip() or self.config.token.strip()
        if secret:
            if not _issue_route_secret_matches(request.headers, secret):
                return connection.respond(401, "Unauthorized")
        else:
            self._log.warning(
                "token_issue_path is set but token_issue_secret is empty; "
                "any client can obtain connection tokens — set token_issue_secret for production."
            )
        if not self.tokens.can_issue():
            self._log.error(
                "too many outstanding issued tokens ({}), rejecting issuance",
                len(self.tokens.issued_tokens),
            )
            return _http_json_response({"error": "too many outstanding tokens"}, status=429)
        token_value = self.tokens.issue_token(self.config.token_ttl_s)
        return _http_json_response(token_response_payload(token_value, self.config.token_ttl_s))

    # -- Bootstrap ----------------------------------------------------------

    def _handle_bootstrap(self, connection: Any, request: Any) -> Response:
        headers = getattr(request, "headers", {}) or {}
        email = _case_insensitive_header(headers, "X-Auth-Email") or ""
        password = _case_insensitive_header(headers, "X-Auth-Password") or ""

        if email and password:
            # MongoDB auth path
            try:
                from nanobot.auth.mongodb_auth import login_user
                login_user(email.strip().lower(), password)
            except ValueError as exc:
                return _http_json_response({"error": str(exc)}, status=401)
            except RuntimeError as exc:
                self._log.error("bootstrap mongodb config error: {}", exc)
                return _http_json_response({"error": "Auth service unavailable"}, status=503)
            except Exception as exc:
                self._log.error("bootstrap mongodb error: {}", exc)
                return _http_json_response({"error": "Login failed"}, status=500)
        else:
            # Original secret-based auth
            secret = self.config.token_issue_secret.strip() or self.config.token.strip()
            if secret:
                if not _issue_route_secret_matches(request.headers, secret):
                    return _http_error(401, "Unauthorized")
            elif not _is_localhost(connection):
                return _http_error(403, "bootstrap is localhost-only")

        if not self.tokens.can_issue(include_api_token=True):
            return _http_response(
                json.dumps({"error": "too many outstanding tokens"}).encode("utf-8"),
                status=429,
                content_type="application/json; charset=utf-8",
            )
        token = self.tokens.issue_token(self.config.token_ttl_s, api_token=True)

        ws_url = self._bootstrap_ws_url(request)
        expected_path = _normalize_config_path(self.config.path)
        return _http_json_response(
            {
                "token": token,
                "ws_path": expected_path,
                "ws_url": ws_url,
                "expires_in": self.config.token_ttl_s,
                "model_name": _resolve_bootstrap_model_name(self.runtime_model_name),
                "runtime_surface": self._runtime_surface,
                "runtime_capabilities": self._capabilities,
            }
        )

    def _handle_signup(self, request: Any) -> Response:
        """Create a new user account and issue a bootstrap token."""
        headers = getattr(request, "headers", {}) or {}
        name = _case_insensitive_header(headers, "X-Auth-Name") or ""
        email = _case_insensitive_header(headers, "X-Auth-Email") or ""
        password = _case_insensitive_header(headers, "X-Auth-Password") or ""
        query = _parse_query(request.path)
        name = name or _query_first(query, "name") or ""
        email = email or _query_first(query, "email") or ""
        password = password or _query_first(query, "password") or ""

        try:
            from nanobot.auth.mongodb_auth import signup_user
            signup_user(name, email.strip().lower(), password)
        except ValueError as exc:
            return _http_json_response({"error": str(exc)}, status=400)
        except RuntimeError as exc:
            self._log.error("signup mongodb config error: {}", exc)
            return _http_json_response({"error": "Auth service unavailable"}, status=503)
        except Exception as exc:
            self._log.error("signup mongodb error: {}", exc)
            return _http_json_response({"error": "Signup failed"}, status=500)

        if not self.tokens.can_issue(include_api_token=True):
            return _http_json_response({"error": "Too many outstanding tokens"}, status=429)
        token = self.tokens.issue_token(self.config.token_ttl_s, api_token=True)
        expected_path = _normalize_config_path(self.config.path)
        return _http_json_response(
            {
                "token": token,
                "ws_path": expected_path,
                "ws_url": self._bootstrap_ws_url(request),
                "expires_in": self.config.token_ttl_s,
                "model_name": _resolve_bootstrap_model_name(self.runtime_model_name),
                "runtime_surface": self._runtime_surface,
                "runtime_capabilities": self._capabilities,
            }
        )

    def _bootstrap_ws_url(self, request: Any) -> str:
        headers = getattr(request, "headers", {}) or {}
        host = _safe_host_header(_case_insensitive_header(headers, "Host"))
        if not host:
            host = _host_for_url(self.config.host, self.config.port)
        proto = _case_insensitive_header(headers, "X-Forwarded-Proto")
        proto = proto.split(",", 1)[0].strip().lower()
        secure = proto in {"https", "wss"} or bool(self.config.ssl_certfile.strip())
        scheme = "wss" if secure else "ws"
        expected_path = _normalize_config_path(self.config.path)
        return f"{scheme}://{host}{expected_path}"

    def _issue_bootstrap_token(self, request: Any) -> dict[str, Any]:
        """Issue a bootstrap token and return the response payload."""
        token = self.tokens.issue_token(self.config.token_ttl_s, api_token=True)
        expected_path = _normalize_config_path(self.config.path)
        return {
            "token": token,
            "ws_path": expected_path,
            "ws_url": self._bootstrap_ws_url(request),
            "expires_in": self.config.token_ttl_s,
            "model_name": _resolve_bootstrap_model_name(self.runtime_model_name),
            "runtime_surface": self._runtime_surface,
            "runtime_capabilities": self._capabilities,
        }

    # -- MongoDB auth routes (public) ---------------------------------------

    async def _handle_auth_login(self, request: WsRequest) -> Response:
        """Login with email + password via MongoDB."""
        try:
            from nanobot.auth.mongodb_auth import login_user

            headers = getattr(request, "headers", {}) or {}
            email = _case_insensitive_header(headers, "X-Auth-Email") or ""
            password = _case_insensitive_header(headers, "X-Auth-Password") or ""
            query = _parse_query(request.path)
            email = email or _query_first(query, "email") or ""
            password = password or _query_first(query, "password") or ""

            await asyncio.to_thread(login_user, email, password)

            if not self.tokens.can_issue(include_api_token=True):
                return _http_error(429, "Too many outstanding tokens")
            return _http_json_response(self._issue_bootstrap_token(request))
        except ValueError as exc:
            return _http_json_response({"error": str(exc)}, status=401)
        except RuntimeError as exc:
            self._log.error("auth login config error: {}", exc)
            return _http_json_response({"error": "Auth service unavailable"}, status=503)
        except Exception as exc:
            self._log.error("auth login error: {}", exc)
            return _http_json_response({"error": "Login failed"}, status=500)

    async def _handle_auth_signup(self, request: WsRequest) -> Response:
        """Register a new user via MongoDB and auto-login."""
        try:
            from nanobot.auth.mongodb_auth import signup_user

            headers = getattr(request, "headers", {}) or {}
            name = _case_insensitive_header(headers, "X-Auth-Name") or ""
            email = _case_insensitive_header(headers, "X-Auth-Email") or ""
            password = _case_insensitive_header(headers, "X-Auth-Password") or ""
            query = _parse_query(request.path)
            name = name or _query_first(query, "name") or ""
            email = email or _query_first(query, "email") or ""
            password = password or _query_first(query, "password") or ""

            await asyncio.to_thread(signup_user, name, email, password)

            if not self.tokens.can_issue(include_api_token=True):
                return _http_error(429, "Too many outstanding tokens")
            return _http_json_response(self._issue_bootstrap_token(request))
        except ValueError as exc:
            return _http_json_response({"error": str(exc)}, status=400)
        except RuntimeError as exc:
            self._log.error("auth signup config error: {}", exc)
            return _http_json_response({"error": "Auth service unavailable"}, status=503)
        except Exception as exc:
            self._log.error("auth signup error: {}", exc)
            return _http_json_response({"error": "Signup failed"}, status=500)

    # -- Session routes -----------------------------------------------------

    def _dispatch_session_routes(self, request: WsRequest, got: str) -> Response | None:
        m = re.match(r"^/api/sessions/([^/]+)/messages$", got)
        if m:
            return self._handle_session_messages(request, m.group(1))

        m = re.match(r"^/api/sessions/([^/]+)/webui-thread$", got)
        if m:
            return self._handle_webui_thread_get(request, m.group(1))

        m = re.match(r"^/api/sessions/([^/]+)/delete$", got)
        if m:
            return self._handle_session_delete(request, m.group(1))

        return None

    def _handle_sessions_list(self, request: WsRequest) -> Response:
        if not self.check_api_token(request):
            return _http_error(401, "Unauthorized")
        if self.session_manager is None:
            return _http_error(503, "session manager unavailable")
        sessions = self.session_manager.list_sessions()
        from nanobot.session.webui_turns import websocket_turn_wall_started_at

        cleaned = []
        for s in sessions:
            key = s.get("key")
            if not (isinstance(key, str) and key.startswith("websocket:")):
                continue
            row = {k: v for k, v in s.items() if k != "path"}
            chat_id = key.split(":", 1)[1]
            started_at = websocket_turn_wall_started_at(chat_id)
            if started_at is not None:
                row["run_started_at"] = started_at
            scope = self.workspaces.scope_for_session_key(key)
            row["workspace_scope"] = scope.payload()
            cleaned.append(row)
        return _http_json_response({"sessions": cleaned})

    def _handle_session_messages(self, request: WsRequest, key: str) -> Response:
        if not self.check_api_token(request):
            return _http_error(401, "Unauthorized")
        if self.session_manager is None:
            return _http_error(503, "session manager unavailable")
        decoded_key = _decode_api_key(key)
        if decoded_key is None:
            return _http_error(400, "invalid session key")
        if not _is_websocket_channel_session_key(decoded_key):
            return _http_error(404, "session not found")
        data = self.session_manager.read_session_file(decoded_key)
        if data is None:
            return _http_error(404, "session not found")
        messages = data.get("messages")
        if isinstance(messages, list):
            scrub_subagent_messages_for_channel(messages)
        self.media.augment_media_urls(data)
        return _http_json_response(data)

    def _handle_webui_thread_get(self, request: WsRequest, key: str) -> Response:
        if not self.check_api_token(request):
            return _http_error(401, "Unauthorized")
        decoded_key = _decode_api_key(key)
        if decoded_key is None:
            return _http_error(400, "invalid session key")
        if not _is_websocket_channel_session_key(decoded_key):
            return _http_error(404, "session not found")
        scope = self.workspaces.scope_for_session_key(decoded_key)
        session_messages: list[dict[str, Any]] | None = None
        if self.session_manager is not None:
            session_data = self.session_manager.read_session_file(decoded_key)
            raw_messages = session_data.get("messages") if isinstance(session_data, dict) else None
            if isinstance(raw_messages, list):
                session_messages = [m for m in raw_messages if isinstance(m, dict)]
        data = build_webui_thread_response(
            decoded_key,
            augment_user_media=self.media.augment_transcript_media,
            augment_assistant_media=self.media.augment_transcript_media,
            augment_assistant_text=lambda text: self.media.rewrite_local_markdown_images(
                text,
                workspace_path=scope.project_path,
            ),
            session_messages=session_messages,
        )
        if data is None:
            return _http_error(404, "webui thread not found")
        data["workspace_scope"] = scope.payload()
        return _http_json_response(data)

    def _handle_session_delete(self, request: WsRequest, key: str) -> Response:
        if not self.check_api_token(request):
            return _http_error(401, "Unauthorized")
        if self.session_manager is None:
            return _http_error(503, "session manager unavailable")
        decoded_key = _decode_api_key(key)
        if decoded_key is None:
            return _http_error(400, "invalid session key")
        if not _is_websocket_channel_session_key(decoded_key):
            return _http_error(404, "session not found")
        deleted = self.session_manager.delete_session(decoded_key)
        delete_webui_thread(decoded_key)
        return _http_json_response({"deleted": bool(deleted)})

    # -- Media routes -------------------------------------------------------

    def _dispatch_media_routes(self, request: WsRequest, got: str) -> Response | None:
        m = re.match(r"^/api/media/([A-Za-z0-9_-]+)/([A-Za-z0-9_-]+)$", got)
        if m:
            return self._handle_media_fetch(m.group(1), m.group(2), request)
        return None

    def _handle_media_fetch(
        self, sig: str, payload: str, request: WsRequest | None = None
    ) -> Response:
        return self.media.serve_signed_media(
            sig,
            payload,
            request=request,
        )

    # -- Misc routes --------------------------------------------------------

    def _dispatch_misc_routes(
        self, connection: Any, request: WsRequest, got: str
    ) -> Response | None:
        if got == "/api/sessions":
            return self._handle_sessions_list(request)
        if got == "/api/commands":
            return self._handle_commands(request)
        if got == "/api/workspaces":
            return self._handle_workspaces(connection, request)
        if got == "/api/webui/sidebar-state":
            return self._handle_webui_sidebar_state(request)
        if got == "/api/webui/sidebar-state/update":
            return self._handle_webui_sidebar_state_update(request)
        m = re.match(r"^/webui/download/([A-Za-z0-9_-]+)$", got)
        if m:
            return self._handle_download(m.group(1))
        return None

    def _handle_commands(self, request: WsRequest) -> Response:
        if not self.check_api_token(request):
            return _http_error(401, "Unauthorized")
        return _http_json_response({"commands": builtin_command_palette()})

    def _handle_workspaces(self, connection: Any, request: WsRequest) -> Response:
        if not self.check_api_token(request):
            return _http_error(401, "Unauthorized")
        return _http_json_response(
            self.workspaces.payload(controls_available=_is_localhost(connection))
        )

    def _handle_webui_sidebar_state(self, request: WsRequest) -> Response:
        if not self.check_api_token(request):
            return _http_error(401, "Unauthorized")
        return _http_json_response(read_webui_sidebar_state())

    def _handle_webui_sidebar_state_update(self, request: WsRequest) -> Response:
        if not self.check_api_token(request):
            return _http_error(401, "Unauthorized")
        query = _parse_query(request.path)
        raw_state = _query_first(query, "state")
        if raw_state is None:
            return _http_error(400, "missing state")
        try:
            decoded = json.loads(raw_state)
        except json.JSONDecodeError:
            return _http_error(400, "state must be JSON")
        if not isinstance(decoded, dict):
            return _http_error(400, "state must be an object")
        try:
            state = write_webui_sidebar_state(decoded)
        except ValueError as e:
            return _http_error(400, str(e))
        except OSError:
            self._log.exception("failed to write webui sidebar state")
            return _http_error(500, "failed to write sidebar state")
        return _http_json_response(state)

    async def _handle_generate_image(self, request: WsRequest) -> Response:
        """Generate an image via the configured custom provider."""
        if not self.check_api_token(request):
            return _http_error(401, "Unauthorized")
        try:
            import os
            import httpx as _httpx
            from nanobot.providers.image_generation import (
                CustomImageGenerationClient,
                ImageGenerationError,
            )

            body_bytes = getattr(request, "body", b"") or b""
            try:
                payload = json.loads(body_bytes) if body_bytes else {}
            except json.JSONDecodeError:
                payload = {}

            query = _parse_query(request.path)
            prompt = payload.get("prompt") or _query_first(query, "prompt") or ""
            model = payload.get("model") or _query_first(query, "model") or "dall-e-3"

            if not prompt:
                return _http_json_response({"error": "prompt is required"}, status=400)

            api_base = os.environ.get("NANOBOT_API_BASE", "").rstrip("/")
            api_key = os.environ.get("NANOBOT_API_KEY", "")

            async with _httpx.AsyncClient(verify=False, timeout=120.0) as http_client:
                gen_client = CustomImageGenerationClient(
                    api_key=api_key or None,
                    api_base=api_base or None,
                    client=http_client,
                )
                result = await gen_client.generate(prompt=prompt, model=model)

            return _http_json_response({"images": result.images, "content": result.content})
        except Exception as exc:
            self._log.error("image generation failed: {}", exc)
            return _http_json_response({"error": str(exc)}, status=500)

    def _handle_download(self, token: str) -> Response:
        from nanobot.webui.download_registry import get_download
        entry = get_download(token)
        if entry is None:
            return _http_error(404, "Download link not found or expired")
        try:
            data = entry.path.read_bytes()
        except Exception:
            return _http_error(500, "Failed to read file")
        safe_name = entry.filename.replace('"', "")
        return _http_response(
            data,
            content_type=entry.content_type,
            extra_headers=[
                ("Content-Disposition", f'attachment; filename="{safe_name}"'),
                ("Cache-Control", "no-cache, no-store"),
            ],
        )

    # -- Static file serving ------------------------------------------------

    def _serve_static(self, request_path: str) -> Response | None:
        assert self.static_dist_path is not None
        rel = request_path.lstrip("/")
        if not rel:
            rel = "index.html"
        if ".." in rel.split("/") or rel.startswith("/"):
            return _http_error(403, "Forbidden")
        candidate = (self.static_dist_path / rel).resolve()
        try:
            candidate.relative_to(self.static_dist_path)
        except ValueError:
            return _http_error(403, "Forbidden")
        if not candidate.is_file():
            index = self.static_dist_path / "index.html"
            if index.is_file():
                candidate = index
            else:
                return None
        try:
            body = candidate.read_bytes()
        except OSError as e:
            self._log.warning("static: failed to read {}: {}", candidate, e)
            return _http_error(500, "Internal Server Error")
        ctype, _ = mimetypes.guess_type(candidate.name)
        if ctype is None:
            ctype = "application/octet-stream"
        if ctype.startswith("text/") or ctype in {"application/javascript", "application/json"}:
            ctype = f"{ctype}; charset=utf-8"
        if candidate.name == "index.html":
            cache = "no-cache"
        else:
            cache = "public, max-age=31536000, immutable"
        return _http_response(
            body,
            status=200,
            content_type=ctype,
            extra_headers=[("Cache-Control", cache)],
        )

def _is_websocket_channel_session_key(key: str) -> bool:
    return key.startswith("websocket:")
