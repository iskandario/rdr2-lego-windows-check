# First slice: RDR-inspired slow time in AC Unity

- Host: user's Steam Assassin's Creed Unity (289650), native x64 AnvilNext. Install path not provided. Report photograph shows build 21970519; game-version resource is null. Exact binary identity not yet machine-verified.
- Guest inspiration: user's Steam RDR2 (1174180), 1.0.1491.50. No guest process, hooks, online interaction or copied assets.
- Method: universal-modder intake/recon/source-of-truth/vertical-slice workflow. No direct game-binary decompilation has occurred.
- Candidate dependency: antr1x/ACUFixes, pinned 80c41d4719362493ddac97e3a4a23b5e23094fa5, advertised Unity 1.5.1 / plugin API 0.9.4.0. User EXE compatibility remains unconfirmed.
- Source route: custom controller integrated into the existing gameplay plugin; use its existing time setter/world clock. No invented memory addresses; no changes to loader, protection logic or version gating.
- Offline requirement: single-player only. Dependency changes an integrity-check thread; its classification and compatibility must be reviewed before installation. Do not bypass DRM, anti-cheat or ownership checks. Our user checkbox is not a network-state detector.
- Lab: actual Windows saves/config paths are not known yet; no backup or modded launch has been performed. Before installation obtain approval and back up with `um backup create`, recording the exact restore path. Do not guess or overwrite saves.
- Compile gate: Windows 2022 C++ build tools. Build only the gameplay DLL into a fresh scratch checkout. No automatic install. Never ship extracted NewAnimations/game data as part of this source package.
- Runtime oracle: real Unity footage/logs showing normal time, F6 hold/release, charge exhaustion/recharge, F7 off, pause, Alt-Tab and location change. Also inspect existing upstream gameplay settings to prevent unrelated changes. Do not hot-unload through external loader controls while time is modified.
- Progress: portable C++ controller tests and source integration passed. Native Windows compilation and all in-game acceptance steps remain open. Full RDR2 character/world crossover is not implemented.
- Publication: user authorized the source upload to the existing public GitHub repository after preparation. No compiled-gameplay claim; third-party source/loader not bundled.
