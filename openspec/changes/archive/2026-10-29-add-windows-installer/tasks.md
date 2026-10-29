# Tasks

## 1. Application lifecycle and upgrade channel

- [x] 1.1 Pin the common stable Velopack app/tool versions, restore dependency locks, and initialize lifecycle handling before WinUI with startup auto-apply disabled; verify locked restore and both publish targets.
- [x] 1.2 Select exact Setup assets for installed apps and ZIP assets for portable apps, update the existing dialog and source localizations, and cover both channels, architecture mismatch, duplicate and untrusted assets in Core/Platform tests.
- [x] 1.3 Update bilingual installation/update and interface contracts for manual installed upgrades, ordinary privileges and preserved private data; verify documentation and generated localization checks.

## 2. Installer packaging and distribution

- [x] 2.1 Implement x64/ARM64 per-user installer packaging from existing validated App payloads using the separate Limecloud.Shou identity, source-bound receipts and final checksums; verify positive and rejection paths with generated packaging tests and actual Setup outputs.
- [x] 2.2 Add explicit optional Authenticode/timestamp signing with intended-certificate and final-byte verification, fail closed on signing errors, and accurately label unsigned previews; verify validation and signing precondition rejection paths.
- [x] 2.3 Extend release workflow attachment/checksum handling and bilingual release/platform documentation; verify workflow structure, archive regression tests and documentation checks.

## 3. Isolated installation acceptance

- [x] 3.1 Add an opt-in generated-identity installation/upgrade/start/uninstall acceptance script that refuses real product targets, isolates private data and retains hash/ACL evidence; verify PowerShell syntax and rejection paths.
- [x] 3.2 Run generated lifecycle acceptance on available native Windows architecture with ordinary privileges, check registration/shortcuts, closed gates, data and ACL preservation, and record actual evidence and unavailable architecture/signing checks in SYNC.md.

## 4. Integration verification

- [x] 4.1 Run relevant Core/Platform/Presentation/CLI checks, actual x64/ARM64 publish and installer builds, Python packaging regressions, resource/localization/document checks, git diff checks and strict OpenSpec validation; record genuine failures and limitations without opening capability gates.

## Workflow follow-up

- Trusted production signing, the other architecture's native lifecycle, SmartScreen and full accessibility acceptance remain separately evidenced release qualifications when the required certificate/hardware is available.
- Archive only after the implementation and available acceptance evidence have been reviewed.
