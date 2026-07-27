# Windows上のPHP開発環境作成ツール

## 1. アプリ概要

本プロジェクトディレクトリで開発するツールの概要は以下の通り。

- PHPのアプリをWindows上で実行できる開発環境を作成する。

## 2. プロジェクトディレクトリ構成

- プロジェクトディレクトリ内のプログラムコードや資料の配置は以下の通り。

```markdown
- project-root-path/
  - README.md: 本書。プロジェクトディレクトリ内の説明を記載。
  - docs/: 仕様書などの資料ディレクトリ。
  - application/: アプリファイル格納ディレクトリ。
  - .dev-env/: PHPアプリを実行するミドルウェアや設定ファイルを配置する。
  - .dev-env-rsrc/：PHPアプリを実行するミドルウェアを配置するための構成管理コードやリソースファイル。
  - .tasks/: AIエージェントの作業情報格納ディレクトリ。作業毎の指示、作業記録、調査結果を格納。
  - .tools/: 開発者利用スクリプトの格納ディレクトリ。
  - .notes/: 開発者の個人メモなどを格納するディレクトリ。
  - .agents/: Codex用設定ディレクトリ。
  - .claude/: Claude Code用設定ディレクトリ。
  - AGENTS.md: Codex用共通プロンプト。
  - CLAUDE.md: Claude Code用共通プロンプト。
```

- 「ソースファイル格納ディレクトリ」は以下の通り。
  - `<project-root-path>/.tools`
  - `<project-root-path>/.dev-env-rsrc`
  - `<project-root-path>/application`
