<#
.SYNOPSIS
    .dev-envのプロセス状態とHTTP疎通を表示する。
.DESCRIPTION
    PIDファイルを基にプロセス状態を取得し、nginxのHTTP疎通を確認する。
.OUTPUTS
    成功時は0、失敗時は1を返す。
.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\status.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 状態確認で使用する設定値と終了コードを定義する。
Set-Variable -Name HTTP_PORT -Option Constant -Value 80
Set-Variable -Name HTTP_TIMEOUT_SECONDS -Option Constant -Value 5
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

    # MySQLがデータディレクトリへ生成したPIDファイルを取得する。
    $dataPath = Join-Path $EnvironmentRoot 'mysql\data'
    $pidFiles = @(Get-ChildItem -LiteralPath $dataPath -Filter '*.pid' -File -ErrorAction SilentlyContinue)

    # PIDファイルの中から実行中のプロセスIDを探す。
    foreach ($pidFile in $pidFiles) {
        $processId = [int](Get-Content -LiteralPath $pidFile.FullName -Raw)
        if ($null -ne (Get-Process -Id $processId -ErrorAction SilentlyContinue)) {
            return $processId
        }
    }

    # 実行中のMySQLプロセスが存在しない。
    return $null
}

<#
.SYNOPSIS
    指定したプロセス名から実行中のプロセスIDを取得する。
.PARAMETER Name
    プロセス名。
#>
function Get-ProcessIdByName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    # 指定名で実行中のプロセスを1件取得する。
    $process = Get-Process -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1

    # 取得できた場合はプロセスIDを返す。
    if ($null -ne $process) {
        return $process.Id
    }

    # 指定名のプロセスが実行されていない。
    return $null
}

<#
.SYNOPSIS
    PIDファイルを基にプロセス状態を返す。
#>
function Get-EnvironmentStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$PidPath,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [Nullable[int]]$ProcessId
    )

    # 引数で指定されたPIDを優先し、未指定時はPIDファイルから読み取る。
    if ($null -eq $ProcessId -and (Test-Path -LiteralPath $PidPath -PathType Leaf)) {
        $ProcessId = [int](Get-Content -LiteralPath $PidPath -Raw)
    }

    # プロセスの実行状態を確認する。
    $isRunning = $null -ne $ProcessId -and $null -ne (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)

    # 状態確認結果をオブジェクトとして返す。
    return [PSCustomObject]@{
        Name      = $Name
        ProcessId = $ProcessId
        Running   = $isRunning
    }
}

#Requires -Version 5.1
<#
.SYNOPSIS
    MySQL、PHP、nginxの状態を表示する。
#>
function Invoke-Main {
    [CmdletBinding()]
    param()

    try {
        # PIDファイルの保存先を解決する。
        $runtimeRoot = Join-Path $PSScriptRoot 'runtime'
        # MySQLは自身がPIDファイルを生成するため、実PIDを優先して状態を確認する。
        $mySqlProcessId = Get-MySqlProcessId -EnvironmentRoot $PSScriptRoot
        $mySqlStatus = Get-EnvironmentStatus -Name 'MySQL' -PidPath (Join-Path $runtimeRoot 'mysql.pid') -ProcessId $mySqlProcessId

        # PHPはランタイムのPIDファイルだけで状態を確認する。
        $phpStatus = Get-EnvironmentStatus -Name 'PHP' -PidPath (Join-Path $runtimeRoot 'php.pid')

        # nginxはマスターとワーカーの複数プロセスで動作するため、プロセス名から実PIDを取得して状態を確認する。
        $nginxProcessId = Get-ProcessIdByName -Name 'nginx'
        $nginxStatus = Get-EnvironmentStatus -Name 'nginx' -PidPath (Join-Path $runtimeRoot 'nginx.pid') -ProcessId $nginxProcessId

        # 3プロセスの状態を一覧表として出力する。
        @($mySqlStatus, $phpStatus, $nginxStatus) |
            Format-Table -Property Name, ProcessId, Running -AutoSize |
            Out-String |
            Write-Output

        # nginxのHTTP疎通を確認する。
        if ($nginxStatus.Running) {
            try {
                $httpUri = 'http://localhost:{0}' -f $HTTP_PORT
                $httpResponse = Invoke-WebRequest -Uri $httpUri -UseBasicParsing -TimeoutSec $HTTP_TIMEOUT_SECONDS
                Write-Output ('HTTP StatusCode: {0}' -f $httpResponse.StatusCode)
            }
            catch {
                Write-Warning $_.Exception.Message
            }
        }

        # 状態確認が完了したため成功の終了コードを設定する。
        exit $SUCCESS_EXIT_CODE
    }
    catch {
        # 状態確認に失敗したためエラー内容を表示し、失敗の終了コードを設定する。
        Write-Error -ErrorRecord $_
        exit $FAILURE_EXIT_CODE
    }
}

Invoke-Main
