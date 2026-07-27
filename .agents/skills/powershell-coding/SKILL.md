---
name: powershell-coding
description: PowerShellのコード規約に従い、プログラムコードを生成する。
---

# PowerShellコード生成スキル

## 1. 処理目的

- 全プログラム言語共通のコード規約とPowerShellのコード規約に従い、プログラムコードを生成する。

## 2. 処理順序

**必ず**、以下の処理を項番にごとに、一つずつ、まとめずに実行する。

- 1. 利用するPowerShellのバージョンをAGENTS.md、docsディレクトリ内の技術スタック、処理対象ソースファイルを元に特定する。
  - 不明な場合は、ユーザーに確認する。
  - 特定したバージョンを現在のPSバージョンと呼ぶ。

- 2. $common-codingスキルを使ってコードを生成し、ソースファイルへ出力する。
  - 生成コードの文字コードと改行コードは、現在のPSバージョンを元に以下の通り。
    - v5：BOM付きUTF-8、LF。
    - v7：UTF-8、LF。

- 3. 項番2で生成したコードが、以下のコード規約に則しているか確認して、則していなければ修正する。
  - 共通コード規約：`<user-skill-folder-path>/references/powershell-common-rules.md`

- 4. 項番2で生成したコードが、現在のPSバージョンに対応した以下のコード規約に則しているか確認して、則していなければ修正する。
  - v5コード規約：`<user-skill-folder-path>/references/powershell-v5-rules.md`
  - v7コード規約：`<user-skill-folder-path>/references/powershell-v7-rules.md`

- 5. 以下の解析スクリプを利用してソースファイルを解析して、問題点があれば修正する。
  - `<user-skill-folder-path>/scripts/analyze-code.ps1`

- 6. ソースファイルの拡張子が`psd1`の場合、以下の解析スクリプを利用してソースファイルを解析して、問題点があれば修正する。
  - psd1ファイル以外はこの処理は不要。

```ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File <skill-folder-path>/scripts/validate-configurationdata.ps1 -FilePaths <psd-file-path>
```
