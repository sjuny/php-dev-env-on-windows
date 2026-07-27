#Requires -Version 5.1

<#
.SYNOPSIS
AIエージェントリソースをGitHubからファイル単位で取得して配置する。

.DESCRIPTION
スクリプトパラメーターに定義した設定に従い、gh apiで必要なファイルのみ取得する。
取得対象は以下である。
  - <resource-name>/skills 配下
  - resources/.tools 配下
  - AGENTS.md
取得後に .codex/skills, .claude/skills, CLAUDE.md のリンクを作成し、
スキル利用向けのルートフォルダを作成する。

.EXAMPLE
.\install-ai-agent-resources.ps1 -repository-url 'git@github.com:example/sample.git'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [Alias('repository-url')]
    [string]$RepositoryUrl,

    [Parameter(Mandatory = $false)]
    [Alias('resource-name')]
    [string]$ResourceName,

    [Parameter(Mandatory = $false)]
    [Alias('exclusive-skill-folder-names')]
    [string[]]$ExclusiveSkillFolderNames,

    [Parameter(Mandatory = $false)]
    [Alias('ref')]
    [string]$RefName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$DEFAULT_REF_NAME = 'main'
$DEFAULT_RESOURCE_NAME = 'software-development'
$DEFAULT_EXCLUSIVE_SKILL_FOLDER_NAME_LIST = @()
$GITHUB_API_JSON_HEADER = 'Accept: application/vnd.github+json'
$GITHUB_API_RAW_HEADER = 'Accept: application/vnd.github.raw'
$GITHUB_API_REPOSITORY_PATH = '/repos/{0}/{1}/contents/{2}?ref={3}'
$AGENTS_FILE_NAME = 'AGENTS.md'
$CLAUDE_FILE_NAME = 'CLAUDE.md'
$SKILLS_FOLDER_NAME = 'skills'
$TOOLS_FOLDER_NAME = '.tools'
$RESOURCES_FOLDER_NAME = 'resources'
$AGENT_SKILLS_RELATIVE_PATH = '.agent\skills'
$AGENT_TOOLS_RELATIVE_PATH = '.agent\tools'
$CODEX_SKILLS_RELATIVE_PATH = '.codex\skills'
$CLAUDE_SKILLS_RELATIVE_PATH = '.claude\skills'
$LINK_TYPE_SYMBOLIC = 'SymbolicLink'
$LINK_TYPE_JUNCTION = 'Junction'
$LINK_TYPE_HARDLINK = 'HardLink'
$SKILL_ROOT_FOLDER_NAME_LIST = @('specs', '.tasks', '.reports', '.tech-notes')
$DEFAULT_GITHUB_HOST_NAME = 'github.com'
$REGEX_REPOSITORY_SSH = '^(?<user>[^@/:]+)@(?<host>[^:/]+):(?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?$'
$REGEX_REPOSITORY_HTTPS = '^https://(?<host>[^/]+)/(?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?/?$'
$REGEX_REPOSITORY_SSH_URL = '^ssh://(?<user>[^@/:]+)@(?<host>[^/]+)/(?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?/?$'
$GH_EXIT_SUCCESS = 0
$GIT_COMMAND_NAME = 'git'
$GIT_REPOSITORY_ROOT_ARGUMENT_LIST = @('rev-parse', '--show-toplevel')

<#
.SYNOPSIS
実行時カレントディレクトリ基点のリポジトリルートを取得する。

.PARAMETER BasePath
gitルート探索の基点とする絶対パス。
#>
function Get-RepositoryRoot {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath
    )

    # gitコマンドの存在を確認する。
    $gitCommand = Get-Command -Name $GIT_COMMAND_NAME -ErrorAction SilentlyContinue
    if ($null -eq $gitCommand) {
        throw 'gitコマンドが見つからないため、gitのインストールが必要である。'
    }

    # 実行ディレクトリを起点にgitリポジトリルートを取得する。
    $originalLocation = Get-Location
    try {
        Set-Location -LiteralPath $BasePath -ErrorAction Stop
        $gitOutputLineList = & $gitCommand.Source @GIT_REPOSITORY_ROOT_ARGUMENT_LIST 2>&1
        if ($LASTEXITCODE -ne $GH_EXIT_SUCCESS) {
            $errorText = ($gitOutputLineList | Out-String).Trim()
            throw ("gitリポジトリのルートを取得できません。基点パス: {0} 詳細: {1}" -f $BasePath, $errorText)
        }

        $repositoryRootPath = ($gitOutputLineList | Select-Object -First 1).ToString().Trim()
        if ([string]::IsNullOrWhiteSpace($repositoryRootPath)) {
            throw ("gitリポジトリのルート取得結果が空です。基点パス: {0}" -f $BasePath)
        }

        return [System.IO.Path]::GetFullPath($repositoryRootPath)
    }
    finally {
        Set-Location -LiteralPath $originalLocation.Path -ErrorAction Stop
    }
}

<#
.SYNOPSIS
GitHubリポジトリURLをowner/repoへ変換する。

.PARAMETER RepositoryUrl
スクリプトパラメーターのrepository-url。
#>
function ConvertTo-RepositoryIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryUrl
    )

    # SSH形式URLを解析する。
    if ($RepositoryUrl -match $REGEX_REPOSITORY_SSH) {
        return [PSCustomObject]@{
            HostName   = $Matches['host']
            Owner      = $Matches['owner']
            Repository = $Matches['repo']
        }
    }

    # HTTPS形式URLを解析する。
    if ($RepositoryUrl -match $REGEX_REPOSITORY_HTTPS) {
        return [PSCustomObject]@{
            HostName   = $Matches['host']
            Owner      = $Matches['owner']
            Repository = $Matches['repo']
        }
    }

    # ssh://形式URLを解析する。
    if ($RepositoryUrl -match $REGEX_REPOSITORY_SSH_URL) {
        return [PSCustomObject]@{
            HostName   = $Matches['host']
            Owner      = $Matches['owner']
            Repository = $Matches['repo']
        }
    }

    throw "GitHubリポジトリURLを解析できません: $RepositoryUrl"
}

<#
.SYNOPSIS
gh apiを実行してJSONを返す。

.PARAMETER ApiPath
gh apiに渡すAPIパス。
#>
function Invoke-GhApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ApiPath,

        [Parameter(Mandatory = $true)]
        [string]$HostName
    )

    # ghコマンドの存在を確認する。
    $ghCommand = Get-Command -Name 'gh' -ErrorAction SilentlyContinue
    if ($null -eq $ghCommand) {
        throw 'ghコマンドが見つからないため、GitHub CLIのインストールが必要である。'
    }

    # gh apiを実行してレスポンスを取得する。
    $ghArgumentList = @('api', '--header', $GITHUB_API_JSON_HEADER)
    if ($HostName -ne $DEFAULT_GITHUB_HOST_NAME) {
        $ghArgumentList += @('--hostname', $HostName)
    }
    $ghArgumentList += $ApiPath
    $apiOutputText = & $ghCommand.Source @ghArgumentList 2>&1
    if ($LASTEXITCODE -ne $GH_EXIT_SUCCESS) {
        $errorText = ($apiOutputText | Out-String).Trim()
        throw "gh apiの実行に失敗した: $errorText"
    }

    $jsonText = ($apiOutputText | Out-String)
    return ($jsonText | ConvertFrom-Json -ErrorAction Stop)
}

<#
.SYNOPSIS
gh apiを実行して生データをバイト配列で返す。

.PARAMETER ApiPath
gh apiに渡すAPIパス。

.PARAMETER HostName
gh apiに渡すホスト名。
#>
function Invoke-GhApiRawByteArray {
    [CmdletBinding()]
    [OutputType([byte[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ApiPath,

        [Parameter(Mandatory = $true)]
        [string]$HostName
    )

    # ghコマンドの存在を確認する。
    $ghCommand = Get-Command -Name 'gh' -ErrorAction SilentlyContinue
    if ($null -eq $ghCommand) {
        throw 'ghコマンドが見つからないため、GitHub CLIのインストールが必要である。'
    }

    # rawレスポンスを取得する。
    $ghArgumentList = @('api', '--header', $GITHUB_API_RAW_HEADER)
    if ($HostName -ne $DEFAULT_GITHUB_HOST_NAME) {
        $ghArgumentList += @('--hostname', $HostName)
    }
    $ghArgumentList += $ApiPath
    $rawOutput = & $ghCommand.Source @ghArgumentList 2>&1
    if ($LASTEXITCODE -ne $GH_EXIT_SUCCESS) {
        $errorText = ($rawOutput | Out-String).Trim()
        throw "gh api(raw)の実行に失敗した: $errorText"
    }

    $rawText = ($rawOutput | Out-String)
    return [System.Text.Encoding]::UTF8.GetBytes($rawText)
}

<#
.SYNOPSIS
gh apiエラーが404(Not Found)かを判定する。

.PARAMETER ErrorMessage
判定対象のエラーメッセージ。
#>
function Test-GhApiNotFoundError {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ErrorMessage
    )

    # ghの404エラー表現を判定する。
    if ($ErrorMessage -match 'HTTP 404') {
        return $true
    }
    if ($ErrorMessage -match '"status"\s*:\s*"?404"?') {
        return $true
    }

    return $false
}

<#
.SYNOPSIS
リモートのリソースルートパスを解決する。

.PARAMETER Owner
GitHubリポジトリのowner。

.PARAMETER Repository
GitHubリポジトリ名。

.PARAMETER RefName
取得対象のref名。

.PARAMETER HostName
gh apiに渡すホスト名。

.PARAMETER ResourceName
リソース名。
#>
function Resolve-RemoteResourceRootPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Owner,

        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [Parameter(Mandatory = $true)]
        [string]$RefName,

        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $true)]
        [string]$ResourceName
    )

    # 互換性のため、resources配下と直下の両方を順に試行する。
    $candidateRepositoryPathList = @(
        ('{0}/{1}' -f $RESOURCES_FOLDER_NAME, $ResourceName),
        $ResourceName
    )
    $attemptedApiPathList = @()
    foreach ($candidateRepositoryPath in $candidateRepositoryPathList) {
        $encodedPath = [Uri]::EscapeDataString($candidateRepositoryPath).Replace('%2F', '/')
        $apiPath = [string]::Format($GITHUB_API_REPOSITORY_PATH, $Owner, $Repository, $encodedPath, [Uri]::EscapeDataString($RefName))
        $attemptedApiPathList += $apiPath
        try {
            [void](Invoke-GhApi -ApiPath $apiPath -HostName $HostName)
            return $candidateRepositoryPath
        }
        catch {
            $errorMessage = $_.Exception.Message
            if (Test-GhApiNotFoundError -ErrorMessage $errorMessage) {
                continue
            }
            throw
        }
    }

    $attemptedApiPathText = $attemptedApiPathList -join ', '
    throw ("リソースルートを解決できなかった。resource-name: {0} 試行API: {1}" -f $ResourceName, $attemptedApiPathText)
}

<#
.SYNOPSIS
指定パス配下のファイル一覧を再帰取得する。

.PARAMETER Owner
GitHubリポジトリのowner。

.PARAMETER Repository
GitHubリポジトリ名。

.PARAMETER RefName
取得対象のref名。

.PARAMETER RepositoryPath
リポジトリ内パス。
#>
function Get-RepositoryFilePathList {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Owner,

        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [Parameter(Mandatory = $true)]
        [string]$RefName,

        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $true)]
        [string]$RepositoryPath
    )

    # contents APIの返却を取得する。
    $encodedPath = [Uri]::EscapeDataString($RepositoryPath).Replace('%2F', '/')
    $apiPath = [string]::Format($GITHUB_API_REPOSITORY_PATH, $Owner, $Repository, $encodedPath, [Uri]::EscapeDataString($RefName))
    $responseObject = Invoke-GhApi -ApiPath $apiPath -HostName $HostName

    # 単一ファイルオブジェクトなら単一要素で返却する。
    if (($responseObject -isnot [System.Array]) -and ($responseObject.type -eq 'file')) {
        return [string[]]@($responseObject.path)
    }

    # ディレクトリ配下を再帰展開する。
    if ($responseObject -isnot [System.Array]) {
        throw "ディレクトリ取得に失敗したため配列を期待した: $RepositoryPath"
    }

    $resultFilePathList = @()
    foreach ($childItem in $responseObject) {
        if ($childItem.type -eq 'file') {
            $resultFilePathList += $childItem.path
            continue
        }
        if ($childItem.type -eq 'dir') {
            $resultFilePathList += Get-RepositoryFilePathList -Owner $Owner -Repository $Repository -RefName $RefName -HostName $HostName -RepositoryPath $childItem.path
        }
    }

    return [string[]]$resultFilePathList
}

<#
.SYNOPSIS
GitHub上の1ファイル内容をバイト配列で取得する。

.PARAMETER Owner
GitHubリポジトリのowner。

.PARAMETER Repository
GitHubリポジトリ名。

.PARAMETER RefName
取得対象のref名。

.PARAMETER RepositoryFilePath
取得対象のファイルパス。
#>
function Get-RepositoryFileContentByteArray {
    [CmdletBinding()]
    [OutputType([byte[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Owner,

        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [Parameter(Mandatory = $true)]
        [string]$RefName,

        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $true)]
        [string]$RepositoryFilePath
    )

    # contents APIで対象ファイルのBase64データを取得する。
    $encodedPath = [Uri]::EscapeDataString($RepositoryFilePath).Replace('%2F', '/')
    $apiPath = [string]::Format($GITHUB_API_REPOSITORY_PATH, $Owner, $Repository, $encodedPath, [Uri]::EscapeDataString($RefName))
    $fileObject = Invoke-GhApi -ApiPath $apiPath -HostName $HostName
    if ($fileObject.type -ne 'file') {
        throw "ファイルとして取得できなかった: $RepositoryFilePath"
    }
    $contentProperty = $fileObject.PSObject.Properties['content']
    if ($null -eq $contentProperty -or [string]::IsNullOrWhiteSpace([string]$contentProperty.Value)) {
        return Invoke-GhApiRawByteArray -ApiPath $apiPath -HostName $HostName
    }

    # 改行を除去してBase64をデコードする。
    $normalizedBase64 = ([string]$contentProperty.Value).Replace("`r", '').Replace("`n", '')
    return [Convert]::FromBase64String($normalizedBase64)
}

<#
.SYNOPSIS
バイト配列を指定パスへ保存する。親フォルダがなければ作成する。

.PARAMETER DestinationFilePath
保存先の絶対パス。

.PARAMETER FileContentBytes
保存するバイト配列。
#>
function Save-FileByteArray {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestinationFilePath,

        [Parameter(Mandatory = $true)]
        [byte[]]$FileContentBytes
    )

    # 保存先フォルダを作成する。
    $parentDirectoryPath = Split-Path -Path $DestinationFilePath -Parent
    if (-not (Test-Path -LiteralPath $parentDirectoryPath)) {
        New-Item -ItemType Directory -Path $parentDirectoryPath -Force -ErrorAction Stop | Out-Null
    }

    # ファイルを書き込む。
    [System.IO.File]::WriteAllBytes($DestinationFilePath, $FileContentBytes)
}

<#
.SYNOPSIS
既存パスを削除する。

.PARAMETER TargetPath
削除対象パス。
#>
function Remove-ExistingPath {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    # 既存パスがある場合のみ削除する。
    if (-not (Test-Path -LiteralPath $TargetPath)) {
        return
    }

    if ($PSCmdlet.ShouldProcess($TargetPath, 'Remove-Item')) {
        Remove-Item -LiteralPath $TargetPath -Recurse -Force -ErrorAction Stop
    }
}

<#
.SYNOPSIS
リンクを作成する。権限不足時はJunction/HardLinkにフォールバックする。

.PARAMETER LinkPath
作成するリンクパス。

.PARAMETER TargetPath
参照先パス。
#>
function New-ResourceLink {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LinkPath,

        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    # 既存リンクがある場合は一度削除する。
    Remove-ExistingPath -TargetPath $LinkPath

    # リンク先の親フォルダを作成する。
    $parentDirectoryPath = Split-Path -Path $LinkPath -Parent
    if (-not (Test-Path -LiteralPath $parentDirectoryPath)) {
        New-Item -ItemType Directory -Path $parentDirectoryPath -Force -ErrorAction Stop | Out-Null
    }

    # 通常はシンボリックリンクを作成する。
    if ($PSCmdlet.ShouldProcess($LinkPath, "New-Item $LINK_TYPE_SYMBOLIC")) {
        try {
            New-Item -ItemType $LINK_TYPE_SYMBOLIC -Path $LinkPath -Target $TargetPath -ErrorAction Stop | Out-Null
            return
        }
        catch {
            $targetItem = Get-Item -LiteralPath $TargetPath -ErrorAction Stop
            if ($targetItem.PSIsContainer) {
                New-Item -ItemType $LINK_TYPE_JUNCTION -Path $LinkPath -Target $TargetPath -ErrorAction Stop | Out-Null
            }
            else {
                New-Item -ItemType $LINK_TYPE_HARDLINK -Path $LinkPath -Target $TargetPath -ErrorAction Stop | Out-Null
            }
        }
    }
}

<#
.SYNOPSIS
取得したskills配下ファイルをローカルへ配置する。

.PARAMETER Owner
GitHubリポジトリのowner。

.PARAMETER Repository
GitHubリポジトリ名。

.PARAMETER RefName
取得対象のref名。

.PARAMETER ResourceName
リソース名。

.PARAMETER DestinationSkillsPath
配置先の .agent/skills 絶対パス。

.PARAMETER ExclusiveSkillFolderNameList
除外対象スキルフォルダ名の配列。
#>
function Install-SkillResource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Owner,

        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [Parameter(Mandatory = $true)]
        [string]$RefName,

        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $true)]
        [string]$ResourceRootRepositoryPath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationSkillsPath,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]]$ExclusiveSkillFolderNameList
    )

    # リモートのskills配下ファイル一覧を取得する。
    $remoteSkillsRootPath = '{0}/{1}' -f $ResourceRootRepositoryPath, $SKILLS_FOLDER_NAME
    $remoteFilePathList = Get-RepositoryFilePathList -Owner $Owner -Repository $Repository -RefName $RefName -HostName $HostName -RepositoryPath $remoteSkillsRootPath

    # 除外判定に使う検索マップを作成する。
    $exclusiveSkillFolderMap = @{}
    foreach ($exclusiveSkillFolderName in $ExclusiveSkillFolderNameList) {
        $exclusiveSkillFolderMap[$exclusiveSkillFolderName] = $true
    }

    # 取得ファイルを順に保存する。
    foreach ($remoteFilePath in $remoteFilePathList) {
        $relativePathFromSkillsRoot = $remoteFilePath.Substring($remoteSkillsRootPath.Length + 1)
        $normalizedRelativePath = $relativePathFromSkillsRoot.Replace('/', '\')
        $firstSegmentName = $normalizedRelativePath.Split('\')[0]
        if ($exclusiveSkillFolderMap.ContainsKey($firstSegmentName)) {
            continue
        }

        $destinationFilePath = Join-Path -Path $DestinationSkillsPath -ChildPath $normalizedRelativePath
        $fileContentBytes = Get-RepositoryFileContentByteArray -Owner $Owner -Repository $Repository -RefName $RefName -HostName $HostName -RepositoryFilePath $remoteFilePath
        Save-FileByteArray -DestinationFilePath $destinationFilePath -FileContentBytes $fileContentBytes
    }
}

<#
.SYNOPSIS
取得した.tools配下ファイルをローカルへ配置する。

.PARAMETER Owner
GitHubリポジトリのowner。

.PARAMETER Repository
GitHubリポジトリ名。

.PARAMETER RefName
取得対象のref名。

.PARAMETER DestinationToolsPath
配置先の .agent/tools 絶対パス。
#>
function Install-ToolsResource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Owner,

        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [Parameter(Mandatory = $true)]
        [string]$RefName,

        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $true)]
        [string]$DestinationToolsPath
    )

    # リモートの.tools配下ファイル一覧を取得する。
    $remoteToolsRootPath = '{0}/{1}' -f $RESOURCES_FOLDER_NAME, $TOOLS_FOLDER_NAME
    $remoteFilePathList = Get-RepositoryFilePathList -Owner $Owner -Repository $Repository -RefName $RefName -HostName $HostName -RepositoryPath $remoteToolsRootPath

    # 取得ファイルを順に保存する。
    foreach ($remoteFilePath in $remoteFilePathList) {
        $relativePathFromToolsRoot = $remoteFilePath.Substring($remoteToolsRootPath.Length + 1)
        $normalizedRelativePath = $relativePathFromToolsRoot.Replace('/', '\')
        $destinationFilePath = Join-Path -Path $DestinationToolsPath -ChildPath $normalizedRelativePath
        $fileContentBytes = Get-RepositoryFileContentByteArray -Owner $Owner -Repository $Repository -RefName $RefName -HostName $HostName -RepositoryFilePath $remoteFilePath
        Save-FileByteArray -DestinationFilePath $destinationFilePath -FileContentBytes $fileContentBytes
    }
}

<#
.SYNOPSIS
AGENTS.mdを取得してローカルへ配置する。

.PARAMETER Owner
GitHubリポジトリのowner。

.PARAMETER Repository
GitHubリポジトリ名。

.PARAMETER RefName
取得対象のref名。

.PARAMETER DestinationAgentsPath
配置先AGENTS.mdの絶対パス。
#>
function Install-AgentsMarkdown {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Owner,

        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [Parameter(Mandatory = $true)]
        [string]$RefName,

        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $true)]
        [string]$ResourceRootRepositoryPath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationAgentsPath
    )

    # AGENTS.mdを取得して上書きする。
    $remoteAgentsFilePath = '{0}/{1}' -f $ResourceRootRepositoryPath, $AGENTS_FILE_NAME
    $agentsContentBytes = Get-RepositoryFileContentByteArray -Owner $Owner -Repository $Repository -RefName $RefName -HostName $HostName -RepositoryFilePath $remoteAgentsFilePath
    Save-FileByteArray -DestinationFilePath $DestinationAgentsPath -FileContentBytes $agentsContentBytes
}

<#
.SYNOPSIS
リンク群を作成する。

.PARAMETER RepositoryRoot
作業リポジトリルートの絶対パス。
#>
function Install-ResourceLink {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot
    )

    # リンク構成を定義する。
    $skillsSourcePath = Join-Path -Path $RepositoryRoot -ChildPath $AGENT_SKILLS_RELATIVE_PATH
    $codexSkillsPath = Join-Path -Path $RepositoryRoot -ChildPath $CODEX_SKILLS_RELATIVE_PATH
    $claudeSkillsPath = Join-Path -Path $RepositoryRoot -ChildPath $CLAUDE_SKILLS_RELATIVE_PATH
    $agentsFilePath = Join-Path -Path $RepositoryRoot -ChildPath $AGENTS_FILE_NAME
    $claudeFilePath = Join-Path -Path $RepositoryRoot -ChildPath $CLAUDE_FILE_NAME

    # 各リンクを作成する。
    New-ResourceLink -LinkPath $codexSkillsPath -TargetPath $skillsSourcePath
    New-ResourceLink -LinkPath $claudeSkillsPath -TargetPath $skillsSourcePath
    New-ResourceLink -LinkPath $claudeFilePath -TargetPath $agentsFilePath
}

<#
.SYNOPSIS
配置先リポジトリの.gitignoreに必要な除外パターンを追記する。

.PARAMETER RepositoryRoot
作業リポジトリルートの絶対パス。
#>
function Update-GitIgnoreFile {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot
    )

    # .gitignoreの対象パスを定義する。
    $gitIgnoreFilePath = Join-Path -Path $RepositoryRoot -ChildPath '.gitignore'
    $requiredPatternList = @(
        '.claude/**',
        '.codex/**',
        $CLAUDE_FILE_NAME
    )

    # .gitignoreが存在しない場合は空ファイルを作成する。
    if (-not (Test-Path -LiteralPath $gitIgnoreFilePath -PathType Leaf)) {
        if ($PSCmdlet.ShouldProcess($gitIgnoreFilePath, 'New-Item File')) {
            New-Item -ItemType File -Path $gitIgnoreFilePath -Force -ErrorAction Stop | Out-Null
        }
    }

    # 既存内容を読み取り、未記載パターンのみ追記する。
    $existingLineList = Get-Content -LiteralPath $gitIgnoreFilePath -Encoding UTF8 -ErrorAction Stop
    $existingLineMap = @{}
    foreach ($existingLine in $existingLineList) {
        $existingLineMap[$existingLine.Trim()] = $true
    }

    $appendLineList = @()
    foreach ($requiredPattern in $requiredPatternList) {
        if ($existingLineMap.ContainsKey($requiredPattern)) {
            continue
        }
        $appendLineList += $requiredPattern
    }

    if ($appendLineList.Count -eq 0) {
        return
    }

    if ($PSCmdlet.ShouldProcess($gitIgnoreFilePath, 'Add-Content')) {
        Add-Content -LiteralPath $gitIgnoreFilePath -Value $appendLineList -Encoding UTF8
    }
}

<#
.SYNOPSIS
スキルで利用するルートフォルダを作成する。

.PARAMETER RepositoryRoot
作業リポジトリルートの絶対パス。
#>
function Install-SkillRootFolder {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot
    )

    foreach ($folderName in $SKILL_ROOT_FOLDER_NAME_LIST) {
        $folderPath = Join-Path -Path $RepositoryRoot -ChildPath $folderName
        if ($PSCmdlet.ShouldProcess($folderPath, 'New-Item Directory')) {
            New-Item -ItemType Directory -Path $folderPath -Force -ErrorAction Stop | Out-Null
        }
    }
}

<#
.SYNOPSIS
メイン処理。
#>
function Invoke-Main {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryUrl,

        [Parameter(Mandatory = $false)]
        [string]$ResourceName,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]]$ExclusiveSkillFolderNames,

        [Parameter(Mandatory = $false)]
        [string]$RefName
    )

    try {
        # スクリプトパラメーターの任意値を既定値で補完する。
        $effectiveResourceName = $ResourceName
        if ([string]::IsNullOrWhiteSpace($effectiveResourceName)) {
            $effectiveResourceName = $DEFAULT_RESOURCE_NAME
        }
        $effectiveRefName = $RefName
        if ([string]::IsNullOrWhiteSpace($effectiveRefName)) {
            $effectiveRefName = $DEFAULT_REF_NAME
        }
        $effectiveExclusiveSkillFolderNameList = @($ExclusiveSkillFolderNames)
        if ($null -eq $ExclusiveSkillFolderNames) {
            $effectiveExclusiveSkillFolderNameList = @($DEFAULT_EXCLUSIVE_SKILL_FOLDER_NAME_LIST)
        }

        # 実行環境と設定を解決する。
        $executionDirectoryPath = (Get-Location).Path
        $repositoryRoot = Get-RepositoryRoot -BasePath $executionDirectoryPath
        Write-Information ("実行ディレクトリ: {0}" -f $executionDirectoryPath) -InformationAction Continue
        Write-Information ("配置先リポジトリルート: {0}" -f $repositoryRoot) -InformationAction Continue
        $repositoryIdentity = ConvertTo-RepositoryIdentity -RepositoryUrl $RepositoryUrl
        $remoteResourceRootRepositoryPath = Resolve-RemoteResourceRootPath `
            -Owner $repositoryIdentity.Owner `
            -Repository $repositoryIdentity.Repository `
            -RefName $effectiveRefName `
            -HostName $repositoryIdentity.HostName `
            -ResourceName $effectiveResourceName

        # ローカル配置先を定義する。
        $destinationSkillsPath = Join-Path -Path $repositoryRoot -ChildPath $AGENT_SKILLS_RELATIVE_PATH
        $destinationToolsPath = Join-Path -Path $repositoryRoot -ChildPath $AGENT_TOOLS_RELATIVE_PATH
        $destinationAgentsPath = Join-Path -Path $repositoryRoot -ChildPath $AGENTS_FILE_NAME

        # 必要ファイルのみ取得して配置する。
        Install-SkillResource `
            -Owner $repositoryIdentity.Owner `
            -Repository $repositoryIdentity.Repository `
            -RefName $effectiveRefName `
            -HostName $repositoryIdentity.HostName `
            -ResourceRootRepositoryPath $remoteResourceRootRepositoryPath `
            -DestinationSkillsPath $destinationSkillsPath `
            -ExclusiveSkillFolderNameList $effectiveExclusiveSkillFolderNameList
        Install-ToolsResource `
            -Owner $repositoryIdentity.Owner `
            -Repository $repositoryIdentity.Repository `
            -RefName $effectiveRefName `
            -HostName $repositoryIdentity.HostName `
            -DestinationToolsPath $destinationToolsPath
        Install-AgentsMarkdown `
            -Owner $repositoryIdentity.Owner `
            -Repository $repositoryIdentity.Repository `
            -RefName $effectiveRefName `
            -HostName $repositoryIdentity.HostName `
            -ResourceRootRepositoryPath $remoteResourceRootRepositoryPath `
            -DestinationAgentsPath $destinationAgentsPath

        # 取得済みリソースのリンクを再作成する。
        Install-ResourceLink -RepositoryRoot $repositoryRoot

        # 配置先の.gitignoreに必要な除外パターンを反映する。
        Update-GitIgnoreFile -RepositoryRoot $repositoryRoot

        # スキルで利用するルートフォルダを作成する。
        Install-SkillRootFolder -RepositoryRoot $repositoryRoot
        exit 0
    }
    catch {
        Write-Error ("処理でエラーが発生した: {0}" -f $_.Exception.Message)
        exit 1
    }
}

Invoke-Main `
    -RepositoryUrl $RepositoryUrl `
    -ResourceName $ResourceName `
    -ExclusiveSkillFolderNames $ExclusiveSkillFolderNames `
    -RefName $RefName
