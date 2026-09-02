# mediaremote-adapter (vendored)

Source: https://github.com/ungive/mediaremote-adapter — BSD 3-Clause, Copyright (c) 2025 Jonas van den Berg and contributors.

macOS 15.4+ only lets entitled system binaries talk to the private MediaRemote framework. This adapter loads a tiny helper framework inside `/usr/bin/perl` and streams Now Playing JSON to stdout. NotchUsage runs it as a child process to show what YouTube Music (or any Now Playing source) is playing.

`build-framework.sh` is our CMake-free build (clang only). Output goes to `build/` and is copied into `NotchUsage.app/Contents/Resources/` by `Scripts/build-app.sh`.
