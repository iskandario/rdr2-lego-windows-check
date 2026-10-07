# RDR2-inspired mechanic in Assassin's Creed Unity — 2026-10-07

## Evidence and limits

- User owns the Steam games and supplied photographs of the local checker's report.
- RDR2: Steam 1174180, build 13773296, x64, file version 1.0.1491.50.
- AC Unity: Steam 289650, build 21970519, x64, EXE length 37458616; version resources are null. Transcribed from photo, not machine-validated JSON. Exact SHA-256 is awaiting the actual report.
- The current execution host is macOS. `universal-modder/bin/um scan "Assassin's Creed Unity" --json` finds no installed game here. No game EXE, live process, frame capture or debugger session is available here.
- Thus this is **community-source analysis**, not a claim that the user's ACU.exe has been decompiled or dynamically reverse engineered.

## Toolkit procedure used

Read universal-modder's AGENTS.md, mod-any-game, game-recon, reverse-engineering, mashup-mods, safety, native and big-framework playbooks. Searched its KB for Assassin, RDR2 and Anvil. The AC-family survey identifies ACUFixes as the mature native route. No RDR2-specific KB result was returned.

## Actual source inspected

Pinned upstream: https://github.com/antr1x/ACUFixes/tree/80c41d4719362493ddac97e3a4a23b5e23094fa5

- `ACUFixes/src/VariousPatches/Hack_SlowMotionTrick.cpp`: exposes existing `ACUSetTimescaleInGameClock`; the built-in trick uses the unpaused/unscaled host clock, time interpolation and a native setter. Slow motion was already implemented by upstream, NOT discovered or invented by this project.
- `CommonLibACU/ACU-RE/src/World.cpp`: `World::GetSingleton()` obtains the world through the player camera component and player entity, with null checks.
- `CommonLibACU/ACU-RE/inc/ACU/Clock.h`: integer clock conversion is 30000 ticks per second.
- `ACUFixes/src/WhatIsDrawnInImGui.cpp`: existing per-frame callback invokes the slow-motion feature. Our integration replaces that invocation, preserving upstream callback timing.
- `CommonLibACU/Common_PluginSide/public_headers/Common_Plugins/ACUPlugin.h`: loader plugin API is 0.9.4.0 in this pin.
- `ACUFixes-PluginLoader/src/dllmain.cpp`: loader checks a memory fingerprint and refuses incompatible games. It claims Unity 1.5.1. Empty EXE version resources are NOT proof of compatibility. We do not remove its version check.
- `ACUFixes-PluginLoader/src/DisableIntegrityChecks.cpp`: dependency terminates an internal integrity-check thread and changes the process debug flag. No such code is implemented or modified here. Its distinction from DRM/anti-cheat has not been established on the user's installation; loader installation/live testing is deferred pending that review, offline setup and approval.

## Chosen route

An original C++ mechanic integrated into the existing ACUFixes gameplay plugin, reusing its world/time API. RDR2 is not injected, launched or used as a second process. No arbitrary retail offsets, game assets or guessed signatures are added. This is a small RDR-inspired gameplay slice, not the full requested world/character crossover.

Original code: charge controller, host adapter, version-pinned source integration and build scripts. The adapter replaces upstream's built-in slow-motion update/menu to avoid two competing writers. Upstream's raw timescale slider is also replaced. The plugin's two explicit unload buttons route through our restore function. Forced external unload is unsupported.

## Verification

- Portable C++17 controller compiled and executed on macOS with clang++ and warnings-as-errors.
- Tests cover key release, pause/Alt-Tab/UI, disabling, world loss/switch, other-timescale-owner detection, exhaustion/recharge, invalid clock deltas and equivalent behaviour at 30/60/144 Hz.
- Source integration applied to a disposable, clean clone at the pinned commit. Only three upstream gameplay source/project files change; two original source files are added. `git diff --check` passes. The loader, proxy and protection code are untouched.
- Controller also passed AddressSanitizer/UndefinedBehaviorSanitizer locally.
- **Not verified:** native Windows adapter compilation; game-loader compatibility; offline safety of dependency; visual HUD; in-game time effect; threading/world-switch races. Logical tests do not prove any of these.

## Next real-game gate

Get actual JSON or exact executable fingerprint, verify matching loader dependency and offline setup, back up saves/configs using `um backup`, obtain approval before installing. Build and test on Windows. Confirm normal speed, hold F6, release, exhaust charge, pause, Alt-Tab, change location and disable. Observe the real game and logs. Do not call the crossover playable before this passes. Character/asset conversion remains a separate unimplemented stage.

After source preparation, the user explicitly authorized uploading this source package to the existing public GitHub repository. This source release does not imply Windows compilation, loader installation or in-game validation.
