#Requires -Version 5.1

<#
.SYNOPSIS
PowerShellソースコードをPSScriptAnalyzerで解析します。

.DESCRIPTION
引数で指定されたPowerShellソースコードのパスを検証し、
PSScriptAnalyzerが未導入ならインストール後に解析を実行します。

.PARAMETER TargetPath
解析対象のPowerShellソースファイルパス。

.EXAMPLE
.\analyze-code.ps1 -TargetPath ".\sample.ps1" -Verbose
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TargetPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SCRIPT_ANALYZER_MODULE_NAME = 'PSScriptAnalyzer'
$ANALYSIS_SUCCESS_EXIT_CODE = 0
$ANALYSIS_WARNING_EXIT_CODE = 1
$EXECUTION_ERROR_EXIT_CODE = 2
$ANALYZER_REEXECUTION_ENV_NAME = 'TRIAD_ANALYZE_REEXECUTED_IN_WINPS'

function Invoke-OnWindowsPowerShell {
    <#
    .SYNOPSIS
    Windows PowerShell 5.1 での再実行が必要な場合に同一スクリプトを再起動します。

    .PARAMETER TargetScriptPath
    解析対象ファイルのパス。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$TargetScriptPath
    )

    $isWindowsPowerShell = ($PSVersionTable.PSEdition -eq 'Desktop') -and ($PSVersionTable.PSVersion.Major -eq 5)
    if ($isWindowsPowerShell) {
        return
    }

    $reexecutionFlag = [Environment]::GetEnvironmentVariable($ANALYZER_REEXECUTION_ENV_NAME, 'Process')
    if ($reexecutionFlag -eq '1') {
        throw 'Windows PowerShell 5.1 への再実行に失敗しました。'
    }

    $windowsPowerShellCommand = Get-Command -Name 'powershell.exe' -ErrorAction SilentlyContinue
    if ($null -eq $windowsPowerShellCommand) {
        throw 'powershell.exe が見つかりません。Windows PowerShell 5.1 を利用できる環境で実行してください。'
    }

    Write-Verbose 'Windows PowerShell 5.1 で再実行します。'
    $reexecutionArguments = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $PSCommandPath,
        '-TargetPath', $TargetScriptPath
    )
    if ($PSBoundParameters.ContainsKey('Verbose')) {
        $reexecutionArguments += '-Verbose'
    }

    [Environment]::SetEnvironmentVariable($ANALYZER_REEXECUTION_ENV_NAME, '1', 'Process')
    try {
        & $windowsPowerShellCommand.Source @reexecutionArguments
        exit $LASTEXITCODE
    }
    finally {
        [Environment]::SetEnvironmentVariable($ANALYZER_REEXECUTION_ENV_NAME, $null, 'Process')
    }
}

function Install-ScriptAnalyzerModule {
    <#
    .SYNOPSIS
    PSScriptAnalyzerモジュールの導入状態を確認し、未導入ならインストールします。
    #>
    [CmdletBinding()]
    param()

    $installedModule = Get-Module -ListAvailable -Name $SCRIPT_ANALYZER_MODULE_NAME
    if ($null -ne $installedModule) {
        Write-Verbose 'PSScriptAnalyzerは既にインストールされています。'
        return
    }

    Write-Verbose 'PSScriptAnalyzerをインストールします。'
    Install-Module -Name PSScriptAnalyzer -Force -ErrorAction Stop
}

function Get-TargetScriptPath {
    <#
    .SYNOPSIS
    解析対象ファイルの存在確認と絶対パス解決を行います。

    .PARAMETER InputPath
    ユーザーが指定した入力パス。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$InputPath
    )

    if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) {
        throw "解析対象ファイルが見つかりません: $InputPath"
    }

    return (Resolve-Path -LiteralPath $InputPath -ErrorAction Stop).Path
}

function Invoke-CodeAnalysis {
    <#
    .SYNOPSIS
    PSScriptAnalyzerを実行し、判定結果をオブジェクトで返します。

    .PARAMETER ScriptPath
    解析対象の絶対パス。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptPath
    )

    $analysisResult = Invoke-ScriptAnalyzer -Path $ScriptPath -ErrorAction Stop
    $issueCount = 0
    if ($null -ne $analysisResult) {
        # 単一オブジェクト/配列の両方を同一処理で件数化します。
        $issueCount = @($analysisResult).Count
    }

    return [PSCustomObject]@{
        TargetPath = $ScriptPath
        IsSuccess  = ($issueCount -eq 0)
        IssueCount = $issueCount
        Issues     = $analysisResult
    }
}

try {
    Invoke-OnWindowsPowerShell -TargetScriptPath $TargetPath
    Install-ScriptAnalyzerModule
    $resolvedPath = Get-TargetScriptPath -InputPath $TargetPath
    $result = Invoke-CodeAnalysis -ScriptPath $resolvedPath

    if (-not $result.IsSuccess) {
        Write-Warning ("解析で{0}件の問題を検出しました。" -f $result.IssueCount)
        $result
        exit $ANALYSIS_WARNING_EXIT_CODE
    }

    Write-Verbose '解析で問題は検出されませんでした。'
    $result
    exit $ANALYSIS_SUCCESS_EXIT_CODE
}
catch {
    Write-Error ("解析処理でエラーが発生しました: {0}" -f $_.Exception.Message)
    exit $EXECUTION_ERROR_EXIT_CODE
}
