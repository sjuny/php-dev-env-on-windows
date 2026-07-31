<#
.SYNOPSIS
    開発環境のDSC構成をコンパイルして適用する。
.DESCRIPTION
    前提条件を確認し、トランスクリプトを保存した上でConfigurationをコンパイルし、
    生成したMOFをStart-DscConfigurationで適用する。
.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# スクリプトの配置場所と構成ファイルを識別するための定数である。
Set-Variable -Name RESOURCE_ROOT -Option Constant -Value $PSScriptRoot
Set-Variable -Name CONFIGURATION_PATH -Option Constant -Value (Join-Path $RESOURCE_ROOT 'configurations\initialize.ps1')
Set-Variable -Name CONFIGURATION_DATA_PATH -Option Constant -Value (Join-Path $RESOURCE_ROOT 'configuration-data\Development.psd1')
Set-Variable -Name ASSET_ROOT -Option Constant -Value (Join-Path $RESOURCE_ROOT 'assets')
Set-Variable -Name INITIALIZE_MYSQL_SCRIPT_PATH -Option Constant -Value (Join-Path $ASSET_ROOT 'scripts\initialize-mysql.ps1')
Set-Variable -Name OUTPUT_ROOT -Option Constant -Value (Join-Path $RESOURCE_ROOT 'outputs')
Set-Variable -Name MOF_PATH -Option Constant -Value (Join-Path $OUTPUT_ROOT 'localhost.mof')
Set-Variable -Name LOG_ROOT -Option Constant -Value (Join-Path $OUTPUT_ROOT 'logs')
Set-Variable -Name LOG_NAME_FORMAT -Option Constant -Value "yyyyMMdd-HHmm_'install.log'"
Set-Variable -Name REQUIRED_PS_VERSION -Option Constant -Value ([Version]'5.1')
Set-Variable -Name SUCCESS_EXIT_CODE -Option Constant -Value 0
Set-Variable -Name FAILURE_EXIT_CODE -Option Constant -Value 1
Set-Variable -Name MULTIBYTE_PATH_PATTERN -Option Constant -Value '[^\x00-\x7F]'
Set-Variable -Name MULTIBYTE_PATH_ERROR_MESSAGE -Option Constant -Value 'MySQLはマルチバイトを含むパスに配置できません。マルチバイトを含まないパスでインストールをしてください'
Set-Variable -Name COMPOSER_FILE_NAME -Option Constant -Value 'composer.phar'

<#
.SYNOPSIS
    WinRMサービスの起動状態を確認し、停止中の場合は起動する。
.DESCRIPTION
    DSC適用に必要なWinRMサービスを取得し、停止中の場合は起動する。
    起動要求後は、サービスが実行中になるまで待機する。
.EXAMPLE
    Start-WinRmService
#>
function Start-WinRmService {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    # WinRMサービスの状態を取得する。
    $service = Get-Service -Name 'WinRM' -ErrorAction Stop
    if ($service.Status -eq 'Running') {
        return
    }

    # WinRMサービスの起動可否を確認する。
    if (-not $PSCmdlet.ShouldProcess('WinRM', 'サービスを起動する')) {
        return
    }

    # WinRMサービスを起動し、実行状態を待機する。
    Start-Service -InputObject $service -ErrorAction Stop
    $service.WaitForStatus(
        [System.ServiceProcess.ServiceControllerStatus]::Running,
        [TimeSpan]::FromSeconds(30)
    )

    # WinRMサービスが実行状態になったことを確認する。
    if ($service.Status -ne 'Running') {
        throw 'WinRMサービスを起動できない。'
    }
}

<#
.SYNOPSIS
    配置先パスにマルチバイト文字が含まれていないことを確認する。
.PARAMETER Path
    検査対象の配置先パス。
.OUTPUTS
    マルチバイト文字を含む場合はTrue、それ以外はFalse。
#>
function Test-MultiBytePath {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    # 配置先パスにマルチバイト文字が含まれるか判定する。
    return $Path -match $MULTIBYTE_PATH_PATTERN
}

<#
.SYNOPSIS
    DSC適用に必要な前提条件を確認する。
#>
function Test-Prerequisite {
    # PowerShellのバージョンを確認する。
    if ($PSVersionTable.PSVersion -lt $REQUIRED_PS_VERSION) {
        throw "PowerShell $REQUIRED_PS_VERSION 以上が必要である。"
    }

    # DSC ConfigurationとConfigurationDataの存在を確認する。
    if (-not (Test-Path -LiteralPath $CONFIGURATION_PATH -PathType Leaf)) {
        throw "Configurationが見つからない: $CONFIGURATION_PATH"
    }

    if (-not (Test-Path -LiteralPath $CONFIGURATION_DATA_PATH -PathType Leaf)) {
        throw "ConfigurationDataが見つからない: $CONFIGURATION_DATA_PATH"
    }

    # MySQL初期化スクリプトの存在を確認する。
    if (-not (Test-Path -LiteralPath $INITIALIZE_MYSQL_SCRIPT_PATH -PathType Leaf)) {
        throw "MySQL初期化スクリプトが見つからない: $INITIALIZE_MYSQL_SCRIPT_PATH"
    }

    # Composer資材とNode.js資材の存在を確認する。
    $composerPath = Join-Path $ASSET_ROOT 'php\composer.phar'
    if (-not (Test-Path -LiteralPath $composerPath -PathType Leaf)) {
        throw "Composerが見つからない: $composerPath"
    }

    $nodeAssetPath = Join-Path $ASSET_ROOT 'nodejs'
    if (-not (Test-Path -LiteralPath $nodeAssetPath -PathType Container)) {
        throw "Node.js資材ディレクトリが見つからない: $nodeAssetPath"
    }

    # MySQL設定テンプレートとphpMyAdmin資材の存在を確認する。
    $mySqlConfigurationTemplatePath = Join-Path $ASSET_ROOT 'mysql\my.ini'
    if (-not (Test-Path -LiteralPath $mySqlConfigurationTemplatePath -PathType Leaf)) {
        throw "MySQL設定テンプレートが見つからない: $mySqlConfigurationTemplatePath"
    }

    $phpMyAdminAssetPath = Join-Path $ASSET_ROOT 'phpmyadmin'
    if (-not (Test-Path -LiteralPath $phpMyAdminAssetPath -PathType Container)) {
        throw "phpMyAdmin資材ディレクトリが見つからない: $phpMyAdminAssetPath"
    }

    # DSC適用コマンドの利用可否を確認する。
    if (-not (Get-Command -Name Start-DscConfiguration -ErrorAction SilentlyContinue)) {
        throw 'Start-DscConfigurationが利用できない。'
    }
}

<#
.SYNOPSIS
application配下から指定したマニフェストを探索する。

.PARAMETER ApplicationRoot
探索対象のapplicationルート。

.PARAMETER Name
探索するマニフェスト名。
#>
function Get-ApplicationManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ApplicationRoot,

        [Parameter(Mandatory = $true)]
        [ValidateSet('composer.json', 'package.json')]
        [string]$Name
    )

    # applicationルートの存在を確認する。
    if (-not (Test-Path -LiteralPath $ApplicationRoot -PathType Container)) {
        return
    }

    # 依存関係管理用ディレクトリを除外してマニフェストを探索する。
    return Get-ChildItem -LiteralPath $ApplicationRoot -Filter $Name -File -Recurse |
        Where-Object { $_.FullName -notmatch '[\\/]((node_modules)|(vendor))([\\/]|$)' }
}

<#
.SYNOPSIS
package.jsonにViteの依存関係が定義されているか確認する。

.PARAMETER Package
解析済みのpackage.json。
#>
function Test-ViteDependency {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [psobject]$Package
    )

    # dependenciesとdevDependenciesを順に確認する。
    foreach ($propertyName in @('dependencies', 'devDependencies')) {
        $property = $Package.PSObject.Properties[$propertyName]
        if ($null -eq $property -or $null -eq $property.Value) {
            continue
        }

        # Viteが依存関係として定義されているか判定する。
        if ($null -ne $property.Value.PSObject.Properties['vite']) {
            return $true
        }
    }

    return $false
}

<#
.SYNOPSIS
指定したアプリケーションでComposer installを実行する。

.PARAMETER ApplicationPath
Composerを実行するアプリケーションディレクトリ。
#>
function Invoke-ComposerInstall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ApplicationPath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PhpPath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ComposerPath
    )

    # 配置済みのPHPとComposerで依存関係をインストールする。
    Write-Verbose "Composer installを実行する: $ApplicationPath"
    & $PhpPath $ComposerPath 'install' '--no-interaction' '--working-dir' $ApplicationPath
    # Composerの終了コードを確認する。
    if ($LASTEXITCODE -ne 0) {
        throw "Composer installが終了コード${LASTEXITCODE}で失敗した: $ApplicationPath"
    }
}

<#
.SYNOPSIS
指定したアプリケーションでnpm installを実行する。

.PARAMETER ApplicationPath
npmを実行するアプリケーションディレクトリ。
#>
function Invoke-NpmInstall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ApplicationPath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$NpmPath
    )

    # 配置済みのnpmで依存関係をインストールする。
    Write-Verbose "npm installを実行する: $ApplicationPath"
    & $NpmPath 'install' '--prefix' $ApplicationPath
    # npm installの終了コードを確認する。
    if ($LASTEXITCODE -ne 0) {
        throw "npm installが終了コード${LASTEXITCODE}で失敗した: $ApplicationPath"
    }
}

<#
.SYNOPSIS
指定したアプリケーションでnpm run buildを実行する。

.PARAMETER ApplicationPath
npmを実行するアプリケーションディレクトリ。
#>
function Invoke-NpmBuild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ApplicationPath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$NpmPath
    )

    # 配置済みのnpmでアプリケーションをビルドする。
    Write-Verbose "Vite buildを実行する: $ApplicationPath"
    & $NpmPath 'run' 'build' '--prefix' $ApplicationPath
    # npm run buildの終了コードを確認する。
    if ($LASTEXITCODE -ne 0) {
        throw "npm run buildが終了コード${LASTEXITCODE}で失敗した: $ApplicationPath"
    }
}

<#
.SYNOPSIS
application配下のComposerおよびnpm依存関係をインストールする。

.PARAMETER ProjectRoot
プロジェクトルート。

.PARAMETER Configuration
localhostの構成データ。
#>
function Invoke-ApplicationDependencyInstall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectRoot,

        [Parameter(Mandatory = $true)]
        [hashtable]$Configuration
    )

    # applicationルートを解決し、存在を確認する。
    $applicationRoot = Join-Path $ProjectRoot 'application'
    if (-not (Test-Path -LiteralPath $applicationRoot -PathType Container)) {
        return
    }

    # 配置済みのPHP、Composer、npmの実行パスを解決する。
    $phpRoot = Join-Path $Configuration.EnvironmentRoot 'php'
    $phpPath = Join-Path $phpRoot 'php.exe'
    $composerPath = Join-Path $phpRoot $COMPOSER_FILE_NAME
    $npmPath = Join-Path (Join-Path $Configuration.EnvironmentRoot 'nodejs') 'npm.cmd'

    # Composerマニフェストごとに依存関係をインストールする。
    foreach ($manifest in Get-ApplicationManifest -ApplicationRoot $applicationRoot -Name 'composer.json') {
        Invoke-ComposerInstall -ApplicationPath $manifest.DirectoryName -PhpPath $phpPath -ComposerPath $composerPath
    }

    # npmマニフェストを解析し、依存関係をインストールする。
    foreach ($manifest in Get-ApplicationManifest -ApplicationRoot $applicationRoot -Name 'package.json') {
        $package = Get-Content -LiteralPath $manifest.FullName -Raw | ConvertFrom-Json
        Invoke-NpmInstall -ApplicationPath $manifest.DirectoryName -NpmPath $npmPath
        # Viteの依存関係がある場合だけビルドする。
        if (Test-ViteDependency -Package $package) {
            Invoke-NpmBuild -ApplicationPath $manifest.DirectoryName -NpmPath $npmPath
        }
    }
}

<#
.SYNOPSIS
    指定したミドルウェア資産からZIPファイル名を取得する。
.PARAMETER AssetDirectory
    ZIPファイルを配置するミドルウェア資産ディレクトリ。
#>
function Get-ArchiveName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$AssetDirectory
    )

    # ミドルウェア資産に配置されたZIPファイルを取得する。
    $archiveFiles = @(Get-ChildItem -LiteralPath $AssetDirectory -Filter '*.zip' -File -ErrorAction Stop)
    # ZIPファイルが1個だけ存在することを確認する。
    if ($archiveFiles.Count -eq 0) {
        throw "ZIPファイルが見つからない: $AssetDirectory"
    }

    if ($archiveFiles.Count -gt 1) {
        throw "ZIPファイルが複数存在する: $AssetDirectory"
    }

    return $archiveFiles[0].Name
}

<#
.SYNOPSIS
    MySQLのデータディレクトリを初期化し、指定データベースを作成する。
.DESCRIPTION
    DSC適用後のMySQLへ初期化スクリプトを実行し、構成データで指定した
    データベースを冪等に作成する。
.PARAMETER Configuration
    localhostの構成データ。
.OUTPUTS
    なし。
.EXAMPLE
    Invoke-MySqlInitialization -Configuration $localhostNode
#>
function Invoke-MySqlInitialization {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Configuration
    )

    # 構成データから作成対象のデータベース名を取得する。
    $databaseName = $Configuration.MySqlDatabaseName
    if ([string]::IsNullOrWhiteSpace($databaseName)) {
        # DB名が空の場合は、MySQLの初期化とDB作成を行わない。
        return
    }

    # MySQL初期化スクリプトを実行する。
    & $INITIALIZE_MYSQL_SCRIPT_PATH -MySqlRoot (Join-Path $Configuration.EnvironmentRoot 'mysql') `
        -DatabaseName $databaseName -Port $Configuration.MySqlPort
    # MySQL初期化スクリプトの終了コードを確認する。
    if ($LASTEXITCODE -ne 0) {
        throw "MySQL初期化が終了コード$LASTEXITCODEで失敗した。"
    }
}

<#
.SYNOPSIS
    MySQL初期化処理が残したMySQLプロセスを停止する。
.PARAMETER EnvironmentRoot
    .dev-envのルートディレクトリ。
#>
function Stop-MySqlProcess {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$EnvironmentRoot
    )

    # MySQLが生成したPIDファイルを取得する。
    # MySQLデータディレクトリからPIDファイルを取得する。
    $dataPath = Join-Path $EnvironmentRoot 'mysql\data'
    $pidFiles = @(Get-ChildItem -LiteralPath $dataPath -Filter '*.pid' -File -ErrorAction SilentlyContinue)
    foreach ($pidFile in $pidFiles) {
        # PIDファイルからプロセスを取得する。
        $processId = [int](Get-Content -LiteralPath $pidFile.FullName -Raw)
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if ($null -eq $process) {
            continue
        }

        # 初期化処理が残したMySQLプロセスを停止する。
        # 対象プロセスを停止し、終了を待機する。
        if ($PSCmdlet.ShouldProcess($processId, 'MySQLプロセスを停止する')) {
            Stop-Process -Id $processId -Force
            $process.WaitForExit()
        }
    }
}

<#
.SYNOPSIS
    DSC構成のコンパイルと適用を実行する。
.OUTPUTS
    成功時は0、失敗時は1を返す。
#>
function Invoke-Main {
    $transcriptPath = $null
    try {
        # 前提条件と出力先を確認する。
        Test-Prerequisite
        # 出力先とログ出力先を作成し、トランスクリプトを開始する。
        New-Item -Path $OUTPUT_ROOT, $LOG_ROOT -ItemType Directory -Force | Out-Null
        $transcriptPath = Join-Path $LOG_ROOT (Get-Date -Format $LOG_NAME_FORMAT)
        Start-Transcript -Path $transcriptPath -Force | Out-Null

        # DSC適用前にWinRMサービスを起動する。
        Start-WinRmService

        # Configurationを読み込み、localhost用MOFを生成する。
        $env:PSModulePath = "$RESOURCE_ROOT\modules;$env:PSModulePath"
        . $CONFIGURATION_PATH
        $configurationData = Import-PowerShellDataFile -Path $CONFIGURATION_DATA_PATH
        $nginxArchiveName = Get-ArchiveName -AssetDirectory (Join-Path $ASSET_ROOT 'nginx')
        $phpArchiveName = Get-ArchiveName -AssetDirectory (Join-Path $ASSET_ROOT 'php')
        $mySqlArchiveName = Get-ArchiveName -AssetDirectory (Join-Path $ASSET_ROOT 'mysql')
        $nodeArchiveName = Get-ArchiveName -AssetDirectory (Join-Path $ASSET_ROOT 'nodejs')
        $phpMyAdminArchiveName = Get-ArchiveName -AssetDirectory (Join-Path $ASSET_ROOT 'phpmyadmin')
        $projectRoot = (Resolve-Path (Join-Path $RESOURCE_ROOT '..')).Path

        # MySQLが起動できない配置先を検出し、.dev-envの生成前に中断する。
        if (Test-MultiBytePath -Path $projectRoot) {
            throw $MULTIBYTE_PATH_ERROR_MESSAGE
        }

        # localhost用の構成データへ実行時パスを設定する。
        $localhostNode = $configurationData.AllNodes | Where-Object { $_.NodeName -eq 'localhost' } | Select-Object -First 1
        $localhostNode.ProjectRoot = $projectRoot
        $localhostNode.EnvironmentRoot = Join-Path $projectRoot '.dev-env'
        $localhostNode.AssetRoot = $ASSET_ROOT
        $localhostNode.OutputRoot = Join-Path $RESOURCE_ROOT 'outputs'
        # DSC ConfigurationをコンパイルしてMOFを生成する。
        $null = Initialize-DevEnvironment -ConfigurationData $configurationData -OutputPath $OUTPUT_ROOT `
            -NginxArchiveName $nginxArchiveName -PhpArchiveName $phpArchiveName -NodeArchiveName $nodeArchiveName `
            -MySqlArchiveName $mySqlArchiveName `
            -PhpMyAdminArchiveName $phpMyAdminArchiveName

        # 生成したMOFをDSC Local Configuration Managerへ適用する。
        $null = Start-DscConfiguration -Path $OUTPUT_ROOT -Wait -Verbose -Force

        # application配下のComposer/npm依存関係をインストールし、必要に応じてViteをビルドする。
        Invoke-ApplicationDependencyInstall -ProjectRoot $projectRoot -Configuration $localhostNode

        # DSC適用後にMySQLデータディレクトリと指定データベースを初期化する。
        $null = Invoke-MySqlInitialization -Configuration $localhostNode

        # MySQL初期化処理が残したMySQLプロセスを停止する。
        Stop-MySqlProcess -EnvironmentRoot $localhostNode.EnvironmentRoot
        exit $SUCCESS_EXIT_CODE
    }
    catch {
        Write-Error -ErrorRecord $_
        exit $FAILURE_EXIT_CODE
    }
    finally {
        # 開始済みのトランスクリプトを必ず終了する。
        if ($null -ne $transcriptPath) {
            Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
        }
    }
}

Invoke-Main
