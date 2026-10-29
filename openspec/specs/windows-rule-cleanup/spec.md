# windows-rule-cleanup Specification

## Purpose

明确 Windows 规则清理如何在部分扫描覆盖下向用户呈现可处理项目，区分文件占用、预算缺口与平台能力，并将明确选择绑定到经过实时复核的当前确认执行，使可处理目标能够安全完成清理。

## Requirements

### Requirement: Scoped native rule cleanup availability
The application and CLI SHALL permit permanent rule cleanup on a native Windows 11 x64 host. Other hosts and unrelated unaccepted mutation capabilities MUST remain unavailable, and discovery and package metadata MUST describe this scope accurately.

#### Scenario: Eligible selection on supported host
- **WHEN** a user selects complete unblocked rule targets on native Windows 11 x64 and explicitly invokes permanent cleanup
- **THEN** the application SHALL prepare the exact selected plan, confirm its current scope, revalidate it and record per-item outcomes

#### Scenario: Unsupported or unrelated execution
- **WHEN** the host is unsupported or the requested plan is for storage removal rather than rule cleanup
- **THEN** the rule-cleanup entry point MUST reject execution before confirmation or mutation
- **AND** privacy, application-uninstall and startup-control availability MUST remain unchanged

### Requirement: Partial coverage preserves independent eligible targets
A partial scan SHALL retain coverage issues and allow explicit selection and planning of independent complete unblocked rule targets. Incomplete, protected, read-only or changed targets MUST NOT become eligible, and partial coverage MUST NOT imply a directory is empty or a full-tree scan succeeded.

#### Scenario: Locked sibling and complete selected target
- **WHEN** one target cannot be read because of file sharing conflicts while an independent target has complete evidence
- **THEN** the independent target SHALL remain selectable and executable after current confirmation and revalidation
- **AND** the locked target SHALL remain blocked and retain its coverage issue

#### Scenario: Single-location rule scan finishes
- **WHEN** a single-location rule-target scan completes its declared scope without analysis issues
- **THEN** the application SHALL display a completed scan even though it did not measure the entire tree

### Requirement: Actionable scan coverage explanations
The application SHALL distinguish file-use conflicts, time limits, entry limits and depth limits in Simplified Chinese and English, and SHALL explain that complete eligible items remain available after partial coverage. Existing bounded budgets and file-sharing protections MUST remain enforced.

#### Scenario: Locked browser cache
- **WHEN** Windows reports a file-sharing or lock conflict during scanning
- **THEN** coverage details SHALL identify the affected path and advise closing the application and rescanning
- **AND** the application MUST NOT stop the owning process or relax file access checks

#### Scenario: Local or shared scan budget expires
- **WHEN** a target reaches a time, entry or depth limit
- **THEN** coverage details SHALL identify the limit and advise rescanning a single location or smaller scope
- **AND** the result SHALL remain partial without granting incomplete targets execution eligibility

### Requirement: Current confirmation and exact evidence remain mandatory
Permanent cleanup MUST require explicit current-scope confirmation, current configuration and rules, complete exact manifests and live identity and activity checks. Cancellation, stale evidence and consumed plans MUST NOT grant permission for further deletion.

#### Scenario: No interactive confirmation
- **WHEN** CLI execution is invoked without an interactive current-scope confirmation
- **THEN** execution MUST fail without modifying any target

#### Scenario: Target changes after scan
- **WHEN** the target, its context, activity or manifest changes before execution
- **THEN** execution MUST reject the stale evidence and preserve unapproved content

#### Scenario: Generated native acceptance
- **WHEN** the rule-cleanup capability is validated
- **THEN** deletion checks SHALL use only newly generated temporary fixtures and SHALL verify retained files, cancellation, rejection and recorded outcomes
