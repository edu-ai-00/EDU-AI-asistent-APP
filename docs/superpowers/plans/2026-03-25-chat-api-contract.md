# Chat API Contract — Backend Requirements

> **Audience:** Backend developer / infra team implementing the Laravel API + AI proxy.
> **Consumer:** Flutter EDU-AI app (Dio HTTP client, SSE via stream response).
> **Auth:** All endpoints require `Authorization: Bearer <sanctum_token>` header.

---

## Overview

The Flutter app needs a **stateless REST API** for chat CRUD and a **Server-Sent Events (SSE) endpoint** for streaming AI responses. The app handles all local persistence and UI — the backend is responsible for:

1. Chat session & message CRUD
2. AI prompt orchestration (system prompt + context injection)
3. **OpenRouter API proxy** with SSE streaming (OpenAI-compatible, supports 200+ models)
4. Message history truncation (context window management)
5. Rate limiting to prevent abuse / cost overruns

---

## Database Schema

### `chat_sessions`

| Column | Type | Notes |
|--------|------|-------|
| `id` | bigint (PK, auto) | Server ID |
| `user_id` | bigint (FK → users) | ON DELETE CASCADE |
| `title` | varchar(255) | Default `''`, auto-generated from first message if empty |
| `persona` | varchar(50) | One of: `ai_teacher`, `math_mentor`, `study_coach`, `language_mentor` |
| `last_message_at` | timestamp | Updated on each new message |
| `created_at` | timestamp | |
| `updated_at` | timestamp | |

Index: `(user_id, last_message_at)`

### `chat_messages`

| Column | Type | Notes |
|--------|------|-------|
| `id` | bigint (PK, auto) | Server ID |
| `chat_session_id` | bigint (FK → chat_sessions) | ON DELETE CASCADE |
| `role` | enum('user','assistant','system') | |
| `content` | longtext | Markdown supported. Empty string for pre-created assistant placeholders |
| `message_type` | varchar(50) | Default `'text'`. Future: `question_mc`, `image`, `audio`, `video` |
| `metadata` | json (nullable) | Future: MC options, media URLs, etc. |
| `feedback_type` | varchar(20) (nullable) | `'like'` or `'dislike'` |
| `feedback_detail` | text (nullable) | Free-text detail for dislike reports |
| `created_at` | timestamp | |
| `updated_at` | timestamp | |

Index: `(chat_session_id, created_at)`

---

## Endpoints

### 1. List Sessions

```
GET /api/chat/sessions
GET /api/chat/sessions?since=2026-03-25T12:00:00Z
```

**Response** `200`:
```json
{
  "data": [
    {
      "id": 1,
      "title": "Zlomky a procenta",
      "persona": "ai_teacher",
      "last_message_at": "2026-03-25T14:30:00Z",
      "created_at": "2026-03-25T10:00:00Z",
      "updated_at": "2026-03-25T14:30:00Z"
    }
  ]
}
```

**`since` param:** If provided, return only sessions with `updated_at > since`. Used for incremental sync.

---

### 2. Create Session

```
POST /api/chat/sessions
Content-Type: application/json

{
  "persona": "ai_teacher",
  "title": ""
}
```

**Validation:**
- `persona`: required, string, one of `ai_teacher|math_mentor|study_coach|language_mentor`
- `title`: optional, string, max 255

**Response** `201`:
```json
{
  "data": {
    "id": 1,
    "title": "",
    "persona": "ai_teacher",
    "last_message_at": "2026-03-25T10:00:00Z",
    "created_at": "2026-03-25T10:00:00Z",
    "updated_at": "2026-03-25T10:00:00Z"
  }
}
```

**Important:** The app creates sessions server-side first (blocking call) before allowing messages. The returned `id` is required for all subsequent message endpoints.

---

### 3. Delete Session

```
DELETE /api/chat/sessions/{id}
```

**Authorization:** Must be session owner (`user_id` matches authenticated user).

**Response** `200`:
```json
{ "message": "Session deleted" }
```

Cascade deletes all messages in the session.

---

### 4. Send Message (Two-Step Flow — Step 1)

```
POST /api/chat/sessions/{sessionId}/messages
Content-Type: application/json

{
  "content": "Ahoj, jak se učit zlomky?"
}
```

**Validation:**
- `content`: required, string, max 4000 characters

**What the server does:**
1. Save the user message
2. Create an **empty** assistant message (content = `''`) as a placeholder
3. Update `session.last_message_at`
4. Return both messages immediately — **do NOT start AI generation yet**

**Response** `201`:
```json
{
  "data": {
    "user_message": {
      "id": 42,
      "role": "user",
      "content": "Ahoj, jak se učit zlomky?",
      "message_type": "text",
      "created_at": "2026-03-25T14:30:00Z"
    },
    "assistant_message": {
      "id": 43,
      "role": "assistant",
      "content": "",
      "message_type": "text",
      "created_at": "2026-03-25T14:30:01Z"
    }
  }
}
```

**Why two-step?** If the SSE connection drops mid-stream, the client can reconnect using the `assistant_message.id`. The assistant message is pre-created so its ID is stable.

**Rate limit:** Max 20 messages per minute per user. Return `429` if exceeded:
```json
{ "message": "Too many messages. Please wait.", "retry_after": 30 }
```

---

### 5. Stream AI Response (Two-Step Flow — Step 2)

```
GET /api/chat/sessions/{sessionId}/stream?message_id={assistantMessageId}
Accept: text/event-stream
```

**What the server does:**
1. Load the assistant message by `message_id` — verify it belongs to this session and is empty
2. Load all prior messages in the session (before the assistant message)
3. Build system prompt with context (see [System Prompt](#system-prompt) below)
4. **Truncate history** to fit the model's context window (see [Context Truncation](#context-truncation))
5. Call OpenRouter Chat Completions API with `stream: true`
6. Forward tokens as SSE events
7. After stream completes, update the assistant message's `content` with the full text

**Response** `200` with `Content-Type: text/event-stream`:

```
data: {"token":"Ahoj"}

data: {"token":"! Zlomky"}

data: {"token":" jsou"}

data: {"token":" zajímavé..."}

data: [DONE]

```

**SSE format rules:**
- Each event is `data: <json>\n\n` (two newlines)
- Token events: `{"token": "<text chunk>"}`
- Error events: `{"error": "<message>"}` (then continue with `[DONE]`)
- End signal: literal string `[DONE]` (not JSON)
- **No buffering:** Set headers `Cache-Control: no-cache`, `X-Accel-Buffering: no` (for nginx)

**Error handling:**
- If OpenRouter call fails, emit `{"error": "AI generation failed"}` then `[DONE]`
- Still update the assistant message content with whatever was generated before the error
- If `message_id` already has content (reconnection case), the server should either re-stream or return the existing content followed by `[DONE]`

**Response headers:**
```
Content-Type: text/event-stream
Cache-Control: no-cache
Connection: keep-alive
X-Accel-Buffering: no
```

---

### 6. Get Messages (per session)

```
GET /api/chat/sessions/{sessionId}/messages
GET /api/chat/sessions/{sessionId}/messages?since=2026-03-25T12:00:00Z
```

**Response** `200`:
```json
{
  "data": [
    {
      "id": 42,
      "role": "user",
      "content": "Ahoj, jak se učit zlomky?",
      "message_type": "text",
      "metadata": null,
      "feedback_type": null,
      "feedback_detail": null,
      "created_at": "2026-03-25T14:30:00Z",
      "updated_at": "2026-03-25T14:30:00Z"
    },
    {
      "id": 43,
      "role": "assistant",
      "content": "Ahoj! Zlomky jsou zajímavé...",
      "message_type": "text",
      "metadata": null,
      "feedback_type": "like",
      "feedback_detail": null,
      "created_at": "2026-03-25T14:30:01Z",
      "updated_at": "2026-03-25T14:31:00Z"
    }
  ]
}
```

Messages ordered by `created_at ASC`. `since` param filters by `updated_at > since`.

---

### 7. Pull All Messages (cross-session sync)

```
GET /api/chat/messages?since=2026-03-25T12:00:00Z
```

Returns messages from **all sessions** belonging to the authenticated user where `updated_at > since`. Used during periodic sync to discover messages from other devices.

**Response** `200`:
```json
{
  "data": [
    {
      "id": 43,
      "chat_session_id": 1,
      "role": "assistant",
      "content": "...",
      "message_type": "text",
      "feedback_type": null,
      "created_at": "2026-03-25T14:30:01Z",
      "updated_at": "2026-03-25T14:31:00Z"
    }
  ]
}
```

**Note:** Include `chat_session_id` in each message so the client can associate messages with local sessions.

---

### 8. Update Feedback

```
PUT /api/chat/messages/{messageId}/feedback
Content-Type: application/json

{
  "feedback_type": "dislike",
  "feedback_detail": "Informace byla nepřesná"
}
```

**Validation:**
- `feedback_type`: nullable, string, one of `like|dislike` (null to clear)
- `feedback_detail`: nullable, string, max 2000

**Authorization:** Message must belong to a session owned by the authenticated user.

**Response** `200`:
```json
{
  "data": {
    "id": 43,
    "feedback_type": "dislike",
    "feedback_detail": "Informace byla nepřesná",
    "updated_at": "2026-03-25T15:00:00Z"
  }
}
```

---

## System Prompt

The server builds a system prompt injected as the first message in the OpenAI call. The app does NOT send system prompts — the server owns all prompt engineering.

**Template (adapt per persona):**

```
Jsi {persona_name}, AI vzdělávací asistent na platformě EDU-AI.

Student: {user.name}
Úroveň: {user_stats.level}, XP: {user_stats.xp_points}
Aktivní kurzy: {list of user's course names}

Pravidla:
- Odpovídej vždy česky
- Buď povzbudivý, srozumitelný a trpělivý
- Přizpůsob náročnost úrovni studenta
- Pokud student dělá chybu, veď ho k správné odpovědi, neříkej ji rovnou
- Používej Markdown pro formátování (tučné, seznamy, kód)
- Odpovědi by měly být stručné (max 3-4 odstavce), pokud student nepožádá o detailnější vysvětlení

{persona-specific instructions}
```

**Persona-specific instructions:**

| Persona | Extra instructions |
|---------|-------------------|
| `ai_teacher` | General teaching assistant. Covers all subjects. |
| `math_mentor` | Focus on mathematical concepts. Use step-by-step problem solving. Include formulas in LaTeX format. |
| `study_coach` | Help with study techniques, planning, and motivation. Don't solve homework directly. |
| `language_mentor` | Focus on language learning. Correct grammar gently. Provide examples in context. |

**Context data needed from DB:**
- `User` → name
- `UserStats` → level, xp_points (via `user_stats` table for this user)
- `UserCourse` + `Course` → list of course names the student is enrolled in

---

## Context Truncation

The server MUST truncate message history before sending to the AI provider to avoid exceeding the context window. Since OpenRouter supports many models with different context sizes, the truncation should be configurable.

**Strategy:**
1. Always keep the system prompt (first message)
2. Always keep the most recent user message (last message)
3. Fill remaining token budget with messages from newest to oldest
4. Rough token estimation: `character_count / 4` (for Czech text, use `/3` to be safe)
5. Target: `AI_MAX_CONTEXT - AI_MAX_TOKENS - 500` (500 token safety margin)

**Context sizes vary by model** — use the `AI_MAX_CONTEXT` env var (see below):
- `openai/gpt-4o`: 128k context
- `anthropic/claude-sonnet-4`: 200k context
- `google/gemini-2.5-flash`: 1M context
- `meta-llama/llama-4-maverick`: 128k context

In practice, conversations rarely hit these limits — but long sessions with many messages will.

---

## Infrastructure Requirements

### SSE / Streaming

- **No WebSocket needed** — pure HTTP SSE over standard REST
- Server must NOT buffer the response body (disable output buffering)
- **nginx:** Add `X-Accel-Buffering: no` header and ensure `proxy_buffering off;` for the stream route
- **Laravel:** Use `response()->stream()` with `ob_flush(); flush();` after each chunk
- **Timeout:** SSE connection should stay open for up to 120 seconds (max AI generation time). Configure nginx `proxy_read_timeout 120s;` for this route.

### OpenRouter API

OpenRouter provides a **unified OpenAI-compatible API** that proxies to 200+ models (GPT-4o, Claude, Llama, Gemini, Mistral, etc.). This lets us switch models without changing any code — just update the env var.

- **Env vars needed:**
  - `AI_API_KEY` — OpenRouter API key (from https://openrouter.ai/keys)
  - `AI_API_URL` — Base URL (default `https://openrouter.ai/api/v1`)
  - `AI_MODEL` — Model ID in OpenRouter format (default `openai/gpt-4o`). Examples:
    - `openai/gpt-4o` — GPT-4o
    - `anthropic/claude-sonnet-4` — Claude Sonnet 4
    - `google/gemini-2.5-flash` — Gemini 2.5 Flash
    - `meta-llama/llama-4-maverick` — Llama 4 Maverick
  - `AI_MAX_TOKENS` — Max response tokens (default `2048`)
  - `AI_MAX_CONTEXT` — Max context tokens for the chosen model (default `128000`). Used for history truncation.

- **Request format** (identical to OpenAI — that's the point):
  ```
  POST https://openrouter.ai/api/v1/chat/completions
  Authorization: Bearer <AI_API_KEY>
  Content-Type: application/json
  HTTP-Referer: https://edu-ai.eu
  X-Title: EDU-AI

  {
    "model": "openai/gpt-4o",
    "messages": [...],
    "stream": true,
    "max_tokens": 2048
  }
  ```

- **Required headers for OpenRouter:**
  - `Authorization: Bearer <key>` — standard
  - `HTTP-Referer: https://edu-ai.eu` — required by OpenRouter for app identification
  - `X-Title: EDU-AI` — shows in OpenRouter dashboard for tracking

- **Streaming:** Identical to OpenAI — `stream: true` returns SSE chunks with `choices[0].delta.content`. Parse and forward to client.

- **Error handling:**
  - `429` (rate limit) → retry with exponential backoff (max 3 retries), then return error to client
  - `402` (insufficient credits) → return error to client immediately, log alert
  - `500`/`503` (provider error) → return error to client immediately
  - Timeout → return error after 60 seconds of no response from OpenRouter
  - OpenRouter may return `error.metadata.provider_name` — log this for debugging which upstream provider failed

### Rate Limiting

- **Per user:** 20 messages per minute (on the `POST /messages` endpoint)
- **Global:** Consider a daily token budget per user if cost is a concern
- Return `429` with `retry_after` header

### Security

- Verify session ownership on every endpoint (`session.user_id === auth_user.id`)
- Sanitize user message content (no XSS in stored content, though it's rendered as Markdown)
- Do NOT store OpenRouter API key in the database or expose it to clients
- Log AI interactions for moderation/audit (session_id, user_id, timestamp, token count, model used)
- OpenRouter provides usage tracking at https://openrouter.ai/activity — useful for cost monitoring

---

## Error Response Format

Follow the existing API pattern:

```json
// Validation error (422)
{
  "message": "The content field is required.",
  "errors": {
    "content": ["The content field is required."]
  }
}

// Auth error (401)
{ "message": "Unauthenticated." }

// Not found (404)
{ "message": "Session not found." }

// Rate limit (429)
{ "message": "Too many messages. Please wait.", "retry_after": 30 }

// Server error (500)
{ "message": "An error occurred." }
```

---

## Summary of Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/chat/sessions` | List user's sessions (supports `?since=`) |
| POST | `/api/chat/sessions` | Create new session |
| DELETE | `/api/chat/sessions/{id}` | Delete session + messages |
| GET | `/api/chat/sessions/{id}/messages` | Get session messages (supports `?since=`) |
| POST | `/api/chat/sessions/{id}/messages` | Send user message → returns user + assistant msg IDs |
| GET | `/api/chat/sessions/{id}/stream` | SSE stream for assistant response (`?message_id=`) |
| GET | `/api/chat/messages` | Pull all new messages cross-session (`?since=`) |
| PUT | `/api/chat/messages/{id}/feedback` | Update like/dislike on a message |
