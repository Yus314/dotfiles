# Orchestration shared skills

Shared coordination procedures for every configured profile. All profiles can be
assigned durable board work even when only some of them normally orchestrate it.

Keep profile-specific boards, tenant data, channel identifiers, and project context local. Only generic orchestration contracts belong here.

`kanban-worker` must remain as a separate package name even though the broader
procedures also live in `kanban-workflows`: the Hermes dispatcher force-loads
that exact skill name for every worker process.
