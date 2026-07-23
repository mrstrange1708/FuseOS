# server — FuseOS control plane

Node 22 + TypeScript + Fastify. Handles auth (Better Auth), the device registry, pairing, presence + LAN signaling (`ws` at `/signal`), and durable jobs (Inngest). Talks to PostgreSQL via Drizzle.

**This is a control plane only — no clipboard or file payloads pass through here.** See [../docs/api.md](../docs/api.md), [../docs/schema.md](../docs/schema.md).

## Running
From the repo root: `pnpm dev` (or `pnpm --filter server dev`) — listens on `:3000`. The native clients (`../clients`) point at this. Use `pnpm`, not `npm`/`yarn` (this is a pnpm workspace).

## Database (Drizzle + Postgres)
Set `DATABASE_URL` in `server/.env` (Neon Postgres; gitignored, loaded via `process.loadEnvFile()`). Schema lives in `src/db/schema.ts`, the lazy client in `src/db/client.ts`. From the repo root:
- `pnpm db:generate` — generate a migration from the schema (drizzle-kit).
- `pnpm db:migrate` — apply migrations to the database.

## Auth
`src/auth/dev-auth.ts` implements `POST /auth/sign-up/email` and `POST /auth/sign-in/email` (scrypt-hashed passwords) so the clients have a real login system today. Sign-up requires `name` (1–100 chars), `email`, and `password` (min 8); sign-in requires `email` + `password`. Accounts are **persisted in Postgres** (the `dev_auth_users` table), so they survive server restarts. **It is a dev stand-in** — to be replaced by **Better Auth + PostgreSQL** (the source of truth) per the design. Tests (`src/auth/dev-auth.test.ts`) run against the database and skip when `DATABASE_URL` is unset (e.g. in CI).

Status: auth, the device registry, pairing by code, and the `/signal` presence socket are all implemented and DB-backed. The clients now open direct encrypted LAN channels to each other using the `lanAddress` and `publicKey` that `/signal` relays — no payload has ever reached this server, which is the point.

Still to come here: Better Auth replacing the dev stand-in, the four Inngest functions, and `DELETE /devices/:id`.
