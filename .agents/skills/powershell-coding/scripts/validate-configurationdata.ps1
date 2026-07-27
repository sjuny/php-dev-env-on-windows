#Requires -Version 5.1
<#
.SYNOPSIS
指定した psd1 ファイルの構文と読み込み可否を検証します。

.DESCRIPTION
-FilePaths で受け取った psd1 について、Parser.ParseFile と
Import-PowerShellDataFile を実行し、結果をオブジェクトで返します。
エラーがある場合のみ ErrorLocations を返します。

.OUTPUTS
System.Management.Automation.PSCustomObject[]
成功時は `FilePath` と `IsSuccess = $true` を返します。
失敗時は `IsSuccess = $false` と `ErrorLocations`（Line/Column/Message）を返します。

.EXAMPLE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\validate-configurationdata.ps1 -FilePaths .\configurationData\prod.psd1
戻り値（成功）:
@{
  FilePath  = 'C:\path\configurationData\prod.psd1'
  IsSuccess = $true
}

.EXAMPLE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\validate-configurationdata.ps1 -FilePaths .\tmp-invalid.psd1
戻り値（失敗）:
@{
  FilePath       = 'C:\path\tmp-invalid.psd1'
  IsSuccess      = $false
  ErrorLocations = @(
    @{ Line = 2; Column = 11; Message = 'Missing expression after '',''.' }
  )
}
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$FilePaths
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SUCCESS_EXIT_CODE = 0
$FAILURE_EXIT_CODE = 1

<#
.SYNOPSIS
Parser.ParseFile による構文検証を実行します。
#>
function Get-SyntaxErrors
{
    param (
        [string]$TargetFilePath
    )

    $parseTokens = $null
    $parseErrors = $null

    # PowerShell パーサーで psd1 の構文エラーを収集します。
    [System.Management.Automation.Language.Parser]::ParseFile(
        $TargetFilePath,
        [ref]$parseTokens,
        [ref]$parseErrors
    ) | Out-Null

    if ($null -eq $parseErrors -or $parseErrors.Count -eq 0) {
        return @()
    }

    # エラー箇所を行・列・メッセージで返します。
    return @($parseErrors | ForEach-Object {
            [PSCustomObject]@{
                Line    = $_.Extent.StartLineNumber
                Column  = $_.Extent.StartColumnNumber
                Message = $_.Message
            }
        })
}

<#
.SYNOPSIS
Import-PowerShellDataFile による読み込み検証を実行します。
#>
function Get-ImportError
{
    param (
        [string]$TargetFilePath
    )

    try {
        # psd1 をデータファイルとして読み込み可能かを検証します。
        Import-PowerShellDataFile -Path $TargetFilePath -ErrorAction Stop | Out-Null
        return $null
    }
    catch {
        return $_.Exception.Message
    }
}

<#
.SYNOPSIS
単一ファイルの検証結果オブジェクトを作成します。
#>
function Get-ValidationResult
{
    param (
        [string]$TargetFilePath
    )

    if (-not (Test-Path -LiteralPath $TargetFilePath -PathType Leaf)) {
        return [PSCustomObject]@{
            FilePath       = $TargetFilePath
            IsSuccess      = $false
            ErrorLocations = @(
                [PSCustomObject]@{
                    Line    = 0
                    Column  = 0
                    Message = 'File not found.'
                }
            )
        }
    }

    $resolvedFilePath = (Resolve-Path -LiteralPath $TargetFilePath).Path
    $syntaxErrors = @(Get-SyntaxErrors -TargetFilePath $resolvedFilePath)
    $importError = Get-ImportError -TargetFilePath $resolvedFilePath

    if ($syntaxErrors.Count -gt 0) {
        return [PSCustomObject]@{
            FilePath       = $resolvedFilePath
            IsSuccess      = $false
            ErrorLocations = $syntaxErrors
        }
    }

    if ($null -ne $importError) {
        return [PSCustomObject]@{
            FilePath       = $resolvedFilePath
            IsSuccess      = $false
            ErrorLocations = @(
                [PSCustomObject]@{
                    Line    = 0
                    Column  = 0
                    Message = $importError
                }
            )
        }
    }

    return [PSCustomObject]@{
        FilePath  = $resolvedFilePath
        IsSuccess = $true
    }
}

<#
.SYNOPSIS
validation のメイン処理を実行します。
#>
function Invoke-Main
{
    $hasFailure = $false
    $results = @()

    # 指定ファイルを順に検証し、失敗有無を集約します。
    foreach ($targetFilePath in $FilePaths) {
        $result = Get-ValidationResult -TargetFilePath $targetFilePath
        $results += $result

        if (-not $result.IsSuccess) {
            $hasFailure = $true
        }
    }

    $results

    if ($hasFailure) {
        exit $FAILURE_EXIT_CODE
    }

    exit $SUCCESS_EXIT_CODE
}

Invoke-Main
