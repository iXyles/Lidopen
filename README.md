# Lidopen

Lidopen is a personal macOS menu bar utility that watches display changes and can disable the built-in display when selected external monitors are connected.

## Why This Exists

This tool was built for a very specific setup: using an ultrawide external monitor while still keeping the MacBook open so the built-in camera, microphone, and speakers remain available.

It exists because that single behavior was the only feature needed, and building a small dedicated utility was preferable to relying on a larger commercial display-management app just for that one capability.

## Project Description

- Product: menu bar app for macOS
- Purpose: automate built-in display behavior based on connected monitor rules
- Architecture: Swift Package with a small app target (`Lidopen`) and a core module (`LidopenCore`)
- UI: AppKit menu bar app with a SwiftUI settings window
- Display control approach: private CoreGraphics / CGS display APIs

## Status

This is a personal sideloaded utility. It is not designed as an App Store distribution target.

## Built And Tested On

- Hardware: Apple Silicon (`arm64`)
- macOS: 26.5.2
- Xcode: 26.5
- Minimum deployment target: macOS 13

Because the app depends on private display APIs, behavior may vary across macOS releases and hardware.

## Build

Build the package:

```bash
swift build
```

Build the app bundle:

```bash
./Scripts/build_app.sh
```

If SwiftPM cache or manifest sandboxing is restricted in your environment:

```bash
CLANG_MODULE_CACHE_PATH=/private/tmp/clang-mod \
SWIFT_MODULE_CACHE_PATH=/private/tmp/swift-mod \
swift build
```

The same override works for app bundle packaging:

```bash
CLANG_MODULE_CACHE_PATH=/private/tmp/clang-mod \
SWIFT_MODULE_CACHE_PATH=/private/tmp/swift-mod \
./Scripts/build_app.sh
```

The generated bundle is written to `dist/Lidopen.app`.

To build and install into `/Applications`:

```bash
./Scripts/build_app.sh --install
```

## Run

Run the app target directly:

```bash
swift run Lidopen
```

Or open the packaged app:

```bash
open "dist/Lidopen.app"
```

## Test

Run the test suite:

```bash
swift test
```

## How It Works

- `Manual` mode never changes display state automatically.
- `Auto` mode evaluates active external monitors against saved rules.
- Unknown external monitors default to safe behavior and keep the built-in display active until a rule is saved.
- The built-in display toggle is attempted through the private `CGSConfigureDisplayEnabled` symbol inside a CoreGraphics display configuration transaction.

## Limitations

- Uses private APIs, so it is not App Store-safe.
- May break across macOS updates.
- Should be treated as a local utility, not a broadly portable product.

## LLM Note

This app was built with substantial help from LLM tooling. The code, structure, and documentation were iterated through human-directed AI-assisted development.

## Project Layout

```text
Sources/
  LidopenCore/
  Lidopen/
Tests/
  LidopenCoreTests/
Package.swift
```
