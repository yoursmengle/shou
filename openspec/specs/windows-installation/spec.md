# windows-installation Specification

## Purpose

为 Windows 用户提供按处理器架构分发的桌面安装、覆盖升级与卸载体验，同时保持当前用户数据、私有访问控制、精确操作确认及现有能力边界，使安装版与便携版的使用方式可明确区分。

## Requirements

### Requirement: Current-user installation
The system SHALL provide self-contained Windows 11 x64 and ARM64 desktop installers with Start menu and system uninstall entries. Installation SHALL use the current user without requiring administrator privileges. The application SHALL run with the caller's ordinary privileges.

#### Scenario: Install on a clean user profile
- **WHEN** a standard user installs the package matching the system architecture
- **THEN** the application starts without a separately installed .NET or Windows App SDK runtime and without requesting administrator elevation.

### Requirement: User data survives installation lifecycle
The system MUST keep its installation root separate from the existing user configuration, diagnostics and execution records. Installation, replacement upgrade and uninstall MUST preserve those records and their private ACLs.

#### Scenario: Upgrade and uninstall preserve existing data
- **WHEN** a user upgrades the installed application and later uninstalls it
- **THEN** installed application files and registration are removed while pre-existing user data remains byte-for-byte unchanged with its original access restrictions.

### Requirement: Installation does not grant operation authorization
Installation MUST NOT widen filesystem ACLs, take ownership of scan targets, enable existing public mutation gates, install a privileged service or grant reusable cleanup authorization.

#### Scenario: Restricted operation after installation
- **WHEN** the installed application encounters an inaccessible target or a disabled public mutation capability
- **THEN** it reports the existing limitation and performs no unauthorized change.

### Requirement: Channel-correct manual upgrade
The update check SHALL select the exact official release version and matching architecture. Installed applications SHALL offer a Setup download; portable applications SHALL offer a ZIP download. Missing, duplicate, redirected or mismatched assets SHALL be rejected. Downloading SHALL NOT be reported as installation or trigger automatic replacement.

#### Scenario: Installed application checks an update
- **WHEN** a newer official release includes exactly one matching installer
- **THEN** the installed application offers that installer and instructs the user to close Shou and run it, preserving local data.

#### Scenario: Wrong or ambiguous installer
- **WHEN** a release contains only another architecture, an untrusted URL, or duplicate matching installers
- **THEN** no update download is offered.

### Requirement: Verifiable installation artifacts
Installer names and receipts SHALL bind the release version, architecture, exact source and final file hashes. Signed output MUST use Authenticode with a timestamp and pass final signature validation. Unsigned preview output MUST be labelled unsigned and MUST NOT be represented as a verified publisher release.

#### Scenario: Signature verification fails
- **WHEN** configured signing fails or final executable verification does not match the intended publisher
- **THEN** packaging fails and no signed release receipt is produced.

### Requirement: Isolated installation acceptance
Native installation acceptance MUST use generated identities and private temporary data, refuse existing product targets, and verify install, replacement upgrade, ordinary-privilege startup, uninstall and data preservation. Architecture-specific execution and production signing acceptance SHALL be reported separately from cross-building and portable logic checks.

#### Scenario: Generated lifecycle fixture
- **WHEN** the opt-in acceptance script runs
- **THEN** it changes only this run's generated installation identity, retains verification evidence, and confirms the generated product is uninstalled without touching an existing Shou installation or personal records.
