# Cathemeral

Cathemeral is a macOS menu bar app that dims each display to a level the user has chosen for the app currently in front on that display.

## Language

### Apps

**App**:
A program macOS identifies by its bundle ID, or by its executable path if it has none. Web apps installed to the Dock and beta or alternate builds each count as separate apps.
_Avoid_: application, process, program

### Dimming

**Level**:
How far an app's content is dimmed, from 10% (dimmest allowed) to 100% (not dimmed). It darkens the image on top of the system brightness and never makes it brighter.
_Avoid_: brightness, dimness, opacity

**App setting**:
The level the user has saved for one app. An app has either its own app setting or uses the default level, and "Use default" removes the app setting.
_Avoid_: profile, preset, rule

**Default level**:
The level for any app the user has not given its own level. It applies only to an app that owns a display, never to an unowned display.
_Avoid_: default brightness, global level

**Master switch**:
Turns all dimming off and back on. While it's off, every display shows 100%, and app settings can still be changed for later. The menu calls it Enable/Disable.
_Avoid_: disabled display, global toggle

**System brightness**:
The display's backlight setting, controlled by macOS through the brightness keys and Control Center. This app never changes it.
_Avoid_: display brightness, backlight level

### Displays

**Display owner**:
The app whose level a display shows. It is the app most recently brought to the front on that display or, once that app has left, the app with the topmost visible window there. Each display has at most one owner, and focus moving to another display does not change it. An app stops owning a display as soon as it has no visible window there, whether it quit, hid, minimised, closed its windows or moved them away.
_Avoid_: active app, focused app, current app

**Ignored app**:
A system app that never becomes a display owner, so bringing it to the front leaves every display as it was. The list is fixed: Spotlight, the Dock, Notification Center, the login window and this app itself. Users cannot edit it.
_Avoid_: excluded app, blacklisted app

**Paused display**:
A display whose colours another app (such as f.lux or a calibration tool) has taken over, so this app stops dimming it. It stays paused until the user chooses Resume, and other displays carry on as normal.
_Avoid_: conflicted display, disabled display, gamma fight

**Unsupported display**:
A display where dimming doesn't take, such as some HDR, Sidecar or AirPlay displays. It is marked "unsupported" and tried again when displays next change.
_Avoid_: incompatible display, broken display

**Unowned display**:
A display with no app windows visible on it, such as an empty desktop Space. It shows at 100%, not the default level.
_Avoid_: idle display, default display
