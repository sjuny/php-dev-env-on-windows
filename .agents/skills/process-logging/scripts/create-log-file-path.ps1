#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
作業記録ファイルの出力先パスを作成する。
.DESCRIPTION
現在のGitブランチとタスクディレクトリから、process-log_yyyymmdd-hhmm.md のパスを標準出力へ出力する。
#>

$EXIT_CODE_SUCCESS = 0
$EXIT_CODE_ERROR = 1
$TASKS_ROOT_FOLDER_NAME = '.tasks'
$NO_TASK_FOLDER_OUTPUT = 'no-task-folder'
$GIT_BRANCH_SEPARATOR = '/'
$DIRECTORY_NAME_PATTERN_FORMAT = '*{0}*'
$TIMESTAMP_FORMAT = 'yyyyMMdd-HHmm'
$LOG_FILE_NAME_FORMAT = 'process-log_{0}.md'
$ERROR_MESSAGE_NOT_GIT_WORKSPACE = 'gitのワークスペース内で実行してください。'
$ERROR_MESSAGE_TASKS_ROOT_NOT_FOUND = '.tasksディレクトリが存在しません。'
$ERROR_MESSAGE_BRANCH_NAME_NOT_FOUND = '現在のgitブランチ名を取得できません。'
$ERROR_MESSAGE_TASK_DIRECTORY_NOT_FOUND = '対象のタスクディレクトリが見つかりません（ブランチ末尾: {0}）。'
$ERROR_MESSAGE_UNEXPECTED = '処理中に予期しないエラーが発生しました: {0}'

<#
.SYNOPSIS
Gitワークスペースのルートパスを取得する。

.OUTPUTS
string
取得できない場合は$nullを返す。
#>
function Get-WorkspaceRoot {
    param ()

    # Gitコマンドからワークスペースのルートパスを取得する。
    $workspaceRoot = & git rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne $EXIT_CODE_SUCCESS -or [string]::IsNullOrWhiteSpace($workspaceRoot)) {
        return $null
    }

    return $workspaceRoot.Trim()
}

<#
.SYNOPSIS
.tasksディレクトリのルートパスを取得する。

.PARAMETER WorkspaceRoot
Gitワークスペースのルートパス。

.OUTPUTS
string
.tasksディレクトリが存在しない場合は$nullを返す。
#>
function Get-TasksRoot {
    param (
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceRoot
    )

    # ワークスペース配下の.tasksディレクトリを探索する。
    $tasksRootPath = Join-Path -Path $WorkspaceRoot -ChildPath $TASKS_ROOT_FOLDER_NAME
    if (-not (Test-Path -LiteralPath $tasksRootPath -PathType Container)) {
        return $null
    }

    return $tasksRootPath
}

<#
.SYNOPSIS
現在のGitブランチ名の末尾要素を取得する。

.DESCRIPTION
ブランチ名が fix/input-error の場合は input-error を返す。

.OUTPUTS
string
取得できない場合は$nullを返す。
#>
function Get-BranchSuffix {
    param ()

    # Gitコマンドから現在ブランチ名を取得する。
    $branchName = & git rev-parse --abbrev-ref HEAD 2>$null
    if ($LASTEXITCODE -ne $EXIT_CODE_SUCCESS -or [string]::IsNullOrWhiteSpace($branchName)) {
        return $null
    }

    # ブランチ名の末尾要素を探索キーとして返す。
    $trimmedBranchName = $branchName.Trim()
    $branchNameSegments = $trimmedBranchName -split $GIT_BRANCH_SEPARATOR
    return $branchNameSegments[$branchNameSegments.Length - 1]
}

<#
.SYNOPSIS
ブランチ末尾を含むタスクディレクトリを1件取得する。

.PARAMETER TasksRoot
.tasksディレクトリのルートパス。

.PARAMETER BranchSuffix
探索対象のブランチ末尾文字列。

.OUTPUTS
System.IO.DirectoryInfo
一致するディレクトリがない場合は$nullを返す。
#>
function Find-TaskDirectory {
    param (
        [Parameter(Mandatory = $true)]
        [string]$TasksRoot,

        [Parameter(Mandatory = $true)]
        [string]$BranchSuffix
    )

    # .tasks直下のサブディレクトリからブランチ末尾を含むディレクトリを抽出する。
    $directoryNamePattern = $DIRECTORY_NAME_PATTERN_FORMAT -f $BranchSuffix
    $taskDirectories = Get-ChildItem -LiteralPath $TasksRoot -Directory
    $matchedTaskDirectory = $taskDirectories |
        Where-Object { $_.Name -like $directoryNamePattern } |
        Select-Object -First 1

    return $matchedTaskDirectory
}

<#
.SYNOPSIS
ログファイルパスを作成する。

.PARAMETER TaskDirectoryPath
ログファイルを配置するタスクディレクトリパス。

.OUTPUTS
string
生成したログファイルパス。
#>
function Get-LogFilePath {
    param (
        [Parameter(Mandatory = $true)]
        [string]$TaskDirectoryPath
    )

    # 現在日時からログファイル名を生成してタスクディレクトリと結合する。
    $timestamp = Get-Date -Format $TIMESTAMP_FORMAT
    $logFileName = $LOG_FILE_NAME_FORMAT -f $timestamp
    return Join-Path -Path $TaskDirectoryPath -ChildPath $logFileName
}

<#
.SYNOPSIS
エラーメッセージを標準エラーへ、no-task-folderを標準出力へ出力して終了する。

.PARAMETER Message
標準エラーへ出力するエラーメッセージ。
#>
function Exit-WithTaskFolderError {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    # 呼び出し側が機械判定しやすいように固定トークンを標準出力へ返す。
    [Console]::Error.WriteLine($Message)
    [Console]::Out.WriteLine($NO_TASK_FOLDER_OUTPUT)
    exit $EXIT_CODE_ERROR
}

<#
.SYNOPSIS
スクリプトのメイン処理を実行する。
#>
function Invoke-Main {
    param ()

    try {
        # Gitワークスペースを取得し、取得できない場合は終了する。
        $workspaceRoot = Get-WorkspaceRoot
        if ([string]::IsNullOrWhiteSpace($workspaceRoot)) {
            Exit-WithTaskFolderError -Message $ERROR_MESSAGE_NOT_GIT_WORKSPACE
        }

        # .tasksディレクトリを取得し、存在しない場合は終了する。
        $tasksRoot = Get-TasksRoot -WorkspaceRoot $workspaceRoot
        if ([string]::IsNullOrWhiteSpace($tasksRoot)) {
            Exit-WithTaskFolderError -Message $ERROR_MESSAGE_TASKS_ROOT_NOT_FOUND
        }

        # 現在ブランチ末尾を取得し、取得できない場合は終了する。
        $branchSuffix = Get-BranchSuffix
        if ([string]::IsNullOrWhiteSpace($branchSuffix)) {
            Exit-WithTaskFolderError -Message $ERROR_MESSAGE_BRANCH_NAME_NOT_FOUND
        }

        # ブランチ末尾を含むタスクディレクトリを探索し、未検出なら終了する。
        $taskDirectory = Find-TaskDirectory -TasksRoot $tasksRoot -BranchSuffix $branchSuffix
        if ($null -eq $taskDirectory) {
            $errorMessage = $ERROR_MESSAGE_TASK_DIRECTORY_NOT_FOUND -f $branchSuffix
            Exit-WithTaskFolderError -Message $errorMessage
        }

        # ログファイルパスを作成して標準出力へ返す。
        $logFilePath = Get-LogFilePath -TaskDirectoryPath $taskDirectory.FullName
        [Console]::Out.WriteLine($logFilePath)
        exit $EXIT_CODE_SUCCESS
    }
    catch {
        $errorMessage = $ERROR_MESSAGE_UNEXPECTED -f $_.Exception.Message
        Exit-WithTaskFolderError -Message $errorMessage
    }
}

Invoke-Main
