# Contributing to Traqula

Thanks for helping. Traqula is small on purpose, so most contributions are quick to review.

## Setting up

```sh
brew install xcodegen
xcodegen generate
open Traqula.xcodeproj
```

Requires macOS 26 and Xcode 26. Run the tests with ⌘U in Xcode or:

```sh
xcodebuild -project Traqula.xcodeproj -scheme Traqula -configuration Debug test
```

## Ground rules

- **Everything stays on-device.** Pull requests that send audio or transcripts to a network service
  will not be merged into the core app. A pluggable `Translator` or `AudioSource` behind the existing
  protocols is welcome as long as the on-device path stays the default.
- **Swift 6, strict concurrency.** The project builds with complete concurrency checking; keep it clean.
- **Say why in the code.** Non-obvious decisions (like the speech module choice) carry a comment with
  the measurement or reason behind them. Follow that style rather than adding docs elsewhere.
- **Icons are code.** Edit `Tools/render-icon.swift` and re-run it; do not hand-edit the PNGs.
- **Keep `project.yml` the source of truth.** The `.xcodeproj` is generated and git-ignored.

## Reporting bugs

Open an issue with your macOS version, the meeting app you were captioning, the language pair, and what
the caption window showed. Transcripts are stored under
`~/Library/Application Support/Traqula/Meetings/`; attach an excerpt only if you are comfortable sharing it.

## Pull requests

1. Open an issue first for anything bigger than a fix, so the scope is agreed before the work.
2. Add or update a test when the change touches `CaptionTimeline`, `MeetingRecord`, or anything else that
   can be tested without audio hardware.
3. Make sure CI is green.
