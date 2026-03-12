import Foundation

extension Bundle {
    /// Custom resource bundle accessor that works in both .app bundles and
    /// unbundled SPM executables (`swift run`).
    ///
    /// SPM's auto-generated `Bundle.module` only checks `Bundle.main.bundleURL`
    /// (the .app root) and a hardcoded build path.  For a properly structured
    /// macOS .app bundle the resources live under `Contents/Resources/`, which
    /// is `Bundle.main.resourceURL` — a path the generated accessor never tries.
    static let appModule: Bundle = {
        let bundleName = "AICP_AICP"

        let candidates = [
            // .app bundle: Contents/Resources/
            Bundle.main.resourceURL,
            // Unbundled SPM executable: next to the binary
            Bundle.main.bundleURL,
        ]

        for candidate in candidates {
            let bundlePath = candidate?.appendingPathComponent(bundleName + ".bundle")
            if let bundlePath, let bundle = Bundle(path: bundlePath.path) {
                return bundle
            }
        }

        // Fallback: use the SPM-generated accessor (works during swift run / swift test)
        return .module
    }()
}
