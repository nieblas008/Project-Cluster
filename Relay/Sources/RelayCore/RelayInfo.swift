import ClusterProtocol

public enum RelayInfo {
    public static let version = "0.1.0"

    /// One-line identity string answered to control-plane PINGs; lets the app's
    /// Connectivity Doctor confirm "I reached a compatible relay" in one round trip.
    public static var banner: String {
        "PONG cluster-relayd/\(version) wire=\(ProtocolInfo.wireVersion)"
    }
}
