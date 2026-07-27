# AIエージェントリソース取得スクリプト

## 1. 処理概要

- GithubのリポジトリからGithub CLI（`gh api`）を利用して、パラメーターで指定したリソース名に該当するディレクトリ内のAIリソースのディレクトリ、または、ファイルを取得する。
  - リポジトリをcloneせず、指定のファイルやディレクトリのみ取得する。
- 取得したリソースディレクトリやファイルを、配置先のgit workspaceディレクトリの直下に配置する。
- 取得したディレクトリやファイルを参照元とするシンボリックリンクを作成する。
- スキルで利用するルートディレクトリの作成。

## 2. 技術スタック

- プログラム言語：PowerShell5.1
- 実行OS：Windows11

## 3. スクリプトパラメーター

- 取得元リポジトリSSHアドレス:repository-url
  - 入力必須。
  - SSHのアドレスを記載する。

- 対象リソース名: resource-name
  - 任意入力。
  - 取得元の`git workspace/resources`直下のディレクトリ名を指定。
  - AIエージェントの処理分類ごとにディレクトリ分けされている。
  - 未指定の場合は`software-development`を利用する。

- 除外スキルディレクトリ名: exclusive-skill-folder-names
  - 任意入力。
  - 配列で取得しないディレクトリ名を記載する。

- 取得対象ref名: ref
  - 任意入力。
  - `gh api`で取得するブランチ名、または、タグ名を指定する。
  - 未指定の場合は`main`を利用する。

## 4. 処理補足

以下、個別の処理において踏襲、および、実現することの詳細を記載する。

### 4-a. ディレクトリやファイルのパスを取得する起点

- スクリプトが処理で扱うパスを取得する場合、以下のスクリプトの実行形態を前提にする。
  - スクリプトを任意の場所においてPATHを通して実行する。
  - スクリプトが配置されたディレクトリを参照するシンボリックリンクを参照して、スクリプトの実体がない場所で実行する。
  - git workspaceディレクトリの直下だけでなく、それより下の任意の階層で実行する。

- 上記の前提からディレクトリやファイルのパスを取得する方法は以下とする。
  - スクリプトの配置場所はパス取得では考慮しない。
  - スクリプトが実行された場所をパス取得の起点とする。

- パスを取得する例は以下の通り。
  - 前提条件
    - スクリプトの配置場所：/utility/script.ps1
    - 実行場所：/Users/user-1/script.ps1
  - 取得パスは、`/Users/user-1`配下から取得する。

## 4-b. git workspaceディレクトリパスの取得

- スクリプトが配置されたgit workspaceディレクトリを以下のコマンドで、任意の階層でも取得する。

```sh
git rev-parse --show-toplevel
```

### 4-c. 取得するディレクトリと配置先

- skillsディレクトリ
  - 取得元：`<取得元：project-root-directory-path>/resources/<リソース名>/skills`
  - 配置先：`<配置先：project-root-directory-path>/.agent/skills`
- AGENTS.mdファイル
  - 取得元：`<取得元：project-root-directory-path>/resources/<リソース名>/AGENTS.md`
  - 配置先：`<配置先：project-root-directory-path>/AGENTS.md`
- .toolsディレクトリ
  - 取得元：`<取得元：project-root-directory-path>/resources/.tools`
  - 配置先：`<配置先：project-root-directory-path>/.agent/tools`

### 4-d. 作成するシンボリックの参照元とリンク名

- skillsディレクトリ
  - 参照元：`<配置先：project-root-directory-path>/.agent/skills`
  - 作成先
    - `<配置先：project-root-directory-path>/.codex/skills`
    - `<配置先：project-root-directory-path>/.claude/skills`

- AGENTS.mdファイル
  - 参照元：`<配置先：project-root-directory-path>/AGENTS.md`
  - 作成先：`<配置先：project-root-directory-path>/CLAUDE.md`

### 4-e. スキルで利用するルートディレクトリの作成

以下のディレクトリをgit workspaceディレクトリの直下に作成する。

- specs, .tasks, .reports, .tech-notes
