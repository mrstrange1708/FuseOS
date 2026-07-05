# server — FuseOS control plane

Node 22 + TypeScript + Fastify. Handles auth (Better Auth), the device registry, pairing, presence + LAN signaling (`ws` at `/signal`), and durable jobs (Inngest). Talks to PostgreSQL via Drizzle.

**This is a control plane only — no clipboard or file payloads pass through here.** See [../docs/api.md](../docs/api.md), [../docs/schema.md](../docs/schema.md).

## Running
From the repo root: `pnpm --filter server dev` (listens on `:3000`). The native clients (`../clients`) point at this.

## Auth
`src/auth/dev-auth.ts` implements `POST /auth/sign-up/email` and `POST /auth/sign-in/email` (scrypt-hashed passwords) so the clients have a real login system today. **It is a dev stand-in** — an in-memory store that resets on restart — to be replaced by **Better Auth + PostgreSQL** (the source of truth) per the design. Tests: `src/auth/dev-auth.test.ts`.

Status: auth flow working; device registry, pairing, and `/signal` come next.
