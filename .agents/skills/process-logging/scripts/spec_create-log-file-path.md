# 作業記録作成スクリプト

## 1. 処理概要

- 現在のgitのブランチ名と指示ファイルディレクトリパスからログファイルパスを作成する。

## 2. 技術スタック

- プログラム言語：bash, powershell5.1

## 3. スクリプト引数

引数なし

## 4. 処理順序

- 1. スクリプトが存在するgitの現在のブランチ名を取得する。

- 2. 取得したブランチ名を含む、以下のタスクディレクトリパス内のサブディレクトリを取得する。
  - `<git-workspace>/.tasks`

  - ディレクトリパスがなければエラーメッセージを表示して「no-task-directory」を標準出力に表示する。

- 3. 項番2のディレクトリパスを取得する。このディレクトリパスを、「タスクディレクトリパス」と呼ぶ。

- 4. 現在の日時と、「タスクディレクトリパス」から以下の形式のログファイルパスを作成し、標準出力に表示する。
  - `<project-root-path>/.tasks/yyyymmdd-hhmm\_<ブランチ名>/process-log_yyyymmdd-hhmm.md`

  - 出力方パスについては、後述の「出力パスの例」に具体例を記載している。

## 5. 出力パスの例

- 現在のgitのワークスペースのブランチ名
  - fix/input-error
- 保存先指示ディレクトリ
  - `<project-root-path>/.tasks/20260116-1433_input-error/process-log_20260116_2020.md`

## 6. スクリプトファイルパス

- `<path-to-skill>/scripts/create-log-file-path.sh`
- `<path-to-skill>/scripts/create-log-file-path.ps1`
