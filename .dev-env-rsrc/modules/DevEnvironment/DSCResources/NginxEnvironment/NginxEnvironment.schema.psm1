<#
.SYNOPSIS
nginx環境を構築するDSC Composite Resourceを定義する。
#>
Configuration NginxEnvironment {
    param(
        [Parameter(Mandatory = $true)]
        [string]$EnvironmentRoot,

        [Parameter(Mandatory = $true)]
        [string]$AssetRoot,

        [Parameter(Mandatory = $true)]
        [string]$ArchiveName,

        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 65535)]
        [int]$PhpCgiPort,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 65535)]
        [int]$PhpMyAdminPort
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration

    if ([string]::IsNullOrWhiteSpace($ArchiveName)) {
        throw 'nginxのZIPファイル名が指定されていない。'
    }

    # nginxの必須ファイルを判定し、未配置の場合だけZIPを展開する。
    Script InstallNginxDirectory {
        # 現在のnginx配置状態を取得する。
        GetScript = {
            return @{ Result = (Test-Path -LiteralPath (Join-Path $using:EnvironmentRoot 'nginx\nginx.exe') -PathType Leaf).ToString() }
        }
        # nginxの必須ファイルが配置済みか検証する。
        TestScript = {
            return Test-Path -LiteralPath (Join-Path $using:EnvironmentRoot 'nginx\nginx.exe') -PathType Leaf
        }
        # nginx ZIPを展開し、配置先を正規化する。
        SetScript = {
            # nginx資材と配置先のパスを解決する。
            $archivePath = Join-Path (Join-Path $using:AssetRoot 'nginx') $using:ArchiveName
            $destinationPath = Join-Path $using:EnvironmentRoot 'nginx'
            # nginxの配置先ディレクトリを作成する。
            if (-not (Test-Path -LiteralPath $destinationPath -PathType Container)) {
                New-Item -Path $destinationPath -ItemType Directory -Force | Out-Null
            }

            # nginx ZIPを展開する。
            Expand-Archive -LiteralPath $archivePath -DestinationPath $destinationPath -Force
            $rootDirectories = @(Get-ChildItem -LiteralPath $destinationPath -Directory)
            if (-not (Test-Path -LiteralPath (Join-Path $destinationPath 'nginx.exe') -PathType Leaf) -and $rootDirectories.Count -ne 1) {
                throw "nginx ZIPのルートディレクトリを特定できない: $destinationPath"
            }

            if (-not (Test-Path -LiteralPath (Join-Path $destinationPath 'nginx.exe') -PathType Leaf)) {
                # バージョン付きルートの内容をnginxディレクトリ直下へ移動する。
                Get-ChildItem -LiteralPath $rootDirectories[0].FullName | Copy-Item -Destination $destinationPath -Recurse -Force
                Remove-Item -LiteralPath $rootDirectories[0].FullName -Recurse -Force
            }
        }
    }

    # 展開したnginxへ基本設定ファイルを配置する。
    File NginxConfiguration {
        DestinationPath = (Join-Path $EnvironmentRoot 'nginx\conf\nginx.conf')
        SourcePath = (Join-Path $AssetRoot 'nginx\nginx.conf')
        Ensure = 'Present'
        Type = 'File'
        Checksum = 'SHA-256'
        DependsOn = '[Script]InstallNginxDirectory'
    }

    # Webアプリケーション設定の配置先ディレクトリを作成する。
    File NginxSitesDirectory {
        DestinationPath = (Join-Path $EnvironmentRoot 'nginx\conf\sites')
        Ensure = 'Present'
        Type = 'Directory'
        DependsOn = '[Script]InstallNginxDirectory'
    }

    # 展開したnginxへWebアプリケーション用サイト設定ファイルを配置する。
    Script WebAppConfiguration {
        # 現在のWebアプリケーション設定状態を取得する。
        GetScript = {
            $destinationPath = Join-Path $using:EnvironmentRoot 'nginx\conf\sites\web-app.conf'
            return @{ Result = (Test-Path -LiteralPath $destinationPath -PathType Leaf).ToString() }
        }
        # 置換後のWebアプリケーション設定が配置済みか検証する。
        TestScript = {
            # nginx設定テンプレートと配置先を解決する。
            $templatePath = Join-Path $using:AssetRoot 'nginx\web-app.conf'
            $destinationPath = Join-Path $using:EnvironmentRoot 'nginx\conf\sites\web-app.conf'
            if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
                throw "nginx設定テンプレートが見つからない: $templatePath"
            }

            # 配置先がない場合は設定が必要である。
            if (-not (Test-Path -LiteralPath $destinationPath -PathType Leaf)) {
                return $false
            }

            # 設定値を置換後の値へ変換する。
            $publicPath = (Join-Path $using:ProjectRoot 'application\public') -replace '\\', '/'
            $phpMyAdminPath = (Join-Path $using:EnvironmentRoot 'phpmyadmin') -replace '\\', '/'
            $phpMyAdminPort = $using:PhpMyAdminPort
            $phpCgiPort = $using:PhpCgiPort
            $template = Get-Content -LiteralPath $templatePath -Raw
            $configuration = Get-Content -LiteralPath $destinationPath -Raw
            # テンプレートに必要なplaceholderが定義されていることを確認する。
            foreach ($placeholder in @('__PROJECT_PUBLIC_PATH__', '__PHPMYADMIN_ROOT_PATH__', '__PHPMYADMIN_PORT__', '__PHP_CGI_PORT__')) {
                if (-not $template.Contains($placeholder)) {
                    throw "nginx設定テンプレートに置換文字列がない: $placeholder"
                }
            }

            # 配置先にplaceholderがなく、置換後の値が存在することを確認する。
            $replacementMap = [ordered]@{
                '__PROJECT_PUBLIC_PATH__' = $publicPath
                '__PHPMYADMIN_ROOT_PATH__' = $phpMyAdminPath
                '__PHPMYADMIN_PORT__' = $phpMyAdminPort.ToString()
                '__PHP_CGI_PORT__' = $phpCgiPort.ToString()
            }
            foreach ($placeholder in $replacementMap.Keys) {
                if ($configuration.Contains($placeholder)) {
                    return $false
                }

                if (-not $configuration.Contains($replacementMap[$placeholder])) {
                    return $false
                }
            }

            return $true
        }
        # placeholderを置換したWebアプリケーション設定を配置する。
        SetScript = {
            # nginx設定テンプレートと配置先を解決する。
            $templatePath = Join-Path $using:AssetRoot 'nginx\web-app.conf'
            $destinationPath = Join-Path $using:EnvironmentRoot 'nginx\conf\sites\web-app.conf'
            # 設定値を解決する。
            $publicPath = (Join-Path $using:ProjectRoot 'application\public') -replace '\\', '/'
            $phpMyAdminPath = (Join-Path $using:EnvironmentRoot 'phpmyadmin') -replace '\\', '/'
            $phpMyAdminPort = $using:PhpMyAdminPort
            $phpCgiPort = $using:PhpCgiPort
            # テンプレートを読み込み、placeholderの存在を確認する。
            $configuration = Get-Content -LiteralPath $templatePath -Raw
            foreach ($placeholder in @('__PROJECT_PUBLIC_PATH__', '__PHPMYADMIN_ROOT_PATH__', '__PHPMYADMIN_PORT__', '__PHP_CGI_PORT__')) {
                if (-not $configuration.Contains($placeholder)) {
                    throw "nginx設定テンプレートに置換文字列がない: $placeholder"
                }
            }

            # placeholderを実際の設定値へ置換する。
            $configuration = $configuration.Replace('__PROJECT_PUBLIC_PATH__', $publicPath)
            $configuration = $configuration.Replace('__PHPMYADMIN_ROOT_PATH__', $phpMyAdminPath)
            $configuration = $configuration.Replace('__PHPMYADMIN_PORT__', $phpMyAdminPort.ToString())
            $configuration = $configuration.Replace('__PHP_CGI_PORT__', $phpCgiPort.ToString())
            # 置換後のnginx設定を配置する。
            [System.IO.File]::WriteAllText(
                $destinationPath,
                $configuration,
                [System.Text.UTF8Encoding]::new($false)
            )
        }
        DependsOn = '[File]NginxSitesDirectory'
    }
}
