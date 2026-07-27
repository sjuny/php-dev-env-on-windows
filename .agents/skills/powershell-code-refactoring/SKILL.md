---
name: powershell-code-refactoring
description: 指定ソースファイルが、全プログラム言語共通のコード規約とPowerShellのコード規約に則すようにコードを修正する。
---

# PowerShellコードリファクタリングスキル

## 1. 処理目的

- 全プログラム言語共通のコード規約とPowerShellコード規約に則すようにコードを修正する。

## 2. 処理順序

以下の項番ごとの処理を、**絶対に** まとめて実行せず、一つずつ実行する。

- 1. 指定されたソースファイルのコードが$common-codingスキルが参照する以下のコード規約に則しているか確認する。
  - `<project-root-path>/.agents/common-coding/references/common-rules.md`

- 2. 項番1でコード規約違反があれば、修正計画を現在のタスクディレクトリに修正計画書として出力する。
  - 違反がなければ計画書への出力は不要。
  - 修正計画ファイル名は、`yyyymmdd-HHmm_plan.md`とする。

- 3. 指定されたソースファイルのコードが$powershell-codingスキルが参照する以下の共通コード規約に則しているか確認する。
  - `<project-root-path>/.agents/powershell-coding/references/powershell-common-rules.md`

- 4. 項番3でコード規約違反があれば、修正計画を項番2で出力したファイルに追記する。
  - 違反がなければ計画書への出力は不要。
  - 修正計画書がなければ、項番2の形式で修正計画書を作成する。

- 5. 利用するPowerShellのバージョンをAGENTS.md、docsディレクトリ内の技術スタック、処理対象ソースファイルを元に特定する。
  - 不明な場合は、ユーザーに確認する。
  - 特定したバージョンを現在のバージョンと呼ぶ。

- 6. 指定されたソースファイルのコードが$powershell-codingスキルが参照する以下のバージョン別のコード規約に則しているか確認する。
  - v5コード規約：`<user-skill-folder-path>/references/powershell-v5-rules.md`
  - v7コード規約：`<user-skill-folder-path>/references/powershell-v7-rules.md`

- 7. 項番6でコード規約違反があれば、修正計画を項番2で出力したファイルに追記する。
  - 違反がなければ計画書への出力は不要。
  - 修正計画書がなければ、項番2の形式で修正計画書を作成する。

- 8. 作成した修正計画書の内容を、ユーザーに確認させる。承認であればyを入力させ、問題があれば回答をえて、修正計画書を修正する。
  - 修正計画書がなければ処理は終了する。

- 9. 修正計画書に従って、コードを修正する。
