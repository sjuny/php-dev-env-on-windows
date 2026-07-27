---
name: task-making
description: 指示内容をユーザーに確認し、gitブランチ、指示ディレクトリと指示書ファイルの雛形を作る。
---

# 指示関連リソース作成スキル

## 1. 処理目的

- 入力したタスク概要から作成したIDを名前に持つブランチとディレクトリを作成する。

## 2. 処理順序

以下の項番ごとの処理を、**絶対に** まとめて実行せず、一つずつ実行する。

- 1. タスクIDを作成するための指示概要をユーザーに入力させる。

- 2. 指示概要を英訳して、英単語からタスクIDを作成する。
  - 例：インストールの不具合修正 → modify install issue → modify-install-issue

- 3. 作成されたタスクIDを表示して、ユーザーに確認する。
  - y以外の回答ならば、ユーザーに修正内容を入力させる。

- 4. 作業種別を以下の選択肢からユーザーに番号で選択させる。
  - 1.新規機能追加：feature
  - 2.不具合修正：fix
  - 3.仕様変更：change
  - 4.調査：research
  - 5.その他：other

- 5. 以下のコマンドに項番2のタスクIDと項番4の作業種別のコードを設定して実行する。
  - 実行OSに応じて、bash版、powershell版を切り替えて実行する。

```sh
# 凡例：Linux
<skill-directory-path>/scripts/make-task.sh <作業種別コード> <タスクID>
# 凡例：Windows
<skill-directory-path>/scripts/make-task.ps1 -InstructionType <作業種別コード> -TaskId <タスクID>

# 実行例：Linux
<skill-directory-path>/scripts/make-task.sh fix modify-install-issue
# 実行例：Windows
<skill-directory-path>/scripts/make-task.ps1 -InstructionType feature -TaskId add-login
```
