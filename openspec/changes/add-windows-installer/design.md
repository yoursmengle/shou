# Design

## Context

See proposal.md for motivation. Windows publishes separate self-contained App/CLI folders with ZIP validation and final hashes. The existing updater validates exact official GitHub ZIP assets. The App already has a custom STA Main, an asInvoker manifest, and user/SYSTEM-only record ACLs. Public cleanup, uninstall and startup mutation gates remain closed.

## Goals / Non-Goals

**Goals:** Reuse the publish folders and existing update validation, provide native per-user installation lifecycle, keep user data outside replaceable program files, and make signing status observable.

**Non-Goals:** Per-machine deployment, UAC relaunch, privileged services, automatic background updates, opening public mutation gates, desktop-managed npm CLI installation, or migrating existing user records.

## Decisions

1. **Pinned Velopack app package and local vpk tool.** The existing Windows plan already names Velopack. Use a common stable pinned version and the current custom Main; run lifecycle handling before diagnostics/WinUI initialization and disable startup auto-apply. Retain WinRT/STA setup. Alternative: inventing a hand-written copier/uninstaller duplicates platform lifecycle handling; MSIX would introduce package identity and a broader deployment change.
2. **Installation ID `Limecloud.Shou`.** Default installation is `%LOCALAPPDATA%/Limecloud.Shou`; data remains `%LOCALAPPDATA%/Shou`. Velopack removes its installation root on uninstall, so packId `Shou` would overlap existing data and is rejected. No installation hook creates data directories or repairs ACLs.
3. **Manual Setup upgrades.** Detect installed/portable status through Velopack, choose exact `Shou-<version>-windows-<arch>-Setup.exe` or existing ZIP through the same bounded metadata parser, and open the download in the browser only on request. No updater download/apply loop is introduced. Existing method callers retain a portable default.
4. **One packaging entry layered on existing build output.** Validate payload architecture/version before vpk packing, preserve notices/license and a source-bound BUILD receipt, reject stale output, and copy only explicitly expected Setup files to release assets. Keep ZIP/CLI validation intact. The release workflow publishes only files named in verified checksum manifests.
5. **Explicit signing mode.** A certificate thumbprint from the current-user certificate store can enable SHA-256 Authenticode with an HTTPS timestamp server. Use native signing tools with argument arrays; never store or print a key or password. Validate publisher identity, signature status and timestamp after signing, then hash final bytes. Without credentials produce explicitly unsigned preview output, retaining the existing preview status. Trusted production signatures require separate real certificate acceptance.
6. **Generated native lifecycle fixture.** An opt-in script creates a random acceptance packId and isolated private data roots, packs two ordered versions from the same current payload, refuses collisions/existing identities and only uninstalls its generated product. Run standard-user acceptance separately from elevated build hosts. Retain install/upgrade/uninstall receipts, hashes and ACL/data-preservation observations. Real personal software is never the target.

## Risks / Trade-offs

- Uninstaller removes its full installation root → fixed non-overlapping ID and lifecycle data-preservation checks.
- Installer startup/update hooks could replace an executing application → disable startup auto-apply and require completing/stopping work and closing Shou before manual upgrades. Velopack external replacement/uninstall can force-stop processes before hooks; hooks cannot veto this. Document the limitation and do not describe it as normal in-app shutdown.
- Installed/portable misclassification → use framework installation state, keep strict exact-asset validation, and cover both channels in tests.
- New dependency/tool version or ARM64 compatibility → pin both versions, restore locks, verify real outputs and report each architecture's runtime evidence independently.
- No production signing certificate is available locally → implement and validate fail-closed signing support, label unsigned artifacts accurately, retain trusted-signing acceptance as an explicit release gap.
- Build host may lack the pinned SDK → provision a task-local SDK without modifying machine defaults; missing native UI access must remain an explicit validation gap.

## Migration Plan

Existing portable users may install the Setup for their architecture; the data location stays unchanged. Installed users run a newer Setup after closing Shou. ZIP remains available with its existing manual replacement behavior. Uninstall removes program files and registration but retains user data. Rollback uses an explicitly selected previously verified installer without changing data or replaying any cleanup plans.
