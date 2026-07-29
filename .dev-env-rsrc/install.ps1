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

    $service = Get-Service -Name 'WinRM' -ErrorAction Stop
    if ($service.Status -eq 'Running') {
        return
    }

    if (-not $PSCmdlet.ShouldProcess('WinRM', 'サービスを起動する')) {
        return
    }

    Start-Service -InputObject $service -ErrorAction Stop
    $service.WaitForStatus(
        [System.ServiceProcess.ServiceControllerStatus]::Running,
        [TimeSpan]::FromSeconds(30)
    )

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

    return $Path -match $MULTIBYTE_PATH_PATTERN
}

<#
.SYNOPSIS
    DSC適用に必要な前提条件を確認する。
#>
function Test-Prerequisite {
    if ($PSVersionTable.PSVersion -lt $REQUIRED_PS_VERSION) {
        throw "PowerShell $REQUIRED_PS_VERSION 以上が必要である。"
    }

    if (-not (Test-Path -LiteralPath $CONFIGURATION_PATH -PathType Leaf)) {
        throw "Configurationが見つからない: $CONFIGURATION_PATH"
    }

    if (-not (Test-Path -LiteralPath $CONFIGURATION_DATA_PATH -PathType Leaf)) {
        throw "ConfigurationDataが見つからない: $CONFIGURATION_DATA_PATH"
    }

    if (-not (Test-Path -LiteralPath $INITIALIZE_MYSQL_SCRIPT_PATH -PathType Leaf)) {
        throw "MySQL初期化スクリプトが見つからない: $INITIALIZE_MYSQL_SCRIPT_PATH"
    }

    $mySqlConfigurationTemplatePath = Join-Path $ASSET_ROOT 'mysql\my.ini'
    if (-not (Test-Path -LiteralPath $mySqlConfigurationTemplatePath -PathType Leaf)) {
        throw "MySQL設定テンプレートが見つからない: $mySqlConfigurationTemplatePath"
    }

    $phpMyAdminAssetPath = Join-Path $ASSET_ROOT 'phpmyadmin'
    if (-not (Test-Path -LiteralPath $phpMyAdminAssetPath -PathType Container)) {
        throw "phpMyAdmin資材ディレクトリが見つからない: $phpMyAdminAssetPath"
    }

    if (-not (Get-Command -Name Start-DscConfiguration -ErrorAction SilentlyContinue)) {
        throw 'Start-DscConfigurationが利用できない。'
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
    配置先のプロジェクトルートに応じてnginxのドキュメントルートを設定する。
.PARAMETER ProjectRoot
    プロジェクトルート。
.PARAMETER EnvironmentRoot
    .dev-envのルートディレクトリ。
.PARAMETER PhpMyAdminPort
    phpMyAdminへアクセスするポート番号。
#>
function Set-NginxDocumentRoot {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectRoot,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$EnvironmentRoot,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 65535)]
        [int]$PhpMyAdminPort
    )

    # nginx設定のテンプレートと出力先を解決する。
    $templatePath = Join-Path $ASSET_ROOT 'nginx\web-app.conf'
    $destinationPath = Join-Path $EnvironmentRoot 'nginx\conf\sites\web-app.conf'
    if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
        throw "nginx設定テンプレートが見つからない: $templatePath"
    }

    if (-not (Test-Path -LiteralPath (Split-Path -Parent $destinationPath) -PathType Container)) {
        throw "nginx設定ディレクトリが見つからない: $(Split-Path -Parent $destinationPath)"
    }

    # Windows形式のパスをnginx設定用のスラッシュ区切りへ変換する。
    $publicPath = (Join-Path $ProjectRoot 'application\public') -replace '\\', '/'
    $phpMyAdminPath = (Join-Path $EnvironmentRoot 'phpmyadmin') -replace '\\', '/'
    $template = Get-Content -LiteralPath $templatePath -Raw
    if (-not $template.Contains('__PROJECT_PUBLIC_PATH__')) {
        throw "nginx設定テンプレートに置換文字列がない: $templatePath"
    }

    if (-not $template.Contains('__PHPMYADMIN_ROOT_PATH__')) {
        throw "nginx設定テンプレートにphpMyAdminの置換文字列がない: $templatePath"
    }

    if (-not $template.Contains('__PHPMYADMIN_PORT__')) {
        throw "nginx設定テンプレートにphpMyAdminのポート置換文字列がない: $templatePath"
    }

    # 配置先に実際のドキュメントルートを反映する。
    $configuration = $template.Replace('__PROJECT_PUBLIC_PATH__', $publicPath)
    $configuration = $configuration.Replace('__PHPMYADMIN_ROOT_PATH__', $phpMyAdminPath)
    $configuration = $configuration.Replace('__PHPMYADMIN_PORT__', $PhpMyAdminPort.ToString())
    if ($PSCmdlet.ShouldProcess($destinationPath, 'nginx設定を配置する')) {
        [System.IO.File]::WriteAllText(
            $destinationPath,
            $configuration,
            [System.Text.UTF8Encoding]::new($false)
        )
    }
}

<#
.SYNOPSIS
    配置先に応じてMySQLの設定ファイルを絶対パスで配置する。
.DESCRIPTION
    my.iniテンプレートの置換文字列をMySQLの実パスへ置換して配置する。
    相対パス指定はカレントディレクトリに依存して起動が失敗するため、絶対パスで設定する。
.PARAMETER EnvironmentRoot
    .dev-envのルートディレクトリ。
.PARAMETER MySqlPort
    MySQLが待ち受けるポート番号。
.EXAMPLE
    Set-MySqlConfiguration -EnvironmentRoot $environmentRoot -MySqlPort 3306
#>
function Set-MySqlConfiguration {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$EnvironmentRoot,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 65535)]
        [int]$MySqlPort
    )

    # MySQL設定のテンプレートと出力先を解決する。
    $templatePath = Join-Path $ASSET_ROOT 'mysql\my.ini'
    $mySqlRoot = Join-Path $EnvironmentRoot 'mysql'
    $destinationPath = Join-Path $mySqlRoot 'conf\my.ini'
    if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
        throw "MySQL設定テンプレートが見つからない: $templatePath"
    }

    if (-not (Test-Path -LiteralPath (Split-Path -Parent $destinationPath) -PathType Container)) {
        throw "MySQL設定ディレクトリが見つからない: $(Split-Path -Parent $destinationPath)"
    }

    # Windows形式のパスをMySQL設定用のスラッシュ区切りへ変換する。
    $replacementMap = [ordered]@{
        '__MYSQL_ROOT_PATH__' = $mySqlRoot -replace '\\', '/'
        '__MYSQL_DATA_PATH__' = (Join-Path $mySqlRoot 'data') -replace '\\', '/'
        '__MYSQL_TEMP_PATH__' = (Join-Path $mySqlRoot 'temp') -replace '\\', '/'
        '__MYSQL_LOG_PATH__'  = (Join-Path $mySqlRoot 'logs\mysql-error.log') -replace '\\', '/'
        '__MYSQL_PORT__'      = $MySqlPort.ToString()
    }

    # テンプレートの置換文字列を実パスへ置換する。
    $configuration = Get-Content -LiteralPath $templatePath -Raw
    foreach ($placeholder in $replacementMap.Keys) {
        if (-not $configuration.Contains($placeholder)) {
            throw "MySQL設定テンプレートに置換文字列がない: $placeholder"
        }

        $configuration = $configuration.Replace($placeholder, $replacementMap[$placeholder])
    }

    if ($PSCmdlet.ShouldProcess($destinationPath, 'MySQL設定を配置する')) {
        [System.IO.File]::WriteAllText(
            $destinationPath,
            $configuration,
            [System.Text.UTF8Encoding]::new($false)
        )
    }
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

    $databaseName = $Configuration.MySqlDatabaseName
    if ([string]::IsNullOrWhiteSpace($databaseName)) {
        # DB名が空の場合は、MySQLの初期化とDB作成を行わない。
        return
    }

    & $INITIALIZE_MYSQL_SCRIPT_PATH -MySqlRoot (Join-Path $Configuration.EnvironmentRoot 'mysql') `
        -DatabaseName $databaseName -Port $Configuration.MySqlPort
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
    $dataPath = Join-Path $EnvironmentRoot 'mysql\data'
    $pidFiles = @(Get-ChildItem -LiteralPath $dataPath -Filter '*.pid' -File -ErrorAction SilentlyContinue)
    foreach ($pidFile in $pidFiles) {
        $processId = [int](Get-Content -LiteralPath $pidFile.FullName -Raw)
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if ($null -eq $process) {
            continue
        }

        # 初期化処理が残したMySQLプロセスを停止する。
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
        $phpMyAdminArchiveName = Get-ArchiveName -AssetDirectory (Join-Path $ASSET_ROOT 'phpmyadmin')
        $projectRoot = (Resolve-Path (Join-Path $RESOURCE_ROOT '..')).Path

        # MySQLが起動できない配置先を検出し、.dev-envの生成前に中断する。
        if (Test-MultiBytePath -Path $projectRoot) {
            throw $MULTIBYTE_PATH_ERROR_MESSAGE
        }

        $localhostNode = $configurationData.AllNodes | Where-Object { $_.NodeName -eq 'localhost' } | Select-Object -First 1
        $localhostNode.ProjectRoot = $projectRoot
        $localhostNode.EnvironmentRoot = Join-Path $projectRoot '.dev-env'
        $localhostNode.AssetRoot = $ASSET_ROOT
        $localhostNode.OutputRoot = Join-Path $RESOURCE_ROOT 'outputs'
        $null = Initialize-DevEnvironment -ConfigurationData $configurationData -OutputPath $OUTPUT_ROOT `
            -NginxArchiveName $nginxArchiveName -PhpArchiveName $phpArchiveName -MySqlArchiveName $mySqlArchiveName `
            -PhpMyAdminArchiveName $phpMyAdminArchiveName

        # 生成したMOFをDSC Local Configuration Managerへ適用する。
        $null = Start-DscConfiguration -Path $OUTPUT_ROOT -Wait -Verbose -Force

        # 配置先のプロジェクトルートをnginx設定へ反映する。
        Set-NginxDocumentRoot -ProjectRoot $projectRoot -EnvironmentRoot $localhostNode.EnvironmentRoot `
            -PhpMyAdminPort $localhostNode.PhpMyAdminPort

        # 配置先の実パスをMySQL設定へ反映する。
        Set-MySqlConfiguration -EnvironmentRoot $localhostNode.EnvironmentRoot `
            -MySqlPort $localhostNode.MySqlPort

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
