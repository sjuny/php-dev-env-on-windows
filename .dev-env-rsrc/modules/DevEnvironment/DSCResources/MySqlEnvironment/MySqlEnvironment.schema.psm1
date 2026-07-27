Configuration MySqlEnvironment {
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
        throw 'MySQLのZIPファイル名が指定されていない。'
    }

    # MySQLの必須ファイルを判定し、未配置の場合だけZIPを展開する。
    Script InstallMySqlDirectory {
        GetScript = {
            return @{ Result = (Test-Path -LiteralPath (Join-Path $using:EnvironmentRoot 'mysql\bin\mysqld.exe') -PathType Leaf).ToString() }
        }
        TestScript = {
            return Test-Path -LiteralPath (Join-Path $using:EnvironmentRoot 'mysql\bin\mysqld.exe') -PathType Leaf
        }
        SetScript = {
            $archivePath = Join-Path (Join-Path $using:AssetRoot 'mysql') $using:ArchiveName
            $destinationPath = Join-Path $using:EnvironmentRoot 'mysql'
            if (-not (Test-Path -LiteralPath $destinationPath -PathType Container)) {
                New-Item -Path $destinationPath -ItemType Directory -Force | Out-Null
            }

            Expand-Archive -LiteralPath $archivePath -DestinationPath $destinationPath -Force
            $rootDirectories = @(Get-ChildItem -LiteralPath $destinationPath -Directory)
            if (-not (Test-Path -LiteralPath (Join-Path $destinationPath 'bin\mysqld.exe') -PathType Leaf) -and $rootDirectories.Count -ne 1) {
                throw "MySQL ZIPのルートディレクトリを特定できない: $destinationPath"
            }

            if (-not (Test-Path -LiteralPath (Join-Path $destinationPath 'bin\mysqld.exe') -PathType Leaf)) {
                # バージョン付きルートの内容をMySQLディレクトリ直下へ移動する。
                Get-ChildItem -LiteralPath $rootDirectories[0].FullName | Copy-Item -Destination $destinationPath -Recurse -Force
                Remove-Item -LiteralPath $rootDirectories[0].FullName -Recurse -Force
            }
        }
    }

    # 展開したMySQLへMySQL設定ファイルを配置する。
    File MySqlConfiguration {
        DestinationPath = (Join-Path $EnvironmentRoot 'mysql\conf\my.ini')
        SourcePath = (Join-Path $AssetRoot 'mysql\my.ini')
        Ensure = 'Present'
        Type = 'File'
        DependsOn = '[Script]InstallMySqlDirectory'
    }

    # MySQLの永続化データ用ディレクトリを作成する。
    File MySqlDataDirectory {
        DestinationPath = (Join-Path $EnvironmentRoot 'mysql\data')
        Type = 'Directory'
        Ensure = 'Present'
        DependsOn = '[Script]InstallMySqlDirectory'
    }

    # MySQLのログ出力用ディレクトリを作成する。
    File MySqlLogDirectory {
        DestinationPath = (Join-Path $EnvironmentRoot 'mysql\logs')
        Type = 'Directory'
        Ensure = 'Present'
        DependsOn = '[Script]InstallMySqlDirectory'
    }

    # MySQLの一時ファイル用ディレクトリを作成する。
    File MySqlTempDirectory {
        DestinationPath = (Join-Path $EnvironmentRoot 'mysql\temp')
        Type = 'Directory'
        Ensure = 'Present'
        DependsOn = '[Script]InstallMySqlDirectory'
    }
}
