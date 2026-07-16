# Cron and Watchdog Audit

For each relevant job, verify:

- declared schedule and owning profile;
- enabled/paused state;
- last start, finish, exit status, and bounded output;
- expected artifact or delivery target;
- whether the artifact was usable and advanced the intended outcome;
- timeout relationship between scheduler, script, network calls, and agent run.

Do not interpret `active`, `success`, or a recent timestamp as proof of value.
Repeated no-op health reports, permanently empty outputs, or alerts that prevent
no misses should be simplified, paused, or retired after confirming ownership.

When a timeout occurs, identify which boundary fired first. Increasing every
timeout hides the root cause; adjust the narrowest justified boundary and run a
real canary.
