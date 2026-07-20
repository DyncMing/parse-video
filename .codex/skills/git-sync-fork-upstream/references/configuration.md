# Git Sync Fork Upstream Configuration

Use this reference when the sync request needs explicit repository, branch, shell, or tag configuration.

## Required Values

| Name | Meaning | Current project default |
| --- | --- | -- |
| `$originUrl` | Fork repository URL, normally remote `origin` | `https://github.com/DyncMing/parse-video.git` |
| `$upstreamUrl` | Original/source repository URL, normally remote `upstream` | `https://github.com/wujunwei928/parse-video.git` |
| `$syncMode` | `single-branch` or `all-branches` | Default to `all-branches`; use `single-branch` only when one branch is requested |
| `$targetBranch` | Local/fork branch to update in `single-branch` mode | Current branch, often `main` |
| `$upstreamBranch` | Upstream branch to merge from in `single-branch` mode | Same name as `$targetBranch` unless specified |
| `$branchMap` | Branch pairs to sync in all-branches mode | Same-name branch intersection between `origin/*` and `upstream/*` |
| `$branchMapFile` | Optional branch map file for all-branches mode when branch names differ | Not required for same-name branches |
| `$initialBranch` | Branch active before sync begins | Output of `git symbolic-ref --short -q HEAD` |
| `$validateCommand` | Command that must pass before script push | Repository-appropriate test/build command |
| `$validateScriptFile` | Validation script file for multi-step validation | Prefer this over `validateCommand` when validation uses variables, loops, or nested quoting |
| `$skipValidation` | Explicit approval to execute without validation | Use only when the user accepts an unvalidated sync; never with push |
| `$confirmAllBranches` | Explicit approval for risky all-branches script execution | Required for >3 branches or protected/release-like names |
| `$refreshPlan` | Refresh remotes and remote refs before dry-run planning | Use when remote refs may be stale or missing |

Treat `$var` names as logical placeholders. Replace them with concrete values or set them in the active shell before running commands.

## Config File

The project-level defaults file is:

```text
.codex/skills/git-sync-fork-upstream/sync-fork-upstream.conf
```

The bundled scripts read it only when explicitly passed:

```bash
scripts/sync_fork_upstream.sh --config-file .codex/skills/git-sync-fork-upstream/sync-fork-upstream.conf --refresh-plan
```

```powershell
scripts/sync_fork_upstream.ps1 -ConfigFile .codex/skills/git-sync-fork-upstream/sync-fork-upstream.conf -RefreshPlan
```

Supported config keys:

```text
originUrl=<fork repository URL>
upstreamUrl=<original/source repository URL>
mode=all-branches
targetBranch=
upstreamBranch=
branchMapFile=
validateCommand=
validateScriptFile=
```

`syncMode` is accepted as an alias for `mode`. Command-line arguments override config file values. Config files cannot enable execution, push, validation skipping, or all-branches confirmation; use `--execute`, `--push`, `--skip-validation`, and `--confirm-all-branches` only as explicit command-line flags. Use either `validateCommand` or `validateScriptFile`, not both.

## Remote Direction

This skill is one-way:

- `upstream` is the read-only original/source repository.
- `origin` is the writable fork repository.
- `upstreamUrl` is used only for fetch, branch discovery, merge sources, and tag inspection.
- `--push` and `-Push` mean push synchronized fork branches to `origin` only.
- Never push, create branches, delete branches, update tags, or force-update anything on `upstream`.

If `originUrl` and `upstreamUrl` are the same URL, stop and fix the remote configuration before syncing. If the user wants fork changes submitted back to upstream, use a separate PR/MR workflow outside this skill.

Remote equality checks in the bundled scripts are exact string comparisons. Different URL forms can still point to the same repository. Confirm repository ownership manually before execution: `origin` must be the fork, and `upstream` must be the original/source repository.

## Current Project Defaults

For this repository:

```text
originUrl=https://github.com/DyncMing/parse-video.git
upstreamUrl=https://github.com/wujunwei928/parse-video.git
```

If the actual `origin` or `upstream` remote differs, report the current value before changing it.

## Branch Mapping

For `single-branch` mode:

- Default `$targetBranch` to the current branch.
- If the checkout is detached and `$targetBranch` is not provided, stop and ask for the target fork branch.
- Default `$upstreamBranch` to the same branch name only if `upstream/$targetBranch` exists.
- If branch names differ, ask for the explicit source branch.
- Use plain branch names only. Do not pass `origin/<branch>` or `upstream/<branch>` as script branch arguments.
- Scripts require `--mode single-branch` or `-Mode single-branch` when target/upstream branch arguments are provided. In default all-branches mode, use a branch map file for branch mapping.

For `all-branches` mode, which is the default:

- Build `$branchMap` from same-name branches that exist on both `origin` and `upstream`.
- If branch names differ and they must be synced in one run, create a branch map file and pass it with `--branch-map-file` or `-BranchMapFile`.
- Skip `HEAD` and `sync-backup/*`.
- Skip fork-only branches by default because upstream has no source branch to sync from.
- Dry-run output and execute summaries list skipped fork-only branches as `skipped: origin/<branch> - exists only on origin`.
- Bundled scripts skip upstream-only branches; create them only as an explicit manual step after user approval.
- Show the final map before merging.

Example map:

```text
origin/main <= upstream/main
origin/develop <= upstream/develop
skipped: origin/feature-local - exists only on origin
```

Branch map file format for different branch names:

```text
# target branch in origin/fork = source branch in upstream/original
develop=main
release/x2=release/upstream-x2
```

Use branch names only. Do not include `origin/` or `upstream/` prefixes in the file. Bundled scripts reject map entries with remote prefixes or invalid Git branch names.

## Shell Notes

Bash/Git Bash:

```bash
originUrl="https://github.com/DyncMing/parse-video.git"
upstreamUrl="https://github.com/wujunwei928/parse-video.git"
targetBranch="main"
upstreamBranch="main"
validateCommand="go test ./..."
initialBranch="$(git symbolic-ref --short -q HEAD)"
```

PowerShell:

```powershell
$originUrl = "https://github.com/DyncMing/parse-video.git"
$upstreamUrl = "https://github.com/wujunwei928/parse-video.git"
$targetBranch = "main"
$upstreamBranch = "main"
$validateCommand = "go test ./..."
$validateScriptFile = ".\validate-sync.ps1"
$initialBranch = git symbolic-ref --short -q HEAD
```

For PowerShell, keep `$validateCommand` to simple one-line commands. If validation needs arrays, loops, module lists, or `$variables`, create a `.ps1` file and pass `-ValidateScriptFile $validateScriptFile`. Avoid nested `powershell -Command "..."` validation strings because the outer shell and script executor can double-parse variables such as `$mods` before the validation command runs.

## Bundled Scripts

Use these scripts when repeatability matters:

| Shell | Script |
| --- | --- |
| Bash, Git Bash, Bash-compatible Linux/macOS shell | `scripts/sync_fork_upstream.sh` |
| PowerShell | `scripts/sync_fork_upstream.ps1` |

Both scripts default to dry-run planning and require an explicit execution flag before changing branches:

```bash
scripts/sync_fork_upstream.sh --upstream-url "$upstreamUrl" --mode all-branches
scripts/sync_fork_upstream.sh --upstream-url "$upstreamUrl" --mode all-branches --refresh-plan
scripts/sync_fork_upstream.sh --upstream-url "$upstreamUrl" --mode all-branches --validate-command "$validateCommand" --execute
scripts/sync_fork_upstream.sh --upstream-url "$upstreamUrl" --mode all-branches --validate-command "$validateCommand" --execute --push --confirm-all-branches
scripts/sync_fork_upstream.sh --upstream-url "$upstreamUrl" --mode all-branches --execute --skip-validation
scripts/sync_fork_upstream.sh --upstream-url "$upstreamUrl" --mode all-branches --branch-map-file sync-branches.map --refresh-plan
```

```powershell
scripts/sync_fork_upstream.ps1 -UpstreamUrl $upstreamUrl -Mode all-branches
scripts/sync_fork_upstream.ps1 -UpstreamUrl $upstreamUrl -Mode all-branches -RefreshPlan
scripts/sync_fork_upstream.ps1 -UpstreamUrl $upstreamUrl -Mode all-branches -ValidateCommand $validateCommand -Execute
scripts/sync_fork_upstream.ps1 -UpstreamUrl $upstreamUrl -Mode all-branches -ValidateScriptFile $validateScriptFile -Execute -ConfirmAllBranches
scripts/sync_fork_upstream.ps1 -UpstreamUrl $upstreamUrl -Mode all-branches -ValidateCommand $validateCommand -Execute -Push -ConfirmAllBranches
scripts/sync_fork_upstream.ps1 -UpstreamUrl $upstreamUrl -Mode all-branches -Execute -SkipValidation
scripts/sync_fork_upstream.ps1 -UpstreamUrl $upstreamUrl -Mode all-branches -BranchMapFile sync-branches.map -RefreshPlan
```

Plain dry-run uses existing local remote refs. Add `--refresh-plan` or `-RefreshPlan` when remotes were just configured, upstream branches may have changed, or the branch map must be based on fresh refs. Refresh planning may add/configure remotes and fetch remote refs, but it does not merge or push.

Execution requires `--validate-command` / `-ValidateCommand` or `--validate-script-file` / `-ValidateScriptFile` unless the user explicitly accepts `--skip-validation` or `-SkipValidation`. Add `--push` or `-Push` only after reviewing the dry-run plan and setting a validation command or script file; push cannot skip validation. The scripts run validation after each merge and re-check that the worktree is clean after validation and before pushing. In all-branches mode, all mapped branches must merge and validate successfully before any branch is pushed. They push branch-by-branch to `origin` only, never to `upstream`, and never call `git push --all`.

The scripts print validation commands before running them. Do not include real passwords, tokens, API keys, cookies, session values, or other sensitive credentials in validation command arguments, logs, or test output.

Validation commands must not leave generated or modified files in the worktree. If `git status --short` is not clean after validation, the scripts stop before processing later branches or pushing.

When execution fails after processing has started, the scripts still print a summary with synchronized, skipped, conflicted, failed-validation, dirty-after-validation, skipped-validation, local-unpublished-commits, missing-upstream, and pushed branches.

For all-branches mode, inspect dry-run output first. If the plan contains more than three branches or branches named `main`, `master`, `develop`, `release/*`, or `hotfix/*`, execution requires `--confirm-all-branches` or `-ConfirmAllBranches`.

If the dry-run reports no matching branches, either the fork and upstream do not share same-name branches or refs are stale. Run refresh planning first; if branch names intentionally differ, use a branch map file.

For Git Bash, Linux, and macOS, run a small dry-run and E2E in that shell before relying on the Bash script for important branches.

For Bash, `--validate-script-file` runs the file with `bash`. For PowerShell, `-ValidateScriptFile` runs the file with PowerShell. Match the script file syntax to the wrapper script you are using.

## Tags

Branch sync does not include tags. If the user asks for tags or releases:

1. Show local and upstream tag differences.
2. Ask before creating missing tags in the fork.
3. Never delete, overwrite, or force-update tags unless explicitly approved after showing the diff.
