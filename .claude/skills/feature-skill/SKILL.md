---
name: feature-skill
description: Implement a new feature by first analyzing existing architecture and similar implementations, forming an explicit plan, then implementing the smallest correct change, testing, linting, and verifying against acceptance criteria before reporting completion.
---

# Implement the feature

Implement the feature requested by the user. Use the current conversation
for requirements and acceptance criteria.

## 0. Establish the working state

Before modifying anything:

- Confirm the current working directory is the correct one for this
  session — a worktree path (e.g. `.claude/worktrees/<name>`) or the
  repo root, whichever this session is meant to operate in — before
  running any git command. Mixing the two is exactly how a worktree
  directory ends up accidentally committed as a gitlink in root's
  history.
- If operating inside a worktree, never run `git add` or commit from
  outside that worktree's directory (e.g. from repo root while a
  worktree exists under it). Stage and commit from inside the worktree
  itself.
- Run `git fetch origin` and compare the local base branch against
  `origin/<base branch>` before diagnosing "missing" or "misplaced"
  code. A branch that's simply behind looks identical to one with
  actual missing work — rule out a plain sync gap (fast-forward fixes
  it) before investigating further.
- Inspect `git status` and the existing diff.
- Identify pre-existing user changes and preserve them.
- Do not reset, revert, overwrite, or reformat unrelated changes.
- Determine the relevant build, test, lint, and type-check commands from
  project configuration rather than assuming standard commands. Note them
  for reuse in the final summary.

## 1. Extract requirements, then analyze existing architecture

- Extract the concrete requirements and acceptance criteria from the current
  conversation before exploring implementation details. Keep them as the
  reference for deciding whether the feature is complete.
- Read applicable CLAUDE.md instructions.
- Map out the relevant parts of the codebase: models, controllers/services,
  routes, and how data flows through the layers involved in this feature.
- Identify the project's established conventions (naming, folder structure,
  service objects vs. fat controllers, error handling style, etc.).

## 2. Find similar implementations

- Search the codebase for existing features that solve a structurally
  similar problem (e.g. another filter, another CRUD resource, another
  policy-gated action).
- Note the patterns they use — do not reinvent an approach the codebase
  already has a convention for.
- If no similar implementation exists, say so explicitly before proceeding.

## 3. Form a plan — do not write code yet

Produce an explicit plan covering:

- Files to create or modify.
- Data model / query changes, if any.
- Which existing pattern(s) from step 2 this plan follows, and why.
- Edge cases and error states to handle.
- Tests that will need to be added or updated.

For non-trivial tasks, state the plan before implementation and then proceed
unless a decision cannot be safely inferred from the existing requirements,
codebase conventions, or similar implementations.

Ask the user only when a missing decision would materially change the
feature's behavior or public interface.

Do not modify public API contracts, database schema, or migrations unless
the feature clearly requires it. Prefer extending existing interfaces over
changing them.

## 4. Implement the feature

- Follow the plan and the established patterns identified in step 2.
- Prefer the smallest change that correctly satisfies the requirements and
  fits the existing architecture. Do not introduce new abstractions,
  dependencies, or architectural patterns unless the feature clearly
  requires them — absence of a similar pattern in step 2 is not by itself
  justification for a new one; consider simpler options first.
- Keep changes focused on the feature; preserve unrelated user changes.
- Do not silently deviate from the plan — if reality forces a deviation,
  state why.

## 5. Write or update tests

Add or update tests covering the new/changed behavior, following the
project's existing test conventions and structure.

## 6. Run the test suite

Run targeted tests covering the changed behavior first.
Run the broader suite only when justified — e.g. shared code changed,
or targeted tests alone can't rule out cross-feature regressions. State
which scope was run and why.

## 7. Run linting

Run the project's configured lint checks for the affected scope.
Run type checking when configured and relevant.
Do not disable checks or weaken rules to make the changes pass.

## 8. Verify the changed behavior manually if possible

Exercise the feature through the relevant interface: UI, API, CLI, or
another available entry point. Check the main flow and relevant error or
edge cases. Reading the code alone does not count as manual verification.

If the environment does not allow manual verification, skip it explicitly
and state exactly what prevented it — do not claim it was done.

## 9. Check for regressions

Identify existing behavior that shares the modified code or interfaces.
Verify it still works using relevant tests and targeted checks. Do not
claim the entire application is regression-free based on limited checks.

## 10. Review your own diff

Inspect every change you made, including newly created files. Check for:

- Incorrect or incomplete behavior.
- Missing edge cases.
- Accidental changes and unnecessary refactoring.
- Unintended changes to public API, schema, or migrations.
- Debug code, unused code, and exposed secrets.
- Tests that pass without actually verifying the intended behavior.
- Deviations from the plan in step 3 — and whether they were justified.
- Unnecessary new abstractions that a simpler change would have avoided.
- Every requirement and acceptance criterion from the original request is
  actually satisfied by the implementation and covered by verification
  where practical.

## 11. Fix any issues found

Fix issues introduced by the changes. Rerun affected checks after fixes
and review the updated diff. Repeat until the relevant checks pass and no
known issues remain within the task's scope.

Do not silently expand the task to fix unrelated existing problems.
Report them separately if they affect verification.

## 12. Only then summarize the result

Provide a concise final summary:

- What was implemented and the main files/layers affected.
- Any deviations from the original plan and why.
- The similar implementation(s) it was modeled on, if relevant.
- Test, lint, and type-check commands actually run, with their results.
- Manual and regression checks performed, or why they were skipped.
- Any remaining limitations or blockers.

Never report an unrun check as passed. If a required check cannot run,
explain why and explicitly mark verification as incomplete. Do not claim
full completion.

Brief progress updates are allowed during implementation.
