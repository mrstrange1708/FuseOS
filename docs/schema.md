# FuseOS — Database Schema

**Engine:** PostgreSQL · **ORM:** Drizzle · **Auth tables:** Better Auth

The database is the **source of truth for identity only** — users, devices, pairing, and trust. It **never** stores clipboard or file payloads; those are ephemeral and LAN-only. Integrity is enforced in the schema itself (NOT NULL, FK, UNIQUE, CHECK) so bad data cannot land even if application code has a bug.

Design goals: deliberate up-front modeling, additive/backward-compatible migrations only, constraints over conventions.

---

## Entity overview

```mermaid
erDiagram
    users ||--o{ devices : owns
    users ||--o{ pairing_codes : issues
    devices ||--o{ device_trust : "A side"
    devices ||--o{ device_trust : "B side"

    users {
        uuid id PK
        text email UK
        timestamptz created_at
    }
    devices {
        uuid id PK
        uuid user_id FK
        text name
        text platform
        text public_key UK
        timestamptz last_seen
    }
    pairing_codes {
        uuid id PK
        uuid user_id FK
        text code
        timestamptz expires_at
        timestamptz used_at
    }
    device_trust {
        uuid id PK
        uuid device_a FK
        uuid device_b FK
        timestamptz created_at
    }
```

## Tables

### `users` (+ Better Auth tables)
User identity is owned by **Better Auth**, which manages its own tables in our Postgres (typically `user`, `account`, `session`, `verification`). We do **not** hand-roll password storage — Better Auth owns credentials, sessions, and JWT issuance. FuseOS-specific tables below reference the Better Auth user id.

| Column | Type | Constraints |
| --- | --- | --- |
| `id` | uuid | PK |
| `email` | text | NOT NULL, UNIQUE |
| `created_at` | timestamptz | NOT NULL, default `now()` |

> **Dev stand-in — `dev_auth_users` / `dev_auth_sessions`.** Until Better Auth is
> wired, the dev-auth login (`server/src/auth/dev-auth.ts`) persists accounts in a
> `dev_auth_users` table (`id`, `email` UNIQUE, `name` NOT NULL + length CHECK,
> `password_salt`, `password_hash`, `created_at`) and issues opaque bearer tokens
> stored in `dev_auth_sessions` (`token` PK → `user_id`). Both are defined in
> `server/src/db/schema.ts` and are **temporary** — dropped once Better Auth owns
> credentials, sessions, and JWTs.
>
> For the same reason, the `devices`, `pairing_codes`, and `device_trust` tables
> below currently FK to `dev_auth_users(id)` (not a real `users` table yet); the
> FK target moves to the Better Auth user id when it lands.

### `devices`
One row per registered device. A user has 2–3 in v1.

| Column | Type | Constraints |
| --- | --- | --- |
| `id` | uuid | PK, default `gen_random_uuid()` |
| `user_id` | uuid | NOT NULL, FK → users(id) ON DELETE CASCADE |
| `name` | text | NOT NULL, CHECK (`length(name) between 1 and 100`) |
| `platform` | text | NOT NULL, CHECK (`platform in ('android','macos')`) |
| `public_key` | text | NOT NULL, UNIQUE |
| `battery` | int | nullable, CHECK (`battery is null or battery between 0 and 100`) — presence metadata, never payload |
| `last_seen` | timestamptz | nullable |
| `created_at` | timestamptz | NOT NULL, default `now()` |

Indexes: `(user_id)` for registry listing.

### `pairing_codes`
Short-lived, one-time, user-scoped pairing codes.

| Column | Type | Constraints |
| --- | --- | --- |
| `id` | uuid | PK |
| `user_id` | uuid | NOT NULL, FK → users(id) ON DELETE CASCADE |
| `device_id` | uuid | NOT NULL, FK → devices(id) ON DELETE CASCADE — the initiator (device A) |
| `code` | text | NOT NULL, CHECK (`length(code) between 6 and 12`) — 8 chars in practice |
| `expires_at` | timestamptz | NOT NULL, CHECK (`expires_at > created_at`) |
| `used_at` | timestamptz | nullable |
| `created_at` | timestamptz | NOT NULL, default `now()` |

Constraints/indexes:
- Partial UNIQUE on `code` **where `used_at is null and expires_at > now()`** — an active code is unique; expired/used codes may be pruned.
- Index `(user_id)`.
- Expiry is enforced logically at claim time **and** swept by an Inngest job (belt and suspenders).

### `device_trust`
A trusted, bidirectional relationship between two of a user's devices (established at pairing).

| Column | Type | Constraints |
| --- | --- | --- |
| `id` | uuid | PK |
| `device_a` | uuid | NOT NULL, FK → devices(id) ON DELETE CASCADE |
| `device_b` | uuid | NOT NULL, FK → devices(id) ON DELETE CASCADE |
| `created_at` | timestamptz | NOT NULL, default `now()` |

Constraints:
- CHECK (`device_a <> device_b`) — no self-trust.
- CHECK (`device_a < device_b`) — canonical ordering so a pair is stored once.
- UNIQUE (`device_a`, `device_b`) — no duplicate trust rows.
- Application-level guard: both devices must belong to the same `user_id` (a device can only be trusted with its owner's other devices).

## What is deliberately NOT here

- **No `clipboard_events` table. No `files` table.** Clipboard content and files are ephemeral and travel LAN-direct (see [protocol.md](protocol.md)). Storing them would violate the latency and privacy invariants and put user payloads in the DB.
- No analytics/event log of payloads.

## Migrations

- Generated with Drizzle (`pnpm db:generate`), applied with `pnpm db:migrate`.
- **Additive first:** new nullable columns, new tables, new indexes are safe. Renames/drops require a real reason and a backfill plan.
- Constraints ship *with* the table that needs them — never rely on application logic for an invariant a CHECK/FK/UNIQUE can guarantee.
