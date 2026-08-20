# Issue tracker: GitHub

Issues, specs, and Wayfinder maps for this repo live as GitHub issues in `Questie/QuestieTDB`. Use the `gh` CLI for all operations. This file is the repository's explicit tracker configuration and overrides Wayfinder's local Markdown fallback.

## Conventions

- **Create an issue**: `gh issue create --title "..." --body "..."`. Use a heredoc for multi-line bodies.
- **Read an issue**: `gh issue view <number> --json number,title,body,state,labels,assignees,comments --jq '{number, title, body, state, labels: [.labels[].name], assignees: [.assignees[].login], comments: [.comments[] | {author: .author.login, body, createdAt}]}'`.
- **List issues**: `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters.
- **Comment on an issue**: `gh issue comment <number> --body "..."`
- **Apply / remove labels**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- **Close**: `gh issue close <number> --comment "..."`

Infer the repo from `git remote -v` — `gh` does this automatically when run inside a clone.

## Pull requests as a triage surface

**PRs as a request surface: no.** _(Set to `yes` if this repo treats external PRs as feature requests; `/triage` reads this flag.)_

When set to `yes`, PRs run through the same labels and states as issues, using the `gh pr` equivalents:

- **Read a PR**: `gh pr view <number> --comments` and `gh pr diff <number>` for the diff.
- **List external PRs for triage**: `gh pr list --state open --json number,title,body,labels,author,authorAssociation,comments` then keep only `authorAssociation` of `CONTRIBUTOR`, `FIRST_TIME_CONTRIBUTOR`, or `NONE` (drop `OWNER`/`MEMBER`/`COLLABORATOR`).
- **Comment / label / close**: `gh pr comment`, `gh pr edit --add-label`/`--remove-label`, `gh pr close`.

GitHub shares one number space across issues and PRs, so a bare `#42` may be either — resolve with `gh pr view 42` and fall back to `gh issue view 42`.

## When a skill says "publish to the issue tracker"

Create a GitHub issue.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> --comments`.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a single issue with **child** issues as tickets.

- **Map**: a single issue labelled `wayfinder:map`, holding the Notes / Decisions-so-far / Fog body. `gh issue create --label wayfinder:map`.
- **Child ticket**: create the issue, fetch its numeric database id with `gh api repos/Questie/QuestieTDB/issues/<child> --jq .id`, then link it with `gh api --method POST repos/Questie/QuestieTDB/issues/<map>/sub_issues -F sub_issue_id=<child-db-id>`. Where sub-issues aren't enabled, add the child to a task list in the map body and put `Part of #<map>` at the top of the child body. Labels: `wayfinder:<type>` (`research`/`prototype`/`grilling`/`task`). Once claimed, the ticket is assigned to the driving dev.
- **Blocking**: GitHub's **native issue dependencies** — the canonical, UI-visible representation. Add an edge with `gh api --method POST repos/Questie/QuestieTDB/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`, where `<blocker-db-id>` is the blocker's numeric **database id** (`gh api repos/Questie/QuestieTDB/issues/<n> --jq .id`, _not_ the `#number` or `node_id`). GitHub reports `issue_dependencies_summary.blocked_by` (open blockers only — the live gate). Where dependencies aren't available, fall back to a `Blocked by: #<n>, #<n>` line at the top of the child body. A ticket is unblocked when every blocker is closed.
- **Frontier query**: list the map's children in map order with `gh api --paginate repos/Questie/QuestieTDB/issues/<map>/sub_issues`. Drop closed children, children with an assignee, and children whose `issue_dependencies_summary.blocked_by` count is nonzero; first remaining child wins. When using the task-list fallback, read child numbers from the map body and apply the same filters, resolving any `Blocked by:` lines manually.
- **Claim**: confirm the ticket is unassigned, then run `gh issue edit <n> --add-assignee @me` as the session's first write and immediately re-read its assignees. If concurrent claimers with different GitHub logins appear, the lexicographically first login keeps the claim and every other claimer removes itself with `gh issue edit <n> --remove-assignee @me`. Assignment cannot distinguish concurrent sessions using the same GitHub account, so those sessions must not claim tickets concurrently.
- **Resolve**: run `gh issue comment <n> --body "<answer>"`, append the context pointer (gist + link) to the map's Decisions-so-far, then run `gh issue close <n>` as the final unlock operation. A dependent ticket must not become claimable before the map links to the decision that unblocked it.
