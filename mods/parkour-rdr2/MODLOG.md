# RDR2 traversal prototype — 0.1.0 experimental

## Scope and route (2026-10-07)

The user approved a first RDR2 ledge-grab / hang / pull-up prototype and asked to
commit it. This supersedes the earlier Dead Eye-in-Unity direction. Use the
ScriptHookRDR2 SDK API in a Windows x64 ASI. No retail offsets, binary patching,
DRM changes, online features, or redistribution of game assets/loaders.

Research follows universal-modder's mod-any-game, reverse-engineering and
publish-mod instructions. Its KB has no RDR2-specific parkour implementation.
ACUFixes' ParkourDebugging source describes action selection, but still calls
Unity internals. This prototype is original traversal logic, NOT recovered
Unity code, an animation port, or a complete Assassin's Creed parkour system.

## Sources of truth

- ScriptHookRDR2 SDK API and samples, read locally from Smerdokryl/RDR2_SDK,
  commit ef53fc71e0ad95cfa8e72a63f15e1c6aa38091de. Build-only dependency;
  never package the SDK or ScriptHookRDR2.dll. Publisher: Alexander Blade,
  https://www.dev-c.com/rdr2/scripthookrdr2/
- femga/rdr3_discoveries commit 477aaaccadb7f0c042286611d9939009636cff12:
  animation dictionary/clip names, Arthur foot bone identifiers, input hashes.
  Only identifiers are referenced; no extracted assets are included.
- User's report: RDR2 1.0.1491.50, Steam. Target build, NOT verified compatibility.

## Implementation acceptance boundary

Geometric probes must reject missing/steep tops, moving entities, blocked body
paths, invalid vectors and timeout/invalid native query results. No noclip,
invincibility or edited game archives. Movement stays near a validated ledge.
Input is opt-in; F9 releases owned freeze/animation state. Pause, focus loss,
death, player replacement, loading and network sessions cancel operation.
Animations reuse native RDR2 clips as placeholders; alignment needs game testing.

## Verification

Implemented original collision-query planner, bounded motion controller,
ScriptHookRDR2 adapter, Windows installer and Windows build workflow. Local
clang++ C++17 tests passed with AddressSanitizer/UndefinedBehaviorSanitizer;
PowerShell installer parser check passed. Expanded-box geometry independently
checks that the lift-then-cross route clears a wall while the direct diagonal
does not. Query failures, support rejection, timeout and 30/60/144Hz paths tested.
Windows compilation is the next check. No game runtime is accessible in this
Mac session. Compilation and synthetic tests cannot establish in-game success.
Public package must remain an explicitly unverified prerelease.
