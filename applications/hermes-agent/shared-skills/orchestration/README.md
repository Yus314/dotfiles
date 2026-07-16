# Orchestration shared skills

Shared coordination procedures for every configured profile. All profiles can be
assigned durable board work even when only some of them normally orchestrate it.

Keep profile-specific boards, tenant data, channel identifiers, and project context local. Only generic orchestration contracts belong here.

`kanban-worker` must remain as a separate package name: the current Hermes
dispatcher probes and force-loads that exact name. Broader orchestrator
procedures live in the default-only `profile-ops/kanban-workflows` package so
domain profiles receive worker guidance without ambient control-plane policy.
