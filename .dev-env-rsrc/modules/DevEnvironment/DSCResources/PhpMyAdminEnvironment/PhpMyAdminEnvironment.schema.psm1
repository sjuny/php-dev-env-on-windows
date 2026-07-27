Configuration PhpMyAdminEnvironment {
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
        throw 'phpMyAdminのZIPファイル名が指定されていない。'
    }

    # phpMyAdminの必須ファイルを判定し、未配置の場合だけZIPを展開する。
    Script InstallPhpMyAdminDirectory {
        GetScript = {
            return @{ Result = (Test-Path -LiteralPath (Join-Path $using:EnvironmentRoot 'phpmyadmin\index.php') -PathType Leaf).ToString() }
        }
        TestScript = {
            return Test-Path -LiteralPath (Join-Path $using:EnvironmentRoot 'phpmyadmin\index.php') -PathType Leaf
        }
        SetScript = {
            $archivePath = Join-Path (Join-Path $using:AssetRoot 'phpmyadmin') $using:ArchiveName
            $destinationPath = Join-Path $using:EnvironmentRoot 'phpmyadmin'
            if (-not (Test-Path -LiteralPath $destinationPath -PathType Container)) {
                New-Item -Path $destinationPath -ItemType Directory -Force | Out-Null
            }

            Expand-Archive -LiteralPath $archivePath -DestinationPath $destinationPath -Force
            $rootDirectories = @(Get-ChildItem -LiteralPath $destinationPath -Directory)
            if (-not (Test-Path -LiteralPath (Join-Path $destinationPath 'index.php') -PathType Leaf) -and $rootDirectories.Count -ne 1) {
                throw "phpMyAdmin ZIPのルートディレクトリを特定できない: $destinationPath"
            }

            if (-not (Test-Path -LiteralPath (Join-Path $destinationPath 'index.php') -PathType Leaf)) {
                Get-ChildItem -LiteralPath $rootDirectories[0].FullName | Copy-Item -Destination $destinationPath -Recurse -Force
                Remove-Item -LiteralPath $rootDirectories[0].FullName -Recurse -Force
            }
        }
    }

    # phpMyAdminへ自動ログインする設定ファイルを配置する。
    File PhpMyAdminConfiguration {
        DestinationPath = (Join-Path $EnvironmentRoot 'phpmyadmin\config.inc.php')
        SourcePath = (Join-Path $AssetRoot 'phpmyadmin\config.inc.php')
        Ensure = 'Present'
        Type = 'File'
        DependsOn = '[Script]InstallPhpMyAdminDirectory'
    }
}
