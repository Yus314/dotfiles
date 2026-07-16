# Profile operations shared skills

Procedures for profile orchestration, handoffs, gateways, and cross-profile operations. Initially exposed only to the `default` profile.

Do not place domain raw-data procedures or secrets here.

`kanban-workflows` contains control-plane decomposition and integration policy.
Worker lifecycle compatibility remains in `orchestration/kanban-worker`, which
is shared with every profile that can receive a durable card.
