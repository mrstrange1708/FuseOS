import Foundation
import FuseOSCore

// MARK: - Wire models (see docs/api.md)

struct DeviceRegisterRequest: Encodable {
    let name: String
    let platform: String
    let publicKey: String
    let battery: Int?
}

struct DeviceRegisterResponse: Decodable {
    let id: String
    let name: String
    let platform: String
}

struct DeviceItem: Decodable, Identifiable {
    let id: String
    let name: String
    let platform: String
    let online: Bool
    let battery: Int?
    let trusted: Bool
    let isSelf: Bool
}

struct DeviceListResponse: Decodable {
    let devices: [DeviceItem]
}

// MARK: - Authenticated control-plane client

/// Talks to the FuseOS control plane with the caller's bearer token. Identity,
/// device registry, and pairing only — never clipboard/file payloads.
struct ControlPlane {
    /// Registers (idempotently) this device and returns its stable server id.
    ///
    /// A `public_key_taken` means this Mac's keypair is still registered to an account
    /// someone signed in with earlier. The server must not hand the key over (that's the
    /// guard in `POST /devices`), so the fix is ours: mint a new identity and retry once.
    @MainActor
    static func registerThisDevice(battery: Int?) async throws -> String {
        do {
            return try await register(battery: battery)
        } catch let error as AuthError where error.code == "public_key_taken" {
            try DeviceKey.reset()
            return try await register(battery: battery)
        }
    }

    @MainActor
    private static func register(battery: Int?) async throws -> String {
        let body = DeviceRegisterRequest(
            name: SessionStore.shared.deviceName ?? SessionStore.detectedDeviceName(),
            platform: "macos",
            publicKey: try SessionStore.shared.deviceKey,
            battery: battery,
        )
        let response: DeviceRegisterResponse = try await send(
            path: "/devices", method: "POST", body: body,
        )
        SessionStore.shared.setDeviceId(response.id)
        return response.id
    }

    static func listDevices(selfId: String?) async throws -> [DeviceItem] {
        var path = "/devices"
        if let selfId { path += "?self=\(selfId)" }
        let response: DeviceListResponse = try await send(
            path: path, method: "GET", body: Optional<DeviceRegisterRequest>.none,
        )
        return response.devices
    }

    // MARK: - Transport

    private static func send<Body: Encodable, Response: Decodable>(
        path: String,
        method: String,
        body: Body?,
    ) async throws -> Response {
        guard let url = URL(string: Config.baseURL.absoluteString + path) else {
            throw AuthError(message: "Invalid server URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let token = await SessionStore.shared.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError(message: "No response from the FuseOS server.")
        }
        if (200 ..< 300).contains(http.statusCode) {
            return try JSONDecoder().decode(Response.self, from: data)
        }
        if let apiError = try? JSONDecoder().decode(APIError.self, from: data) {
            throw AuthError(message: apiError.error.message, code: apiError.error.code)
        }
        throw AuthError(message: "Something went wrong (\(http.statusCode)). Is the FuseOS server running?")
    }

}
