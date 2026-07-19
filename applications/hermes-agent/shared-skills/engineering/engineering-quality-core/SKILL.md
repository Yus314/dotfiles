---
name: engineering-quality-core
description: "Baseline completion invariants for software changes; use local specialist skills for detailed debugging, TDD, spike, review, evaluation, or release workflows."
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [engineering, quality, verification, completion]
---

# Engineering Quality Core

This skill is a shared quality floor, not a detailed engineering workflow. Apply it to software changes while letting a more specific local skill control debugging, strict TDD, experiments, review, benchmarking, deployment, or release procedure.

## Baseline contract

1. **Define the outcome.** State the intended observable behavior and acceptance criteria before editing.
2. **Inspect before changing.** Read the smallest relevant code, configuration, tests, and project instructions. Preserve unrelated work and source/generated boundaries.
3. **Choose the risk-reduction mode deliberately.**
   - Use a disposable spike when feasibility or API behavior is uncertain.
   - Add a failing regression oracle before a bug fix or behavior change when practical.
   - Preserve behavior explicitly during simplification.
   - Use the repository's own quality gates for completion.
4. **Keep scope narrow and reversible.** Do not widen the change merely because adjacent cleanup is possible. Prefer the smallest change that proves or delivers the requested outcome.
5. **Exercise the real artifact.** Run the smallest relevant check first, then the broader build, test, lint, type, packaging, or smoke gate justified by the change. Verify generated or distributed artifacts separately when they are deliverables.
6. **Report evidence honestly.** Record the command, exit status, and material result. Distinguish new failures from known baseline failures; inspection, mocks, and partial gates do not prove end-to-end success.
7. **Reverify and dispose explicitly.** Re-run affected gates after review fixes or refactoring. Finish with one clear disposition: verified production change, discarded or promoted spike, or an unresolved blocker with the remaining uncertainty.

## Completion gates

Treat these as separate claims:

- **Contract:** the requested behavior and non-goals are explicit.
- **Correctness:** relevant executable checks pass against the changed artifact.
- **Integration:** configuration, packaging, distribution, or runtime resolution works where applicable.
- **Side effects:** writes, network actions, publication, deployment, and external communication stayed within the approved scope.
- **Disposition:** the result, evidence, remaining risks, and rollback or restart information are clear.

Passing one gate does not imply the others. A running process is not proof of user value, reviewer output is advisory rather than authoritative, and a plausible-looking artifact is not a substitute for real execution.

## Do not use as the primary workflow

Route to a local specialist skill when the task requires root-cause debugging, strict RED/GREEN/REFACTOR semantics, performance methodology, pull-request interaction, evaluation fixtures or scoring, security response, domain release policy, or credentials. This core may remain as the final completion floor, but it must not weaken or replace the specialist procedure.
