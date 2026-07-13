---
name: hermes-shared-smoke-test
description: Verify cross-profile shared-skill loading safely.
version: 1.0.0
author: Kaki
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [hermes, profiles, verification]
---

# Hermes Shared Skill Smoke Test

## When to Use

Use only while validating that a Hermes profile can discover and load the shared read-only skill directory.

## Procedure

1. Identify the active Hermes profile from the runtime session context or `/profile` information already available.
2. State the active profile name.
3. State that `hermes-shared-smoke-test` was loaded successfully.
4. Do not modify files, configuration, memory, services, or external systems.
5. Do not infer that any other shared skill is healthy; this smoke test proves only its own discovery and loading path.

## Expected Output

Return exactly two short facts:

- `profile=<active-profile>`
- `shared_skill_loaded=true`

## Verification

The caller must separately confirm that every profile resolves this skill to the same read-only source and SHA-256 hash.
