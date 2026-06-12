/// Versioning for everything that crosses the wire.
public enum ProtocolInfo {
    /// Bumped on any incompatible change to message encodings.
    /// Host and joiners refuse to pair across different versions.
    /// v2: welcome gained mapVersion + UDP policy; world/datagram space added (ADR 0002).
    public static let wireVersion: UInt16 = 2
}
