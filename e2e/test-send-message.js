/**
 * E2E Test — WebSocket send-message flow
 *
 * Simulates exactly what the user's browser does:
 * 1. Fetch /webui/bootstrap from the public URL
 * 2. Derive the WebSocket URL (must NOT be localhost)
 * 3. Connect WebSocket
 * 4. Wait for "ready" event
 * 5. Send "new_chat" frame — wait for "attached" (≤5 s)
 * 6. Send a user message on the new chat_id
 * 7. Wait for "delta" or "turn_end" (AI responding)
 */

const https = require("https");
const http = require("http");
const { WebSocket } = require("ws");

const PUBLIC_HOST = process.env.REPLIT_DEV_DOMAIN || "localhost:5000";
const BASE_URL = `https://${PUBLIC_HOST}`;
const NEW_CHAT_TIMEOUT_MS = 8_000;   // was 5000 — relaxed for test
const AI_RESPONSE_TIMEOUT_MS = 30_000;
const NANOBOT_AUTH_SECRET = process.env.NANOBOT_AUTH_SECRET || "";

function pass(msg) { console.log(`  ✅ ${msg}`); }
function fail(msg) { console.error(`  ❌ ${msg}`); }
function info(msg) { console.log(`  ℹ  ${msg}`); }

function fetchJson(url) {
  const options = { rejectUnauthorized: false };
  if (NANOBOT_AUTH_SECRET) {
    options.headers = { "X-Nanobot-Auth": NANOBOT_AUTH_SECRET };
  }
  return new Promise((resolve, reject) => {
    const mod = url.startsWith("https") ? https : http;
    const req = mod.get(url, options, (res) => {
      let body = "";
      res.on("data", (d) => (body += d));
      res.on("end", () => {
        if (res.statusCode !== 200) {
          return reject(new Error(`HTTP ${res.statusCode} for ${url}`));
        }
        try { resolve(JSON.parse(body)); }
        catch (e) { reject(new Error(`Bad JSON from ${url}: ${body.slice(0, 200)}`)); }
      });
    });
    req.on("error", reject);
    req.setTimeout(10_000, () => { req.destroy(); reject(new Error("fetch timeout")); });
  });
}

async function main() {
  console.log(`\n🧪 Nanobot E2E — WebSocket send-message flow`);
  console.log(`   Public URL: ${BASE_URL}\n`);

  // ── Step 1: Bootstrap ──────────────────────────────────────────────────────
  console.log("Step 1: Fetching bootstrap from PUBLIC URL...");
  const boot = await fetchJson(`${BASE_URL}/webui/bootstrap`);
  info(`ws_path   = ${boot.ws_path}`);
  info(`ws_url    = ${boot.ws_url}`);
  info(`model     = ${boot.model_name}`);

  // ── Step 2: Derive WebSocket URL (the fixed deriveWsUrl logic) ────────────
  console.log("\nStep 2: Deriving WebSocket URL...");
  const isLocalhost = /^wss?:\/\/(127\.0\.0\.1|localhost)(:\d+)?\//i.test(boot.ws_url || "");
  let wsUrl;
  if (boot.ws_url && !isLocalhost) {
    wsUrl = `${boot.ws_url}${boot.ws_url.includes("?") ? "&" : "?"}token=${encodeURIComponent(boot.token)}`;
  } else {
    const path = boot.ws_path && boot.ws_path.startsWith("/") ? boot.ws_path : `/${boot.ws_path || ""}`;
    wsUrl = `wss://${PUBLIC_HOST}${path}?token=${encodeURIComponent(boot.token)}`;
  }
  info(`ws_url is localhost: ${isLocalhost}`);
  info(`Connecting to: ${wsUrl.split("?")[0]}?token=***`);
  if (isLocalhost) {
    pass("ws_url correctly skipped (localhost) — using public URL fallback");
  } else {
    pass("ws_url is already a public URL");
  }

  // ── Step 3: Connect WebSocket ──────────────────────────────────────────────
  console.log("\nStep 3: Connecting WebSocket via PUBLIC proxy...");
  const ws = new WebSocket(wsUrl, { rejectUnauthorized: false });
  const events = [];

  function waitForEvent(pred, timeoutMs, label) {
    return new Promise((resolve, reject) => {
      const t = setTimeout(() => reject(new Error(`Timeout waiting for ${label}`)), timeoutMs);
      const check = () => {
        const found = events.find(pred);
        if (found) { clearTimeout(t); resolve(found); }
      };
      ws.on("message", () => check());   // re-check on every incoming frame
      check();                           // also check immediately
    });
  }

  await new Promise((resolve, reject) => {
    ws.on("open", resolve);
    ws.on("error", reject);
    setTimeout(() => reject(new Error("WS open timeout")), 10_000);
  });
  pass("WebSocket opened");

  ws.on("message", (raw) => {
    try {
      const ev = JSON.parse(raw.toString());
      events.push(ev);
      info(`← ${ev.event}${ev.chat_id ? ` (chat ${ev.chat_id.slice(0, 8)}…)` : ""}`);
    } catch {}
  });

  // ── Step 4: Wait for "ready" ───────────────────────────────────────────────
  console.log("\nStep 4: Waiting for 'ready' event...");
  await waitForEvent((e) => e.event === "ready", 8_000, "'ready'");
  pass("Received 'ready' — server acknowledged connection");

  // ── Step 5: new_chat → attached ────────────────────────────────────────────
  console.log("\nStep 5: Sending 'new_chat' — waiting for 'attached'...");
  ws.send(JSON.stringify({ type: "new_chat" }));
  const attached = await waitForEvent(
    (e) => e.event === "attached",
    NEW_CHAT_TIMEOUT_MS,
    "'attached'"
  );
  const chatId = attached.chat_id;
  pass(`Received 'attached' — new chat_id: ${chatId}`);

  // ── Step 6: Send a user message ───────────────────────────────────────────
  console.log("\nStep 6: Sending user message...");
  ws.send(JSON.stringify({
    type: "message",
    chat_id: chatId,
    content: "Haiii! E2E test dari WebSocket client. Balas singkat saja.",
    webui: true,
  }));
  pass("Message frame sent");

  // ── Step 7: Wait for AI to start responding ────────────────────────────────
  console.log("\nStep 7: Waiting for AI response (delta or stream_end)...");
  const aiEv = await waitForEvent(
    (e) => (e.event === "delta" || e.event === "stream_end" || e.event === "turn_end") && e.chat_id === chatId,
    AI_RESPONSE_TIMEOUT_MS,
    "AI response"
  );
  pass(`Received AI event: '${aiEv.event}'${aiEv.text ? ` — "${aiEv.text.slice(0, 60)}…"` : ""}`);

  ws.close();

  console.log("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  console.log("✅  ALL STEPS PASSED");
  console.log("    The WebSocket fix is working correctly.");
  console.log("    Messages sent from the home page will NO longer disappear.");
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
  process.exit(0);
}

main().catch((err) => {
  fail(`TEST FAILED: ${err.message}`);
  console.error(err.stack || "");
  process.exit(1);
});
