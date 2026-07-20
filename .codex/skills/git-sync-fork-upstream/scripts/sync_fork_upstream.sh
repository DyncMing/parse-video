#!/usr/bin/env bash
set -euo pipefail

origin_url=""
upstream_url=""
mode="all-branches"
target_branch=""
upstream_branch=""
branch_map_file=""
config_file=""
validate_command=""
validate_script_file=""
execute=0
push_after=0
confirm_all_branches=0
refresh_plan=0
skip_validation=0

usage() {
  cat <<'USAGE'
Usage:
  sync_fork_upstream.sh --upstream-url URL [options]

Options:
  --origin-url URL           Expected fork remote URL.
  --upstream-url URL         Original/source repository URL.
  --mode MODE                single-branch or all-branches. Default: all-branches.
  --target-branch BRANCH     Single-branch target fork branch. Default: current branch.
  --upstream-branch BRANCH   Single-branch upstream branch. Default: target branch.
  --branch-map-file FILE     Optional all-branches map. Lines use target=upstream.
  --config-file FILE         Optional key=value defaults file.
  --validate-command CMD     Validation command to run after each successful merge.
  --validate-script-file FILE
                              Validation script to run after each successful merge.
  --execute                  Apply changes. Without this, only prints the plan.
  --push                     Push synchronized branches to origin after validation succeeds.
  --confirm-all-branches     Required for risky all-branches execution plans.
  --refresh-plan             In dry-run mode, configure remotes and fetch before printing the plan.
  --skip-validation          Allow --execute without validation. Cannot be used with --push.
  -h, --help                 Show this help.

Safety:
  The script refuses dirty worktrees, uses fetch --prune, creates timestamped backups,
  skips fork-only branches by default, stops on conflicts, pushes only to origin,
  never pushes to upstream, and never uses git push --all.
  Validation commands are printed before execution; do not pass secrets in command text.
  Remote URL checks are exact string checks; confirm origin/upstream ownership manually.
USAGE
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

apply_config_value() {
  local key="$1"
  local value="$2"
  case "$key" in
    originUrl) origin_url="$value" ;;
    upstreamUrl) upstream_url="$value" ;;
    mode|syncMode) mode="$value" ;;
    targetBranch) target_branch="$value" ;;
    upstreamBranch) upstream_branch="$value" ;;
    branchMapFile) branch_map_file="$value" ;;
    validateCommand) validate_command="$value" ;;
    validateScriptFile) validate_script_file="$value" ;;
    *)
      echo "Unsupported config key '$key' in $config_file. Supported keys: originUrl, upstreamUrl, mode, syncMode, targetBranch, upstreamBranch, branchMapFile, validateCommand, validateScriptFile" >&2
      exit 2
      ;;
  esac
}

read_config_file() {
  if [[ -z "$config_file" ]]; then
    return
  fi
  if [[ ! -f "$config_file" ]]; then
    echo "Config file not found: $config_file" >&2
    exit 2
  fi
  local line_number=0 line key value
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_number=$((line_number + 1))
    line="$(trim "$line")"
    [[ -z "$line" || "${line:0:1}" == "#" ]] && continue
    if [[ "$line" != *"="* ]]; then
      echo "Invalid config line $line_number in $config_file: use key=value" >&2
      exit 2
    fi
    key="$(trim "${line%%=*}")"
    value="$(trim "${line#*=}")"
    if [[ "${value:0:1}" == '"' && "${value:${#value}-1:1}" == '"' ]] || [[ "${value:0:1}" == "'" && "${value:${#value}-1:1}" == "'" ]]; then
      value="${value:1:${#value}-2}"
    fi
    apply_config_value "$key" "$value"
  done < "$config_file"
}

args=("$@")
for ((idx = 0; idx < ${#args[@]}; idx++)); do
  if [[ "${args[$idx]}" == "--config-file" ]]; then
    config_file="${args[$((idx + 1))]:-}"
  fi
done
read_config_file

while [[ $# -gt 0 ]]; do
  case "$1" in
    --origin-url) origin_url="${2:-}"; shift 2 ;;
    --upstream-url) upstream_url="${2:-}"; shift 2 ;;
    --mode) mode="${2:-}"; shift 2 ;;
    --target-branch) target_branch="${2:-}"; shift 2 ;;
    --upstream-branch) upstream_branch="${2:-}"; shift 2 ;;
    --branch-map-file) branch_map_file="${2:-}"; shift 2 ;;
    --config-file) config_file="${2:-}"; shift 2 ;;
    --validate-command) validate_command="${2:-}"; shift 2 ;;
    --validate-script-file) validate_script_file="${2:-}"; shift 2 ;;
    --execute) execute=1; shift ;;
    --push) push_after=1; shift ;;
    --confirm-all-branches) confirm_all_branches=1; shift ;;
    --refresh-plan) refresh_plan=1; shift ;;
    --skip-validation) skip_validation=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ "$mode" != "single-branch" && "$mode" != "all-branches" ]]; then
  echo "--mode must be single-branch or all-branches" >&2
  exit 2
fi
if [[ "$mode" == "all-branches" && ( -n "$target_branch" || -n "$upstream_branch" ) ]]; then
  echo "--target-branch and --upstream-branch require --mode single-branch. In all-branches mode, use --branch-map-file for branch mapping." >&2
  exit 2
fi

require_git_repo() {
  git rev-parse --show-toplevel >/dev/null
}

current_branch() {
  git symbolic-ref --short -q HEAD || true
}

ensure_clean_worktree() {
  if [[ -n "$(git status --short)" ]]; then
    echo "Working tree is not clean; commit, stash, or remove changes before syncing." >&2
    git status --short >&2
    exit 1
  fi
}

ensure_clean_after_validation() {
  local target="$1"
  local command="$2"
  local status
  status="$(git status --short)"
  if [[ -n "$status" ]]; then
    dirty_after_validation_branches+=("$target - $command")
    echo "Validation left the working tree dirty on $target. Commit, remove, or ignore generated files before continuing." >&2
    printf '%s\n' "$status" >&2
    exit 1
  fi
}

ensure_remote() {
  local name="$1"
  local url="$2"
  if [[ -z "$url" ]]; then
    return
  fi
  if git remote get-url "$name" >/dev/null 2>&1; then
    local current
    current="$(git remote get-url "$name")"
    if [[ "$current" != "$url" ]]; then
      echo "Remote $name points to $current, expected $url" >&2
      exit 1
    fi
  else
    git remote add "$name" "$url"
  fi
}

assert_different_remote_urls() {
  local origin_candidate="$1"
  local upstream_candidate="$2"
  if [[ -n "$origin_candidate" && -n "$upstream_candidate" && "$origin_candidate" == "$upstream_candidate" ]]; then
    echo "origin and upstream URLs must differ; this skill never writes back to upstream." >&2
    exit 1
  fi
}

remote_url_or_empty() {
  git remote get-url "$1" 2>/dev/null || true
}

fetch_remotes() {
  git fetch --prune origin
  git fetch --prune upstream
}

run_validation() {
  local target="$1"
  if [[ -z "$validate_command" && -z "$validate_script_file" ]]; then
    if [[ "$skip_validation" -eq 1 ]]; then
      echo "validation skipped: $target"
      skipped_validation_branches+=("$target")
    fi
    return 0
  fi
  local validation_label="$validate_command"
  if [[ -n "$validate_script_file" ]]; then
    local resolved_script
    resolved_script="$(cd "$(dirname "$validate_script_file")" && pwd)/$(basename "$validate_script_file")"
    echo "validation script: $resolved_script"
    if ! bash "$resolved_script"; then
      failed_validation_branches+=("$target - script:$resolved_script")
      echo "Validation failed: script:$resolved_script" >&2
      exit 1
    fi
    validation_label="script:$resolved_script"
  else
    echo "validation: $validate_command"
    if ! bash -lc "$validate_command"; then
      failed_validation_branches+=("$target - $validate_command")
      echo "Validation failed: $validate_command" >&2
      exit 1
    fi
  fi
  echo "validation passed"
  ensure_clean_after_validation "$target" "$validation_label"
}

assert_validation_inputs() {
  if [[ -n "$validate_command" && -n "$validate_script_file" ]]; then
    echo "Use either --validate-command or --validate-script-file, not both." >&2
    exit 1
  fi
  if [[ -n "$validate_script_file" && ! -f "$validate_script_file" ]]; then
    echo "Validate script file not found: $validate_script_file" >&2
    exit 2
  fi
}

assert_branch_name() {
  local branch="$1"
  local label="$2"
  if [[ -z "$branch" ]]; then
    echo "$label branch is empty." >&2
    exit 2
  fi
  case "$branch" in
    origin/*|upstream/*)
      echo "$label branch must not include origin/ or upstream/ prefix: $branch" >&2
      exit 2
      ;;
  esac
  if ! git check-ref-format --branch "$branch" >/dev/null 2>&1; then
    echo "$label branch is not a valid Git branch name: $branch" >&2
    exit 2
  fi
}

branch_needs_confirmation() {
  case "$1" in
    main|master|develop|release/*|hotfix/*) return 0 ;;
    *) return 1 ;;
  esac
}

require_all_branches_confirmation() {
  local count="$#"
  local needs_confirmation=0
  local branch
  if [[ "$count" -gt 3 ]]; then
    needs_confirmation=1
  fi
  for branch in "$@"; do
    if branch_needs_confirmation "$branch"; then
      needs_confirmation=1
    fi
  done
  if [[ "$needs_confirmation" -eq 1 && "$confirm_all_branches" -ne 1 ]]; then
    echo "All-branches execution requires --confirm-all-branches for this plan: $*" >&2
    exit 2
  fi
}

remote_branch_exists() {
  git show-ref --verify --quiet "refs/remotes/$1/$2"
}

local_branch_exists() {
  git show-ref --verify --quiet "refs/heads/$1"
}

backup_branch() {
  local branch="$1"
  local backup="sync-backup/${branch}-before-upstream-sync-$(date +%Y%m%d-%H%M%S)"
  git branch "$backup"
  echo "backup: $backup"
}

commit_count() {
  git rev-list --count "$1"
}

merge_one_branch() {
  local target="$1"
  local upstream="$2"

  if local_branch_exists "$target"; then
    git checkout "$target"
  elif remote_branch_exists origin "$target"; then
    git checkout -b "$target" "origin/$target"
  else
    echo "skipped: $target - no local/origin branch"
    skipped_branches+=("$target - no local/origin branch")
    return 0
  fi

  if remote_branch_exists origin "$target"; then
    if git merge-base --is-ancestor HEAD "origin/$target"; then
      git merge --ff-only "origin/$target"
    elif ! git merge-base --is-ancestor "origin/$target" HEAD; then
      echo "Local $target diverged from origin/$target; stop before upstream merge." >&2
      exit 1
    else
      local ahead_count
      ahead_count="$(commit_count "origin/$target..HEAD")"
      if [[ "$ahead_count" -gt 0 ]]; then
        echo "local unpublished commits: $target - $ahead_count commit(s) ahead of origin/$target"
        unpublished_branches+=("$target - $ahead_count commit(s) ahead of origin/$target")
      fi
    fi
  fi

  backup_branch "$target"
  if ! git merge "upstream/$upstream"; then
    echo "conflicted: $target"
    conflicted_branches+=("$target")
    git status
    echo "Resolve conflicts or run: git merge --abort" >&2
    exit 1
  fi

  echo "synced: $target <= upstream/$upstream"
  synced_branches+=("$target <= upstream/$upstream")
  run_validation "$target"
  ready_to_push_branches+=("$target")
}

push_ready_branches() {
  if [[ "$push_after" -ne 1 ]]; then
    return 0
  fi
  local branch
  local pushed=""
  for branch in "${ready_to_push_branches[@]}"; do
    if [[ " $pushed " == *" $branch "* ]]; then
      continue
    fi
    ensure_clean_worktree
    git push origin "$branch"
    echo "pushed: $branch"
    pushed_branches+=("$branch")
    pushed="$pushed $branch"
  done
}

same_name_branch_map() {
  comm -12 \
    <(git for-each-ref --format='%(refname:strip=3)' refs/remotes/origin | grep -vE '^(HEAD|sync-backup/)' | sort) \
    <(git for-each-ref --format='%(refname:strip=3)' refs/remotes/upstream | grep -vE '^(HEAD|sync-backup/)' | sort)
}

is_mapped_target() {
  local candidate="$1"
  local mapped
  shift || true
  for mapped in "$@"; do
    [[ "$mapped" == "$candidate" ]] && return 0
  done
  return 1
}

fork_only_branches() {
  comm -23 \
    <(git for-each-ref --format='%(refname:strip=3)' refs/remotes/origin | grep -vE '^(HEAD|sync-backup/)' | sort) \
    <(git for-each-ref --format='%(refname:strip=3)' refs/remotes/upstream | grep -vE '^(HEAD|sync-backup/)' | sort)
}

configured_branch_map() {
  if [[ -z "$branch_map_file" ]]; then
    while IFS= read -r branch; do
      [[ -z "$branch" ]] && continue
      printf '%s|%s\n' "$branch" "$branch"
    done < <(same_name_branch_map)
    return
  fi

  if [[ ! -f "$branch_map_file" ]]; then
    echo "Branch map file not found: $branch_map_file" >&2
    exit 2
  fi

  local line target upstream
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "${line:0:1}" == "#" ]] && continue
    if [[ "$line" == *"="* ]]; then
      target="${line%%=*}"
      upstream="${line#*=}"
    elif [[ "$line" == *":"* ]]; then
      target="${line%%:*}"
      upstream="${line#*:}"
    else
      echo "Invalid branch map line: $line" >&2
      exit 2
    fi
    target="${target#"${target%%[![:space:]]*}"}"
    target="${target%"${target##*[![:space:]]}"}"
    upstream="${upstream#"${upstream%%[![:space:]]*}"}"
    upstream="${upstream%"${upstream##*[![:space:]]}"}"
    if [[ -z "$target" || -z "$upstream" ]]; then
      echo "Invalid branch map line: $line" >&2
      exit 2
    fi
    assert_branch_name "$target" "target"
    assert_branch_name "$upstream" "upstream"
    printf '%s|%s\n' "$target" "$upstream"
  done < "$branch_map_file"
}

require_non_empty_branch_map() {
  if [[ "$#" -eq 0 ]]; then
    echo "No matching branches to sync. In all-branches mode, provide --branch-map-file for different branch names or confirm that origin and upstream have same-name branches." >&2
    exit 2
  fi
}

print_sync_summary() {
  if [[ "$summary_printed" -eq 1 ]]; then
    return 0
  fi
  summary_printed=1
  if [[ "${#synced_branches[@]}" -eq 0 && "${#skipped_branches[@]}" -eq 0 && "${#conflicted_branches[@]}" -eq 0 && "${#failed_validation_branches[@]}" -eq 0 && "${#missing_upstream_branches[@]}" -eq 0 && "${#pushed_branches[@]}" -eq 0 ]]; then
    return 0
  fi
  echo "summary:"
  local item
  for item in "${synced_branches[@]}"; do echo "synced: $item"; done
  for item in "${skipped_branches[@]}"; do echo "skipped: $item"; done
  for item in "${conflicted_branches[@]}"; do echo "conflicted: $item"; done
  for item in "${failed_validation_branches[@]}"; do echo "failed validation: $item"; done
  for item in "${dirty_after_validation_branches[@]}"; do echo "dirty after validation: $item"; done
  for item in "${skipped_validation_branches[@]}"; do echo "skipped validation: $item"; done
  for item in "${unpublished_branches[@]}"; do echo "local unpublished commits: $item"; done
  for item in "${missing_upstream_branches[@]}"; do echo "missing upstream: $item"; done
  for item in "${pushed_branches[@]}"; do echo "pushed: $item"; done
}

finish() {
  local status=$?
  if [[ "$execute" -eq 1 ]]; then
    print_sync_summary
  fi
  if [[ -n "${initial_branch:-}" && "$(current_branch)" != "$initial_branch" && -z "$(git status --short)" ]] && local_branch_exists "$initial_branch"; then
    git checkout "$initial_branch"
  fi
  exit "$status"
}

require_git_repo
assert_different_remote_urls "$origin_url" "$upstream_url"
assert_validation_inputs
if [[ "$push_after" -eq 1 && -z "$validate_command" && -z "$validate_script_file" ]]; then
  echo "--push requires --validate-command or --validate-script-file so synchronized branches are validated before pushing to origin." >&2
  exit 2
fi
if [[ "$push_after" -eq 1 && "$skip_validation" -eq 1 ]]; then
  echo "--push cannot be combined with --skip-validation." >&2
  exit 2
fi
if [[ "$execute" -eq 1 && -z "$validate_command" && -z "$validate_script_file" && "$skip_validation" -ne 1 ]]; then
  echo "--execute requires --validate-command or --validate-script-file. Use --skip-validation only when the user explicitly accepts an unvalidated sync." >&2
  exit 2
fi
initial_branch="$(current_branch)"
synced_branches=()
skipped_branches=()
conflicted_branches=()
failed_validation_branches=()
dirty_after_validation_branches=()
skipped_validation_branches=()
unpublished_branches=()
missing_upstream_branches=()
ready_to_push_branches=()
pushed_branches=()
summary_printed=0
trap finish EXIT
if [[ "$mode" == "single-branch" ]]; then
  if [[ -z "$target_branch" ]]; then
    if [[ -z "$initial_branch" ]]; then
      echo "Current checkout is detached; pass --target-branch explicitly." >&2
      exit 2
    fi
    target_branch="$initial_branch"
  fi
  if [[ -z "$upstream_branch" ]]; then
    upstream_branch="$target_branch"
  fi
  assert_branch_name "$target_branch" "target"
  assert_branch_name "$upstream_branch" "upstream"
fi

if [[ "$execute" -eq 0 ]]; then
  if [[ "$refresh_plan" -eq 1 ]]; then
    ensure_remote origin "$origin_url"
    ensure_remote upstream "$upstream_url"
    assert_different_remote_urls "$(remote_url_or_empty origin)" "$(remote_url_or_empty upstream)"
    fetch_remotes
  fi
  echo "dry-run: no branch or worktree changes will be made"
  echo "mode: $mode"
  echo "refreshPlan: $refresh_plan"
  echo "originUrl: ${origin_url:-<current origin>}"
  echo "upstreamUrl: ${upstream_url:-<current upstream>}"
  echo "configFile: ${config_file:-<none>}"
  echo "validateCommand: ${validate_command:-<none>}"
  echo "validateScriptFile: ${validate_script_file:-<none>}"
  echo "skipValidation: $skip_validation"
  echo "branchMapFile: ${branch_map_file:-<same-name branches>}"
  if [[ "$mode" == "single-branch" ]]; then
    echo "plan: origin/$target_branch <= upstream/$upstream_branch"
  else
    echo "plan: $([[ -n "$branch_map_file" ]] && echo "branch map file" || echo "same-name branch intersection from existing refs")"
    all_branch_plan=()
    while IFS='|' read -r target upstream; do
      [[ -z "$target" ]] && continue
      all_branch_plan+=("$target|$upstream")
      printf 'plan: origin/%s <= upstream/%s\n' "$target" "$upstream"
    done < <(configured_branch_map)
    require_non_empty_branch_map "${all_branch_plan[@]}"
    planned_targets=()
    for pair in "${all_branch_plan[@]}"; do
      planned_targets+=("${pair%%|*}")
    done
    while IFS= read -r branch; do
      [[ -z "$branch" ]] && continue
      if ! is_mapped_target "$branch" "${planned_targets[@]}"; then
        printf 'skipped: origin/%s - exists only on origin\n' "$branch"
      fi
    done < <(fork_only_branches)
    if [[ "${#all_branch_plan[@]}" -gt 3 ]]; then
      echo "safety: all-branches execution requires --confirm-all-branches for this plan"
    else
      for pair in "${all_branch_plan[@]}"; do
        if branch_needs_confirmation "${pair%%|*}"; then
          echo "safety: all-branches execution requires --confirm-all-branches for this plan"
          break
        fi
      done
    fi
    echo "fork-only branches are skipped by default"
  fi
  echo "safety: upstream is read-only; --push pushes to origin only"
  echo "rerun with --execute to apply"
  exit 0
fi

ensure_clean_worktree
ensure_remote origin "$origin_url"
ensure_remote upstream "$upstream_url"
assert_different_remote_urls "$(remote_url_or_empty origin)" "$(remote_url_or_empty upstream)"
fetch_remotes

if [[ "$mode" == "single-branch" ]]; then
  if ! remote_branch_exists upstream "$upstream_branch"; then
    missing_upstream_branches+=("upstream/$upstream_branch")
    echo "Missing upstream branch: upstream/$upstream_branch" >&2
    exit 1
  fi
  merge_one_branch "$target_branch" "$upstream_branch"
  push_ready_branches
else
  branch_map=()
  branch_targets=()
  while IFS='|' read -r target upstream; do
    [[ -z "$target" ]] && continue
    branch_map+=("$target|$upstream")
    branch_targets+=("$target")
  done < <(configured_branch_map)
  require_non_empty_branch_map "${branch_map[@]}"
  require_all_branches_confirmation "${branch_targets[@]}"
  while IFS= read -r branch; do
    [[ -z "$branch" ]] && continue
    if ! is_mapped_target "$branch" "${branch_targets[@]}"; then
      skipped_branches+=("origin/$branch - exists only on origin")
    fi
  done < <(fork_only_branches)
  for pair in "${branch_map[@]}"; do
    target="${pair%%|*}"
    upstream="${pair#*|}"
    if ! remote_branch_exists upstream "$upstream"; then
      missing_upstream_branches+=("upstream/$upstream")
      echo "Missing upstream branch: upstream/$upstream" >&2
      exit 1
    fi
    merge_one_branch "$target" "$upstream"
  done
  push_ready_branches
fi

print_sync_summary

if [[ -n "$initial_branch" && "$(current_branch)" != "$initial_branch" && -z "$(git status --short)" ]] && local_branch_exists "$initial_branch"; then
  git checkout "$initial_branch"
fi
