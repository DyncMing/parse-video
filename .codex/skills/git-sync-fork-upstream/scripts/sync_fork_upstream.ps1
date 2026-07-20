[CmdletBinding()]
param(
    [string]$OriginUrl = "",
    [Parameter(Mandatory = $false)]
    [string]$UpstreamUrl = "",
    [ValidateSet("single-branch", "all-branches")]
    [string]$Mode = "all-branches",
    [string]$TargetBranch = "",
    [string]$UpstreamBranch = "",
    [string]$BranchMapFile = "",
    [string]$ConfigFile = "",
    [string]$ValidateCommand = "",
    [string]$ValidateScriptFile = "",
    [switch]$Execute,
    [switch]$Push,
    [switch]$ConfirmAllBranches,
    [switch]$RefreshPlan,
    [switch]$SkipValidation
)

# One-way fork sync: upstream is read-only; optional pushes go to origin only.
# Validation commands are printed before execution; do not pass secrets in command text.
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$script:CliParameters = @{} + $PSBoundParameters

function Invoke-Git {
    & git @args
    if ($LASTEXITCODE -ne 0) {
        throw "git command failed: git $($args -join ' ')"
    }
}

function Test-GitRef {
    param([string]$Ref)
    & git show-ref --verify --quiet $Ref
    return $LASTEXITCODE -eq 0
}

function Get-CurrentBranch {
    $value = & git symbolic-ref --short -q HEAD
    if ($LASTEXITCODE -ne 0) {
        return ""
    }
    return $value.Trim()
}

function Assert-GitRepo {
    & git rev-parse --show-toplevel *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "Not inside a Git repository."
    }
}

function Assert-CleanWorktree {
    $status = & git status --short
    if ($status) {
        Write-Error "Working tree is not clean; commit, stash, or remove changes before syncing.`n$status"
    }
}

function Assert-CleanAfterValidation {
    param(
        [string]$Target,
        [string]$Command
    )
    $status = & git status --short
    if ($status) {
        $script:DirtyAfterValidationBranches += "$Target - $Command"
        throw "Validation left the working tree dirty on $Target. Commit, remove, or ignore generated files before continuing.`n$status"
    }
}

function Read-SyncConfig {
    param([string]$Path)
    $config = @{}
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $config
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Config file not found: $Path"
    }
    $allowed = @(
        "originUrl",
        "upstreamUrl",
        "mode",
        "syncMode",
        "targetBranch",
        "upstreamBranch",
        "branchMapFile",
        "validateCommand",
        "validateScriptFile"
    )
    $lineNumber = 0
    foreach ($rawLine in Get-Content -Encoding UTF8 -LiteralPath $Path) {
        $lineNumber++
        $line = $rawLine.Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) {
            continue
        }
        if ($line -notmatch "^([^=]+)=(.*)$") {
            throw "Invalid config line $lineNumber in ${Path}: use key=value"
        }
        $key = $matches[1].Trim()
        $value = $matches[2].Trim()
        if (($value.StartsWith('"') -and $value.EndsWith('"')) -or
            ($value.StartsWith("'") -and $value.EndsWith("'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        if ($allowed -notcontains $key) {
            throw "Unsupported config key '$key' in ${Path}. Supported keys: $($allowed -join ', ')"
        }
        $config[$key] = $value
    }
    return $config
}

function Apply-SyncConfig {
    $config = Read-SyncConfig $ConfigFile
    if ($config.Count -eq 0) {
        return
    }
    if ($config.ContainsKey("originUrl") -and -not $script:CliParameters.ContainsKey("OriginUrl")) { $script:OriginUrl = $config["originUrl"] }
    if ($config.ContainsKey("upstreamUrl") -and -not $script:CliParameters.ContainsKey("UpstreamUrl")) { $script:UpstreamUrl = $config["upstreamUrl"] }
    if ($config.ContainsKey("mode") -and -not $script:CliParameters.ContainsKey("Mode")) { $script:Mode = $config["mode"] }
    if ($config.ContainsKey("syncMode") -and -not $script:CliParameters.ContainsKey("Mode")) { $script:Mode = $config["syncMode"] }
    if ($config.ContainsKey("targetBranch") -and -not $script:CliParameters.ContainsKey("TargetBranch")) { $script:TargetBranch = $config["targetBranch"] }
    if ($config.ContainsKey("upstreamBranch") -and -not $script:CliParameters.ContainsKey("UpstreamBranch")) { $script:UpstreamBranch = $config["upstreamBranch"] }
    if ($config.ContainsKey("branchMapFile") -and -not $script:CliParameters.ContainsKey("BranchMapFile")) { $script:BranchMapFile = $config["branchMapFile"] }
    if ($config.ContainsKey("validateCommand") -and -not $script:CliParameters.ContainsKey("ValidateCommand")) { $script:ValidateCommand = $config["validateCommand"] }
    if ($config.ContainsKey("validateScriptFile") -and -not $script:CliParameters.ContainsKey("ValidateScriptFile")) { $script:ValidateScriptFile = $config["validateScriptFile"] }
}

function Ensure-Remote {
    param(
        [string]$Name,
        [string]$Url
    )
    if ([string]::IsNullOrWhiteSpace($Url)) {
        return
    }
    $remoteExists = @(& git remote) -contains $Name
    if ($remoteExists) {
        $current = & git remote get-url $Name
        $current = $current.Trim()
        if ($current -ne $Url) {
            throw "Remote $Name points to $current, expected $Url"
        }
    } else {
        Invoke-Git remote add $Name $Url
    }
}

function Assert-DifferentRemoteUrls {
    param(
        [string]$OriginCandidate,
        [string]$UpstreamCandidate
    )
    if (-not [string]::IsNullOrWhiteSpace($OriginCandidate) -and
        -not [string]::IsNullOrWhiteSpace($UpstreamCandidate) -and
        $OriginCandidate.Trim() -eq $UpstreamCandidate.Trim()) {
        throw "origin and upstream URLs must differ; this skill never writes back to upstream."
    }
}

function Get-RemoteUrlOrEmpty {
    param([string]$Name)
    if (@(& git remote) -contains $Name) {
        $value = & git remote get-url $Name
        if ($LASTEXITCODE -eq 0) {
            return $value.Trim()
        }
    }
    return ""
}

function Fetch-Remotes {
    Invoke-Git fetch --prune origin
    Invoke-Git fetch --prune upstream
}

function Invoke-Validation {
    param(
        [string]$Command,
        [string]$ScriptFile,
        [string]$Target
    )
    if ([string]::IsNullOrWhiteSpace($Command) -and [string]::IsNullOrWhiteSpace($ScriptFile)) {
        if ($SkipValidation) {
            Write-Host "validation skipped: $Target"
            $script:SkippedValidationBranches += $Target
        }
        return
    }

    $validationLabel = $Command
    $global:LASTEXITCODE = 0
    if (-not [string]::IsNullOrWhiteSpace($ScriptFile)) {
        $resolvedScript = (Resolve-Path -LiteralPath $ScriptFile -ErrorAction Stop).Path
        Write-Host "validation script: $resolvedScript"
        & $resolvedScript
        $validationLabel = "script:$resolvedScript"
    } else {
        Write-Host "validation: $Command"
        Invoke-Expression $Command
    }
    if (-not $? -or $LASTEXITCODE -ne 0) {
        $script:FailedValidationBranches += "$Target - $validationLabel"
        throw "Validation failed: $validationLabel"
    }
    Write-Host "validation passed"
    Assert-CleanAfterValidation $Target $validationLabel
}

function Assert-BranchName {
    param(
        [string]$Branch,
        [string]$Label
    )
    if ([string]::IsNullOrWhiteSpace($Branch)) {
        throw "$Label branch is empty."
    }
    if ($Branch -match '^(origin|upstream)/') {
        throw "$Label branch must not include origin/ or upstream/ prefix: $Branch"
    }
    & git check-ref-format --branch $Branch *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "$Label branch is not a valid Git branch name: $Branch"
    }
}

function Test-HighRiskBranch {
    param([string]$Branch)
    return $Branch -match '^(main|master|develop)$|^(release|hotfix)/'
}

function Assert-AllBranchesConfirmed {
    param([string[]]$Branches)
    $highRisk = @($Branches | Where-Object { Test-HighRiskBranch $_ })
    if (-not $ConfirmAllBranches -and ($Branches.Count -gt 3 -or $highRisk.Count -gt 0)) {
        $branchList = ($Branches -join ", ")
        throw "All-branches execution requires -ConfirmAllBranches for this plan: $branchList"
    }
}

function Test-RemoteBranch {
    param(
        [string]$Remote,
        [string]$Branch
    )
    return Test-GitRef "refs/remotes/$Remote/$Branch"
}

function Test-LocalBranch {
    param([string]$Branch)
    return Test-GitRef "refs/heads/$Branch"
}

function New-BackupBranch {
    param([string]$Branch)
    $backup = "sync-backup/$Branch-before-upstream-sync-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Invoke-Git branch $backup
    Write-Host "backup: $backup"
}

function Test-Ancestor {
    param(
        [string]$MaybeAncestor,
        [string]$Commit
    )
    & git merge-base --is-ancestor $MaybeAncestor $Commit
    return $LASTEXITCODE -eq 0
}

function Get-CommitCount {
    param([string]$Range)
    $value = (& git rev-list --count $Range).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "git command failed: git rev-list --count $Range"
    }
    return [int]$value
}

function Merge-OneBranch {
    param(
        [string]$Target,
        [string]$Upstream
    )

    if (Test-LocalBranch $Target) {
        Invoke-Git checkout $Target
    } elseif (Test-RemoteBranch origin $Target) {
        Invoke-Git checkout -b $Target "origin/$Target"
    } else {
        Write-Host "skipped: $Target - no local/origin branch"
        $script:SkippedBranches += "$Target - no local/origin branch"
        return
    }

    if (Test-RemoteBranch origin $Target) {
        if (Test-Ancestor HEAD "origin/$Target") {
            Invoke-Git merge --ff-only "origin/$Target"
        } elseif (-not (Test-Ancestor "origin/$Target" HEAD)) {
            throw "Local $Target diverged from origin/$Target; stop before upstream merge."
        } else {
            $aheadCount = Get-CommitCount "origin/$Target..HEAD"
            if ($aheadCount -gt 0) {
                Write-Host "local unpublished commits: $Target - $aheadCount commit(s) ahead of origin/$Target"
                $script:UnpublishedBranches += "$Target - $aheadCount commit(s) ahead of origin/$Target"
            }
        }
    }

    New-BackupBranch $Target
    & git merge "upstream/$Upstream"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "conflicted: $Target"
        $script:ConflictedBranches += $Target
        & git status
        throw "Resolve conflicts or run: git merge --abort"
    }

    Write-Host "synced: $Target <= upstream/$Upstream"
    $script:SyncedBranches += "$Target <= upstream/$Upstream"
    Invoke-Validation $ValidateCommand $ValidateScriptFile $Target
    $script:ReadyToPushBranches += $Target
}

function Push-ReadyBranches {
    if (-not $Push) {
        return
    }
    foreach ($branch in @($ReadyToPushBranches | Select-Object -Unique)) {
        Assert-CleanWorktree
        Invoke-Git push origin $branch
        Write-Host "pushed: $branch"
        $script:PushedBranches += $branch
    }
}

function Get-SameNameBranchMap {
    $originBranches = & git for-each-ref --format='%(refname:strip=3)' refs/remotes/origin
    $upstreamBranches = & git for-each-ref --format='%(refname:strip=3)' refs/remotes/upstream
    $originSet = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($branch in $originBranches) {
        if ($branch -and $branch -ne "HEAD" -and -not $branch.StartsWith("sync-backup/")) {
            [void]$originSet.Add($branch)
        }
    }
    foreach ($branch in $upstreamBranches) {
        if ($branch -and $branch -ne "HEAD" -and -not $branch.StartsWith("sync-backup/") -and $originSet.Contains($branch)) {
            $branch
        }
    }
}

function Get-ForkOnlyBranches {
    param([string[]]$MappedTargets = @())
    $originBranches = & git for-each-ref --format='%(refname:strip=3)' refs/remotes/origin
    $upstreamBranches = & git for-each-ref --format='%(refname:strip=3)' refs/remotes/upstream
    $upstreamSet = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($branch in $upstreamBranches) {
        if ($branch -and $branch -ne "HEAD" -and -not $branch.StartsWith("sync-backup/")) {
            [void]$upstreamSet.Add($branch)
        }
    }
    $mappedSet = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($branch in $MappedTargets) {
        if ($branch) {
            [void]$mappedSet.Add($branch)
        }
    }
    foreach ($branch in $originBranches) {
        if ($branch -and $branch -ne "HEAD" -and -not $branch.StartsWith("sync-backup/") -and
            -not $upstreamSet.Contains($branch) -and -not $mappedSet.Contains($branch)) {
            $branch
        }
    }
}

function Get-ConfiguredBranchMap {
    if ([string]::IsNullOrWhiteSpace($BranchMapFile)) {
        foreach ($branch in Get-SameNameBranchMap) {
            [pscustomobject]@{ Target = $branch; Upstream = $branch }
        }
        return
    }

    if (-not (Test-Path -LiteralPath $BranchMapFile)) {
        throw "Branch map file not found: $BranchMapFile"
    }

    foreach ($line in Get-Content -LiteralPath $BranchMapFile) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith("#")) {
            continue
        }
        $parts = $trimmed -split '\s*(?:=|<=|:)\s*', 2
        if ($parts.Count -ne 2 -or -not $parts[0] -or -not $parts[1]) {
            throw "Invalid branch map line: $line"
        }
        $target = $parts[0].Trim()
        $upstream = $parts[1].Trim()
        Assert-BranchName $target "target"
        Assert-BranchName $upstream "upstream"
        [pscustomobject]@{ Target = $target; Upstream = $upstream }
    }
}

function Assert-BranchMapNotEmpty {
    param([object[]]$BranchMap)
    if ($BranchMap.Count -eq 0) {
        throw "No matching branches to sync. In all-branches mode, provide -BranchMapFile for different branch names or confirm that origin and upstream have same-name branches."
    }
}

function Write-SyncSummary {
    if ($SyncedBranches.Count -eq 0 -and $SkippedBranches.Count -eq 0 -and $ConflictedBranches.Count -eq 0 -and $FailedValidationBranches.Count -eq 0 -and $MissingUpstreamBranches.Count -eq 0 -and $PushedBranches.Count -eq 0) {
        return
    }
    Write-Host "summary:"
    foreach ($item in $SyncedBranches) { Write-Host "synced: $item" }
    foreach ($item in $SkippedBranches) { Write-Host "skipped: $item" }
    foreach ($item in $ConflictedBranches) { Write-Host "conflicted: $item" }
    foreach ($item in $FailedValidationBranches) { Write-Host "failed validation: $item" }
    foreach ($item in $DirtyAfterValidationBranches) { Write-Host "dirty after validation: $item" }
    foreach ($item in $SkippedValidationBranches) { Write-Host "skipped validation: $item" }
    foreach ($item in $UnpublishedBranches) { Write-Host "local unpublished commits: $item" }
    foreach ($item in $MissingUpstreamBranches) { Write-Host "missing upstream: $item" }
    foreach ($item in $PushedBranches) { Write-Host "pushed: $item" }
}

$script:SyncedBranches = @()
$script:SkippedBranches = @()
$script:ConflictedBranches = @()
$script:FailedValidationBranches = @()
$script:DirtyAfterValidationBranches = @()
$script:SkippedValidationBranches = @()
$script:UnpublishedBranches = @()
$script:MissingUpstreamBranches = @()
$script:ReadyToPushBranches = @()
$script:PushedBranches = @()

$exitCode = 0
$initialBranch = ""
try {
    Assert-GitRepo
    Apply-SyncConfig
    if ($Mode -ne "single-branch" -and $Mode -ne "all-branches") {
        throw "-Mode must be single-branch or all-branches"
    }
    if ($Mode -eq "all-branches" -and
        (-not [string]::IsNullOrWhiteSpace($TargetBranch) -or
         -not [string]::IsNullOrWhiteSpace($UpstreamBranch))) {
        throw "-TargetBranch and -UpstreamBranch require -Mode single-branch. In all-branches mode, use -BranchMapFile for branch mapping."
    }
    Assert-DifferentRemoteUrls $OriginUrl $UpstreamUrl
    if (-not [string]::IsNullOrWhiteSpace($ValidateCommand) -and -not [string]::IsNullOrWhiteSpace($ValidateScriptFile)) {
        throw "Use either -ValidateCommand or -ValidateScriptFile, not both."
    }
    if (-not [string]::IsNullOrWhiteSpace($ValidateScriptFile) -and -not (Test-Path -LiteralPath $ValidateScriptFile -PathType Leaf)) {
        throw "Validate script file not found: $ValidateScriptFile"
    }
    if ($Push -and [string]::IsNullOrWhiteSpace($ValidateCommand) -and [string]::IsNullOrWhiteSpace($ValidateScriptFile)) {
        throw "-Push requires -ValidateCommand or -ValidateScriptFile so synchronized branches are validated before pushing to origin."
    }
    if ($Push -and $SkipValidation) {
        throw "-Push cannot be combined with -SkipValidation."
    }
    if ($Execute -and [string]::IsNullOrWhiteSpace($ValidateCommand) -and [string]::IsNullOrWhiteSpace($ValidateScriptFile) -and -not $SkipValidation) {
        throw "-Execute requires -ValidateCommand or -ValidateScriptFile. Use -SkipValidation only when the user explicitly accepts an unvalidated sync."
    }
    $initialBranch = Get-CurrentBranch
    if ($Mode -eq "single-branch") {
        if ([string]::IsNullOrWhiteSpace($TargetBranch)) {
            if ([string]::IsNullOrWhiteSpace($initialBranch)) {
                throw "Current checkout is detached; pass -TargetBranch explicitly."
            }
            $TargetBranch = $initialBranch
        }
        if ([string]::IsNullOrWhiteSpace($UpstreamBranch)) {
            $UpstreamBranch = $TargetBranch
        }
        Assert-BranchName $TargetBranch "target"
        Assert-BranchName $UpstreamBranch "upstream"
    }

    if (-not $Execute) {
        if ($RefreshPlan) {
            Ensure-Remote origin $OriginUrl
            Ensure-Remote upstream $UpstreamUrl
            Assert-DifferentRemoteUrls (Get-RemoteUrlOrEmpty origin) (Get-RemoteUrlOrEmpty upstream)
            Fetch-Remotes
        }
        Write-Host "dry-run: no branch or worktree changes will be made"
        Write-Host "mode: $Mode"
        Write-Host "refreshPlan: $RefreshPlan"
        Write-Host "originUrl: $(if ($OriginUrl) { $OriginUrl } else { '<current origin>' })"
        Write-Host "upstreamUrl: $(if ($UpstreamUrl) { $UpstreamUrl } else { '<current upstream>' })"
        Write-Host "configFile: $(if ($ConfigFile) { $ConfigFile } else { '<none>' })"
        Write-Host "validateCommand: $(if ($ValidateCommand) { $ValidateCommand } else { '<none>' })"
        Write-Host "validateScriptFile: $(if ($ValidateScriptFile) { $ValidateScriptFile } else { '<none>' })"
        Write-Host "skipValidation: $SkipValidation"
        Write-Host "branchMapFile: $(if ($BranchMapFile) { $BranchMapFile } else { '<same-name branches>' })"
        if ($Mode -eq "single-branch") {
            Write-Host "plan: origin/$TargetBranch <= upstream/$UpstreamBranch"
        } else {
            Write-Host "plan: $(if ($BranchMapFile) { 'branch map file' } else { 'same-name branch intersection from existing refs' })"
            $plannedBranches = @(Get-ConfiguredBranchMap)
            Assert-BranchMapNotEmpty $plannedBranches
            foreach ($pair in $plannedBranches) {
                Write-Host "plan: origin/$($pair.Target) <= upstream/$($pair.Upstream)"
            }
            foreach ($branch in Get-ForkOnlyBranches @($plannedBranches | ForEach-Object { $_.Target })) {
                Write-Host "skipped: origin/$branch - exists only on origin"
            }
            if ($plannedBranches.Count -gt 3 -or @($plannedBranches | Where-Object { Test-HighRiskBranch -Branch ($_.Target) }).Count -gt 0) {
                Write-Host "safety: all-branches execution requires -ConfirmAllBranches for this plan"
            }
            Write-Host "fork-only branches are skipped by default"
        }
        Write-Host "safety: upstream is read-only; -Push pushes to origin only"
        Write-Host "rerun with -Execute to apply"
        exit 0
    }

    Assert-CleanWorktree
    Ensure-Remote origin $OriginUrl
    Ensure-Remote upstream $UpstreamUrl
    Assert-DifferentRemoteUrls (Get-RemoteUrlOrEmpty origin) (Get-RemoteUrlOrEmpty upstream)
    Fetch-Remotes

    if ($Mode -eq "single-branch") {
        if (-not (Test-RemoteBranch upstream $UpstreamBranch)) {
            $script:MissingUpstreamBranches += "upstream/$UpstreamBranch"
            throw "Missing upstream branch: upstream/$UpstreamBranch"
        }
        Merge-OneBranch $TargetBranch $UpstreamBranch
        Push-ReadyBranches
    } else {
        $branchMap = @(Get-ConfiguredBranchMap)
        Assert-BranchMapNotEmpty $branchMap
        Assert-AllBranchesConfirmed @($branchMap | ForEach-Object { $_.Target })
        foreach ($branch in Get-ForkOnlyBranches @($branchMap | ForEach-Object { $_.Target })) {
            $script:SkippedBranches += "origin/$branch - exists only on origin"
        }
        foreach ($pair in $branchMap) {
            if (-not (Test-RemoteBranch upstream $pair.Upstream)) {
                $script:MissingUpstreamBranches += "upstream/$($pair.Upstream)"
                throw "Missing upstream branch: upstream/$($pair.Upstream)"
            }
            Merge-OneBranch $pair.Target $pair.Upstream
        }
        Push-ReadyBranches
    }
} catch {
    $exitCode = 1
    Write-Error -ErrorAction Continue $_
} finally {
    Write-SyncSummary
    if ($initialBranch -and (Test-LocalBranch $initialBranch) -and (Get-CurrentBranch) -ne $initialBranch -and -not (& git status --short)) {
        Invoke-Git checkout $initialBranch
    }
    if ($exitCode -ne 0) {
        exit $exitCode
    }
    $global:LASTEXITCODE = 0
}
