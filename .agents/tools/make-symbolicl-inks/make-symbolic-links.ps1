#Requires -Version 5.1

<#
.SYNOPSIS
AIリソースのシンボリックリンクを作成します。

.DESCRIPTION
gitリポジトリのルートフォルダ直下に以下のリンクを作成します。
  - .claude/skills  -> .agents/skills
  - CLAUDE.md       -> AGENTS.md
  - .dev-tools/git-merge-current-branch.ps1 -> .agents/skills/process-logging-and-merging/scripts/git-merge-current-branch.ps1

可能な場合はSymbolicLinkを作成し、権限不足時は以下へ自動フォールバックします。
  - ディレクトリ: Junction
  - ファイル: HardLink

.EXAMPLE
.\make-symbolic-links.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# PowerShellコマンドとリンク種別を定義する定数相当変数
$Script:GitCommandName = 'git'
$Script:GitDirectoryOption = '-C'
$Script:GitRootCommand = 'rev-parse'
$Script:GitRootOption = '--show-toplevel'
$Script:SymbolicLinkItemType = 'SymbolicLink'
$Script:JunctionItemType = 'Junction'
$Script:HardLinkItemType = 'HardLink'
$Script:ReparsePointAttribute = [System.IO.FileAttributes]::ReparsePoint
$Script:NoErrorCount = 0
$Script:FailureExitCode = 1
$Script:SkillsSourceSuffix = '.agents\skills'
$Script:ClaudeSkillsSuffix = '.claude\skills'
$Script:AgentsFileName = 'AGENTS.md'
$Script:ClaudeFileName = 'CLAUDE.md'
$Script:MergeScriptSourceSuffix = '.agents\skills\process-logging-and-merging\scripts\git-merge-current-branch.ps1'
$Script:DevToolsDirectorySuffix = '.dev-tools'
$Script:MergeScriptFileName = 'git-merge-current-branch.ps1'
$Script:RemoveLinkOperation = 'Remove existing link'
$Script:CreateDirectoryOperation = 'New parent directory'
$Script:CreateItemOperation = 'New-Item'
$Script:GitRepositoryNotFoundMessage = 'gitリポジトリが見つかりません。'
$Script:TargetNotFoundMessage = 'リンク元が見つかりません'
$Script:ExistingItemMessage = 'リンク先に通常のファイルまたはディレクトリが存在します'
$Script:ProcessErrorMessage = '処理でエラーが発生しました'
$Script:LinkErrorMessage = 'リンク作成に失敗しました'
$Script:LinkErrorsMessage = '一部のリンク作成に失敗しました。'
$Script:NewLine = [Environment]::NewLine
$Script:ExistingLinkInformation = '既存リンクを削除しました'
$Script:SymbolicLinkInformation = 'シンボリックリンクを作成しました'
$Script:JunctionInformation = '権限不足のためJunctionで作成しました'
$Script:HardLinkInformation = '権限不足のためHardLinkで作成しました'
$Script:ExecutionDirectoryInformation = '実行ディレクトリ'
$Script:RepositoryRootInformation = '配置先リポジトリルート'
$Script:PrivilegeErrorPatterns = @(
    'Administrator privilege required',
    'Access to the path .+ is denied',
    'Access is denied',
    'アクセスが拒否されました',
    '権限',
    '特権'
)

<#
.SYNOPSIS
指定した基点パスが属するgitリポジトリのルートパスを取得します。

.PARAMETER BasePath
gitルート探索の基点とする絶対パス。
#>
function Get-RepoRoot {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath
    )

    $RepoRoot = & $Script:GitCommandName $Script:GitDirectoryOption $BasePath $Script:GitRootCommand $Script:GitRootOption 2>$null
    if (($LASTEXITCODE -ne 0) -or [string]::IsNullOrEmpty($RepoRoot)) {
        throw $Script:GitRepositoryNotFoundMessage
    }

    return (Resolve-Path $RepoRoot).Path
}

<#
.SYNOPSIS
エラーが権限不足によるものか判定します。

.PARAMETER ErrorMessage
判定するエラーメッセージ。
#>
function Test-PrivilegeError {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ErrorMessage
    )

    foreach ($Pattern in $Script:PrivilegeErrorPatterns) {
        if ($ErrorMessage -match $Pattern) {
            return $true
        }
    }

    return $false
}

<#
.SYNOPSIS
権限不足時のリンクを作成します。

.PARAMETER LinkPath
作成するリンクのパス。

.PARAMETER TargetPath
リンク元のパス。
#>
function New-FallbackLink {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LinkPath,

        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    $TargetItem = Get-Item -LiteralPath $TargetPath -ErrorAction Stop
    if ($TargetItem.PSIsContainer) {
        $CreateOperation = ("{0} {1} (-> {2})" -f $Script:CreateItemOperation, $Script:JunctionItemType, $TargetPath)
        if ($PSCmdlet.ShouldProcess($LinkPath, $CreateOperation)) {
            New-Item -ItemType $Script:JunctionItemType -Path $LinkPath -Target $TargetPath -ErrorAction Stop | Out-Null
            Write-Information ("{0}: {1} -> {2}" -f $Script:JunctionInformation, $LinkPath, $TargetPath) -InformationAction Continue
        }
        return
    }

    $CreateOperation = ("{0} {1} (-> {2})" -f $Script:CreateItemOperation, $Script:HardLinkItemType, $TargetPath)
    if ($PSCmdlet.ShouldProcess($LinkPath, $CreateOperation)) {
        New-Item -ItemType $Script:HardLinkItemType -Path $LinkPath -Target $TargetPath -ErrorAction Stop | Out-Null
        Write-Information ("{0}: {1} -> {2}" -f $Script:HardLinkInformation, $LinkPath, $TargetPath) -InformationAction Continue
    }
}

<#
.SYNOPSIS
指定項目がリンクであることを確認し、既存リンクを返します。

.PARAMETER LinkPath
確認するリンクのパス。
#>
function Get-ExistingLink {
    [CmdletBinding()]
    [OutputType([System.IO.FileSystemInfo])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LinkPath
    )

    $ExistingItem = Get-Item -LiteralPath $LinkPath -Force -ErrorAction SilentlyContinue
    if ($null -eq $ExistingItem) {
        return $null
    }

    $IsReparsePoint = ($ExistingItem.Attributes -band $Script:ReparsePointAttribute) -ne 0
    if (-not $IsReparsePoint) {
        throw ("{0}: {1}" -f $Script:ExistingItemMessage, $LinkPath)
    }

    return $ExistingItem
}

<#
.SYNOPSIS
既存のリンクを削除します。

.PARAMETER LinkPath
削除するリンクのパス。
#>
function Remove-ExistingLink {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LinkPath
    )

    $ExistingLink = Get-ExistingLink -LinkPath $LinkPath
    if ($null -eq $ExistingLink) {
        return
    }

    if ($PSCmdlet.ShouldProcess($LinkPath, $Script:RemoveLinkOperation)) {
        $RemoveParameters = @{
            LiteralPath = $LinkPath
            Force = $true
            Confirm = $false
            ErrorAction = 'Stop'
        }
        if ($ExistingLink.PSIsContainer) {
            $RemoveParameters.Recurse = $true
        }

        Remove-Item @RemoveParameters
        Write-Information ("{0}: {1}" -f $Script:ExistingLinkInformation, $LinkPath) -InformationAction Continue
    }
}

<#
.SYNOPSIS
指定パスの既存リンクを削除し、リンクを作成します。

.PARAMETER LinkPath
作成するリンクのパス。

.PARAMETER TargetPath
リンク元のパス。
#>
function New-SymbolicLinkItem {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LinkPath,

        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    if (-not (Test-Path -LiteralPath $TargetPath)) {
        throw ("{0}: {1}" -f $Script:TargetNotFoundMessage, $TargetPath)
    }

    $ParentDir = Split-Path -Parent $LinkPath
    if (-not (Test-Path -LiteralPath $ParentDir)) {
        if ($PSCmdlet.ShouldProcess($ParentDir, $Script:CreateDirectoryOperation)) {
            New-Item -ItemType Directory -Path $ParentDir -Force -ErrorAction Stop | Out-Null
        }
    }

    $CreateOperation = ("{0} {1} (-> {2})" -f $Script:CreateItemOperation, $Script:SymbolicLinkItemType, $TargetPath)
    if (-not $PSCmdlet.ShouldProcess($LinkPath, $CreateOperation)) {
        return
    }

    try {
        New-Item -ItemType $Script:SymbolicLinkItemType -Path $LinkPath -Target $TargetPath -ErrorAction Stop | Out-Null
        Write-Information ("{0}: {1} -> {2}" -f $Script:SymbolicLinkInformation, $LinkPath, $TargetPath) -InformationAction Continue
    }
    catch {
        if (-not (Test-PrivilegeError -ErrorMessage $_.Exception.Message)) {
            throw
        }

        New-FallbackLink -LinkPath $LinkPath -TargetPath $TargetPath
    }
}

<#
.SYNOPSIS
既存のリンクを削除してから指定したリンクを作成します。

.PARAMETER LinkPath
作成先リンクのパス。

.PARAMETER TargetPath
リンク元のパス。
#>
function Invoke-LinkOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LinkPath,

        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    Remove-ExistingLink -LinkPath $LinkPath
    if ($null -ne (Get-ExistingLink -LinkPath $LinkPath)) {
        return
    }

    New-SymbolicLinkItem -LinkPath $LinkPath -TargetPath $TargetPath
}

<#
.SYNOPSIS
仕様書で定義されたリンク操作の一覧を取得します。

.PARAMETER RepoRoot
リンクを配置するgitリポジトリのルートパス。
#>
function Get-LinkOperation {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    return @(
        [PSCustomObject]@{
            LinkPath = Join-Path $RepoRoot $Script:ClaudeSkillsSuffix
            TargetPath = Join-Path $RepoRoot $Script:SkillsSourceSuffix
        },
        [PSCustomObject]@{
            LinkPath = Join-Path $RepoRoot $Script:ClaudeFileName
            TargetPath = Join-Path $RepoRoot $Script:AgentsFileName
        },
        [PSCustomObject]@{
            LinkPath = Join-Path (Join-Path $RepoRoot $Script:DevToolsDirectorySuffix) $Script:MergeScriptFileName
            TargetPath = Join-Path $RepoRoot $Script:MergeScriptSourceSuffix
        }
    )
}

<#
.SYNOPSIS
仕様書で定義されたAIリソースのリンクを作成します。
#>
function Invoke-Main {
    [CmdletBinding()]
    param()

    try {
        $ExecutionDirectoryPath = (Get-Location).Path
        Write-Information ("{0}: {1}" -f $Script:ExecutionDirectoryInformation, $ExecutionDirectoryPath) -InformationAction Continue
        $RepoRoot = Get-RepoRoot -BasePath $ExecutionDirectoryPath
        Write-Information ("{0}: {1}" -f $Script:RepositoryRootInformation, $RepoRoot) -InformationAction Continue

        $Errors = @()
        $Operations = Get-LinkOperation -RepoRoot $RepoRoot

        foreach ($Operation in $Operations) {
            try {
                Invoke-LinkOperation -LinkPath $Operation.LinkPath -TargetPath $Operation.TargetPath
            }
            catch {
                $Errors += ("{0}: {1} -> {2}: {3}" -f $Script:LinkErrorMessage, $Operation.LinkPath, $Operation.TargetPath, $_.Exception.Message)
                Write-Warning ("{0}: {1} -> {2}" -f $Script:LinkErrorMessage, $Operation.LinkPath, $Operation.TargetPath)
            }
        }

        if ($Errors.Count -gt $Script:NoErrorCount) {
            throw ("{0}`n{1}" -f $Script:LinkErrorsMessage, ($Errors -join $Script:NewLine))
        }
    }
    catch {
        Write-Error ("{0}: {1}" -f $Script:ProcessErrorMessage, $_.Exception.Message)
        exit $Script:FailureExitCode
    }
}

Invoke-Main
