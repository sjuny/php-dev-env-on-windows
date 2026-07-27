# AIリソースのシンボリックリンク作成

## 1. 処理目的

gitのリポジトリルートディレクトリ直下にAIリソースへのシンボリックリンクを作成する。

## 2. 技術スタック

- プログラム言語：PowerShell5.1
- 実行OS：Windows11

## 3. .スクリプトパラメーター

なし

## 4. スクリプト名

make-symbolic-links.ps1

## 5. 処理補足

以下、個別の処理において踏襲する事項を記載する。

## 5-a. gitトップレベルディレクトリパスを取得する起点

- 以下のコマンドでgitのトップレベルディレクトリパスを取得する。

```sh
git rev-parse --show-toplevel
```

## 5-b. gitトップレベルディレクトリパスを取得する起点

- gitのトップレベルディレクトリパスを取得する場合、スクリプトの配置場所ではなく、スクリプトを実行したディレクトリを含む、gitの作業ディレクトリのトップレベルディレクトリパスを取得する。
  - 前提としてスクリプトの配置されたディレクトリにPATHが通されている。
  - パスを取得する例は以下の通り。
    - 前提条件
      - スクリプトの配置場所：/utility/script.ps1
      - 実行場所：/Users/user-1/work/sub1
      - リポジトリパス：/Users/user-1/work/.git
    - 取得パス：`/Users/user-1/work`
      - `/Users/user-1/work/sub1`を含むgitの作業ディレクトリのトップレベルを取得する。

### 4-c. 作成するシンボリックの参照元とリンク名

- skillsディレクトリ
  - コピー元：`<git-repository-root-directory-path>/.agents/skills`
  - リンク先：`<git-repository-root-directory-path>/.claude/skills`

- 共通プロンプトファイル
  - コピー元：`<git-repository-root-directory-path>/AGENTS.md`
  - コピー先：`<git-repository-root-directory-path>/CLAUDE.md`

- マージコマンドファイル
  - コピー元：`<git-repository-root-directory-path>/.agents/process-logging-and-merging/scripts/git-merge-current-branch.ps1`
  - コピー先：`<git-repository-root-directory-path>/.dev-tools/git-merge-current-branch.ps1`

### 4-d. 再作成

- 既にシンボリックリンクがある場合は、削除して、再作成する。
