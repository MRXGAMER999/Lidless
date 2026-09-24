# Lidless

A free, open-source macOS menu bar app for MacBooks used at a desk. It's an alternative to BetterDisplay.

- **Desk Mode** turns the built-in screen off while the lid stays open, so the Mac runs cooler with external displays.
- **Brightness Boost** makes the XDR screen brighter using its HDR headroom, within the panel's real limits.
- **Safety net** always brings the built-in screen back: when displays are unplugged, after a crash, with a panic key, or through a keep-or-revert prompt.

> **Status:** early development. The menu bar popover is done; Desk Mode and Brightness Boost are still being built.

## Requirements

- A Mac with Apple silicon
- macOS 12 Monterey or later

## Build

1. Install Xcode 27 or later.
2. Open `Lidless/Lidless.xcodeproj`.
3. Choose the **Lidless** scheme and press ⌘R.

Run the tests with ⌘U.

## License

The source code is released under the [MIT License](LICENSE).

The app icon artwork (`Lidless/Lidless/AppIcon.icon` and `Lidless/Lidless/Assets.xcassets/AppIconArt.imageset`) is **not** covered by the MIT License. It was made with Arrow by QuiverAI on its free tier, which allows personal, non-commercial use only. If you fork Lidless for anything else, replace the icon with your own.
