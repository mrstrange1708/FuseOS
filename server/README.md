# server — FuseOS control plane

Node 22 + TypeScript + Fastify. Handles auth (Better Auth), the device registry, pairing, presence + LAN signaling (`ws` at `/signal`), and durable jobs (Inngest). Talks to PostgreSQL via Drizzle.

**This is a control plane only — no clipboard or file payloads pass through here.** See [../docs/api.md](../docs/api.md), [../docs/schema.md](../docs/schema.md).

Status: scaffold. Implementation begins in the first build milestone (see the plan / `../docs/`).
