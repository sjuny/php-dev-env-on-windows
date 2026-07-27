Configuration NginxEnvironment {
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
        throw 'nginxのZIPファイル名が指定されていない。'
    }

    # nginxの必須ファイルを判定し、未配置の場合だけZIPを展開する。
    Script InstallNginxDirectory {
        GetScript = {
            return @{ Result = (Test-Path -LiteralPath (Join-Path $using:EnvironmentRoot 'nginx\nginx.exe') -PathType Leaf).ToString() }
        }
        TestScript = {
            return Test-Path -LiteralPath (Join-Path $using:EnvironmentRoot 'nginx\nginx.exe') -PathType Leaf
        }
        SetScript = {
            $archivePath = Join-Path (Join-Path $using:AssetRoot 'nginx') $using:ArchiveName
            $destinationPath = Join-Path $using:EnvironmentRoot 'nginx'
            if (-not (Test-Path -LiteralPath $destinationPath -PathType Container)) {
                New-Item -Path $destinationPath -ItemType Directory -Force | Out-Null
            }

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

    # 展開したnginxへWebアプリケーション用サイト設定ファイルを配置する。
    File WebAppConfiguration {
        DestinationPath = (Join-Path $EnvironmentRoot 'nginx\conf\sites\web-app.conf')
        SourcePath = (Join-Path $AssetRoot 'nginx\web-app.conf')
        Ensure = 'Present'
        Type = 'File'
        Checksum = 'SHA-256'
        DependsOn = '[Script]InstallNginxDirectory'
    }
}
