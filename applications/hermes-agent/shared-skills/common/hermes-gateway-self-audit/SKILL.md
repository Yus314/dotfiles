---
name: hermes-gateway-self-audit
description: Evidence-first audit of Hermes gateway configuration, security controls, services, Discord connectivity, cron health, and runtime instability without relying on stale static baselines.
version: 2.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos]
metadata:
  hermes:
    tags: [hermes, gateway, audit, security, discord, systemd]
---

# Hermes Gateway Self-Audit

## Purpose

Use this skill when auditing or troubleshooting a Hermes installation, profile,
gateway service, Discord connection, approval/security policy, cron automation,
or runtime instability. Read the live configuration and authoritative Hermes
documentation before applying a remembered baseline: models, providers, approval
modes, web backends, service names, and profile topology can drift.

A running process is not proof that the gateway is reachable, authorized,
correctly routed, or useful. A green cron is not proof that it advanced a user
outcome.

## Audit Sequence

1. **Define scope and profile.** Identify `default` or the exact named profile.
   Do not silently inspect the default config for a named-profile incident.
2. **Read authoritative documentation.** Use the current Hermes docs for config
   schema, gateway, provider, Discord, security, cron, and profile semantics.
3. **Inspect live config structurally.** Parse YAML and report selected fields;
   do not dump the entire file into context.
4. **Resolve the actual service/process.** Discover configured units rather than
   assuming a hard-coded unit name. Distinguish intentionally absent services
   from failed services.
5. **Check runtime evidence.** Service state, recent bounded logs, process command,
   and provider/channel status answer different questions.
6. **Run the smallest safe smoke test.** Choose the provider/backend declared by
   the selected profile. Never source a secret environment file merely to test.
7. **Classify findings.** `pass`, `warning`, `failure`, or `not applicable`, each
   with evidence and a reversible next action.
8. **Verify value.** State what miss was prevented, capability restored, or
   recurring burden reduced. Stop if the gain is unproven.

## Profile and Config Resolution

- Default config: `~/.hermes/config.yaml`
- Named profile config: `~/.hermes/profiles/<profile>/config.yaml`

Read current values for model/provider, approvals, command allowlist, secret
redaction, web/search provider, gateway platform settings, and external skill
roots. Never claim a value from an old skill reference when the live config is
available.

Expected security invariants should be derived from current user policy and then
verified. For this installation the normal checks include Codex-only routing,
smart approvals, a real empty-list command allowlist, and secret redaction, but a
live mismatch must be reported rather than overwritten without authorization.

## Credential-Safe Inspection

- Report credential **key names, presence, source class, owner, and mode only**.
- Never print, hash, compare, or persist complete token/secret values unless an
  explicitly authorized investigation makes that indispensable.
- Do not print `/proc/<pid>/environ`, auth JSON, `.env`, sops outputs, or gateway
  environment contents.
- A smoke test should inherit the already configured service/runtime boundary or
  use an official status command; do not `source` secret files into a shell.
- Shared skills must not contain credential values, channel IDs, private corpus,
  or required secret capabilities.

## Service and Channel Interpretation

Discover units dynamically, then map them to profiles using declarative config,
unit `ExecStart`, and the profile flag. Flag duplicate or legacy unit names only
when evidence shows they target the same profile and one is obsolete.

Keep these states separate:

- unit enabled/disabled;
- process active/inactive;
- gateway startup complete;
- Discord/websocket connected;
- authorization/channel allowlist accepted;
- message received and response delivered.

For Discord auto-thread behavior, verify the configured mode and observed event
flow. Do not infer success from service state alone.

## Runtime and Cron Triage

Bound logs by unit and time. Extract the first actionable error, failing provider,
profile, and retry pattern instead of returning broad journal output. For timeout,
OAuth rotation, rate-limit, or transport failures, confirm the currently selected
model/provider before using a historical incident signature.

For cron, inspect schedule, last run, exit status, bounded output, and the expected
artifact/delivery. A watchdog that repeatedly reports health but prevents no miss
should be simplified or retired.

## Reporting Format

```markdown
# Hermes gateway audit: <profile>
- Scope and config path:
- Live model/provider/backend:
- Security controls:
- Service/process/channel state:
- Cron/runtime findings:
- Pass/warning/failure/not-applicable evidence:
- Smallest reversible action:
- Verification and user-value signal:
```

See the on-demand references for bounded triage and channel semantics.
