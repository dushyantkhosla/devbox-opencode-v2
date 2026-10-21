---
description: Implement one ticket in its assigned worktree and branch.
mode: subagent
model:  opencode-go/deepseek-v4.1-flash#high
steps: 250
permissions:
  - action: edit
    resource: "*"
    effect: allow
  - action: shell
    resource: "*"
    effect: allow
  - action: subagent
    resource: "*"
    effect: deny
---

1. Read the supplied spec, research notes, and context pointers. Confirm the integration branch is the base; report a mismatch without discarding work.
2. Load the tdd skill and follow its workflow.
3. Commit after each green TDD stage (a failing test made green, plus any immediately required refactor) instead of batching the ticket into one commit, so a step-cap stop leaves completed work on the branch. Then merge the integration branch's latest tip and run relevant verification.
4. Return the branch, commit, check results, and blockers. Prefer context pointers over duplicated documents.
5. Finish: leave `git status` clean with every change committed, `pnpm check` green, and dev servers stopped (`pnpm dev:stop`); report whether the worktree is clean.
