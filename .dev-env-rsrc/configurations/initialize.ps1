<#
.SYNOPSIS
    .dev-envを構築するDSC Configurationを定義する。
.DESCRIPTION
    ミドルウェアのComposite Resourceと共通スクリプトの配置を定義する。
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

configuration Initialize-DevEnvironment {
    param(
        [Parameter(Mandatory = $true)]
        [string]$NginxArchiveName,

        [Parameter(Mandatory = $true)]
        [string]$PhpArchiveName,

        [Parameter(Mandatory = $true)]
        [string]$NodeArchiveName,

        [Parameter(Mandatory = $true)]
        [string]$MySqlArchiveName,

        [Parameter(Mandatory = $true)]
        [string]$PhpMyAdminArchiveName
    )

    Import-DscResource -ModuleName DevEnvironment
    Import-DscResource -ModuleName PSDesiredStateConfiguration

    Node 'localhost' {
        $NodeEnvironmentRoot = $Node.EnvironmentRoot
        $NodeAssetRoot = $Node.AssetRoot
        $NodePhpCgiPort = $Node.PhpCgiPort

        # ミドルウェアをそれぞれのComposite Resourceで配置する。
        NginxEnvironment Nginx {
            EnvironmentRoot = $Node.EnvironmentRoot
            AssetRoot = $Node.AssetRoot
            ArchiveName = $NginxArchiveName
            ProjectRoot = $Node.ProjectRoot
            PhpCgiPort = $Node.PhpCgiPort
            PhpMyAdminPort = $Node.PhpMyAdminPort
            DependsOn = '[File]EnvironmentRoot'
        }

        PhpEnvironment Php {
            EnvironmentRoot = $Node.EnvironmentRoot
            AssetRoot = $Node.AssetRoot
            ArchiveName = $PhpArchiveName
            DependsOn = '[NginxEnvironment]Nginx'
        }

        NodeEnvironment Node {
            EnvironmentRoot = $Node.EnvironmentRoot
            AssetRoot = $Node.AssetRoot
            ArchiveName = $NodeArchiveName
            DependsOn = '[PhpEnvironment]Php'
        }

        MySqlEnvironment MySql {
            EnvironmentRoot = $Node.EnvironmentRoot
            AssetRoot = $Node.AssetRoot
            ArchiveName = $MySqlArchiveName
            MySqlPort = $Node.MySqlPort
            DependsOn = '[NodeEnvironment]Node'
        }

        PhpMyAdminEnvironment PhpMyAdmin {
            EnvironmentRoot = $Node.EnvironmentRoot
            AssetRoot = $Node.AssetRoot
            ArchiveName = $PhpMyAdminArchiveName
            DependsOn = '[PhpEnvironment]Php'
        }

        # 実行時ディレクトリと共通スクリプトを配置する。
        File EnvironmentRoot {
            DestinationPath = $Node.EnvironmentRoot
            Type = 'Directory'
            Ensure = 'Present'
        }

        File RuntimeDirectory {
            DestinationPath = (Join-Path $Node.EnvironmentRoot 'runtime')
            Type = 'Directory'
            Ensure = 'Present'
            DependsOn = '[File]EnvironmentRoot'
        }

        File StartScript {
            DestinationPath = (Join-Path $Node.EnvironmentRoot 'start.ps1')
            SourcePath = (Join-Path $Node.AssetRoot 'scripts\start.ps1')
            Ensure = 'Present'
            Type = 'File'
            DependsOn = '[File]EnvironmentRoot'
        }

        # PHP-CGIのポートを起動スクリプトへ反映する。
        Script StartScriptConfiguration {
            GetScript = {
                $destinationPath = Join-Path $using:NodeEnvironmentRoot 'start.ps1'
                return @{ Result = (Test-Path -LiteralPath $destinationPath -PathType Leaf).ToString() }
            }
            TestScript = {
                # 起動スクリプトの原本と配置先を解決する。
                $sourcePath = Join-Path $using:NodeAssetRoot 'scripts\start.ps1'
                $destinationPath = Join-Path $using:NodeEnvironmentRoot 'start.ps1'
                if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
                    throw "起動スクリプトの原本が見つからない: $sourcePath"
                }

                # 配置先がない場合は設定が必要である。
                if (-not (Test-Path -LiteralPath $destinationPath -PathType Leaf)) {
                    return $false
                }

                # 原本のplaceholderと配置先の置換状態を確認する。
                $sourceConfiguration = Get-Content -LiteralPath $sourcePath -Raw
                $configuration = Get-Content -LiteralPath $destinationPath -Raw
                if (-not $sourceConfiguration.Contains('__PHP_CGI_PORT__')) {
                    throw "起動スクリプトにPHP-CGIのポート置換文字列がない: $sourcePath"
                }

                if ($configuration.Contains('__PHP_CGI_PORT__')) {
                    return $false
                }

                if (-not $configuration.Contains(([string]$using:NodePhpCgiPort))) {
                    return $false
                }

                return $true
            }
            SetScript = {
                # 起動スクリプトの原本と配置先を解決する。
                $sourcePath = Join-Path $using:NodeAssetRoot 'scripts\start.ps1'
                $destinationPath = Join-Path $using:NodeEnvironmentRoot 'start.ps1'
                # 原本を読み込み、placeholderの存在を確認する。
                $configuration = Get-Content -LiteralPath $sourcePath -Raw
                if (-not $configuration.Contains('__PHP_CGI_PORT__')) {
                    throw "起動スクリプトにPHP-CGIのポート置換文字列がない: $sourcePath"
                }

                # PHP-CGIのポートを置換する。
                $configuration = $configuration.Replace('__PHP_CGI_PORT__', ([string]$using:NodePhpCgiPort))
                # 置換後の起動スクリプトを配置する。
                [System.IO.File]::WriteAllText(
                    $destinationPath,
                    $configuration,
                    [System.Text.UTF8Encoding]::new($true)
                )
            }
            DependsOn = '[File]StartScript'
        }

        File StopScript {
            DestinationPath = (Join-Path $Node.EnvironmentRoot 'stop.ps1')
            SourcePath = (Join-Path $Node.AssetRoot 'scripts\stop.ps1')
            Ensure = 'Present'
            Type = 'File'
            DependsOn = '[File]EnvironmentRoot'
        }

        File StatusScript {
            DestinationPath = (Join-Path $Node.EnvironmentRoot 'status.ps1')
            SourcePath = (Join-Path $Node.AssetRoot 'scripts\status.ps1')
            Ensure = 'Present'
            Type = 'File'
            DependsOn = '[File]EnvironmentRoot'
        }

    }
}
