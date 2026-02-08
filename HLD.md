# FuseOS – High Level Design (HLD)
**Version:** v1.0  
**Status:** Initial Design  
**Scope:** Authentication, Device Connectivity, Clipboard Sync

---

## 1. Purpose & Scope

FuseOS v1 establishes a secure and low-latency bridge between macOS and Android devices.  
The primary objective of this version is to validate reliable cross-device communication through:

- Secure user authentication
- Trusted device pairing and connectivity
- Real-time clipboard synchronization (copy–paste)

This version is intentionally minimal and foundational. Advanced features are explicitly out of scope.

---

## 2. System Overview

FuseOS follows a **local-first architecture** where devices communicate directly whenever possible.  
An optional backend is used only for identity and authentication purposes.

### Design Principles
- Local network–first communication
- Persistent encrypted connections
- Minimal latency
- Explicit user consent and control

---

## 3. System Components

### 3.1 macOS Client
A native macOS application responsible for:
- User authentication
- Device pairing approval
- Clipboard monitoring and injection
- Secure connection management

---

### 3.2 Android Client
A native Android application with background services responsible for:
- User authentication
- Clipboard monitoring
- Connection initiation
- Secure event transmission

---

### 3.3 Backend (Minimal & Optional)
The backend is used only for:
- User identity management
- Device registration metadata
- Authentication token issuance

**No clipboard data or device communication passes through the backend.**

---

## 4. Authentication Model

### 4.1 User Authentication
- Users authenticate using a single FuseOS account
- Authentication occurs independently on each device
- A short-lived access token is issued upon successful login

---

### 4.2 Device Identity
Each device is assigned:
- A unique device identifier
- A device-specific cryptographic key pair

Device identity is persistent and bound to the user account.

---

## 5. Device Pairing & Trust Establishment

### 5.1 Pairing Flow
1. User initiates pairing on one device
2. A one-time pairing code or QR code is generated
3. The second device verifies the code
4. Devices exchange public keys
5. A trusted relationship is stored locally on both devices

---

### 5.2 Trust Rules
- Pairing requires explicit user approval
- Trusted devices reconnect automatically
- Trust can be revoked manually at any time

---

## 6. Connectivity Model

### 6.1 Connection Type
- Persistent, bidirectional connection
- Transport priority:
  1. Local Wi-Fi
  2. USB (fallback)

---

### 6.2 Connection Lifecycle
- Discover → Authenticate → Establish secure channel → Maintain
- Automatic reconnection on network changes
- Heartbeat mechanism to detect disconnections

---

### 6.3 Security
- End-to-end encrypted communication
- Session-based encryption keys
- Message authentication and integrity verification

---

## 7. Clipboard Synchronization (Core Feature)

### 7.1 Supported Data
- Plain text only

---

### 7.2 Clipboard Monitoring
- Both clients monitor local clipboard changes
- Only user-initiated changes are propagated

---

### 7.3 Synchronization Flow
1. Clipboard change detected on Device A
2. Change event is serialized and encrypted
3. Event is transmitted over the secure channel
4. Device B validates the source
5. Clipboard is updated on Device B
6. Acknowledgment is sent back

---

### 7.4 Conflict Resolution
- Last-write-wins strategy
- Duplicate propagation is suppressed to prevent loops

---

## 8. Latency Considerations

- Persistent connections avoid repeated handshakes
- Clipboard events are event-driven and lightweight
- No polling mechanisms are used
- Backend is never part of the critical data path

Expected behavior: clipboard sync should feel instantaneous under normal network conditions.

---

## 9. Failure Handling

- Temporary disconnections trigger automatic reconnection
- Clipboard sync pauses gracefully during outages
- No indefinite queuing of clipboard events
- User-visible indicators reflect connection state

---

## 10. Non-Goals (v1 Explicit)

- No file transfer
- No screen mirroring
- No remote device control
- No cloud-based clipboard storage
- No multi-device synchronization beyond one-to-one pairing

---

## 11. Success Criteria

FuseOS v1 is considered successful if:
- Devices pair reliably
- Connections remain stable
- Clipboard synchronization is fast and consistent
- User permissions and trust are always explicit