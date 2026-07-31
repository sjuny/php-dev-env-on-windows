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

    # DSC標準リソースを読み込む。
    Import-DscResource -ModuleName PSDesiredStateConfiguration

    # PHP資材の入力値を検証する。
    if ([string]::IsNullOrWhiteSpace($ArchiveName)) {
        throw 'PHPのZIPファイル名が指定されていない。'
    }

    # PHP本体を配置する。
    Script InstallPhpDirectory {
        # PHP本体の配置状態を取得する。
        GetScript = {
            return @{ Result = (Test-Path -LiteralPath (Join-Path $using:EnvironmentRoot 'php\php.exe') -PathType Leaf).ToString() }
        }
        # PHP本体が配置済みか検証する。
        TestScript = {
            return Test-Path -LiteralPath (Join-Path $using:EnvironmentRoot 'php\php.exe') -PathType Leaf
        }
        # PHP ZIPを展開し、配置先を整える。
        SetScript = {
            # PHP ZIP資材と配置先のパスを解決する。
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

    # PHP設定ファイルを配置する。
    Script PhpConfiguration {
        # 配置済みPHP設定ファイルを取得する。
        GetScript = {
            $destinationPath = Join-Path $using:EnvironmentRoot 'php\php.ini'
            if (-not (Test-Path -LiteralPath $destinationPath -PathType Leaf)) {
                return @{ Result = '' }
            }

            return @{ Result = Get-Content -LiteralPath $destinationPath -Raw }
        }
        # PHP設定テンプレートを配置先のパスへ展開し、配置済みの内容と比較する。
        TestScript = {
            # PHP設定テンプレートと配置先を解決する。
            $sourcePath = Join-Path $using:AssetRoot 'php\php.ini'
            $destinationPath = Join-Path $using:EnvironmentRoot 'php\php.ini'
            if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf) -or
                -not (Test-Path -LiteralPath $destinationPath -PathType Leaf)) {
                return $false
            }

            # 配置先の絶対パスを反映した期待値を生成する。
            $phpRoot = Join-Path $using:EnvironmentRoot 'php'
            $expectedContent = Get-Content -LiteralPath $sourcePath -Raw
            $expectedContent = $expectedContent.Replace(
                '__PHP_EXTENSION_DIR__',
                (Join-Path $phpRoot 'ext')
            )
            $expectedContent = $expectedContent.Replace(
                '__PHP_ERROR_LOG__',
                (Join-Path $phpRoot 'php_errors.log')
            )
            $actualContent = Get-Content -LiteralPath $destinationPath -Raw
            return $actualContent -ceq $expectedContent
        }
        # PHP設定テンプレートを展開し、配置先の絶対パスで保存する。
        SetScript = {
            # PHP設定テンプレートと配置先を解決する。
            $sourcePath = Join-Path $using:AssetRoot 'php\php.ini'
            $destinationPath = Join-Path $using:EnvironmentRoot 'php\php.ini'
            $phpRoot = Join-Path $using:EnvironmentRoot 'php'

            # PHP設定テンプレートを読み込む。
            $content = Get-Content -LiteralPath $sourcePath -Raw

            # 配置先の絶対パスをテンプレートへ反映する。
            $content = $content.Replace(
                '__PHP_EXTENSION_DIR__',
                (Join-Path $phpRoot 'ext')
            )
            $content = $content.Replace(
                '__PHP_ERROR_LOG__',
                (Join-Path $phpRoot 'php_errors.log')
            )

            # 生成したPHP設定ファイルをUTF-8で保存する。
            [System.IO.File]::WriteAllText(
                $destinationPath,
                $content,
                (New-Object System.Text.UTF8Encoding($false))
            )
        }
        DependsOn = '[Script]InstallPhpDirectory'
    }

    # Composerを配置する。
    File Composer {
        DestinationPath = (Join-Path $EnvironmentRoot 'php\composer.phar')
        SourcePath = (Join-Path $AssetRoot 'php\composer.phar')
        Ensure = 'Present'
        Type = 'File'
        Checksum = 'SHA-256'
        DependsOn = '[Script]InstallPhpDirectory'
    }
}
