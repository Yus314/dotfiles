# Lean-assisted proof exercises

Use this protocol when a proof-based textbook exercise is studied with Lean or Mathlib as a checker.

## Source and statement gate

1. Verify the exact exercise statement against the canonical edition before choosing notation or theorem shape.
2. Record both printed page and PDF page when they differ.
3. Separate three claims:
   - the book statement was source-verified;
   - the Lean encoding type-checks;
   - the learner understands and can reconstruct the mathematics.
4. Create only a statement scaffold before the learner's first attempt. An intentional `sorry` is acceptable if the checker reports it clearly; it is not a solved exercise.

## Two-track dialogue

Keep every hint under one of these headings:

- **Mathematical hint**: definitions, examples/non-examples, choice of test objects, proof strategy, or a local mathematical bridge.
- **Lean/Mathlib hint**: representation, types, coercions, syntax, elaboration, library API, or proof-state manipulation.

Do not let Lean tactics reveal the mathematical bridge before the learner has attempted it. Resolve routine syntax/API friction directly, but escalate mathematical help through the normal hint ladder.

## Operational sequence

1. Identify the domain, codomain, parameters, hypotheses, conclusion, and both directions of any equivalence.
2. Ask for the learner's mathematical attempt before filling the proof body.
3. Verify the smallest statement scaffold with the real checker.
4. Classify Lean failures as syntax/editor, elaboration/typeclass, Mathlib API/coercion, or proof-state/mathematics.
5. After compilation, ask for a code-free mathematical reconstruction.
6. Keep `statement`, `attempting`, `compiled`, and `reconstructed` as distinct states in the exercise log.
7. Record a learning-ledger event only after an actual initial attempt and corrected reconstruction.

## Coordinate-space encoding pattern

For finite coordinate spaces, a useful Mathlib representation is `Fin n → 𝕜`. A raw parameterized function can be stated first, with linearity expressed by `IsLinearMap 𝕜 f`; only construct a bundled `LinearMap` after linearity is established or when the exercise specifically calls for one. This avoids assuming the conclusion in the input type.

Before formal proof work, compile the representation and theorem statement independently. A successful build validates only the encoded proposition, not fidelity to the book or learner mastery.
