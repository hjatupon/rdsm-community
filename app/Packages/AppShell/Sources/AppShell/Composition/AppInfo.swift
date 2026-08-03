import Foundation

/// Per-edition app identity, read from the running bundle.
///
/// `AppShell` is shared by both editions (RDSM Community and RDSM Pro), so it must
/// never hardcode a product name. Each app target supplies its own
/// `CFBundleDisplayName`, and the shell renders whatever it finds.
public enum AppInfo {
    /// User-facing app name, e.g. "RDSM Community" or "RDSM Pro".
    public static var displayName: String {
        let info = Bundle.main.infoDictionary
        return (info?["CFBundleDisplayName"] as? String)
            ?? (info?["CFBundleName"] as? String)
            ?? "RDSM"
    }

    /// Marketing version, e.g. "1.0".
    public static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    /// Build number, e.g. "1".
    public static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    /// Documentation site.
    public static let docsURL = URL(string: "https://rdsm.app/docs")!

    /// Support contact address.
    public static let supportEmail = "jatupon.h@icloud.com"
}
