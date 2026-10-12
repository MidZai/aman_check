import Foundation

/// Version shown by the app (when not read from its bundle) and by diskprobe.
/// Must match the VERSION file at the repository root, which build_app.sh and scripts/bundle.sh
/// read; VersionTests checks both stay equal.
public enum AmanVersion {
    public static let current = "1.0.1"
}
