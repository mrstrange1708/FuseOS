# FuseOS – Architecture Notes & Design Clarifications

## 1. Difference Between HLD and LLD

### Low-Level Design (LLD)
LLD describes how the system is implemented internally.

It focuses on:
- Database schemas
- API request/response structures
- WebSocket message formats
- Device lifecycle states
- Error handling and constraints

LLD answers:
> How exactly will this system be implemented?

---

### Summary Table

| Aspect | HLD | LLD |
|-----|-----|-----|
| Abstraction level | High | Detailed |
| Focus | System structure | Implementation |
| DB schema | ❌ | ✅ |
| APIs & sockets | ❌ | ✅ |
| State handling | ❌ | ✅ |
| Interview depth | Mid-level | Strong signal |

---

## 2. Core Design Assumptions (V1)

- A user owns **2–3 personal devices**
- Devices belong to the **same user account**
- Clipboard sync is **text-only**
- Real-time sync is required
- Internet connectivity is assumed
- Backend is always the coordinator

These assumptions simplify V1 and keep scope realistic.

---

## 3. Why No “Main Device” Exists

There is **no master or primary device** in FuseOS.

Reasons:
- Any device can go offline
- Devices must work independently
- Central coordination avoids conflicts
- Backend ensures consistency

Each device:
- Manages its own clipboard
- Sends events to backend
- Receives events from backend

---

## 4. Device Ownership Model

- One user → multiple devices
- Devices are peers
- Backend enforces:
  - Ownership
  - Limits
  - Authorization

This prevents:
- Cross-user leaks
- Infinite clipboard loops
- Unauthorized device access

---

## 5. Clipboard Ownership & Loop Prevention

### Clipboard Rules
- Each clipboard event has a `source_device_id`
- Backend broadcasts to all devices except source
- Receiving devices do NOT re-emit received content

This guarantees:
- No infinite loops
- No duplicate propagation
- Clean event flow

---

## 6. Why WebSockets Are Mandatory

Clipboard sync requires:
- Low latency
- Bi-directional communication
- Server push capability

HTTP polling is rejected because:
- High latency
- Battery inefficient
- Poor UX

WebSockets provide:
- Persistent connection
- Instant broadcast
- Scalable real-time sync

---

## 7. Authentication Design Reasoning

JWT-based authentication is used because:
- Stateless backend
- Easy WebSocket integration
- Horizontal scalability

Each request and socket connection:
- Is validated independently
- Uses the same user identity

---

## 8. Device Pairing Design Reasoning

Pairing uses short-lived codes to:
- Avoid QR complexity in V1
- Keep UX simple
- Prevent accidental pairing

Security properties:
- Time-limited
- One-time use
- User-scoped

---

## 9. Backend as Source of Truth

The backend is responsible for:
- User identity validation
- Device ownership mapping
- Clipboard event ordering
- Broadcasting consistency

Clients are intentionally kept thin.

---

## 10. Scalability Notes (Post-V1)

The current design can scale by:
- Horizontal WebSocket servers
- Redis pub/sub for broadcasts
- Database partitioning by user_id

No architectural rewrite is required for V2.

---

## 11. Known Limitations (Accepted for V1)

- No offline clipboard queue
- No encryption beyond TLS
- Clipboard size limit
- No conflict resolution logic

These are consciously postponed.

---

## 12. Interview Explanation Strategy

When explaining FuseOS:

1. Start with the problem
2. Explain peer-device model
3. Justify backend coordination
4. Walk through clipboard flow
5. Mention constraints and trade-offs

Clarity > complexity.

---

## 13. Conclusion

FuseOS V1 is designed to:
- Be simple
- Be correct
- Be extensible

The system avoids over-engineering while maintaining
production-level architectural discipline.