# Shared Hermes Skills

This directory is the user-owned source of truth for procedures intentionally shared by multiple Hermes profiles.

## Groups

| Group | Profiles | Purpose |
|---|---|---|
| `common/` | all configured profiles | Minimal universally safe procedures and safe user handoffs |
| `study/` | default, career, economics, english, math | Book/source ingestion and cross-subject study procedures |
| `engineering/` | default, career, indiedev, researcheval | Shared software/research engineering procedures |
| `orchestration/` | all configured profiles | Generic Kanban and multi-worker coordination procedures |
| `profile-ops/` | default | Profile orchestration and handoff procedures |
| `usage-ops/` | default, career, english, indiedev, researcheval | Local usage accounting and context-efficiency diagnostics |

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

Every Nix build runs `shared_skills_config.py check-source` before producing the
read-only shared-skill derivation. The gate rejects malformed frontmatter,
directory/frontmatter name mismatches, normalized slash or Discord command
collisions, generated/transient artifacts, duplicate names, orphan packages,
symlinks, probable secrets, unsafe frontmatter text, broken package-local
Markdown links, unapproved secret capabilities in every shared group, and drift
between this profile/group table and the Python matrix. The derivation runs the
shared-skill unit tests and includes `.manifest.json` with both `SKILL.md` and
whole-package hashes plus an ownership/schema marker.

After deployment, run:

```bash
python ~/.hermes/scripts/shared_skills_config.py check-live
```

The live check fails unless:

1. every configured profile is represented in the profile/group matrix;
2. every profile lists exactly its intended shared skills;
3. no active profile-local or unmanaged external skill shadows a shared name;
4. runtime package hashes match the Nix build manifest;
5. the runtime shared root is read-only;
6. profile configs are private regular files (`0600`) owned by the current user;
7. configured managed roots use only the stable logical paths, with stale store
   paths and symlink aliases rejected; and
8. the report records each external root's resolved path and each shared skill's
   source and content/package hashes.

Start a fresh Hermes session after deployment so its prompt index includes the
new directories. Use `/reload-skills` in a long-lived CLI/gateway process when
an immediate slash-command refresh is needed. Restart a gateway only when it is
idle; do not interrupt active agents solely to refresh skills. Finally, run one
representative task from each changed profile group; discovery health alone
does not prove workflow value.
