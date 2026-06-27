# Caliber Learnings

Accumulated patterns and anti-patterns from development sessions.
Auto-managed by [caliber](https://github.com/caliber-ai-org/ai-setup) — do not edit manually.

- **[gotcha]** Don't grep-count `if` vs `end if` in `.brs` files as a brace-balance sanity check — BrightScript single-line `if … then …` statements and `else if` clauses have no matching `end if`, so a healthy file shows far more `if` than `end if` (e.g. PlayerScene.brs: 35 vs 23). A mismatch is NOT a syntax error.
- **[gotcha]** Local clones of the native-client repos under `/home/sites/phlix/` (roku, mobile, windows) can be on a divergent local `master` (same commit messages, different SHAs from a prior history rewrite) while `tizen` stays in sync. Branching a feature off local `master` bases the PR on commits origin lacks → `gh pr merge` fails with phantom merge conflicts even for a one-line change. Branch from origin instead: `git fetch origin && git checkout -B <branch> origin/master`.
- **[pattern]** After editing a `.brs`/`.xml` change in this repo, `make validate-xml` is the only verification that actually exits non-zero on failure (`make lint`/`make test` never fail). Run it as the real gate; treat `make lint` output as informational only.
