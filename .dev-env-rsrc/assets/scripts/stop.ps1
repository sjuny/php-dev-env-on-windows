<#
.SYNOPSIS
    .dev-envのnginx、PHP-CGI、MySQLを停止する。
.DESCRIPTION
    PIDファイルを基にnginx、PHP-CGI、MySQLを停止する。
.OUTPUTS
    成功時は0、失敗時は1を返す。
.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\stop.ps1
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 停止処理の終了コードを定義する。
Set-Variable -Name SUCCESS_EXIT_CODE -Option Constant -Value 0
Set-Variable -Name FAILURE_EXIT_CODE -Option Constant -Value 1

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
    PIDファイルに記録されたプロセスを停止する。
#>
function Stop-ProcessByPidFile {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PidPath,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [Nullable[int]]$ProcessId
    )

    # PIDファイルの存在を確認する。
    if ($null -eq $ProcessId -and -not (Test-Path -LiteralPath $PidPath -PathType Leaf)) {
        return
    }

    # 引数で指定されたPIDを優先し、未指定時はPIDファイルから読み取る。
    if ($null -eq $ProcessId) {
        $ProcessId = [int](Get-Content -LiteralPath $PidPath -Raw)
    }

    # プロセスを停止し、PIDファイルを削除する。
    if ($PSCmdlet.ShouldProcess($ProcessId, 'プロセスを停止する')) {
        Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $PidPath -Force -ErrorAction SilentlyContinue
    }
}

<#
.SYNOPSIS
    指定したプロセス名のプロセスを停止する。
.PARAMETER Name
    停止対象のプロセス名。
#>
function Stop-ProcessByName {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $processes = @(Get-Process -Name $Name -ErrorAction SilentlyContinue)
    foreach ($process in $processes) {
        if ($PSCmdlet.ShouldProcess($process.Id, 'プロセスを停止する')) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
    }
}

<#
.SYNOPSIS
    仕様書の停止順序でプロセスを停止する。
#>
function Invoke-Main {
    [CmdletBinding()]
    param()

    try {
        # PIDファイルの保存先を解決する。
        $runtimeRoot = Join-Path $PSScriptRoot 'runtime'

        # 仕様書の停止順序に従い、nginx、PHP-CGI、MySQLを停止する。
        # nginxを停止する。
        Stop-ProcessByName -Name 'nginx'
        # PHP-CGIを停止する。
        Stop-ProcessByPidFile -PidPath (Join-Path $runtimeRoot 'php.pid')
        # MySQLを停止する。
        $mySqlProcessId = Get-MySqlProcessId -EnvironmentRoot $PSScriptRoot
        Stop-ProcessByPidFile -PidPath (Join-Path $runtimeRoot 'mysql.pid') -ProcessId $mySqlProcessId
        exit $SUCCESS_EXIT_CODE
    }
    catch {
        Write-Error -ErrorRecord $_
        exit $FAILURE_EXIT_CODE
    }
}

Invoke-Main
