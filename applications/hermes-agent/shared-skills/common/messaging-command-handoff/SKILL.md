---
name: messaging-command-handoff
description: Prepare shell commands and small scripts for users to copy or run from Discord, Telegram, or mobile messaging clients without losing safety or legibility.
version: 1.1.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [messaging, discord, mobile, shell, command-handoff, safety]
---

# Messaging Command Handoff

## When to Use

Use this only when the user genuinely must run a command—for example because the
agent lacks access, an approval remains pending, or a privileged/interactive step
cannot be completed safely with available tools. Do not hand routine work back to
the user when the agent can execute and verify it directly.

## Core Principles

1. **Optimize for the actual client.** Mobile clients may not support clean
   desktop-style code-block selection.
2. **Separate explanation from the copy target.** Put context first and the exact
   command in a command-only message or attachment.
3. **Prefer safety over terseness.** Keep path and resource guards for destructive
   operations even when they make the command longer.
4. **Use one obvious unit of execution.** Prefer one pasteable command or one script
   attachment rather than prose interleaved with commands.
5. **State scope first.** Name what will be touched, what will not, and whether the
   action needs elevated privileges.
6. **Never use handoff to bypass approval.** A denied or pending action remains
   subject to the same safety boundary when performed manually.

## Recommended Formats

### Desktop or web client

Use one fenced command block after a short explanation. Keep one logical task per
block.

### Mobile client

Prefer, in order:

1. a separate command-only message;
2. a guarded single-line command when it remains readable;
3. a script attachment for long or multi-step operations.

## Safe Cleanup Pattern

```bash
set -euo pipefail
TARGET='/absolute/expected/path'
case "$TARGET" in
  /absolute/expected/path) ;;
  *) echo "Refusing unexpected target: $TARGET" >&2; exit 2 ;;
esac
# perform the scoped action only after the guard
```

Adapt the exact allowlisted path to the task. Do not provide placeholder deletion
commands that become dangerous if copied without editing.

## Approval or Access Block

1. Explain whether the blocker is approval, privilege, missing access, or an
   unsupported interaction.
2. Prefer waiting for supported approval when that preserves the intended safety
   boundary.
3. If manual execution is necessary and authorized, provide the smallest scoped
   command with a verification command.
4. Retry through the agent only when the latest user message clearly authorizes the
   same action.
5. After execution, verify the resulting files, configuration, or service state
   with read-only checks.

## Pitfalls

- Mixing long prose into the text the user needs to copy.
- Removing path guards merely to produce a one-liner.
- Encoding a transient approval failure as a durable claim that a tool is broken.
- Asking the user to edit several similar paths inside a destructive command.
- Reporting success before receiving or independently checking real output.
