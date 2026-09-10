---
name: code-review
description: Review code changes for actionable bugs, regressions, security issues, and missing requirements. Use whenever the user asks for a code review, to review a PR or commits, "review my changes", "check this diff", "check code before merging", "перевір код", or "перевір PR", even without explicitly using the word "review". Applies to pull requests, branches, commits, and local changes. Report evidence-backed findings; do not implement fixes unless requested.
---

# Review the code

Review the changes requested by the user.
Use the current conversation for requirements and acceptance criteria.
Respond in the user's language.

## 1. Establish the review scope

- Read applicable CLAUDE.md and other repository instructions.
- Identify the target: PR, commit range, branch, or local changes.
- Preserve all existing user work.
- If no target is specified, review local changes when present.
  Otherwise ask what should be reviewed.
- State the scope briefly. Do not silently substitute a local checkout
  or another revision for the requested target.

Use these commands as starting points, adapting refs and paths to the
actual repository.

### Local changes

```bash
git status --short
git diff --stat
git diff
git diff --cached --stat
git diff --cached
git ls-files --others --exclude-standard
```

Include staged, unstaged, and relevant untracked files unless the user
limits the scope. Git diff does not include untracked file contents;
inspect those separately.

### Branch or commit range

For changes introduced by a branch relative to its actual base:

```bash
git diff --stat <base>...<head>
git diff --name-status <base>...<head>
git diff <base>...<head>
```

The three-dot form compares the merge base with the head. For an explicit
comparison of two snapshots, use `git diff <old> <new>` instead.

Do not assume the base is main or master.

### Pull request

When GitHub CLI is available:

```bash
gh pr view <PR> --json title,body,baseRefName,headRefName,headRefOid,files
gh pr diff <PR> --stat
gh pr diff <PR>
gh pr checks <PR>
```

Record the reviewed head SHA. Confirm that any local tests or file reads
use that revision before treating them as PR evidence.

Use an isolated worktree if another revision must be checked out.
Do not disturb the user's current checkout.

If these tools are unavailable, use available repository integrations
or the supplied diff. State any resulting context or verification gaps.
A passing CI status is evidence about the checks that ran, not proof
that every changed behavior is correct.

Review only by default. Do not modify project files, commit changes,
or publish review comments unless the user requests those actions.

## 2. Understand the intended behavior

Before judging the implementation:

- Extract requirements from the task, PR description, and relevant
  documentation. Distinguish requirements from assumptions.
- Read changed code in its surrounding context.
- Trace affected callers, consumers, data contracts, and execution paths.
- Inspect similar implementations and established project conventions.
- Read relevant tests and configuration to identify supported test,
  lint, type-check, and build commands.

Do not assume the implementation or its tests define correct behavior.
Compare both against the intended requirements.

### Large changesets

Start with the file inventory and diff statistics. Group changes by
feature or execution path, such as a schema change together with its
service, API, and UI consumers.

Prioritize authentication, permissions, data writes, migrations, shared
contracts, and other changes with broad impact. Review each group in
manageable batches while tracing dependencies across groups.

Keep a compact coverage record: reviewed, partially reviewed, and pending.
Give progress updates at meaningful boundaries.

Treat generated files, lockfiles, and mechanical edits according to their
risk. Inspect source changes and relevant consequences rather than reading
every generated line.

Do not silently sample substantive code and claim a complete review.
If constraints prevent full coverage, identify exactly what was reviewed,
what was sampled or skipped, and what remains uncertain.

## 3. Inspect the changes

Prioritize issues with concrete impact:

- Incorrect business logic or missing acceptance criteria.
- Broken API contracts, serialization, validation, or error handling.
- Authentication, authorization, ownership, or data exposure problems.
- Data integrity, migration compatibility, transactions, and concurrency.
- Incorrect state updates, stale data, races, and resource cleanup.
- Broken loading, empty, error, retry, or other supported user flows.
- Accessibility or responsive behavior regressions in affected UI.
- Performance problems supported by an actual execution path.
- Tests that miss, conceal, or incorrectly assert changed behavior.

Apply only checks relevant to the change.

Follow dependencies beyond the diff when needed to establish impact.
Focus findings on issues introduced or exposed by the change.
Identify pre-existing issues separately when they materially affect the task.

Do not report personal style preferences, speculative abstractions,
or unrelated refactoring opportunities as defects.

### Secrets and credentials

If the diff contains a suspected secret, do not reproduce its value in
the report, examples, commands, or additional tool output. Identify the
file, lines, credential type, and exposure without quoting the secret.

Distinguish plausible credentials from clearly documented placeholders.
Do not test credentials against live services.

For a plausibly real exposed credential, recommend revocation or rotation
and removal from tracked code. Deleting the current line alone does not
invalidate the credential or remove it from Git history.

## 4. Validate candidate findings

Before reporting an issue:

1. Identify the input, state, or sequence that triggers it.
2. Trace the execution path and check existing safeguards.
3. Establish expected behavior and the actual consequence.
4. Confirm its relationship to the reviewed change.
5. Reproduce it when practical, or provide a clear code-based argument.

Run relevant existing tests and linting when the environment permits.
Run type checks or builds when they help validate affected behavior.
Choose commands from project configuration; avoid autofix modes.

For UI changes, verify affected behavior manually when a suitable
environment is available.

Use isolated temporary reproductions when needed. Do not change project
files merely to prove a finding.

If a check fails, distinguish a change-related failure from a pre-existing
failure or environment problem. Compare against the base in an isolated
checkout when necessary and practical.

Do not invent successful checks. Report blocked or skipped verification
and its effect on confidence.

Missing test coverage alone is not proof of a bug. Explain the specific
behavior left unverified when the gap is material.

## 5. Filter and prioritize

Report only actionable findings supported by evidence.
Keep unresolved material questions separate from confirmed defects.
Do not manufacture findings to reach a quota.

Assign priority according to impact and triggering conditions:

- P0 — Critical: immediate action required; broad outage, severe data loss,
  or an active, broadly exploitable security failure.
- P1 — High: fix before merging; a major supported flow is broken or
  there is a significant security or data integrity problem.
- P2 — Medium: a real defect under specific supported conditions.
- P3 — Low: a limited-impact defect that can reasonably be deferred.

Do not inflate priority based on hypothetical worst-case scenarios.
Combine findings with the same root cause unless they need distinct fixes.

## 6. Report the review

Lead with findings, ordered by priority.

For each finding, include:

- Priority and a short, specific title.
- File path and the smallest useful line range.
- Concrete triggering conditions.
- What fails and why, supported by evidence.
- The smallest appropriate correction direction.

Prefer locations within the reviewed diff. If the symptom is elsewhere,
connect it to the changed code that causes it.

After findings, briefly include:

- Material open questions or assumptions, if any.
- Verification performed and its results.
- Scope, coverage limitations, and significant untested behavior.
- Overall assessment: blocking issues, non-blocking issues, or no
  actionable findings within the reviewed scope.

If no actionable issues are found, say so explicitly.
Do not equate passing tests or an empty findings list with proof that
the change is bug-free.

Before responding, recheck findings against the code, remove duplicates
and unsupported claims, and verify locations and priorities.

### Example complete report

This is an illustrative format. Never copy its findings, commands, counts,
or results unless they are supported by the actual review.

#### Findings

**[P1] Restrict order updates to the authenticated owner**

- Location: `app/controllers/orders_controller.rb:42–44`.
- Trigger: an authenticated user submits PATCH `/orders/:id` with an
  order ID belonging to another account.
- Impact: the new action uses `Order.find(params[:id])` and updates the
  record without an ownership check. The inherited callbacks authenticate
  the user but do not authorize access to that order.
- Suggested fix: look up the order through the authenticated user's
  permitted scope and test a cross-account update attempt.

#### Material open questions

- Should administrators use this endpoint? The PR does not specify an
  administrator exception, and the existing route is customer-facing.

#### Verification performed

- `bundle exec rspec spec/requests/orders_spec.rb` — passed, 12 examples.
  Existing examples cover only updates by the owner.
- `bundle exec rubocop app/controllers/orders_controller.rb` — passed.
- The ownership finding is based on tracing the route, inherited callbacks,
  lookup, and update; a cross-account request was not executed.

#### Scope and limitations

- Reviewed the order-update changes at head `abc1234`, including the
  controller, route, model, and request specs.
- Browser behavior and the full test suite were not verified.

#### Overall assessment

Fix the ownership check before merging. Passing existing tests does not
cover the cross-account update scenario.
