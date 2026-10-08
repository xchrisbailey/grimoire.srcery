# Domain docs

This repo uses a single-context layout. Domain terminology belongs in root `GLOSSARY.md`; architecture decisions belong in `docs/adr/`.

## Before exploring

Read `GLOSSARY.md` if it exists, then any ADRs in `docs/adr/` relevant to the work. If either is absent, continue without requiring it. The domain-modeling skill creates these docs when terms or decisions are resolved.

## Use the glossary's vocabulary

Use terms defined in `GLOSSARY.md` when naming domain concepts in issues, proposals, hypotheses, and tests. If a needed concept is missing, check whether the project already has a term for it; otherwise note the gap for domain modeling.

## Flag ADR conflicts

If proposed work contradicts an existing ADR, call out the conflict explicitly so the decision can be revisited.
