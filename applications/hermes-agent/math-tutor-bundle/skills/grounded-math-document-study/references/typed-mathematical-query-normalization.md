# Conservative typed mathematical query normalization

Use this pattern when notation-heavy textbook queries must survive OCR/Unicode variation without creating broad lexical false positives.

## Principle

Keep the user's original query and attach a typed sidecar AST. Do not flatten mathematical meaning into one destructively normalized string. Each entity should retain `kind`, exact `surface`, source `span`, `confidence`, and typed `value`; preserve an offset map whenever Unicode glyphs are normalized.

Useful class-level entity types include:

- `PolynomialSpace(field, max_degree|unbounded)`
- `MapSignature(map, domain, codomain)`
- `Composition(outer, inner)`
- `QuotientSpace(ambient, subspace)` and `Coset(representative, subspace)`
- `MatrixShape(rows, columns)`
- `NullSpace(map)` and `Range(map)`
- `FiniteList(length|item_pattern)` and `Sequence(index_domain|item_pattern)`

## Parse conservatively

1. Normalize mathematical alphabets and arrows only with surface-span preservation. Keep meaningful boundaries such as the underscore in `P_m(F)`.
2. Require local type or lexical cues before interpreting overloaded notation:
   - parse `P_m(F)`, `Pₘ(F)`, and calligraphic variants as bounded-degree polynomial spaces; keep `P(F)` distinct as unbounded; do not infer from bare ambiguous `Pm(F)` without a polynomial cue;
   - parse `T:V→W`, `T from V to W`, or `T∈L(V,W)` as map signatures;
   - parse juxtaposition `ST` as composition only when map/operator/composition cues or compatible signatures identify `S` and `T`; represent `ST` as outer `S`, inner `T`, so `T` acts first;
   - parse `V/U` as a quotient only with quotient/subspace/coset cues or a known relation `U ≤ V`; parse `v+U` as a coset only with coset/translate/quotient cues or an established quotient context;
   - parse `m-by-n`, `m×n`, or `m rows and n columns` only in matrix context; rows come first;
   - recognize `null T`, `ker T`, `range T`, and `im T` only when the argument is map-like. Never globally rewrite ordinary words such as `page image`, `null hypothesis`, or `mountain range`;
   - distinguish terminally indexed finite notation `(v_1,…,v_m)` from open-ended `(x_1,x_2,…)`, but require list/basis cues for the former and sequence/infinite/`F^∞` cues for the latter. An ellipsis alone is not enough.
3. Use a type environment to check composition and derived matrix dimensions. Suppress retrieval expansion for ill-typed combinations.
4. Leave unresolved candidates unresolved rather than converting low-confidence syntax into a fact.

## Query variants

Always retain the normalized user query as the first variant. Generate at most one or two focused variants per typed entity and cap the total. Examples:

- `P_m(F)` → `polynomials over F of degree at most m`
- `T:V→W` → `linear map T from V to W`, `T in L(V,W)`
- `ST` → `product of linear maps ST; composition S after T; T acts first`
- `V/U` → `quotient space V/U of V by subspace U`
- `v+U` → `coset v+U; translate of subspace U`
- `m-by-n` → `m-by-n matrix with m rows and n columns`
- `null T` / `range T` → LADR wording plus `kernel of linear map T` / `image of linear map T`

Do not append downstream facts—well-defined quotient operations, noncommutativity, finite-dimensionality—unless the question explicitly asks for them. Variants are retrieval aids, not mathematical claims.

## Minimum tests

Cover exact typed values, source-span round trips, deduplicated variants, composition order and type mismatch, and negative controls. Negative controls should include probability `P(A)`, projection `P_U`, URLs containing `V/U`, bare vector addition `v+U`, abbreviations `ST`, room/lumber dimensions `3×4`, `page image`, `null hypothesis`, `mountain range`, and ellipsis expressions without list/sequence cues.

Also regression-test the real source spellings emitted by every extraction layer (native PDF text, layout text, OCR, and user ASCII/LaTeX). Measure retrieval gains and wrong-section/false-positive rates separately; a higher hit rate does not justify semantic over-expansion.
