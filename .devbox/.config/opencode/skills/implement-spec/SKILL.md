---
name: implement-spec
description: "Implement the result of /to-spec and /to-tickets in code."
disable-model-invocation: true
---

> Note: this skill sets `disable-model-invocation: true`, so it cannot be loaded with the Skill tool -- read this file directly and follow it.

You have been provided a spec. This spec should have tickets associated with it, describing how to implement the spec.

The issue tracker should have been provided to you. If not, tell the user to run `/setup-matt-pocock-skills`.

The goal is the entire spec implemented on a single **integration branch**, with every ticket resolved the way the issue tracker closes work.

The tickets are not a list of steps. They are a **task graph** with blocking relationships between them. This means there is always a **frontier** of tickets which are ready to be grabbed.

Communication to and from subagents should be sparse. Communicate primarily through **context pointers**: to the spec, tickets, research notes, and previous commits. Don't duplicate information already available via pointers.

**Implementer subagents** should be run in the background where possible for maximum concurrency. Dispatch is not delivery: reap a finished implementer from its ticket branch (`git log`, ticket file), not from a completion callback. If a background subagent goes silent, consult your harness's session transcript or log (see Harness notes) before deciding it is stuck.

**Checkpoint** after every merged ticket and around browser/verify passes: emit one `done / running / remaining` line and append it to the active ticket, so a long run shows progress without a status request.

## Steps

1. Read the spec and tickets to understand the task graph.

2. (optional) Use an **exploration subagent** to conduct any exploration required by the tickets - relevant codebase files or external documentation. Prefer an agent that can persist notes outside the repo where every implementer can reach them; if the available exploration agent is read-only, have it return notes inline and save them yourself (see Harness notes).

3. Create the integration branch. If the issue tracker closes work through PRs, or the user asks for one, open a draft PR after the first merge in step 6 (a branch with no commits ahead of main can't open one), marked as closing the spec and tickets.

4. Write the shared contract to tracked `.scratch/<feature>/contract.md`, then run a **spec review** over the contract and tickets before dispatching any implementer. Every rule traces to a spec line; resolve ambiguity here rather than in a fix pass after merge.

5. Use **implementer subagents** to implement each ticket, each in its own worktree on its own branch. Each implementer subagent:
    - confirms its worktree is based on the integration branch before starting, and resets onto it if not;
    - calls the Skill tool with `tdd` to build the ticket;
    - commits after each green TDD stage, so a step-cap stop leaves completed work on the branch;
    - updates its ticket at the canonical checkout path (absolute), never the worktree copy, until ticket files travel with worktrees;
    - merges the integration branch tip into its own branch before reporting done

6. Once an **implementer subagent** completes, or its branch shows it completed, merge its work to the integration branch with a **merger subagent**.

7. If this changes the **frontier** of available tickets, kick off more **implementer subagents** to work on the new tickets. This allows for maximum concurrency.

8. Once all tickets are complete, call the Skill tool with `code-review` on the integration branch. Fix all issues raised by the code review in a single **implementer subagent**.

9. If a draft PR exists, mark it ready for review. Otherwise, resolve each ticket the way the issue tracker closes work, and report the integration branch.

10. Clean up all **implementer subagent** worktrees.

## Harness notes

The steps above assume an orchestrator with background subagents, git worktrees, and a re-readable session transcript. The concrete mapping below is for the OpenCode harness this skill was built against; on any other harness (Codex, Claude Code, …), map each item to the local equivalent and ignore the OpenCode paths and names.

- **OpenCode agents:** `matt-exploration` (or `general`) persists notes outside the repo; the plain `explore` agent is read-only and returns notes inline. Implementers are `matt-implementer`, mergers `matt-merger`, reviewers `matt-spec-review` / `matt-standards-review`.
- **Silent subagents:** re-read the transcript in `session_v2` / `session_message` in `~/.local/share/opencode/opencode.db` — open read-only, never write to it.
- **Worktrees:** creation links the canonical checkout's gitignored env files and dependencies into the new worktree; confirm them (or run the repo's worktree-prepare step) before an implementer starts.
