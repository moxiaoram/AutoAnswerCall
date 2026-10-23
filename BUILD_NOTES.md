# Build and verification notes for 0.4.2

Expected local checks:
- C11 battle controller compiled with `-Wall -Wextra -Werror`; seven state-machine test groups passed (synthetic inputs only).
- Python analyzer tests and evidence-baseline tests pass.
- Static diagnostics/UI consistency checks cover the observation APIs, runtime baseline injection, fail-closed contract, five-second loot-growth scheduler, and bounded loop.

Not performed in this environment: iOS SDK/Theos compilation, `.deb` packaging, injection, ABI verification, live-game integration, real search/deployment/end/return-home actions, device layout checks, crash recovery, or concurrent Hook stress testing. No iOS SDK/Theos is configured here.

The supplied log does not contain verified action APIs or actual scene/resource/troop samples. The evidence fixture deliberately excludes raw argument words, pointer-like values, caller offsets, and inferred action mappings.
