/// Versioning for everything that crosses the wire.
public enum ProtocolInfo {
    /// Bumped on any incompatible change to message encodings.
    /// Host and joiners refuse to pair across different versions.
    public static let wireVersion: UInt16 = 1
}
