# git-sync-fork-upstream

## 中文

### 作用

`git-sync-fork-upstream` 用于把源项目的新代码同步到 fork 项目。

同步方向固定为：

```text
upstream/original repository -> local fork branch -> origin/fork repository
```

这个 skill 不负责把 fork 中的改动提交回 `upstream`。如果需要向源项目贡献代码，应使用 Pull Request 或 Merge Request 流程。

### 第一次使用

所有命令都在项目根目录执行。

1. 确认当前仓库状态：

```shell
git status --short
git symbolic-ref --short -q HEAD
git remote -v
```

`git status --short` 必须为空。若有输出，先提交、stash 或明确保留这些改动。

2. 确认或修改项目默认配置文件：

```text
.codex/skills/git-sync-fork-upstream/sync-fork-upstream.conf
```

在该文件中维护本项目的默认值：

```text
originUrl=<fork-repository-url>
upstreamUrl=<upstream-repository-url>
mode=all-branches
```

本项目当前默认值是：

```text
originUrl=http://gitlab.agrtc.cn:82/x2meet/x2taskruntime.git
upstreamUrl=http://gitlab.agrtc.cn:82/EricMao/x2taskruntime.git
```

`sync-fork-upstream.conf` 支持以下 key：`originUrl`、`upstreamUrl`、`mode`、`syncMode`、`targetBranch`、`upstreamBranch`、`branchMapFile`、`validateCommand`。命令行参数优先级高于配置文件。

配置文件不能开启 `Execute`、`Push`、`SkipValidation` 或 `ConfirmAllBranches`。这些会改动分支或推送代码的参数必须在命令行中显式传入。

详细配置说明见：

```text
.codex/skills/git-sync-fork-upstream/references/configuration.md
```

3. 配置实际 Git remote：

```shell
git remote set-url origin <fork-repository-url>
git remote add upstream <upstream-repository-url>
```

如果 `upstream` 已存在，使用：

```shell
git remote set-url upstream <upstream-repository-url>
```

再次确认：

```shell
git remote -v
```

`origin` 必须是 fork 仓库，`upstream` 必须是源项目仓库。两者不能是同一个地址。

脚本只做 URL 字符串比较，不能判断 `ssh://`、`http://`、是否带 `.git`、大小写或别名不同但实际指向同一个仓库的情况。执行前必须人工确认 `origin` 是 fork 仓库，`upstream` 是源项目仓库。

### 默认同步所有同名分支

默认情况下，脚本同步 `origin` 和 `upstream` 都存在的同名分支。fork-only 分支会跳过，upstream-only 分支不会自动创建。

先看计划，不执行 merge，不 push：

PowerShell:

```powershell
.\.codex\skills\git-sync-fork-upstream\scripts\sync_fork_upstream.ps1 -ConfigFile .\.codex\skills\git-sync-fork-upstream\sync-fork-upstream.conf -RefreshPlan
```

Bash / Git Bash / Linux / macOS:

```bash
./.codex/skills/git-sync-fork-upstream/scripts/sync_fork_upstream.sh --config-file ./.codex/skills/git-sync-fork-upstream/sync-fork-upstream.conf --refresh-plan
```

执行并推送前，先确认 dry-run 计划。高风险 all-branches 计划需要 `-ConfirmAllBranches` / `--confirm-all-branches`：

PowerShell:

```powershell
.\.codex\skills\git-sync-fork-upstream\scripts\sync_fork_upstream.ps1 -ConfigFile .\.codex\skills\git-sync-fork-upstream\sync-fork-upstream.conf -ValidateCommand "go test ./..." -Execute -Push -ConfirmAllBranches
```

Bash / Git Bash / Linux / macOS:

```bash
./.codex/skills/git-sync-fork-upstream/scripts/sync_fork_upstream.sh --config-file ./.codex/skills/git-sync-fork-upstream/sync-fork-upstream.conf --validate-command "go test ./..." --execute --push --confirm-all-branches
```

脚本会逐个分支处理；任何分支发生冲突、验证失败或验证后工作区变脏时，流程会停止，不会继续处理后续分支。使用 `-Push` / `--push` 时，all-branches 模式会先完成所有分支的 merge 和验证，再逐个 push 到 `origin`。

### 同步单个分支

只有在明确只同步一个分支时，才使用 `single-branch`。

先看计划，不执行 merge，不 push：

PowerShell:

```powershell
.\.codex\skills\git-sync-fork-upstream\scripts\sync_fork_upstream.ps1 -Mode single-branch -UpstreamUrl "<upstream-repository-url>" -TargetBranch <fork-branch> -UpstreamBranch <upstream-branch> -RefreshPlan
.\.codex\skills\git-sync-fork-upstream\scripts\sync_fork_upstream.ps1 -ConfigFile .\.codex\skills\git-sync-fork-upstream\sync-fork-upstream.conf -Mode single-branch -RefreshPlan
```

Bash / Git Bash / Linux / macOS:

```bash
./.codex/skills/git-sync-fork-upstream/scripts/sync_fork_upstream.sh --mode single-branch --upstream-url "<upstream-repository-url>" --target-branch <fork-branch> --upstream-branch <upstream-branch> --refresh-plan
./.codex/skills/git-sync-fork-upstream/scripts/sync_fork_upstream.sh --config-file ./.codex/skills/git-sync-fork-upstream/sync-fork-upstream.conf --mode single-branch --refresh-plan
```

确认计划无误后执行同步。执行阶段默认必须提供验证命令：

PowerShell:

```powershell
.\.codex\skills\git-sync-fork-upstream\scripts\sync_fork_upstream.ps1 -Mode single-branch -UpstreamUrl "<upstream-repository-url>" -TargetBranch <fork-branch> -UpstreamBranch <upstream-branch> -ValidateCommand "go test ./..." -Execute
.\.codex\skills\git-sync-fork-upstream\scripts\sync_fork_upstream.ps1 -ConfigFile .\.codex\skills\git-sync-fork-upstream\sync-fork-upstream.conf -Mode single-branch -ValidateCommand "go test ./..." -Execute
```

Bash / Git Bash / Linux / macOS:

```bash
./.codex/skills/git-sync-fork-upstream/scripts/sync_fork_upstream.sh --mode single-branch --upstream-url "<upstream-repository-url>" --target-branch <fork-branch> --upstream-branch <upstream-branch> --validate-command "go test ./..." --execute
./.codex/skills/git-sync-fork-upstream/scripts/sync_fork_upstream.sh --config-file ./.codex/skills/git-sync-fork-upstream/sync-fork-upstream.conf --mode single-branch --validate-command "go test ./..." --execute
```

只有在明确接受“本次同步不做验证”的风险时，才使用 `-SkipValidation` / `--skip-validation`。该参数不能和 `-Push` / `--push` 一起使用。

如果需要把同步后的分支推送到 fork 仓库，必须提供验证命令：

PowerShell:

```powershell
.\.codex\skills\git-sync-fork-upstream\scripts\sync_fork_upstream.ps1 -Mode single-branch -UpstreamUrl "<upstream-repository-url>" -TargetBranch <fork-branch> -UpstreamBranch <upstream-branch> -ValidateCommand "go test ./..." -Execute -Push
```

Bash / Git Bash / Linux / macOS:

```bash
./.codex/skills/git-sync-fork-upstream/scripts/sync_fork_upstream.sh --mode single-branch --upstream-url "<upstream-repository-url>" --target-branch <fork-branch> --upstream-branch <upstream-branch> --validate-command "go test ./..." --execute --push
```

将 `go test ./...` 替换为当前项目真正的验证命令，例如 `npm test`、`make test`、`mvn test` 或项目 README/CI 中定义的构建命令。

验证命令会被脚本打印到终端。不要把真实密码、token、API key、cookie、session 或其他敏感凭据写进 `-ValidateCommand` / `--validate-command`，也不要使用会把敏感环境变量打印出来的验证命令。需要凭据时，应使用项目已有的安全配置方式，并确保命令不会输出敏感值。

验证命令执行完成后，工作区必须保持干净。如果验证命令生成或修改了文件，脚本会停止并输出 `dirty after validation`。请先清理这些文件、把应忽略的文件加入 `.gitignore`，或按项目流程提交必要文件后再继续。

### 所有分支模式规则

默认 all-branches 模式遵循以下规则：

- fork-only 分支跳过。
- upstream-only 分支不自动创建。
- dry-run 和执行 summary 会列出被跳过的 fork-only 分支，格式为 `skipped: origin/<branch> - exists only on origin`。
- 分支名超过 3 个，或包含 `main`、`master`、`develop`、`release/*`、`hotfix/*` 时，执行阶段必须加确认参数。

脚本会逐个分支处理；任何分支发生冲突、验证失败或验证后工作区变脏时，流程会停止，不会继续处理后续分支。使用 `-Push` / `--push` 时，all-branches 模式会先完成所有分支的 merge 和验证，全部通过后才逐分支 push 到 `origin`。失败退出前仍会输出 summary。

### 同步不同名分支

单分支同步时，直接分别指定 fork 分支和 upstream 分支：

```powershell
.\.codex\skills\git-sync-fork-upstream\scripts\sync_fork_upstream.ps1 -Mode single-branch -UpstreamUrl "<upstream-repository-url>" -TargetBranch develop -UpstreamBranch main -RefreshPlan
```

```bash
./.codex/skills/git-sync-fork-upstream/scripts/sync_fork_upstream.sh --mode single-branch --upstream-url "<upstream-repository-url>" --target-branch develop --upstream-branch main --refresh-plan
```

批量同步不同名分支时，先创建一个映射文件，例如：

```text
sync-branches.map
```

文件内容：

```text
# fork/origin target branch = upstream source branch
develop=main
release/x2=release/upstream-x2
```

只写分支名，不要写 `origin/` 或 `upstream/` 前缀。脚本会拒绝带 remote 前缀或不是合法 Git 分支名的映射项。

查看计划：

```powershell
.\.codex\skills\git-sync-fork-upstream\scripts\sync_fork_upstream.ps1 -UpstreamUrl "<upstream-repository-url>" -Mode all-branches -BranchMapFile sync-branches.map -RefreshPlan
```

```bash
./.codex/skills/git-sync-fork-upstream/scripts/sync_fork_upstream.sh --upstream-url "<upstream-repository-url>" --mode all-branches --branch-map-file sync-branches.map --refresh-plan
```

执行并推送：

```powershell
.\.codex\skills\git-sync-fork-upstream\scripts\sync_fork_upstream.ps1 -UpstreamUrl "<upstream-repository-url>" -Mode all-branches -BranchMapFile sync-branches.map -ValidateCommand "go test ./..." -Execute -Push -ConfirmAllBranches
```

```bash
./.codex/skills/git-sync-fork-upstream/scripts/sync_fork_upstream.sh --upstream-url "<upstream-repository-url>" --mode all-branches --branch-map-file sync-branches.map --validate-command "go test ./..." --execute --push --confirm-all-branches
```

### 冲突处理

脚本遇到 merge 冲突会停止。先查看冲突文件：

```shell
git status
git diff --name-only --diff-filter=U
```

只处理冲突块，不要顺手重构无关代码。若要放弃本次 merge：

```shell
git merge --abort
```

脚本在 merge 前会创建 `sync-backup/...` 备份分支，可用于恢复或比较。

### 参数速查

| PowerShell | Bash / Git Bash | 说明 |
| --- | --- | --- |
| `-ConfigFile sync-fork-upstream.conf` | `--config-file sync-fork-upstream.conf` | 读取 `key=value` 默认配置；命令行参数优先。 |
| `-RefreshPlan` | `--refresh-plan` | dry-run 时配置 remote 并 fetch 最新引用，不 merge，不 push。 |
| `-Execute` | `--execute` | 执行同步 merge。 |
| `-Push` | `--push` | 验证通过后 push 到 `origin`。 |
| `-ValidateCommand "go test ./..."` | `--validate-command "go test ./..."` | 执行和 push 前必须通过的验证命令。 |
| `-SkipValidation` | `--skip-validation` | 明确跳过执行阶段验证；不能和 push 同时使用。 |
| `-ConfirmAllBranches` | `--confirm-all-branches` | 确认执行高风险 all-branches 计划。 |
| `-BranchMapFile sync-branches.map` | `--branch-map-file sync-branches.map` | 批量同步不同名分支时使用的映射文件。 |

### 跨平台验证

PowerShell 脚本已在 Windows 环境验证。Bash 脚本已在 WSL Ubuntu 18.04 做过语法和关键 dry-run 验证，用于 Git Bash、Linux 和 macOS。首次在新的 Bash 环境使用前，建议先用临时 fork 仓库或非关键分支执行一次 dry-run 和一次最小 E2E，至少覆盖 `--refresh-plan`、`--branch-map-file`、验证失败 summary、all-branches 延迟 push。

如果 Windows PowerShell 直接查看 README 时中文显示乱码，请用支持 UTF-8 的终端或编辑器打开；文件内容本身按 UTF-8 保存。

## English

### Purpose

`git-sync-fork-upstream` synchronizes code from an original repository into a fork repository.

The direction is fixed:

```text
upstream/original repository -> local fork branch -> origin/fork repository
```

This skill does not submit fork changes back to `upstream`. Use a Pull Request or Merge Request workflow for that.

### First-Time Setup

Run all commands from the project root.

1. Check the repository state:

```shell
git status --short
git symbolic-ref --short -q HEAD
git remote -v
```

`git status --short` must be empty. If it prints anything, commit, stash, or explicitly preserve those changes first.

2. Confirm or update the project defaults file:

```text
.codex/skills/git-sync-fork-upstream/sync-fork-upstream.conf
```

Maintain this project's defaults there:

```text
originUrl=<fork-repository-url>
upstreamUrl=<upstream-repository-url>
mode=all-branches
```

Current defaults:

```text
originUrl=http://gitlab.agrtc.cn:82/x2meet/x2taskruntime.git
upstreamUrl=http://gitlab.agrtc.cn:82/EricMao/x2taskruntime.git
```

`sync-fork-upstream.conf` supports these keys: `originUrl`, `upstreamUrl`, `mode`, `syncMode`, `targetBranch`, `upstreamBranch`, `branchMapFile`, and `validateCommand`. Command-line arguments override config file values.

The config file cannot enable `Execute`, `Push`, `SkipValidation`, or `ConfirmAllBranches`. Flags that modify branches or push code must be passed explicitly on the command line.

Detailed configuration notes:

```text
.codex/skills/git-sync-fork-upstream/references/configuration.md
```

3. Configure actual Git remotes:

```shell
git remote set-url origin <fork-repository-url>
git remote add upstream <upstream-repository-url>
```

If `upstream` already exists, use:

```shell
git remote set-url upstream <upstream-repository-url>
```

Confirm the result:

```shell
git remote -v
```

`origin` must be the fork repository. `upstream` must be the original/source repository. They must not be the same URL.

The scripts compare remote URLs as strings only. They cannot prove that different URL forms, such as SSH vs HTTP, with or without `.git`, case differences, or aliases, point to different repositories. Before execution, manually confirm that `origin` is the fork repository and `upstream` is the original/source repository.

### Default Sync For All Same-Name Branches

By default, the scripts sync same-name branches that exist on both `origin` and `upstream`. Fork-only branches are skipped, and upstream-only branches are not created.

Review the plan first. This does not merge or push:

PowerShell:

```powershell
.\.codex\skills\git-sync-fork-upstream\scripts\sync_fork_upstream.ps1 -ConfigFile .\.codex\skills\git-sync-fork-upstream\sync-fork-upstream.conf -RefreshPlan
```

Bash / Git Bash / Linux / macOS:

```bash
./.codex/skills/git-sync-fork-upstream/scripts/sync_fork_upstream.sh --config-file ./.codex/skills/git-sync-fork-upstream/sync-fork-upstream.conf --refresh-plan
```

Review the dry-run plan before executing and pushing. Risky all-branches plans require `-ConfirmAllBranches` / `--confirm-all-branches`:

PowerShell:

```powershell
.\.codex\skills\git-sync-fork-upstream\scripts\sync_fork_upstream.ps1 -ConfigFile .\.codex\skills\git-sync-fork-upstream\sync-fork-upstream.conf -ValidateCommand "go test ./..." -Execute -Push -ConfirmAllBranches
```

Bash / Git Bash / Linux / macOS:

```bash
./.codex/skills/git-sync-fork-upstream/scripts/sync_fork_upstream.sh --config-file ./.codex/skills/git-sync-fork-upstream/sync-fork-upstream.conf --validate-command "go test ./..." --execute --push --confirm-all-branches
```

The scripts process one branch at a time. If any branch has a conflict, validation failure, or dirty worktree after validation, the process stops and does not continue to later branches. With `-Push` / `--push`, all-branches mode merges and validates every mapped branch first, then pushes branch-by-branch to `origin`.

### Sync One Branch

Use `single-branch` only when exactly one branch should be synchronized.

Review the plan first. This does not merge or push:

PowerShell:

```powershell
.\.codex\skills\git-sync-fork-upstream\scripts\sync_fork_upstream.ps1 -Mode single-branch -UpstreamUrl "<upstream-repository-url>" -TargetBranch <fork-branch> -UpstreamBranch <upstream-branch> -RefreshPlan
.\.codex\skills\git-sync-fork-upstream\scripts\sync_fork_upstream.ps1 -ConfigFile .\.codex\skills\git-sync-fork-upstream\sync-fork-upstream.conf -Mode single-branch -RefreshPlan
```

Bash / Git Bash / Linux / macOS:

```bash
./.codex/skills/git-sync-fork-upstream/scripts/sync_fork_upstream.sh --mode single-branch --upstream-url "<upstream-repository-url>" --target-branch <fork-branch> --upstream-branch <upstream-branch> --refresh-plan
./.codex/skills/git-sync-fork-upstream/scripts/sync_fork_upstream.sh --config-file ./.codex/skills/git-sync-fork-upstream/sync-fork-upstream.conf --mode single-branch --refresh-plan
```

Execute the sync after reviewing the plan. Execution normally requires a validation command:

PowerShell:

```powershell
.\.codex\skills\git-sync-fork-upstream\scripts\sync_fork_upstream.ps1 -Mode single-branch -UpstreamUrl "<upstream-repository-url>" -TargetBranch <fork-branch> -UpstreamBranch <upstream-branch> -ValidateCommand "go test ./..." -Execute
.\.codex\skills\git-sync-fork-upstream\scripts\sync_fork_upstream.ps1 -ConfigFile .\.codex\skills\git-sync-fork-upstream\sync-fork-upstream.conf -Mode single-branch -ValidateCommand "go test ./..." -Execute
```

Bash / Git Bash / Linux / macOS:

```bash
./.codex/skills/git-sync-fork-upstream/scripts/sync_fork_upstream.sh --mode single-branch --upstream-url "<upstream-repository-url>" --target-branch <fork-branch> --upstream-branch <upstream-branch> --validate-command "go test ./..." --execute
./.codex/skills/git-sync-fork-upstream/scripts/sync_fork_upstream.sh --config-file ./.codex/skills/git-sync-fork-upstream/sync-fork-upstream.conf --mode single-branch --validate-command "go test ./..." --execute
```

Use `-SkipValidation` / `--skip-validation` only when you explicitly accept an unvalidated sync. It cannot be combined with `-Push` / `--push`.

To push the synchronized branch to the fork repository, provide a validation command:

PowerShell:

```powershell
.\.codex\skills\git-sync-fork-upstream\scripts\sync_fork_upstream.ps1 -Mode single-branch -UpstreamUrl "<upstream-repository-url>" -TargetBranch <fork-branch> -UpstreamBranch <upstream-branch> -ValidateCommand "go test ./..." -Execute -Push
```

Bash / Git Bash / Linux / macOS:

```bash
./.codex/skills/git-sync-fork-upstream/scripts/sync_fork_upstream.sh --mode single-branch --upstream-url "<upstream-repository-url>" --target-branch <fork-branch> --upstream-branch <upstream-branch> --validate-command "go test ./..." --execute --push
```

Replace `go test ./...` with the real validation command for the project, such as `npm test`, `make test`, `mvn test`, or the build command defined in README/CI.

The scripts print the validation command to the terminal. Do not put real passwords, tokens, API keys, cookies, sessions, or other sensitive credentials in `-ValidateCommand` / `--validate-command`, and do not use validation commands that print sensitive environment variables. If credentials are required, use the project's existing secure configuration mechanism and ensure the command does not echo sensitive values.

After validation finishes, the working tree must remain clean. If the validation command creates or modifies files, the scripts stop and print `dirty after validation`. Clean those files, add generated files to `.gitignore`, or commit required files through the normal project workflow before continuing.

### All-Branches Mode Rules

Default all-branches mode follows these rules:

- Fork-only branches are skipped.
- Upstream-only branches are not created.
- Dry-run output and execute summaries list skipped fork-only branches as `skipped: origin/<branch> - exists only on origin`.
- Plans with more than three branches, or branches named `main`, `master`, `develop`, `release/*`, or `hotfix/*`, require an explicit confirmation flag during execution.

The scripts process one branch at a time. If any branch has a conflict, validation failure, or dirty worktree after validation, the process stops and does not continue to later branches. With `-Push` / `--push`, all-branches mode merges and validates every mapped branch first, then pushes branch-by-branch to `origin` only after the full set has passed. A summary is still printed before failed execution exits.

### Sync Branches With Different Names

For one branch, pass the fork branch and upstream branch separately:

```powershell
.\.codex\skills\git-sync-fork-upstream\scripts\sync_fork_upstream.ps1 -Mode single-branch -UpstreamUrl "<upstream-repository-url>" -TargetBranch develop -UpstreamBranch main -RefreshPlan
```

```bash
./.codex/skills/git-sync-fork-upstream/scripts/sync_fork_upstream.sh --mode single-branch --upstream-url "<upstream-repository-url>" --target-branch develop --upstream-branch main --refresh-plan
```

For all-branches mode with different names, create a map file first:

```text
sync-branches.map
```

File content:

```text
# fork/origin target branch = upstream source branch
develop=main
release/x2=release/upstream-x2
```

Use branch names only. Do not include `origin/` or `upstream/` prefixes.
The scripts reject map entries with remote prefixes or invalid Git branch names.

Review the plan:

```powershell
.\.codex\skills\git-sync-fork-upstream\scripts\sync_fork_upstream.ps1 -UpstreamUrl "<upstream-repository-url>" -Mode all-branches -BranchMapFile sync-branches.map -RefreshPlan
```

```bash
./.codex/skills/git-sync-fork-upstream/scripts/sync_fork_upstream.sh --upstream-url "<upstream-repository-url>" --mode all-branches --branch-map-file sync-branches.map --refresh-plan
```

Execute and push:

```powershell
.\.codex\skills\git-sync-fork-upstream\scripts\sync_fork_upstream.ps1 -UpstreamUrl "<upstream-repository-url>" -Mode all-branches -BranchMapFile sync-branches.map -ValidateCommand "go test ./..." -Execute -Push -ConfirmAllBranches
```

```bash
./.codex/skills/git-sync-fork-upstream/scripts/sync_fork_upstream.sh --upstream-url "<upstream-repository-url>" --mode all-branches --branch-map-file sync-branches.map --validate-command "go test ./..." --execute --push --confirm-all-branches
```

### Conflict Handling

The scripts stop when a merge conflict occurs. Inspect conflicted files first:

```shell
git status
git diff --name-only --diff-filter=U
```

Resolve conflict blocks only. To abandon the merge:

```shell
git merge --abort
```

The scripts create a `sync-backup/...` branch before merging. Use it for recovery or comparison when needed.

### Parameter Reference

| PowerShell | Bash / Git Bash | Description |
| --- | --- | --- |
| `-ConfigFile sync-fork-upstream.conf` | `--config-file sync-fork-upstream.conf` | Load `key=value` defaults; command-line arguments override them. |
| `-RefreshPlan` | `--refresh-plan` | Configure remotes and fetch current refs during dry-run. Does not merge or push. |
| `-Execute` | `--execute` | Run the sync merge. |
| `-Push` | `--push` | Push to `origin` after validation passes. |
| `-ValidateCommand "go test ./..."` | `--validate-command "go test ./..."` | Validation command required before execution and push. |
| `-SkipValidation` | `--skip-validation` | Explicitly skip execution validation; cannot be combined with push. |
| `-ConfirmAllBranches` | `--confirm-all-branches` | Confirm a high-risk all-branches plan. |
| `-BranchMapFile sync-branches.map` | `--branch-map-file sync-branches.map` | Map different branch names in all-branches mode. |

### Cross-Platform Verification

The PowerShell script has been verified on Windows. The Bash script has syntax and key dry-run coverage on WSL Ubuntu 18.04, and is intended for Git Bash, Linux, and macOS. Before first use in a new Bash environment, run a dry-run and a minimal E2E against a temporary fork repository or non-critical branches. Cover at least `--refresh-plan`, `--branch-map-file`, failed-validation summary, and delayed all-branches push.

If Chinese text appears garbled in Windows PowerShell, open this README with a UTF-8 capable terminal or editor. The file itself is saved as UTF-8.
