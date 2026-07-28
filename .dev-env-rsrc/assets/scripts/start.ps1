<#
.SYNOPSIS
    .dev-envのMySQL、PHP-CGI、nginxを起動する。
.DESCRIPTION
    .dev-envのMySQL、PHP-CGI、nginxを起動する。
.OUTPUTS
    成功時は0、失敗時は1を返す。
.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\start.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 起動処理の終了コードを定義する。
Set-Variable -Name SUCCESS_EXIT_CODE -Option Constant -Value 0
Set-Variable -Name FAILURE_EXIT_CODE -Option Constant -Value 1
Set-Variable -Name MYSQL_START_TIMEOUT_SECONDS -Option Constant -Value 10
Set-Variable -Name MYSQL_START_POLL_INTERVAL_SECONDS -Option Constant -Value 1

#Requires -Version 5.1
<#
.SYNOPSIS
    MySQLが生成したPIDファイルから実行中のプロセスIDを取得する。
.PARAMETER EnvironmentRoot
    .dev-envのルートディレクトリ。
#>
function Get-MySqlProcessId {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$EnvironmentRoot
    )

    $dataPath = Join-Path $EnvironmentRoot 'mysql\data'
    $pidFiles = @(Get-ChildItem -LiteralPath $dataPath -Filter '*.pid' -File -ErrorAction SilentlyContinue)
    foreach ($pidFile in $pidFiles) {
        $processId = [int](Get-Content -LiteralPath $pidFile.FullName -Raw)
        if ($null -ne (Get-Process -Id $processId -ErrorAction SilentlyContinue)) {
            return $processId
        }
    }

    return $null
}

<#
.SYNOPSIS
    .dev-envのプロセスを起動する。
#>
function Start-ManagedProcess {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory,

        [Parameter(Mandatory = $true)]
        [string]$PidPath,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string[]]$ArgumentList
    )

    # 起動対象の実行ファイルが存在することを確認する。
    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        throw "${Name}の実行ファイルが見つからない: $FilePath"
    }

    # 既存PIDを確認し、停止済みプロセスのPIDファイルを整理する。
    if (Test-Path -LiteralPath $PidPath -PathType Leaf) {
        $processId = [int](Get-Content -LiteralPath $PidPath -Raw)
        if ($null -ne (Get-Process -Id $processId -ErrorAction SilentlyContinue)) {
            return
        }

        if ($PSCmdlet.ShouldProcess($PidPath, '古いPIDファイルを削除する')) {
            Remove-Item -LiteralPath $PidPath -Force
        }
    }

    # プロセスを起動し、PIDを保存する。
    if ($PSCmdlet.ShouldProcess($FilePath, "${Name}を起動する")) {
        $startParameters = @{
            FilePath         = $FilePath
            WorkingDirectory = $WorkingDirectory
            PassThru         = $true
            WindowStyle      = 'Hidden'
        }
        if ($null -ne $ArgumentList -and $ArgumentList.Count -gt 0) {
            $startParameters.ArgumentList = $ArgumentList
        }

        $process = Start-Process @startParameters
        $process.Id | Set-Content -LiteralPath $PidPath
    }
}

<#
.SYNOPSIS
    .dev-envのミドルウェアを起動する。
.OUTPUTS
    成功時は0、失敗時は1を返す。
#>
function Invoke-Main {
    [CmdletBinding()]
    param()

    try {
        $environmentRoot = $PSScriptRoot
        # PIDファイルの保存先を準備する。
        $runtimeRoot = Join-Path $environmentRoot 'runtime'
        New-Item -Path $runtimeRoot -ItemType Directory -Force | Out-Null

        # 既存のミドルウェアを停止する。
        $stopScriptPath = Join-Path $environmentRoot 'stop.ps1'
        if (-not (Test-Path -LiteralPath $stopScriptPath -PathType Leaf)) {
            throw "停止スクリプトが見つからない: $stopScriptPath"
        }

        & $stopScriptPath
        if ($LASTEXITCODE -ne $SUCCESS_EXIT_CODE) {
            throw "既存ミドルウェアの停止が終了コード$LASTEXITCODEで失敗した。"
        }

        # 既存のMySQLプロセスを検出し、実PIDをランタイムへ反映する。
        $mySqlProcessId = Get-MySqlProcessId -EnvironmentRoot $environmentRoot
        if ($null -eq $mySqlProcessId) {
            # MySQLの設定ファイル、データディレクトリ、起動引数を解決する。
            $mySqlRoot = Join-Path $environmentRoot 'mysql'
            $mySqlArguments = @(
                ('--defaults-file={0}' -f (Join-Path $mySqlRoot 'conf\my.ini')),
                ('--datadir={0}' -f (Join-Path $mySqlRoot 'data')),
                '--console'
            )

            # MySQLを起動する。
            Start-ManagedProcess -Name 'MySQL' `
                -FilePath (Join-Path $environmentRoot 'mysql\bin\mysqld.exe') `
                -WorkingDirectory $mySqlRoot `
                -PidPath (Join-Path $runtimeRoot 'mysql.pid') `
                -ArgumentList $mySqlArguments

            # MySQLが生成したPIDファイルを待機する。
            for ($attempt = 0; $attempt -lt $MYSQL_START_TIMEOUT_SECONDS; $attempt++) {
                Start-Sleep -Seconds $MYSQL_START_POLL_INTERVAL_SECONDS
                $mySqlProcessId = Get-MySqlProcessId -EnvironmentRoot $environmentRoot
                if ($null -ne $mySqlProcessId) {
                    break
                }
            }
        }

        if ($null -eq $mySqlProcessId) {
            throw 'MySQLの実PIDを取得できない。'
        }

        $mySqlProcessId | Set-Content -LiteralPath (Join-Path $runtimeRoot 'mysql.pid')
        # PHP-CGIを起動する。
        Start-ManagedProcess -Name 'PHP-CGI' `
            -FilePath (Join-Path $environmentRoot 'php\php-cgi.exe') `
            -WorkingDirectory (Join-Path $environmentRoot 'php') `
            -PidPath (Join-Path $runtimeRoot 'php.pid') `
            -ArgumentList @('-b', '127.0.0.1:9000')
        # nginxを起動する。
        Start-ManagedProcess -Name 'nginx' `
            -FilePath (Join-Path $environmentRoot 'nginx\nginx.exe') `
            -WorkingDirectory (Join-Path $environmentRoot 'nginx') `
            -PidPath (Join-Path $runtimeRoot 'nginx.pid')
        exit $SUCCESS_EXIT_CODE
    }
    catch {
        Write-Error -ErrorRecord $_
        exit $FAILURE_EXIT_CODE
    }
}

Invoke-Main
