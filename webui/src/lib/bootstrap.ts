import type { BootstrapResponse } from "./types";
import { fetchWithTimeout } from "./http";

const SECRET_STORAGE_KEY = "dzeck-webui.bootstrap-secret";
const EMAIL_STORAGE_KEY = "dzeck-webui.user-email";
const PASSWORD_SESSION_KEY = "dzeck-webui.session-password";

/** Read a previously saved bootstrap secret from localStorage. */
export function loadSavedSecret(): string {
  if (typeof window === "undefined") return "";
  try {
    return window.localStorage.getItem(SECRET_STORAGE_KEY) ?? "";
  } catch {
    return "";
  }
}

/** Persist the bootstrap secret so page reloads don't re-prompt. */
export function saveSecret(secret: string): void {
  try {
    window.localStorage.setItem(SECRET_STORAGE_KEY, secret);
  } catch {
    // ignore storage errors (private mode, etc.)
  }
}

/** Clear the saved bootstrap secret (sign out). */
export function clearSavedSecret(): void {
  try {
    window.localStorage.removeItem(SECRET_STORAGE_KEY);
  } catch {
    // ignore
  }
}

/** Read the saved user email from localStorage. */
export function loadSavedEmail(): string {
  if (typeof window === "undefined") return "";
  try {
    return window.localStorage.getItem(EMAIL_STORAGE_KEY) ?? "";
  } catch {
    return "";
  }
}

/** Persist the user email to localStorage. */
export function saveEmail(email: string): void {
  try {
    window.localStorage.setItem(EMAIL_STORAGE_KEY, email);
  } catch {}
}

/** Read the session password from sessionStorage (cleared on tab close). */
export function loadSessionPassword(): string {
  if (typeof window === "undefined") return "";
  try {
    return window.sessionStorage.getItem(PASSWORD_SESSION_KEY) ?? "";
  } catch {
    return "";
  }
}

/** Persist the session password to sessionStorage. */
export function saveSessionPassword(pw: string): void {
  try {
    window.sessionStorage.setItem(PASSWORD_SESSION_KEY, pw);
  } catch {}
}

/** Clear all auth session data (sign out). */
export function clearAuthSession(): void {
  try {
    window.localStorage.removeItem(EMAIL_STORAGE_KEY);
  } catch {}
  try {
    window.sessionStorage.removeItem(PASSWORD_SESSION_KEY);
  } catch {}
  clearSavedSecret();
}

/**
 * Fetch a short-lived token + the WebSocket path from the gateway's
 * ``/webui/bootstrap`` endpoint.
 */
export async function fetchBootstrap(
  baseUrl: string = "",
  secret: string = "",
  timeoutMs?: number,
): Promise<BootstrapResponse> {
  const headers: Record<string, string> = {};
  if (secret) {
    headers["X-Nanobot-Auth"] = secret;
  }
  const res = await fetchWithTimeout(`${baseUrl}/webui/bootstrap`, {
    method: "GET",
    credentials: "same-origin",
    headers,
  }, timeoutMs);
  if (!res.ok) {
    throw new Error(`bootstrap failed: HTTP ${res.status}`);
  }
  const body = (await res.json()) as BootstrapResponse;
  if (!body.token || !body.ws_path) {
    throw new Error("bootstrap response missing token or ws_path");
  }
  return body;
}

/**
 * Login with email + password via MongoDB auth.
 * Uses /webui/bootstrap with X-Auth-Email and X-Auth-Password headers.
 */
export async function fetchAuthLogin(
  email: string,
  password: string,
  timeoutMs?: number,
): Promise<BootstrapResponse> {
  const res = await fetchWithTimeout("/webui/bootstrap", {
    method: "GET",
    credentials: "same-origin",
    headers: {
      "X-Auth-Email": email,
      "X-Auth-Password": password,
    },
  }, timeoutMs);
  if (!res.ok) {
    let errMsg = `Login failed: HTTP ${res.status}`;
    try {
      const body = (await res.json()) as { error?: string };
      if (body.error) errMsg = body.error;
    } catch {}
    throw new Error(errMsg);
  }
  const body = (await res.json()) as BootstrapResponse;
  if (!body.token || !body.ws_path) {
    throw new Error("Login response missing token or ws_path");
  }
  return body;
}

/**
 * Register a new account via MongoDB auth.
 * Uses /webui/signup which creates the user then issues a bootstrap token.
 */
export async function fetchAuthSignup(
  name: string,
  email: string,
  password: string,
  timeoutMs?: number,
): Promise<BootstrapResponse> {
  const res = await fetchWithTimeout("/webui/signup", {
    method: "GET",
    credentials: "same-origin",
    headers: {
      "X-Auth-Name": name,
      "X-Auth-Email": email,
      "X-Auth-Password": password,
    },
  }, timeoutMs);
  if (!res.ok) {
    let errMsg = `Signup failed: HTTP ${res.status}`;
    try {
      const body = (await res.json()) as { error?: string };
      if (body.error) errMsg = body.error;
    } catch {}
    throw new Error(errMsg);
  }
  const body = (await res.json()) as BootstrapResponse;
  if (!body.token || !body.ws_path) {
    throw new Error("Signup response missing token or ws_path");
  }
  return body;
}

/** Derive a WebSocket URL from the current window location and the server-provided path.
 *
 * Keeps the path segment exactly as the server registered it: the root ``/``
 * stays ``/`` and non-root paths are not given an extra trailing slash. This
 * matters because some WS servers dispatch handshakes based on the literal
 * path, not a normalised form.
 */
export function deriveWsUrl(
  wsPath: string,
  token: string,
  wsUrl?: string | null,
): string {
  const query = `?token=${encodeURIComponent(token)}`;
  if (wsUrl && /^(wss?|dzeck-host):\/\//i.test(wsUrl)) {
    const isServerLocalhost = /^wss?:\/\/(127\.0\.0\.1|localhost)(:\d+)?\//i.test(wsUrl);
    if (!isServerLocalhost) {
      const join = wsUrl.includes("?") ? "&" : "?";
      return `${wsUrl}${join}token=${encodeURIComponent(token)}`;
    }
  }
  const path = wsPath && wsPath.startsWith("/") ? wsPath : `/${wsPath || ""}`;
  if (typeof window === "undefined") {
    return `ws://127.0.0.1:8765${path}${query}`;
  }
  if (window.location.port === "5173") {
    const host = window.location.hostname.includes(":")
      ? `[${window.location.hostname}]`
      : window.location.hostname;
    return `ws://${host}:8765${path}${query}`;
  }
  const scheme = window.location.protocol === "https:" ? "wss" : "ws";
  const host = window.location.host;
  return `${scheme}://${host}${path}${query}`;
}
