<#
.SYNOPSIS
MySQL環境を構築するDSC Composite Resourceを定義する。
#>
Configuration MySqlEnvironment {
    param(
        [Parameter(Mandatory = $true)]
        [string]$EnvironmentRoot,

        [Parameter(Mandatory = $true)]
        [string]$AssetRoot,

        [Parameter(Mandatory = $true)]
        [string]$ArchiveName,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 65535)]
        [int]$MySqlPort
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration

    if ([string]::IsNullOrWhiteSpace($ArchiveName)) {
        throw 'MySQLのZIPファイル名が指定されていない。'
    }

    # MySQLの必須ファイルを判定し、未配置の場合だけZIPを展開する。
    Script InstallMySqlDirectory {
        # 現在のMySQL配置状態を取得する。
        GetScript = {
            return @{ Result = (Test-Path -LiteralPath (Join-Path $using:EnvironmentRoot 'mysql\bin\mysqld.exe') -PathType Leaf).ToString() }
        }
        # MySQLの必須ファイルが配置済みか検証する。
        TestScript = {
            return Test-Path -LiteralPath (Join-Path $using:EnvironmentRoot 'mysql\bin\mysqld.exe') -PathType Leaf
        }
        # MySQL ZIPを展開し、配置先を正規化する。
        SetScript = {
            # MySQL資材と配置先のパスを解決する。
            $archivePath = Join-Path (Join-Path $using:AssetRoot 'mysql') $using:ArchiveName
            $destinationPath = Join-Path $using:EnvironmentRoot 'mysql'
            # MySQLの配置先ディレクトリを作成する。
            if (-not (Test-Path -LiteralPath $destinationPath -PathType Container)) {
                New-Item -Path $destinationPath -ItemType Directory -Force | Out-Null
            }

            # MySQL ZIPを展開する。
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

    # MySQL設定ファイルの配置先ディレクトリを作成する。
    File MySqlConfigurationDirectory {
        DestinationPath = (Join-Path $EnvironmentRoot 'mysql\conf')
        Type = 'Directory'
        Ensure = 'Present'
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

    # MySQL設定ファイルへ配置先の実パスとポートを反映する。
    Script MySqlConfiguration {
        # 現在のMySQL設定状態を取得する。
        GetScript = {
            $destinationPath = Join-Path $using:EnvironmentRoot 'mysql\conf\my.ini'
            return @{ Result = (Test-Path -LiteralPath $destinationPath -PathType Leaf).ToString() }
        }
        # 置換後のMySQL設定が配置済みか検証する。
        TestScript = {
            # MySQL設定テンプレートと配置先を解決する。
            $templatePath = Join-Path $using:AssetRoot 'mysql\my.ini'
            $destinationPath = Join-Path $using:EnvironmentRoot 'mysql\conf\my.ini'
            if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
                throw "MySQL設定テンプレートが見つからない: $templatePath"
            }

            # 配置先がない場合は設定が必要である。
            if (-not (Test-Path -LiteralPath $destinationPath -PathType Leaf)) {
                return $false
            }

            # 設定値を置換後の値へ変換する。
            $mySqlRoot = Join-Path $using:EnvironmentRoot 'mysql'
            $mySqlPort = $using:MySqlPort
            $replacementMap = [ordered]@{
                '__MYSQL_ROOT_PATH__' = $mySqlRoot -replace '\\', '/'
                '__MYSQL_DATA_PATH__' = (Join-Path $mySqlRoot 'data') -replace '\\', '/'
                '__MYSQL_TEMP_PATH__' = (Join-Path $mySqlRoot 'temp') -replace '\\', '/'
                '__MYSQL_LOG_PATH__'  = (Join-Path $mySqlRoot 'logs\mysql-error.log') -replace '\\', '/'
                '__MYSQL_PORT__'      = $mySqlPort.ToString()
            }
            # テンプレートのplaceholderと配置先の設定値を確認する。
            $template = Get-Content -LiteralPath $templatePath -Raw
            $configuration = Get-Content -LiteralPath $destinationPath -Raw
            foreach ($placeholder in $replacementMap.Keys) {
                if (-not $template.Contains($placeholder)) {
                    throw "MySQL設定テンプレートに置換文字列がない: $placeholder"
                }

                if ($configuration.Contains($placeholder)) {
                    return $false
                }

                if (-not $configuration.Contains($replacementMap[$placeholder])) {
                    return $false
                }
            }

            return $true
        }
        # placeholderを置換したMySQL設定を配置する。
        SetScript = {
            # MySQL設定テンプレートと配置先を解決する。
            $templatePath = Join-Path $using:AssetRoot 'mysql\my.ini'
            $destinationPath = Join-Path $using:EnvironmentRoot 'mysql\conf\my.ini'
            $mySqlRoot = Join-Path $using:EnvironmentRoot 'mysql'
            $mySqlPort = $using:MySqlPort
            $replacementMap = [ordered]@{
                '__MYSQL_ROOT_PATH__' = $mySqlRoot -replace '\\', '/'
                '__MYSQL_DATA_PATH__' = (Join-Path $mySqlRoot 'data') -replace '\\', '/'
                '__MYSQL_TEMP_PATH__' = (Join-Path $mySqlRoot 'temp') -replace '\\', '/'
                '__MYSQL_LOG_PATH__'  = (Join-Path $mySqlRoot 'logs\mysql-error.log') -replace '\\', '/'
                '__MYSQL_PORT__'      = $mySqlPort.ToString()
            }
            # テンプレートを読み込み、placeholderの存在を確認する。
            $configuration = Get-Content -LiteralPath $templatePath -Raw
            foreach ($placeholder in $replacementMap.Keys) {
                if (-not $configuration.Contains($placeholder)) {
                    throw "MySQL設定テンプレートに置換文字列がない: $placeholder"
                }

                # placeholderを実際の設定値へ置換する。
                $configuration = $configuration.Replace($placeholder, $replacementMap[$placeholder])
            }

            # 置換後のMySQL設定を配置する。
            [System.IO.File]::WriteAllText(
                $destinationPath,
                $configuration,
                [System.Text.UTF8Encoding]::new($false)
            )
        }
        DependsOn = @(
            '[File]MySqlConfigurationDirectory'
            '[File]MySqlDataDirectory'
            '[File]MySqlLogDirectory'
            '[File]MySqlTempDirectory'
        )
    }
}
