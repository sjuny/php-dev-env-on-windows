<#
.SYNOPSIS
Node.js環境を構築するDSC Composite Resourceを定義する。
#>
Configuration NodeEnvironment {
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
        throw 'Node.jsのZIPファイル名が指定されていない。'
    }

    $nodeAssetRoot = Join-Path $AssetRoot 'nodejs'
    $nodeEnvironmentRoot = Join-Path $EnvironmentRoot 'nodejs'

    # Node.jsの必須ファイルを判定し、未配置の場合だけZIPを展開する。
    Script InstallNodeDirectory {
        # 現在のNode.js配置状態を取得する。
        GetScript = {
            return @{ Result = (Test-Path -LiteralPath (Join-Path $using:nodeEnvironmentRoot 'node.exe') -PathType Leaf).ToString() }
        }
        # Node.jsの必須ファイルが配置済みか検証する。
        TestScript = {
            $nodePath = Join-Path $using:nodeEnvironmentRoot 'node.exe'
            $npmPath = Join-Path $using:nodeEnvironmentRoot 'npm.cmd'
            return (
                (Test-Path -LiteralPath $nodePath -PathType Leaf) -and
                (Test-Path -LiteralPath $npmPath -PathType Leaf)
            )
        }
        # Node.js ZIPを展開し、配置先を正規化する。
        SetScript = {
            # Node.js資材と配置先のパスを解決する。
            $archivePath = Join-Path $using:nodeAssetRoot $using:ArchiveName
            $destinationPath = $using:nodeEnvironmentRoot
            # Node.jsの配置先ディレクトリを作成する。
            if (-not (Test-Path -LiteralPath $destinationPath -PathType Container)) {
                New-Item -Path $destinationPath -ItemType Directory -Force | Out-Null
            }

            # Node.js ZIPを展開する。
            Expand-Archive -LiteralPath $archivePath -DestinationPath $destinationPath -Force
            $nodePath = Join-Path $destinationPath 'node.exe'
            $npmPath = Join-Path $destinationPath 'npm.cmd'
            if (-not (Test-Path -LiteralPath $nodePath -PathType Leaf)) {
                # バージョン付きルートの内容をNode.jsディレクトリ直下へ移動する。
                $rootDirectories = @(Get-ChildItem -LiteralPath $destinationPath -Directory)
                if ($rootDirectories.Count -ne 1) {
                    throw "Node.js ZIPのルートディレクトリを特定できない: $destinationPath"
                }

                Get-ChildItem -LiteralPath $rootDirectories[0].FullName |
                    Copy-Item -Destination $destinationPath -Recurse -Force
                Remove-Item -LiteralPath $rootDirectories[0].FullName -Recurse -Force
            }

            if (-not (Test-Path -LiteralPath $nodePath -PathType Leaf)) {
                throw "Node.js ZIPにnode.exeが存在しない: $destinationPath"
            }

            if (-not (Test-Path -LiteralPath $npmPath -PathType Leaf)) {
                throw "Node.js ZIPにnpm.cmdが存在しない: $destinationPath"
            }
        }
    }
}
