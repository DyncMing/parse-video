---
name: git-sync-fork-upstream
description: Use when synchronizing one branch or all branches of a Git fork with its upstream/original repository, configuring origin and upstream URLs, mapping fork branches to upstream branches, merging upstream changes, handling conflicts, validating results, or pushing synchronized fork branches.
---

# Git Sync Fork Upstream

## Overview

Use this skill to sync all matching branches, or one explicitly selected branch, of a fork repository from its original upstream without losing local work on Windows, Linux, or macOS. Default to all-branches merge-based sync; do not rebase shared branches unless the user explicitly asks for history rewriting.

This is a one-way fork sync workflow: read/fetch/merge from `upstream` into the local fork branch, then optionally push the synchronized fork branch to `origin`. Never push, create branches, delete branches, update tags, or perform any write operation against `upstream`. If the user wants to submit fork changes back to upstream, stop and treat that as a separate PR/MR contribution workflow, not this sync skill.

## Configuration

Before running sync commands, establish `$originUrl`, `$upstreamUrl`, `$syncMode`, and `$branchMap`. For single-branch mode, also establish `$targetBranch` and `$upstreamBranch`. For repeat use, store repository defaults in [sync-fork-upstream.conf](sync-fork-upstream.conf) and pass it with `--config-file` or `-ConfigFile`.

Read [references/configuration.md](references/configuration.md) when:

- Any config value is unclear.
- The user wants to sync another fork repository.
- The user asks to sync all branches.
- Branch names differ between `origin` and `upstream`.
- Tags/releases are mentioned.

If a value remains unclear after inspection and the configuration reference, ask before changing remotes or merging.

## Command Syntax

Most Git commands are identical on Windows PowerShell, Linux shells, and macOS shells. When a command uses variable assignment, command substitution, or timestamps, choose the syntax for the active shell:

| Shell | Variable example | Timestamp example |
| --- | --- | --- |
| Bash, Git Bash | `backup="sync-backup/main-$(date +%Y%m%d-%H%M%S)"` | `$(date +%Y%m%d-%H%M%S)` |
| PowerShell | `$backup = "sync-backup/main-$(Get-Date -Format yyyyMMdd-HHmmss)"` | `$(Get-Date -Format yyyyMMdd-HHmmss)` |

Do not run a PowerShell-only assignment in Bash/Git Bash, or a Bash-only assignment in PowerShell.

Variables such as `$originUrl`, `$targetBranch`, and `$upstreamBranch` are logical placeholders in this guide. Before executing commands, either set them in the active shell or replace them with concrete values.

## Shared Setup

For deterministic execution, prefer the bundled scripts when a shell is available:

- Bash/Git Bash/Linux/macOS shells with Bash: [scripts/sync_fork_upstream.sh](scripts/sync_fork_upstream.sh)
- Windows PowerShell: [scripts/sync_fork_upstream.ps1](scripts/sync_fork_upstream.ps1)

The scripts default to dry-run planning. They modify branches or the worktree only when `--execute` or `-Execute` is supplied. Plain dry-run uses existing remote refs. Use `--refresh-plan` or `-RefreshPlan` when the plan must fetch fresh remote refs first; that may add/configure remotes and run `git fetch --prune`, but it still does not merge or push. Use `--config-file` or `-ConfigFile` to load safe defaults such as `originUrl`, `upstreamUrl`, branch names, branch map file, and validation command or script file; command-line arguments override config values. Config files cannot enable execute, push, validation skipping, or all-branches confirmation. Execution requires `--validate-command` / `-ValidateCommand` or `--validate-script-file` / `-ValidateScriptFile` unless the user explicitly accepts `--skip-validation` or `-SkipValidation`; never skip validation silently. If `--push` or `-Push` is used, validation is required and must pass before pushing to `origin`; the scripts also re-check that the worktree is clean after validation and immediately before pushing. Use `ValidateCommand` only for simple commands. For multi-step PowerShell validation, loops, variables such as `$mods`, or nested quoting, write a `.ps1` file and pass `-ValidateScriptFile`; do not wrap complex PowerShell in `powershell -Command "..."`. The scripts print validation commands and script paths before running them, so never put real passwords, tokens, API keys, cookies, session values, or other secrets in validation command text, file paths, or script output. In all-branches mode, scripts merge and validate every mapped branch first, then push only after the full branch set has passed. If validation creates or modifies files, the scripts stop before touching later branches. Risky plans require `--confirm-all-branches` or `-ConfirmAllBranches`. For different branch names in all-branches mode, use `--branch-map-file` or `-BranchMapFile`; otherwise the scripts sync only same-name branches. Dry-run output and execute summaries list fork-only branches skipped because they exist only on `origin`. Still inspect the dry-run plan before executing.

1. Inspect the checkout and protect user work:

```shell
git status --short
git status -sb
git symbolic-ref --short -q HEAD
git branch -vv
git remote -v
```

Stop before syncing if there are uncommitted or untracked user changes that could be overwritten. Ask whether to commit, stash, or leave them untouched.

Remember the initial branch before switching branches during all-branches sync. At the end, switch back to it unless the user wants to stay on the last processed branch.

2. Configure remotes:

```shell
git remote get-url origin
git remote get-url upstream
```

If `origin` is missing or points to the wrong fork, report it and ask before changing it. If `upstream` is missing, add it from `$upstreamUrl`:

```shell
git remote add upstream $upstreamUrl
```

If `upstream` points elsewhere, state the current URL and change it only when it is clearly stale or the user confirms:

```shell
git remote set-url upstream $upstreamUrl
```

The scripts compare remote URLs as strings only. They can stop exact URL matches, but they cannot prove that different URL forms, such as SSH vs HTTP, with or without `.git`, or aliases, point to different repositories. Confirm manually that `origin` is the fork and `upstream` is the original/source repository before executing.

3. Fetch both remotes:

```shell
git fetch --prune origin
git fetch --prune upstream
```

After shared setup, use the all-branches workflow by default, or the single-branch workflow only when a specific branch is requested.

## Single-Branch Workflow

Script examples:

Bash/Git Bash:

```bash
scripts/sync_fork_upstream.sh --mode single-branch --upstream-url "$upstreamUrl" --target-branch "$targetBranch" --upstream-branch "$upstreamBranch"
scripts/sync_fork_upstream.sh --mode single-branch --config-file .codex/skills/git-sync-fork-upstream/sync-fork-upstream.conf --refresh-plan
scripts/sync_fork_upstream.sh --mode single-branch --upstream-url "$upstreamUrl" --target-branch "$targetBranch" --upstream-branch "$upstreamBranch" --refresh-plan
scripts/sync_fork_upstream.sh --mode single-branch --upstream-url "$upstreamUrl" --target-branch "$targetBranch" --upstream-branch "$upstreamBranch" --validate-command "go test ./..." --execute
scripts/sync_fork_upstream.sh --mode single-branch --upstream-url "$upstreamUrl" --target-branch "$targetBranch" --upstream-branch "$upstreamBranch" --validate-command "go test ./..." --execute --push
```

PowerShell:

```powershell
scripts/sync_fork_upstream.ps1 -Mode single-branch -UpstreamUrl $upstreamUrl -TargetBranch $targetBranch -UpstreamBranch $upstreamBranch
scripts/sync_fork_upstream.ps1 -Mode single-branch -ConfigFile .codex/skills/git-sync-fork-upstream/sync-fork-upstream.conf -RefreshPlan
scripts/sync_fork_upstream.ps1 -Mode single-branch -UpstreamUrl $upstreamUrl -TargetBranch $targetBranch -UpstreamBranch $upstreamBranch -RefreshPlan
scripts/sync_fork_upstream.ps1 -Mode single-branch -UpstreamUrl $upstreamUrl -TargetBranch $targetBranch -UpstreamBranch $upstreamBranch -ValidateCommand "go test ./..." -Execute
scripts/sync_fork_upstream.ps1 -Mode single-branch -UpstreamUrl $upstreamUrl -TargetBranch $targetBranch -UpstreamBranch $upstreamBranch -ValidateScriptFile .\validate-sync.ps1 -Execute
scripts/sync_fork_upstream.ps1 -Mode single-branch -UpstreamUrl $upstreamUrl -TargetBranch $targetBranch -UpstreamBranch $upstreamBranch -ValidateCommand "go test ./..." -Execute -Push
```

1. Choose branches:

```shell
git symbolic-ref --short -q HEAD
git branch -r
git branch -vv
```

Use the current branch as `$targetBranch` unless the user names another branch. If the checkout is detached and no target branch was provided, stop and ask for the target fork branch. Use `upstream/$targetBranch` as `$upstreamBranch` only if it exists. If the upstream branch name differs, stop and ask which upstream branch to merge. Branch names passed to scripts or branch map files must be plain branch names; do not include `origin/` or `upstream/` prefixes.

2. Check whether local, origin, and upstream have diverged:

```shell
git status -sb
git log --oneline --left-right --cherry-pick HEAD...origin/$targetBranch
git log --oneline --left-right --cherry-pick HEAD...upstream/$upstreamBranch
```

If local is behind `origin/$targetBranch` and has no unpublished commits, update from origin first:

```shell
git merge --ff-only origin/$targetBranch
```

If local and `origin/$targetBranch` have diverged, stop and ask before combining origin divergence with upstream sync. If local has unpublished commits, call out the commit count before merging upstream.

3. Create a timestamped safety branch:

```bash
backup="sync-backup/$targetBranch-before-upstream-sync-$(date +%Y%m%d-%H%M%S)"
git branch "$backup"
```

PowerShell:

```powershell
$backup = "sync-backup/$targetBranch-before-upstream-sync-$(Get-Date -Format yyyyMMdd-HHmmss)"
git branch $backup
```

4. Merge upstream into the target branch:

```shell
git checkout $targetBranch
git merge upstream/$upstreamBranch
```

If Git reports conflicts, inspect before editing:

```shell
git status
git diff --name-only --diff-filter=U
```

Resolve only conflict blocks. Do not clean unrelated dead code, formatting, comments, or neighboring logic. If a conflict requires a semantic choice, such as API contracts, config defaults, protocol fields, data migrations, or build behavior, stop and ask.

If the merge should be abandoned:

```shell
git merge --abort
git checkout $targetBranch
```

The backup branch remains available for comparison or recovery.

5. Validate after a clean merge:

```shell
git status --short
git log --oneline --decorate -5
```

Pick validation from the repository shape. Prefer the narrowest command that proves the sync did not break the touched area:

```shell
go test ./...
```

For non-Go or mixed repositories, inspect existing build/test entry points such as `README.md`, `build.sh`, `CMakeLists.txt`, `Makefile`, `package.json`, or CI config before choosing validation. Do not claim the sync is complete while validation is still running or failing.

Do not include secrets in validation commands, command arguments, echoed environment variables, logs, or test output. If a validation command requires credentials, configure them through the existing secure project mechanism and ensure the command does not print them.

For PowerShell, keep `-ValidateCommand` to simple commands such as `go test ./...` or `git status --short`. If validation needs variables, arrays, loops, here-strings, or multiple module commands, put the logic in a `.ps1` file and pass `-ValidateScriptFile .\validate-sync.ps1`. This avoids double parsing through the outer shell and the script's validation executor.

For Bash/Git Bash, `--validate-script-file` runs the file with `bash`; for Windows PowerShell, `-ValidateScriptFile` runs the file with PowerShell. Match the validation file syntax to the wrapper script being used.

6. Push only after validation:

```shell
git push origin $targetBranch
```

`origin` is the only allowed push destination in this skill. Do not run any `git push` command whose destination is `upstream`.

When using the bundled scripts, `--execute` or `-Execute` must be paired with `--validate-command` or `-ValidateCommand`, unless the user explicitly accepts `--skip-validation` or `-SkipValidation`. `--push` or `-Push` cannot skip validation; it must be paired with a validation command.

## All-Branches Workflow

Use this workflow by default for generic fork sync requests. It syncs same-name branches that already exist on both `origin` and `upstream`; fork-only branches are skipped unless an explicit branch map says otherwise.

Script examples:

Bash/Git Bash:

```bash
scripts/sync_fork_upstream.sh --upstream-url "$upstreamUrl" --mode all-branches
scripts/sync_fork_upstream.sh --upstream-url "$upstreamUrl" --mode all-branches --refresh-plan
scripts/sync_fork_upstream.sh --upstream-url "$upstreamUrl" --mode all-branches --branch-map-file sync-branches.map --refresh-plan
scripts/sync_fork_upstream.sh --upstream-url "$upstreamUrl" --mode all-branches --validate-command "go test ./..." --execute
scripts/sync_fork_upstream.sh --upstream-url "$upstreamUrl" --mode all-branches --validate-command "go test ./..." --execute --push --confirm-all-branches
```

PowerShell:

```powershell
scripts/sync_fork_upstream.ps1 -UpstreamUrl $upstreamUrl -Mode all-branches
scripts/sync_fork_upstream.ps1 -UpstreamUrl $upstreamUrl -Mode all-branches -RefreshPlan
scripts/sync_fork_upstream.ps1 -UpstreamUrl $upstreamUrl -Mode all-branches -BranchMapFile sync-branches.map -RefreshPlan
scripts/sync_fork_upstream.ps1 -UpstreamUrl $upstreamUrl -Mode all-branches -ValidateCommand "go test ./..." -Execute
scripts/sync_fork_upstream.ps1 -UpstreamUrl $upstreamUrl -Mode all-branches -ValidateScriptFile .\validate-sync.ps1 -Execute -ConfirmAllBranches
scripts/sync_fork_upstream.ps1 -UpstreamUrl $upstreamUrl -Mode all-branches -ValidateCommand "go test ./..." -Execute -Push -ConfirmAllBranches
```

1. Build a branch map from remote branches:

```shell
git branch -r
git for-each-ref --format='%(refname:strip=3)' refs/remotes/origin
git for-each-ref --format='%(refname:strip=3)' refs/remotes/upstream
```

When storing the branch lists in variables, use shell-appropriate syntax.

Bash/Git Bash:

```bash
originBranches="$(git for-each-ref --format='%(refname:strip=3)' refs/remotes/origin)"
upstreamBranches="$(git for-each-ref --format='%(refname:strip=3)' refs/remotes/upstream)"
```

PowerShell:

```powershell
$originBranches = git for-each-ref --format='%(refname:strip=3)' refs/remotes/origin
$upstreamBranches = git for-each-ref --format='%(refname:strip=3)' refs/remotes/upstream
```

Exclude remote symbolic refs and backup/generated branches:

- Exclude `HEAD`.
- Exclude branches under `sync-backup/`.
- Exclude branches that exist only on `origin`; these are fork-created branches and are skipped by default because upstream has no source branch to sync from.
- Exclude branches that exist only on `upstream` unless the user asks to create them in the fork.

Default `$branchMap` to same-name branches that exist on both remotes, such as `main -> main` and `develop -> develop`. If branch names differ, stop and ask for an explicit map. For bundled scripts, put the map in a text file and pass `--branch-map-file` or `-BranchMapFile`:

```text
# target branch in origin/fork = source branch in upstream/original
develop=main
release/x2=release/upstream-x2
```

Use branch names only; do not include `origin/` or `upstream/` prefixes. The bundled scripts reject branch map entries with remote prefixes or invalid Git branch names.

The bundled scripts intentionally sync only branches that already exist on `origin`. They do not create upstream-only branches in the fork. If the user asks to create upstream-only branches, show the list first and handle that as an explicit manual step outside the scripts.

2. Print the planned branch map before changing branches:

```text
origin/<targetBranch> <= upstream/<upstreamBranch>
```

Ask for confirmation before continuing if the map includes more than three branches, creates local branches, or touches protected/release branches. The bundled scripts enforce this for plans with more than three branches or branches named `main`, `master`, `develop`, `release/*`, or `hotfix/*`; use `--confirm-all-branches` or `-ConfirmAllBranches` only after reviewing the dry-run plan.

3. Process one branch at a time. For each `$targetBranch` and `$upstreamBranch` pair, use this order:

   1. Ensure the local branch exists.
   2. Switch to the target branch.
   3. Check local, origin, and upstream divergence.
   4. Create a timestamped backup branch.
   5. Merge the upstream branch.

If the local branch already exists:

```shell
git checkout $targetBranch
```

If the local branch does not exist but `origin/$targetBranch` does, create it from origin:

```shell
git checkout -b $targetBranch origin/$targetBranch
```

If `origin/$targetBranch` does not exist and the user approved creating a new fork branch from upstream outside the bundled scripts:

```shell
git checkout -b $targetBranch upstream/$upstreamBranch
```

After switching or creating the local branch, inspect divergence:

```shell
git status --short
git status -sb
git log --oneline --left-right --cherry-pick HEAD...origin/$targetBranch
git log --oneline --left-right --cherry-pick HEAD...upstream/$upstreamBranch
```

If local is behind `origin/$targetBranch` and has no unpublished commits:

```shell
git merge --ff-only origin/$targetBranch
```

If local and `origin/$targetBranch` have diverged, stop and ask before merging upstream. If local is ahead of `origin/$targetBranch`, call out the unpublished commit count before merging upstream; bundled scripts print this count in the summary.

Create the backup branch with the active shell's timestamp syntax before the merge.

Bash/Git Bash:

```bash
backup="sync-backup/$targetBranch-before-upstream-sync-$(date +%Y%m%d-%H%M%S)"
git branch "$backup"
```

PowerShell:

```powershell
$backup = "sync-backup/$targetBranch-before-upstream-sync-$(Get-Date -Format yyyyMMdd-HHmmss)"
git branch $backup
```

Then merge upstream:

```shell
git merge upstream/$upstreamBranch
```

4. Stop the all-branches loop immediately on conflict, validation failure, dirty worktree after validation, or unclear semantic change. Do not continue to later branches while one branch is unresolved.

Bundled scripts print the final summary even when execution stops on conflict, missing upstream branch, validation failure, or dirty worktree after validation.

For conflicts:

```shell
git status
git diff --name-only --diff-filter=U
```

Resolve only conflict blocks. If the merge should be abandoned:

```shell
git merge --abort
```

5. Validate each branch after its merge. At minimum:

```shell
git status --short
git log --oneline --decorate -5
```

Run repository-appropriate tests/builds when feasible. If full validation is too expensive for every branch, state the tradeoff and ask before using a lighter validation command. Validation commands must leave `git status --short` clean; generated files should be cleaned, ignored, or committed through the normal project workflow before sync continues.

Bundled scripts require a validation command or validation script file for execution. Use `--skip-validation` or `-SkipValidation` only when the user explicitly accepts an unvalidated sync, and do not combine it with push. Do not pass both `-ValidateCommand` and `-ValidateScriptFile` in the same run.

6. Push all synchronized branches only after every processed branch is clean and validation results have been reported. If validation creates or modifies files, stop before pushing:

```shell
git push origin $targetBranch
```

Push branch-by-branch to `origin`. Do not push to `upstream`. Do not use `git push --all` unless the user explicitly asks for it after seeing the planned branch list.

7. Report a final branch summary:

```text
synced: <branch> <= upstream/<branch>
skipped: <branch> - exists only on origin
skipped: <branch> - user excluded
conflicted: <branch> - <files>
failed validation: <branch> - <command>
dirty after validation: <branch> - <command>
skipped validation: <branch>
local unpublished commits: <branch> - <count> commit(s) ahead of origin/<branch>
pushed: <branch>
```

After the summary, return to the initial branch when it still exists:

```shell
git checkout $initialBranch
```

If returning is unsafe because the working tree is not clean, report the current branch and ask before switching.

## Tags

This skill syncs branches by default, not tags. If the user asks to sync tags or releases, inspect tag differences first:

```shell
git tag -l
git ls-remote --tags upstream
```

Do not delete, overwrite, or force-update tags unless the user explicitly asks after seeing the tag diff.

## Decision Rules

| Situation | Action |
| --- | --- |
| Dirty worktree before sync | Stop and ask how to preserve changes. |
| `origin` missing or wrong | Report it; ask before changing fork destination. |
| `upstream` missing | Add it from `$upstreamUrl`. |
| `upstream` URL differs | Report current URL; change only if stale or confirmed. |
| `origin` and `upstream` resolve to the same URL | Stop; the fork destination and upstream source must be different remotes. |
| `origin` and `upstream` use different URL forms | Confirm repository ownership manually; script checks are exact-string checks only. |
| User asks to push/sync fork changes back to upstream | Stop; explain that upstream contribution is a separate PR/MR workflow and is outside this skill. |
| Source branch unclear | Ask which upstream branch to merge. |
| Single-branch mode with detached HEAD and target branch omitted | Stop; ask for the target fork branch. |
| All-branches mode receives single-branch parameters | Stop; require `--mode single-branch` / `-Mode single-branch`, or use a branch map file. |
| Generic sync request or user asks to sync all branches | Build and show `$branchMap`; process branches one at a time. |
| All-branches plan has no matching branches | Stop; refresh refs or use an explicit branch map file for different branch names. |
| Branch map entry includes `origin/` or `upstream/` | Stop; require plain branch names. |
| Branch exists only on origin | Skip by default; do not delete, overwrite, or try to sync it. |
| Branch exists only on upstream | Do not create it in the fork unless user approves; bundled scripts skip it. |
| All-branches loop hits a conflict | Stop the loop; resolve or abort before touching another branch. |
| Local branch behind origin | Use `git merge --ff-only origin/$targetBranch` when safe; ask if local and origin diverged. |
| Local unpublished commits | Call out the commit count before merging. |
| Merge conflicts | Resolve conflict blocks only; ask for semantic conflicts. |
| Merge needs to be abandoned | Use `git merge --abort`; keep the backup branch. |
| Tests or builds fail | Report the failing command and first useful error; do not push unless explicitly asked. |
| Validation command leaves generated or modified files | Stop; report `dirty after validation` and the `git status --short` output. |
| Script execute requested without validation | Stop; require `--validate-command` / `-ValidateCommand`, `--validate-script-file` / `-ValidateScriptFile`, or explicit `--skip-validation` / `-SkipValidation`. |
| Script push requested without validation | Stop; require `--validate-command` / `-ValidateCommand` or `--validate-script-file` / `-ValidateScriptFile`; push cannot use skip-validation. |
| Complex PowerShell validation is needed | Use `-ValidateScriptFile`; do not embed loops or `$variables` inside nested `powershell -Command` strings. |
| Both validation forms are provided | Stop; use either command or script file, not both. |
| Validation command contains or prints secrets | Stop; require a non-secret command or secure project credential mechanism that does not echo sensitive values. |
| Risky all-branches script execution lacks confirmation flag | Stop; require `--confirm-all-branches` or `-ConfirmAllBranches` after dry-run review. |
| User asks to sync tags | Show tag differences first; do not force-update tags by default. |

## Success Criteria

The sync is complete only when:

- `origin` points to the intended fork and `upstream` points to the intended original repository.
- No write operation was performed against `upstream`; `upstream` was used only as the source remote.
- In single-branch mode, the selected `$targetBranch` contains the selected `upstream/$upstreamBranch` changes.
- In all-branches mode, every branch in `$branchMap` has either been synchronized and validated or explicitly skipped with a reason.
- Fork-only branches that do not exist in upstream are skipped by default and listed in the final summary.
- `git status --short` has no unexpected files.
- Validation commands have completed and their result is reported.
- Validation commands did not leave generated or modified files in the worktree.
- If validation was explicitly skipped, the final summary says which branch skipped validation.
- Push to `origin $targetBranch` has succeeded for each requested branch, if pushing was requested.
