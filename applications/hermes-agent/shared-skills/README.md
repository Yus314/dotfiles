# Shared Hermes Skills

This directory is the user-owned source of truth for procedures intentionally shared by multiple Hermes profiles.

## Groups

| Group | Profiles | Purpose |
|---|---|---|
| `common/` | all configured profiles | Minimal universally safe procedures |
| `study/` | default, career, economics, english, math | Book/source ingestion and cross-subject study procedures |
| `engineering/` | default, career, indiedev, researcheval | Shared software/research engineering procedures |
| `profile-ops/` | default | Profile orchestration and handoff procedures |

Profiles reference the group directories explicitly through `skills.external_dirs`; the repository root itself is not an external skill directory.

## Ownership and update path

- Edit skills in this dotfiles repository.
- Home Manager publishes this directory at `~/.local/share/hermes/shared-skills` through the Nix store.
- The runtime path is intentionally read-only. Do not use `skill_manage` to update shared skills in place.
- Rebuild and activate Home Manager after changing a shared skill, then verify it from every target profile.

## Inclusion policy

A shared skill must:

- be useful to at least two profiles in its group without profile-specific behavior;
- contain no secrets or domain-specific raw data;
- have a name that does not collide with a local or bundled skill in target profiles;
- remain valid when loaded from every target profile;
- reduce duplicate maintenance enough to justify shared ownership.

Keep these local instead:

- Hermes bundled or Skills Hub-managed skills;
- finance, health, food, math, career, English, economics, or indie-development procedures that are domain-specific;
- skills whose profile variants intentionally differ;
- temporary experiments that have not demonstrated recurring value.

## Verification

After deployment:

1. Start a fresh Hermes session so its prompt index includes the shared directories.
2. Run `/reload-skills` in long-lived CLI/gateway processes when immediate slash-command refresh is needed. Restart a gateway only when it is idle; do not interrupt active agents solely to refresh skills.
3. Confirm every configured profile lists only its intended groups.
4. Confirm each shared skill resolves exactly once and hashes match the repository source.
5. Confirm runtime edits fail because the Nix store is read-only.
6. Run one representative task from each profile group that actually uses the skill.
