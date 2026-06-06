---
name: nanobot newChat timeout fix
description: Why newChat resets to home on new projects and how it was fixed
---

## Rule
The `newChat` timer in `nanobot-client.ts` must NOT start until the WebSocket is actually open. If it starts while the frame is still queued, it times out before the backend connects → `onCreateChat` returns null → UI resets to home screen.

**Why:** On fresh projects, the frontend (Vite) loads fast but the backend (nanobot gateway) starts slower. The user sends their first message before WS is open. The frame gets queued, but the 5s timer was already running → timeout → silent reset.

**How to apply:** When adding/modifying `newChat` or `queueSend`:
- Timer starts in `newChat` only if `socket.readyState === WS_OPEN`  
- Timer starts in `handleOpen` (after queue flush) if `pendingNewChat.timer === null`
- All `clearTimeout(pendingNewChat.timer)` calls must guard: `if (timer !== null)`
- Default timeout increased from 5s → 15s for slower environments
