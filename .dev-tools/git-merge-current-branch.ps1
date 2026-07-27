#Requires -Version 5.1

<#
.SYNOPSIS
現在の作業ブランチを指定したブランチへマージし、リモートへpushする。

.DESCRIPTION
未コミットの変更がないことを確認した後、現在の作業ブランチをマージ先へ
マージする。マージとpushが成功した場合、元のローカル作業ブランチを削除する。

.PARAMETER TargetBranch
マージ先のブランチ名。省略時はローカルブランチから選択する。

.PARAMETER Message
マージコミットのメッセージ。省略時は既定のメッセージを使用する。

.EXAMPLE
.\git-merge-current-branch.ps1

.EXAMPLE
.\git-merge-current-branch.ps1 -TargetBranch develop -Message 'リリース準備'
#>

[CmdletBinding()]
Param(
    [Parameter(Mandatory = $false)]
    [string]$TargetBranch,

    [Parameter(Mandatory = $false)]
    [string]$Message
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 正常終了を示す終了コード
$SUCCESS_EXIT_CODE = 0

# 異常終了を示す終了コード
$FAILURE_EXIT_CODE = 1

# ブランチ選択で表示する最初の番号
$FIRST_SELECTION_NUMBER = 1

# 外部コマンドで使用するリモート名
$RemoteName = 'origin'

<#
.SYNOPSIS
現在のディレクトリがgitリポジトリ内であることを確認する。
#>
function Test-GitRepository {
    # Gitリポジトリ内で実行していることを確認する。
    & git rev-parse --is-inside-work-tree 2>$null | Out-Null
    if ($LASTEXITCODE -ne $SUCCESS_EXIT_CODE) {
        throw '現在のディレクトリはgitリポジトリ内ではない。'
    }
}

<#
.SYNOPSIS
現在チェックアウトされているブランチ名を取得する。
#>
function Get-CurrentBranch {
    # 現在のブランチ名を取得する。
    $BranchName = (& git rev-parse --abbrev-ref HEAD 2>$null).Trim()

    # ブランチ名の取得結果とdetached HEADを確認する。
    if ($LASTEXITCODE -ne $SUCCESS_EXIT_CODE -or [string]::IsNullOrEmpty($BranchName)) {
        throw '現在のブランチ名の取得に失敗した。'
    }

    if ($BranchName -eq 'HEAD') {
        throw 'detached HEADでは実行できない。ブランチをcheckoutしてから再実行すること。'
    }

    return $BranchName
}

<#
.SYNOPSIS
マージ先のローカルブランチをユーザーに選択させる。

.PARAMETER CurrentBranch
現在の作業ブランチ名。
#>
function Select-TargetBranch {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CurrentBranch
    )

    # 現在の作業ブランチを除外したローカルブランチ一覧を取得する。
    $BranchNames = @(
        & git for-each-ref '--format=%(refname:short)' 'refs/heads/' 2>$null |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne $CurrentBranch }
    )
    if ($LASTEXITCODE -ne $SUCCESS_EXIT_CODE) {
        throw 'ローカルブランチ一覧の取得に失敗した。'
    }

    # 選択可能なブランチが存在することを確認する。
    if ($BranchNames.Count -eq $SUCCESS_EXIT_CODE) {
        throw '選択可能なローカルブランチが存在しない。'
    }

    # ローカルブランチを番号付きで表示する。
    for ($Index = $SUCCESS_EXIT_CODE; $Index -lt $BranchNames.Count; $Index++) {
        $DisplayNumber = $Index + $FIRST_SELECTION_NUMBER
        Write-Information ("{0}: {1}" -f $DisplayNumber, $BranchNames[$Index]) -InformationAction Continue
    }

    # ユーザーからマージ先の番号を取得する。
    $SelectionInput = Read-Host 'マージ先の番号を入力する'
    $SelectionNumber = $SUCCESS_EXIT_CODE
    if (-not [int]::TryParse($SelectionInput, [ref]$SelectionNumber)) {
        throw 'マージ先の番号には整数を指定すること。'
    }

    # 選択番号を配列インデックスへ変換し、選択範囲を確認する。
    $SelectionIndex = $SelectionNumber - $FIRST_SELECTION_NUMBER
    if ($SelectionIndex -lt $SUCCESS_EXIT_CODE -or $SelectionIndex -ge $BranchNames.Count) {
        throw 'マージ先の番号が選択肢の範囲外である。'
    }

    return $BranchNames[$SelectionIndex]
}

<#
.SYNOPSIS
ブランチ名がgitで使用できる形式であることを確認する。

.PARAMETER BranchName
確認対象のブランチ名。
#>
function Test-BranchName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BranchName
    )

    # ブランチ名が空でないことを確認する。
    if ([string]::IsNullOrWhiteSpace($BranchName)) {
        throw 'マージ先ブランチ名が空である。'
    }

    # Gitのブランチ名として使用できる形式であることを確認する。
    & git check-ref-format --branch $BranchName 2>$null | Out-Null
    if ($LASTEXITCODE -ne $SUCCESS_EXIT_CODE) {
        throw "マージ先ブランチ名 '$BranchName' はgitのブランチ名として使用できない。"
    }
}

<#
.SYNOPSIS
マージ前提条件を確認する。

.PARAMETER CurrentBranch
現在の作業ブランチ名。
#>
function Test-PreCondition {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CurrentBranch
    )

    # 現在のブランチとマージ先ブランチが異なることを確認する。
    if ($CurrentBranch -eq $TargetBranch) {
        throw "マージ先ブランチ '$TargetBranch' 上では実行できない。作業ブランチで実行すること。"
    }

    # 未コミットの変更がないことを確認する。
    $Status = & git status --porcelain 2>$null
    if ($LASTEXITCODE -ne $SUCCESS_EXIT_CODE) {
        throw 'git statusの取得に失敗した。'
    }

    if (-not [string]::IsNullOrWhiteSpace(($Status -join [Environment]::NewLine))) {
        throw '未コミットの変更がある。コミットまたはstashしてから再実行すること。'
    }
}

<#
.SYNOPSIS
マージ先ブランチをcheckoutし、リモートの最新状態を取得する。
#>
function Switch-ToTargetBranch {
    # マージ先ブランチのリモート上での存在を確認する。
    $RemoteRef = & git ls-remote --heads $RemoteName $TargetBranch 2>$null
    if ($LASTEXITCODE -ne $SUCCESS_EXIT_CODE) {
        throw "リモートのブランチ '$TargetBranch' の確認に失敗した。"
    }

    # リモートブランチが存在する場合は最新状態を取得する。
    $RemoteBranchExists = -not [string]::IsNullOrWhiteSpace(($RemoteRef -join [Environment]::NewLine))
    if ($RemoteBranchExists) {
        Write-Information "リモートの${TargetBranch}ブランチを取得中..." -InformationAction Continue

        $ErrorActionPreference = 'Continue'
        & git fetch $RemoteName $TargetBranch 2>$null
        $FetchCode = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        if ($FetchCode -ne $SUCCESS_EXIT_CODE) {
            throw 'git fetchに失敗した。'
        }
    }
    else {
        Write-Information "リモートに${TargetBranch}ブランチが存在しないため、ローカルブランチを使用する。" -InformationAction Continue
    }

    # マージ先のローカルブランチを作成またはcheckoutする。
    $LocalBranchExists = & git branch --list $TargetBranch
    if ([string]::IsNullOrWhiteSpace(($LocalBranchExists -join [Environment]::NewLine))) {
        Write-Information "ローカルに${TargetBranch}ブランチが存在しないため、新規作成する。" -InformationAction Continue
        & git checkout -b $TargetBranch
    }
    else {
        & git checkout $TargetBranch
    }

    if ($LASTEXITCODE -ne $SUCCESS_EXIT_CODE) {
        throw "${TargetBranch}ブランチへのcheckoutに失敗した。"
    }

    # リモートブランチが存在する場合はローカルブランチを同期する。
    if ($RemoteBranchExists) {
        $ErrorActionPreference = 'Continue'
        & git pull --ff-only $RemoteName $TargetBranch 2>$null
        $PullCode = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        if ($PullCode -ne $SUCCESS_EXIT_CODE) {
            throw 'git pullに失敗した。'
        }
    }
}

<#
.SYNOPSIS
作業ブランチをマージ先ブランチへマージする。

.PARAMETER SourceBranch
マージ元のブランチ名。

.PARAMETER ExtraMessage
マージコミットへ設定するメッセージ。
#>
function Invoke-MergeBranch {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceBranch,

        [Parameter(Mandatory = $false)]
        [string]$ExtraMessage
    )

    # マージコミットのメッセージを決定する。
    $MergeMessage = "Merged $SourceBranch into $TargetBranch."
    if (-not [string]::IsNullOrWhiteSpace($ExtraMessage)) {
        $MergeMessage = $ExtraMessage
    }

    # 作業ブランチをマージ先ブランチへマージする。
    & git merge --no-ff $SourceBranch -m $MergeMessage
    if ($LASTEXITCODE -ne $SUCCESS_EXIT_CODE) {
        Write-Warning 'マージ中にコンフリクトが発生した。マージを中止する。'
        & git merge --abort 2>$null
        & git checkout $SourceBranch 2>$null
        throw 'マージに失敗した。コンフリクトを解決してから再実行すること。'
    }
}

<#
.SYNOPSIS
マージ先ブランチをリモートへpushする。
#>
function Push-ToRemote {
    # マージ先ブランチをリモートへpushする。
    $ErrorActionPreference = 'Continue'
    & git push $RemoteName $TargetBranch 2>$null
    $PushCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($PushCode -ne $SUCCESS_EXIT_CODE) {
        throw 'git pushに失敗した。'
    }
}

<#
.SYNOPSIS
マージ済みの作業ブランチをローカルから削除する。

.PARAMETER BranchName
削除対象のブランチ名。
#>
function Remove-SourceBranch {
    [CmdletBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = 'Medium'
    )]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BranchName
    )

    # マージ済みの作業ブランチをローカルから削除する。
    if ($PSCmdlet.ShouldProcess($BranchName, 'ローカルブランチを削除する')) {
        & git branch -d $BranchName
        if ($LASTEXITCODE -ne $SUCCESS_EXIT_CODE) {
            throw "作業ブランチ '$BranchName' の削除に失敗した。"
        }
    }
}

<#
.SYNOPSIS
マージ処理全体を実行する。
#>
function Invoke-Main {
    param(
        [Parameter(Mandatory = $false)]
        [string]$TargetBranch,

        [Parameter(Mandatory = $false)]
        [string]$Message
    )

    try {
        # 日本語パスの問題を回避するためWindows標準OpenSSHを使用する。
        $WinSsh = 'C:/Windows/System32/OpenSSH/ssh.exe'
        if (Test-Path -LiteralPath $WinSsh) {
            $env:GIT_SSH_COMMAND = $WinSsh
        }

        # Gitリポジトリと現在の作業ブランチを確認する。
        Test-GitRepository
        $SourceBranch = Get-CurrentBranch

        # マージ先ブランチを決定する。
        if ([string]::IsNullOrWhiteSpace($TargetBranch)) {
            $TargetBranch = Select-TargetBranch -CurrentBranch $SourceBranch
        }

        # マージ前提条件を確認する。
        Test-BranchName -BranchName $TargetBranch
        Test-PreCondition -CurrentBranch $SourceBranch

        Write-Information "作業ブランチ: $SourceBranch" -InformationAction Continue
        Write-Information "マージ先: $TargetBranch" -InformationAction Continue

        # マージ先をcheckoutして作業ブランチをマージする。
        Switch-ToTargetBranch
        Invoke-MergeBranch -SourceBranch $SourceBranch -ExtraMessage $Message

        # マージ先をリモートへpushし、作業ブランチを削除する。
        Push-ToRemote
        Remove-SourceBranch -BranchName $SourceBranch

        Write-Information "完了: '$SourceBranch' を '$TargetBranch' にマージした。" -InformationAction Continue
        exit $SUCCESS_EXIT_CODE
    }
    catch {
        Write-Error "エラー: $($_.Exception.Message)"
        exit $FAILURE_EXIT_CODE
    }
}

Invoke-Main -TargetBranch $TargetBranch -Message $Message
