Rockxy source reference
=======================

The Network debugger module is allowed to reuse Rockxy internals for this
private/internal build. Keep Rockxy-derived files in this folder or preserve a
short source note in the Swift file that was adapted.

Primary upstream repository:
https://github.com/RockxyApp/Rockxy

The current in-app proxy implementation is a compact first-pass adapter shaped
after Rockxy's SwiftNIO proxy architecture, with the rest of the Rockxy feature
surface intentionally staged behind the Network UI.

