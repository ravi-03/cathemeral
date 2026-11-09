/// System apps that never become a display owner, so bringing one to the front leaves every
/// display as it was. The list is fixed; users can't edit it.
public enum IgnoredApps {
    /// Spotlight, the Dock, Notification Center and the login window. Cathemeral itself is added
    /// by the engine, because its ID depends on the build.
    public static let system: Set<AppID> = [
        AppID(bundleID: "com.apple.Spotlight"),
        AppID(bundleID: "com.apple.dock"),
        AppID(bundleID: "com.apple.notificationcenterui"),
        AppID(bundleID: "com.apple.loginwindow"),
    ]
}
