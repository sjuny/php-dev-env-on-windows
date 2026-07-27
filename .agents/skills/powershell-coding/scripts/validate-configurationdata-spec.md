# validate-configurationdata.ps1 仕様

## 1. 目的
- 指定した 1 件以上の `.psd1` ファイルに対して、PowerShell パーサー構文検証と `Import-PowerShellDataFile` 読み込み検証を実行する。
- 検証結果を機械可読なオブジェクトで返却し、異常時のみエラー箇所を返す。

## 2. 入力
- パラメーター: `-FilePaths [string[]]`（必須）
- 1 件以上のファイルパスを受け付ける。

## 3. 検証ロジック
1. ファイル存在確認（`Test-Path -PathType Leaf`）
2. `Parser.ParseFile` による構文エラー収集
3. `Import-PowerShellDataFile` による読み込み可否確認

## 4. 出力仕様
- 戻り値型: `PSCustomObject[]`
- 各要素の共通プロパティ:
  - `FilePath`: 解決済みのフルパス（存在しない場合は入力値）
  - `IsSuccess`: `true` / `false`
- 失敗時のみ追加プロパティ:
  - `ErrorLocations`: `PSCustomObject[]`
    - `Line`: 行番号（不明時は `0`）
    - `Column`: 列番号（不明時は `0`）
    - `Message`: エラーメッセージ

## 5. 終了コード
- `0`: 全ファイル成功
- `1`: 1 件以上失敗

## 6. 実行例
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\validate-configurationdata.ps1 -FilePaths .\..\..\..\..\dsc\configurationData\dev.psd1,.\..\..\..\..\dsc\configurationData\prod.psd1
```

## 7. 実装制約
- `#Requires -Version 5.1`
- `Set-StrictMode -Version Latest`
- 例外は呼び出し元で検知しやすいよう終了コードで明示する。