# SESH Worker

Social backend for the SESH app — friends' presence, Cyphers (shared
sessions), live streams, chat rooms, and the activity feed. Poll-based and
KV-backed so it deploys with zero extra infrastructure.

The app points at `https://sesh-worker.stocked.workers.dev` (set in
`BuildConfig.workerURL`). If the Worker is unreachable, the app falls back to a
rich seeded local state, so it always works offline.

## Deploy

```bash
cd _worker/sesh-worker
npm i -g wrangler            # if needed
wrangler kv:namespace create SESH
# paste the returned id into wrangler.toml -> kv_namespaces[0].id
wrangler deploy
```

## Endpoints

| Method | Path | Body | Returns |
|--------|------|------|---------|
| GET  | `/api/snapshot` | — | `{ friends, cyphers, rooms, live, feed }` |
| POST | `/api/activity` | `{ activity, detail }` | `{ ok }` |
| POST | `/api/cyphers` | `{ id, title, strain, live, visibility }` | `{ ok }` |
| POST | `/api/cyphers/:id/join` | — | `{ ok }` |
| POST | `/api/cyphers/:id/leave` | — | `{ ok }` |
| POST | `/api/live` | `{ id, title, strain, cypher }` | `{ ok }` |
| POST | `/api/live/:id/end` | — | `{ ok }` |
| GET  | `/api/rooms/:id/messages` | — | `[ ChatMessage ]` |
| POST | `/api/rooms/:id/messages` | `{ id, text }` | `{ ok }` |
| GET  | `/health` | — | `{ ok, ts }` |

## Going realtime later

This Worker is request/response only. For true live presence and chat,
migrate state to a Durable Object and add a `/ws` WebSocket route — the app's
existing endpoints can stay as a fallback, so no client rewrite is needed.
