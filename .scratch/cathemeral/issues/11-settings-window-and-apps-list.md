# 11: Settings window and Apps list

**What to build:** A Settings window, opened from the popover's gear and the right-click menu. Its Apps tab lists every saved app setting alphabetically: icon, name, level slider and a remove button (the same as "Use default"). Apps that are no longer installed appear greyed out. Apps without a bundle ID show by their file name. A slider here behaves like any other: live if its app owns a display, otherwise it only saves. Settings also shows the manual recovery steps for a screen stuck dim, matching the README.

**Blocked by:** 04 (Saved app settings and default level)

**Status:** ready-for-agent

- [ ] Every saved app setting appears in the Apps list, including apps that aren't running.
- [ ] Changing a level there takes effect live if the app owns a display, and is saved either way.
- [ ] Remove deletes the app setting, and the app then follows the default level.
- [ ] Uninstalled apps are greyed out.
- [ ] The recovery steps are shown in Settings.
