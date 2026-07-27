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
        GetScript = {
            return @{ Result = (Test-Path -LiteralPath (Join-Path $using:EnvironmentRoot 'php\php.exe') -PathType Leaf).ToString() }
        }
        TestScript = {
            return Test-Path -LiteralPath (Join-Path $using:EnvironmentRoot 'php\php.exe') -PathType Leaf
        }
        SetScript = {
            $archivePath = Join-Path (Join-Path $using:AssetRoot 'php') $using:ArchiveName
            $destinationPath = Join-Path $using:EnvironmentRoot 'php'
            if (-not (Test-Path -LiteralPath $destinationPath -PathType Container)) {
                New-Item -Path $destinationPath -ItemType Directory -Force | Out-Null
            }

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
}
