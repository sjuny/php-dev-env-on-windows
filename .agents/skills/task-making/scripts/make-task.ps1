#Requires -Version 5.1

<#
.SYNOPSIS
ブランチとタスクディレクトリ、指示書雛形を一括生成します。

.DESCRIPTION
引数で受け取ったタスクIDと対話入力された指示の種類をもとに、
gitブランチ、タスクディレクトリ、指示書雛形を作成します。

.PARAMETER TaskId
タスクID。正規化前の文字列を指定します。

.EXAMPLE
.\make-task.ps1 -TaskId add-login
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TaskId,

    [Parameter(Mandatory = $false)]
    [ValidateSet('feature', 'fix', 'change', 'research', 'other')]
    [string]$InstructionType
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 有効な指示の種類の一覧
$VALID_TYPES = @('feature', 'fix', 'change', 'research', 'other')
# 指示の種類を表示するメニュー項目
$TYPE_MENU = @(
    '1.新規機能追加：feature'
    '2.不具合修正：fix'
    '3.仕様変更：change'
    '4.調査：research'
    '5.その他：other'
)
# タスクディレクトリの親ディレクトリ名
$TASK_FOLDER_NAME = '.tasks'
# タスク指示書のファイル名
$TASK_INSTRUCTION_FILE_NAME = 'instr-01.md'
# Gitリポジトリのルート取得に使用する引数
$GIT_ROOT_ARGUMENTS = @('rev-parse', '--show-toplevel')
# タスクIDの正規化に使用する正規表現
$TASK_ID_PATTERN = '[^a-z0-9-]+'
# 指示種類選択の表示文
$TYPE_SELECTION_MESSAGE = '指示の種類を選択してください。'
# 指示種類選択の入力文
$TYPE_SELECTION_PROMPT = '番号'
# 指示種類選択のエラーメッセージ
$TYPE_SELECTION_ERROR = '指示の種類は1～5の番号で指定してください。'
# ハイフン文字
$HYPHEN = '-'
# 情報メッセージを継続表示する指定値
$CONTINUE_ACTION = 'Continue'
# 正規化後の空タスクIDのエラーメッセージ
$EMPTY_TASK_ID_ERROR = 'IDが空になりました。英数字で指定してください。'
# ブランチ作成のGit操作名
$CREATE_BRANCH_ACTION = 'git checkout -b'
# タスクディレクトリ作成の操作名
$CREATE_FOLDER_ACTION = 'New-Item Directory'
# タスク指示書作成の操作名
$CREATE_FILE_ACTION = 'New-Item File'
# タスクディレクトリの時刻書式
$TASK_TIMESTAMP_FORMAT = 'yyyyMMdd-HHmm'
# 作成結果の表示書式
$SUCCESS_MESSAGE_FORMAT = 'タスク用のブランチとディレクトリが作成されました。/ branch={0} , directory={1}'
# 処理エラーの表示書式
$PROCESS_ERROR_FORMAT = '処理でエラーが発生しました: {0}'
# ブランチ名の構成書式
$BRANCH_NAME_FORMAT = '{0}/{1}'
# 指示種類の区切り文字
$TYPE_SEPARATOR = '/'
# 指示種類の不正値エラー書式
$INVALID_TYPE_ERROR_FORMAT = '指示の種類は {0} のいずれかで指定してください。'
# ブランチ作成失敗のエラー書式
$BRANCH_ERROR_FORMAT = 'ブランチの作成に失敗しました: {0}'
# タスクディレクトリ名の構成書式
$TASK_FOLDER_NAME_FORMAT = '{0}_{1}'
# 既存タスクディレクトリのエラー書式
$EXISTING_FOLDER_ERROR_FORMAT = 'タスクディレクトリが既に存在します: {0}'
# 処理成功時の終了コード
$SUCCESS_EXIT_CODE = 0
# 処理失敗時の終了コード
$FAILURE_EXIT_CODE = 1

<#
.SYNOPSIS
スクリプトが属するgitリポジトリのルートパスを取得します。

.OUTPUTS
System.String
#>
function Get-RepoRoot {
    [CmdletBinding()]
    param()

    # スクリプトのあるディレクトリを起点にリポジトリルートを解決する
    $RepoRoot = git -C $PSScriptRoot @GIT_ROOT_ARGUMENTS 2>$null
    if ($null -ne $RepoRoot) {
        $RepoRoot = $RepoRoot.Trim()
    }
    if ([string]::IsNullOrEmpty($RepoRoot)) {
        throw 'gitリポジトリが見つかりません。'
    }

    return $RepoRoot
}

<#
.SYNOPSIS
指示内容IDをブランチ名・ディレクトリ名で使用できる形式に正規化します。

.PARAMETER RawId
正規化前の指示内容ID。
#>
function Format-InstructionId {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RawId
    )

    # 小文字化し、英数字・ハイフン以外の文字をハイフンに置換する
    $Normalized = $RawId.ToLower()
    $Normalized = [regex]::Replace($Normalized, $TASK_ID_PATTERN, $HYPHEN)

    # 先頭・末尾のハイフンを除去する
    $Normalized = $Normalized.Trim($HYPHEN)

    # 正規化後に空になった場合はエラー
    if ([string]::IsNullOrEmpty($Normalized)) {
        throw $EMPTY_TASK_ID_ERROR
    }

    return $Normalized
}

<#
.SYNOPSIS
指示の種類を対話形式で選択します。

.DESCRIPTION
仕様で定義された5種類の指示の選択肢を表示し、選択値を指示の種類へ変換します。

.OUTPUTS
System.String
#>
function Read-InstructionType {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # 仕様で定義された選択肢を表示する
    Write-Information $TYPE_SELECTION_MESSAGE -InformationAction $CONTINUE_ACTION
    foreach ($MenuItem in $TYPE_MENU) {
        Write-Information $MenuItem -InformationAction $CONTINUE_ACTION
    }

    $Selection = Read-Host $TYPE_SELECTION_PROMPT
    $SelectionIndex = 0
    if (-not [int]::TryParse($Selection, [ref]$SelectionIndex)) {
        throw $TYPE_SELECTION_ERROR
    }

    $SelectionIndex = $SelectionIndex - 1
    if ($SelectionIndex -lt 0 -or $SelectionIndex -ge $VALID_TYPES.Count) {
        throw $TYPE_SELECTION_ERROR
    }

    return $VALID_TYPES[$SelectionIndex]
}

<#
.SYNOPSIS
入力パラメーターの基本バリデーションを行います。

.DESCRIPTION
指示の種類が定義済みの値であることを検証します。

.PARAMETER TypeValue
指示の種類。

.OUTPUTS
なし
#>
function Test-InputParameter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TypeValue
    )

    if ($TypeValue -notin $VALID_TYPES) {
        throw ($INVALID_TYPE_ERROR_FORMAT -f ($VALID_TYPES -join $TYPE_SEPARATOR))
    }
}

<#
.SYNOPSIS
指示の種類とIDをもとにgitブランチを作成します。

.PARAMETER TypeValue
指示の種類。

.PARAMETER NormalizedId
正規化済みの指示内容ID。

.DESCRIPTION
指定された指示の種類とIDでGitブランチを作成し、ブランチ名を返します。
#>
function New-InstructionBranch {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TypeValue,

        [Parameter(Mandatory = $true)]
        [string]$NormalizedId
    )

    # 「種類/ID」形式でブランチ名を組み立てる
    $BranchName = $BRANCH_NAME_FORMAT -f $TypeValue, $NormalizedId

    # ブランチを作成してチェックアウトする
    if ($PSCmdlet.ShouldProcess($BranchName, $CREATE_BRANCH_ACTION)) {
        git checkout -b $BranchName
        if ($LASTEXITCODE -ne 0) {
            throw ($BRANCH_ERROR_FORMAT -f $BranchName)
        }
    }

    return $BranchName
}

<#
.SYNOPSIS
リポジトリルート直下の.tasksディレクトリ内にタイムスタンプ付きのタスクディレクトリを作成します。

.PARAMETER RepoRootPath
gitリポジトリのルートパス。

.PARAMETER NormalizedId
正規化済みの指示内容ID。

.DESCRIPTION
指定されたIDでタスクディレクトリを作成し、ディレクトリ名とパスを返します。
#>
function New-TaskFolder {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRootPath,

        [Parameter(Mandatory = $true)]
        [string]$NormalizedId
    )

    # タイムスタンプ付きのディレクトリ名を生成する（形式: yyyymmdd-hhmm_id）
    $Timestamp = Get-Date -Format $TASK_TIMESTAMP_FORMAT
    $FolderName = $TASK_FOLDER_NAME_FORMAT -f $Timestamp, $NormalizedId

    # .tasksディレクトリ配下にタスクディレクトリのフルパスを組み立てる
    $TaskRoot = Join-Path $RepoRootPath $TASK_FOLDER_NAME
    $TaskFolderPath = Join-Path $TaskRoot $FolderName

    # 同一分に作成済みのタスクを上書きしない
    if (Test-Path -LiteralPath $TaskFolderPath) {
        throw ($EXISTING_FOLDER_ERROR_FORMAT -f $TaskFolderPath)
    }

    # タスクディレクトリを作成する
    if ($PSCmdlet.ShouldProcess($TaskFolderPath, $CREATE_FOLDER_ACTION)) {
        New-Item -ItemType Directory -Path $TaskFolderPath -ErrorAction Stop | Out-Null
    }

    return [pscustomobject]@{
        Name = $FolderName
        Path = $TaskFolderPath
    }
}

<#
.SYNOPSIS
タスクディレクトリ内に指示書雛形ファイルを作成します。

.PARAMETER TaskFolderPath
作成先のタスクディレクトリパス。

.OUTPUTS
System.String
#>
function New-TaskInstructionFile {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskFolderPath
    )

    # タスク指示書のフルパスを組み立てる
    $InstructionFilePath = Join-Path $TaskFolderPath $TASK_INSTRUCTION_FILE_NAME

    # 指示書雛形を空ファイルとして作成する
    if ($PSCmdlet.ShouldProcess($InstructionFilePath, $CREATE_FILE_ACTION)) {
        New-Item -ItemType File -Path $InstructionFilePath -ErrorAction Stop | Out-Null
    }

    return $InstructionFilePath
}

<#
.SYNOPSIS
スクリプトのエントリーポイント。ブランチ、タスクディレクトリ、指示書雛形を作成します。

.PARAMETER TaskId
正規化前のタスクID。
#>
function Invoke-Main {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskId,

        [Parameter(Mandatory = $false)]
        [string]$InstructionType
    )

    try {
        # リポジトリルートの取得と指示種類の選択
        $RepoRoot = Get-RepoRoot

        if ([string]::IsNullOrEmpty($InstructionType)) {
            $TypeValue = Read-InstructionType
        } else {
            $TypeValue = $InstructionType
        }

        Test-InputParameter -TypeValue $TypeValue

        # IDを正規化してブランチ、タスクディレクトリ、指示書雛形を作成する
        $NormalizedId = Format-InstructionId -RawId $TaskId
        $BranchName = New-InstructionBranch -TypeValue $TypeValue -NormalizedId $NormalizedId
        $TaskFolder = New-TaskFolder -RepoRootPath $RepoRoot -NormalizedId $NormalizedId
        $null = New-TaskInstructionFile -TaskFolderPath $TaskFolder.Path

        # 仕様で指定された作成結果を出力する
        Write-Information (
            $SUCCESS_MESSAGE_FORMAT -f
            $BranchName,
            $TaskFolder.Name
        ) -InformationAction $CONTINUE_ACTION
        return $SUCCESS_EXIT_CODE
    }
    catch {
        Write-Error ($PROCESS_ERROR_FORMAT -f $_.Exception.Message)
        return $FAILURE_EXIT_CODE
    }
}

exit (Invoke-Main -TaskId $TaskId -InstructionType $InstructionType)
