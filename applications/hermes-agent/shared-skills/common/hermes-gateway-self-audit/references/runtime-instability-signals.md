# Runtime Instability Signals

## Bounded evidence funnel

1. Identify profile and configured model/provider.
2. Resolve the actual unit/process.
3. Read only recent logs for that unit and incident window.
4. Capture the first actionable error and a small amount of surrounding context.
5. Check whether retries made progress or repeated the same failure.
6. Reproduce with the smallest non-destructive request when safe.

## Interpret conditionally

Timeouts, OAuth refresh failures, rate limits, websocket disconnects, and model
streaming failures are version/provider-specific signals. Historical signatures
are hypotheses, not a current baseline. Report timestamps, selected provider,
model, profile, and whether another request succeeded before proposing a change.

Avoid dumping journals, HTTP bodies, or environment values into model context.
