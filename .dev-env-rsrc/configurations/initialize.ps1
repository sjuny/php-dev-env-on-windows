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
        [string]$MySqlArchiveName,

        [Parameter(Mandatory = $true)]
        [string]$PhpMyAdminArchiveName
    )

    Import-DscResource -ModuleName DevEnvironment
    Import-DscResource -ModuleName PSDesiredStateConfiguration

    Node 'localhost' {
        # ミドルウェアをそれぞれのComposite Resourceで配置する。
        NginxEnvironment Nginx {
            EnvironmentRoot = $Node.EnvironmentRoot
            AssetRoot = $Node.AssetRoot
            ArchiveName = $NginxArchiveName
            DependsOn = '[File]EnvironmentRoot'
        }

        PhpEnvironment Php {
            EnvironmentRoot = $Node.EnvironmentRoot
            AssetRoot = $Node.AssetRoot
            ArchiveName = $PhpArchiveName
            DependsOn = '[NginxEnvironment]Nginx'
        }

        MySqlEnvironment MySql {
            EnvironmentRoot = $Node.EnvironmentRoot
            AssetRoot = $Node.AssetRoot
            ArchiveName = $MySqlArchiveName
            DependsOn = '[PhpEnvironment]Php'
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
