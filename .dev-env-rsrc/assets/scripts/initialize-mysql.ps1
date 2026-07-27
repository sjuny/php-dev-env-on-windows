#Requires -Version 5.1
<#
.SYNOPSIS
    MySQLのデータディレクトリを初期化し、指定データベースを作成する。
.DESCRIPTION
    未初期化のデータディレクトリだけを初期化し、MySQLを一時起動して
    指定データベースを冪等に作成する。
.PARAMETER MySqlRoot
    MySQLのルートディレクトリ。
.PARAMETER DatabaseName
    作成するデータベース名。
.PARAMETER Port
    一時起動したMySQLへ接続するポート番号。
.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\initialize-mysql.ps1 -MySqlRoot 'C:\project\.dev-env\mysql' `
        -DatabaseName 'laravel' -Port 3306 
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$MySqlRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$DatabaseName,

    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 65535)]
    [int]$Port
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# MySQL初期化処理で使用する定数である。
Set-Variable -Name DATA_DIRECTORY_NAME -Option Constant -Value 'data'
Set-Variable -Name CONFIGURATION_PATH -Option Constant -Value 'conf\my.ini'
Set-Variable -Name SERVER_EXECUTABLE_NAME -Option Constant -Value 'bin\mysqld.exe'
Set-Variable -Name CLIENT_EXECUTABLE_NAME -Option Constant -Value 'bin\mysql.exe'
Set-Variable -Name SERVER_START_TIMEOUT_SECONDS -Option Constant -Value 60
Set-Variable -Name SERVER_POLL_INTERVAL_SECONDS -Option Constant -Value 1
Set-Variable -Name SUCCESS_EXIT_CODE -Option Constant -Value 0
Set-Variable -Name FAILURE_EXIT_CODE -Option Constant -Value 1

<#
.SYNOPSIS
    データベース名がMySQL識別子として使用可能か確認する。
.DESCRIPTION
    保守的な文字セットでデータベース名を検証し、SQL識別子への埋め込みを安全にする。
.PARAMETER Name
    検証するデータベース名。
.EXAMPLE
    Test-DatabaseName -Name 'laravel'
#>
function Test-DatabaseName {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    # MySQL識別子として使用可能な文字だけで構成されているか確認する。
    return $Name -match '^[A-Za-z0-9_$]+$'
}

<#
.SYNOPSIS
    MySQLのデータディレクトリを初期化する。
.DESCRIPTION
    MySQLのシステムデータベースが存在しない場合だけ初期化コマンドを実行する。
.PARAMETER DataPath
    初期化するデータディレクトリ。
.PARAMETER ServerPath
    MySQLサーバー実行ファイルのパス。
.EXAMPLE
    Initialize-MySqlData -DataPath $DataPath -ServerPath $ServerPath
#>
function Initialize-MySqlData {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DataPath,

        [Parameter(Mandatory = $true)]
        [string]$ServerPath
    )

    # 初期化済みかをシステムデータベースの存在で判定する。
    $systemDatabasePath = Join-Path $DataPath 'mysql'
    if (Test-Path -LiteralPath $systemDatabasePath -PathType Container) {
        return
    }

    # MySQLの初期化コマンドを実行する。
    if ($PSCmdlet.ShouldProcess($DataPath, 'MySQLデータディレクトリを初期化する')) {
        $arguments = @('--initialize-insecure', "--datadir=$DataPath")
        & $ServerPath @arguments

        # 初期化コマンドの終了コードを確認する。
        if ($LASTEXITCODE -ne 0) {
            throw "MySQLデータディレクトリの初期化が終了コード$LASTEXITCODEで失敗した。"
        }
    }
}

<#
.SYNOPSIS
    MySQLへ一時接続して指定データベースを作成する。
.DESCRIPTION
    MySQLサーバーを一時起動し、接続可能になるまで待機してからデータベースを作成する。
.PARAMETER Configuration
    MySQL接続に必要な設定値。
.EXAMPLE
    New-MySqlDatabase -Configuration $Configuration
#>
function New-MySqlDatabase {
    [CmdletBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = 'Medium'
    )]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Configuration
    )

    # データベース作成の実行可否を確認する。
    if (-not $PSCmdlet.ShouldProcess($Configuration.DatabaseName, 'MySQLデータベースを作成する')) {
        return
    }

    $serverProcess = $null
    try {
        # 一時MySQLサーバーの起動引数を構成する。
        $arguments = @(
            ('--defaults-file={0}' -f $Configuration.ConfigurationPath),
            '--skip-networking=0',
            '--bind-address=127.0.0.1',
            ('--port={0}' -f $Configuration.Port),
            '--console'
        )
        $serverProcess = Start-Process -FilePath $Configuration.ServerPath `
            -ArgumentList $arguments -WorkingDirectory $Configuration.MySqlRoot `
            -PassThru -WindowStyle Hidden

        # MySQLへ接続できるまで待機する。
        $isReady = $false
        for ($attempt = 0; $attempt -lt $Configuration.TimeoutSeconds; $attempt++) {
            if ($serverProcess.HasExited) {
                throw 'MySQL一時プロセスが接続前に終了した。'
            }

            & $Configuration.ClientPath '--protocol=tcp' '--host=127.0.0.1' `
            ('--port={0}' -f $Configuration.Port) '--user=root' '--execute=SELECT 1;'
            if ($LASTEXITCODE -eq 0) {
                $isReady = $true
                break
            }

            Start-Sleep -Seconds $Configuration.PollIntervalSeconds
        }

        if (-not $isReady) {
            throw 'MySQLが接続可能になる前にタイムアウトした。'
        }

        # データベース名をSQL識別子へ安全に埋め込み、作成する。
        $escapedName = $Configuration.DatabaseName.Replace('`', '``')
        $query = "CREATE DATABASE IF NOT EXISTS ``$escapedName``;"
        & $Configuration.ClientPath '--protocol=tcp' '--host=127.0.0.1' `
        ('--port={0}' -f $Configuration.Port) '--user=root' ('--execute={0}' -f $query)
        if ($LASTEXITCODE -ne 0) {
            throw "データベース作成が終了コード$LASTEXITCODEで失敗した。"
        }
    }
    finally {
        # 一時MySQLサーバーを停止する。
        if ($null -ne $serverProcess -and -not $serverProcess.HasExited) {
            Stop-Process -Id $serverProcess.Id -Force
            $serverProcess.WaitForExit()
        }
    }
}

<#
.SYNOPSIS
    MySQL初期化処理を実行する。
.DESCRIPTION
    パスを解決し、データディレクトリを初期化して指定データベースを作成する。
.EXAMPLE
    Invoke-Main
#>
function Invoke-Main {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$MySqlRoot,

        [Parameter(Mandatory = $true)]
        [string]$DatabaseName,

        [Parameter(Mandatory = $true)]
        [int]$Port
    )

    try {
        # データベース名を検証する。
        if (-not (Test-DatabaseName -Name $DatabaseName)) {
            throw "データベース名に使用できない文字が含まれている: $DatabaseName"
        }

        # MySQL関連パスを解決する。
        $dataPath = Join-Path $MySqlRoot $DATA_DIRECTORY_NAME
        $serverPath = Join-Path $MySqlRoot $SERVER_EXECUTABLE_NAME
        $clientPath = Join-Path $MySqlRoot $CLIENT_EXECUTABLE_NAME
        $configurationPath = Join-Path $MySqlRoot $CONFIGURATION_PATH
        # 初期化に必要なパスの存在を確認する。
        foreach ($path in @($MySqlRoot, $serverPath, $clientPath, $configurationPath)) {
            if (-not (Test-Path -LiteralPath $path)) {
                throw "MySQL初期化に必要なパスが存在しない: $path"
            }
        }

        # MySQL接続設定を構成する。
        $configuration = [pscustomobject]@{
            ConfigurationPath   = $configurationPath
            MySqlRoot           = $MySqlRoot
            ServerPath          = $serverPath
            ClientPath          = $clientPath
            DatabaseName        = $DatabaseName
            Port                = $Port
            TimeoutSeconds      = $SERVER_START_TIMEOUT_SECONDS
            PollIntervalSeconds = $SERVER_POLL_INTERVAL_SECONDS
        }
        # データディレクトリを初期化し、データベースを作成する。
        Initialize-MySqlData -DataPath $dataPath -ServerPath $serverPath
        New-MySqlDatabase -Configuration $configuration
        return [int]$SUCCESS_EXIT_CODE
    }
    catch {
        Write-Error -ErrorRecord $_
        return [int]$FAILURE_EXIT_CODE
    }
}

exit (Invoke-Main -MySqlRoot $MySqlRoot -DatabaseName $DatabaseName -Port $Port)

