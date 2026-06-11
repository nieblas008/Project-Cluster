import Foundation

/// Where the relay lives. No DNS: a static IP and a pinned certificate
/// fingerprint (SHA-256 of the DER cert, lowercase hex) are the whole story.
public struct RelayEndpoint: Equatable, Sendable {
    public var host: String
    public var controlPort: UInt16
    public var udpPort: UInt16
    public var certFingerprint: String

    public init(host: String, controlPort: UInt16 = 7600, udpPort: UInt16 = 7601, certFingerprint: String) {
        self.host = host
        self.controlPort = controlPort
        self.udpPort = udpPort
        self.certFingerprint = certFingerprint.lowercased()
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    public var isConfigured: Bool {
        !host.isEmpty && certFingerprint.count == 64
    }
}
