# Diagnostics and Interpretation

## Start with aggregates

Read the analyzer's JSON and `summary.md` before opening tables. Useful follow-up
files include:

- `task_groups.csv`: parent task with subagent sessions rolled up;
- `sessions.csv`: session-level accounting;
- `tools.csv`: tool call and output volume;
- `skills.csv`: skill load count and returned characters;
- `large_tool_outputs.csv`: bounded, redacted examples over the threshold;
- `tool_output_patterns.csv`: repeated output classes and mitigations;
- `suspicious_sessions.csv`: retry/API/context anomalies;
- `summary_queue.csv`: candidates only, not authorization to publish notes;
- `next_actions.csv`: reversible operational suggestions.

## Driver classification

| Signal | Likely driver | First mitigation |
|---|---|---|
| large terminal/JSON/HTML output | tool result volume | filter or aggregate before tool output enters context |
| many API calls with little progress | retry or unclear acceptance criteria | reproduce narrowly and define a stop condition |
| repeated large skill loads | procedural context | split always-needed core from on-demand references |
| one long task with coherent progress | legitimate task complexity | preserve handoff and continue only while evidence stays relevant |
| repeated transcript/session searches | restart cost | create a compact restart handoff |
| many subagents without advanced artifacts | orchestration overhead | reduce fan-out and require verifiable outputs |

## Safety

Analyzer artifacts remain local. Report aggregates instead of raw message text.
Samples must remain bounded and secret-redacted. Treat heuristic classification as
a prompt for inspection, not ground truth or an automatic policy decision.
