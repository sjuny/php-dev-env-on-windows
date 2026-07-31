<#
.SYNOPSIS
PHP環境を構築するDSC Composite Resourceを定義する。
#>
Configuration PhpEnvironment {
    param(
        [Parameter(Mandatory = $true)]
        [string]$EnvironmentRoot,

        [Parameter(Mandatory = $true)]
        [string]$AssetRoot,

        [Parameter(Mandatory = $true)]
        [string]$ArchiveName
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration

    if ([string]::IsNullOrWhiteSpace($ArchiveName)) {
        throw 'PHPのZIPファイル名が指定されていない。'
    }

    # PHPの必須ファイルを判定し、未配置の場合だけZIPを展開する。
    Script InstallPhpDirectory {
        # 現在のPHP配置状態を取得する。
        GetScript = {
            return @{ Result = (Test-Path -LiteralPath (Join-Path $using:EnvironmentRoot 'php\php.exe') -PathType Leaf).ToString() }
        }
        # PHPの必須ファイルが配置済みか検証する。
        TestScript = {
            return Test-Path -LiteralPath (Join-Path $using:EnvironmentRoot 'php\php.exe') -PathType Leaf
        }
        # PHP ZIPを展開し、配置先を正規化する。
        SetScript = {
            # PHP資材と配置先のパスを解決する。
            $archivePath = Join-Path (Join-Path $using:AssetRoot 'php') $using:ArchiveName
            $destinationPath = Join-Path $using:EnvironmentRoot 'php'
            # PHPの配置先ディレクトリを作成する。
            if (-not (Test-Path -LiteralPath $destinationPath -PathType Container)) {
                New-Item -Path $destinationPath -ItemType Directory -Force | Out-Null
            }

            # PHP ZIPを展開する。
            Expand-Archive -LiteralPath $archivePath -DestinationPath $destinationPath -Force
            if (-not (Test-Path -LiteralPath (Join-Path $destinationPath 'php.exe') -PathType Leaf)) {
                throw "PHP ZIPのルートにphp.exeが存在しない: $destinationPath"
            }
        }
    }

    # 展開したPHPへPHP設定ファイルを配置する。
    File PhpConfiguration {
        DestinationPath = (Join-Path $EnvironmentRoot 'php\php.ini')
        SourcePath = (Join-Path $AssetRoot 'php\php.ini')
        Ensure = 'Present'
        Type = 'File'
        DependsOn = '[Script]InstallPhpDirectory'
    }

    # 展開したPHPへComposerを配置する。
    File Composer {
        DestinationPath = (Join-Path $EnvironmentRoot 'php\composer.phar')
        SourcePath = (Join-Path $AssetRoot 'php\composer.phar')
        Ensure = 'Present'
        Type = 'File'
        Checksum = 'SHA-256'
        DependsOn = '[Script]InstallPhpDirectory'
    }
}
