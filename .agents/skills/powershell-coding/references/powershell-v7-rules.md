# PowerShellv7系固有コーディング規約

## 1. 対象バージョン

PowerShell 7系には複数のバージョンがあるため、プロジェクトごとに最低対応バージョンを明示する。

例：

```powershell
#Requires -Version 7.4
```

モジュールでは、マニフェストへ指定する。

```powershell
PowerShellVersion = '7.4'
```

PowerShell 7.0以降で導入された機能であっても、7系の途中で追加・変更された機能があるため、「PowerShell 7対応」だけではなく最低マイナーバージョンを定める。

---

## 2. 実行環境

### 2-a. 実行ファイル

PowerShell 7を明示的に起動する場合は、次を使用する。

```powershell
pwsh
```

Windowsでは次の実行ファイル名となる。

```powershell
pwsh.exe
```

Windows PowerShell 5.1の`powershell.exe`と混同しない。

### 2-b. エディション

PowerShell 7では、通常、次の値となる。

```powershell
$PSVersionTable.PSEdition
```

```text
Core
```

PowerShell 7専用コードであることを検証する場合は、次のようにする。

```powershell
if ($PSVersionTable.PSEdition -ne 'Core') {
    throw 'このスクリプトはPowerShell 7専用である。'
}
```

---

## 3. .NETへの依存

PowerShell 7は、PowerShellのリリースごとに異なるバージョンの.NETを基盤とする。

.NET型やメソッドを直接使用する場合は、対象となる最低PowerShellバージョンが使用する.NETで利用可能かを確認する。

新しい.NET APIを使用する場合は、次を明記する。

- 最低PowerShellバージョン
- 最低.NETバージョン
- 対応OS
- Windows PowerShell 5.1では動作しないこと

PowerShellのバージョン更新によって.NETのバージョンも変わるため、.NETメソッドのオーバーロードや動作差を実行テストする。

---

## 4. パス

クロスプラットフォームコードでは、パス区切り文字を固定しない。

避ける例：

```powershell
$ConfigPath = "$RootPath\config\application.json"
```

推奨例：

```powershell
$ConfigPath = Join-Path `
    -Path $RootPath `
    -ChildPath 'config/application.json'
```

または、複数回に分けて結合する。

```powershell
$ConfigDirectory = Join-Path -Path $RootPath -ChildPath 'config'
$ConfigPath = Join-Path -Path $ConfigDirectory -ChildPath 'application.json'
```

Windows固有コードである場合を除き、次を固定しない。

- ドライブ文字
- `C:\`
- バックスラッシュ
- `/tmp`
- `/home`
- `/var`
- 利用者ホームディレクトリ

利用者ホームは、必要に応じて次を使用する。

```powershell
$HOME
```

一時ディレクトリは、次を検討する。

```powershell
[System.IO.Path]::GetTempPath()
```

---

## 5. ファイル名の大文字と小文字

Windows以外のファイルシステムでは、ファイル名の大文字と小文字が区別される場合がある。

次の表記を一致させる。

- 実ファイル名
- `Import-Module`のパス
- ドットソースするファイル名
- 設定ファイル名
- テスト対象のファイル名
- モジュールマニフェストの`RootModule`

例えば、実ファイルが次の場合、

```text
ApplicationConfig.ps1
```

次のような異なる表記を使用しない。

```powershell
. './applicationconfig.ps1'
```

---

## 6. PowerShell 7構文

PowerShell 7専用コードでは、可読性が向上する場合に限り、PowerShell 7で追加された構文を使用できる。

### 6-a. 三項演算子

単純な二者択一に使用できる。

```powershell
$Status = $IsEnabled ? 'Enabled' : 'Disabled'
```

複雑な条件、複数の処理、副作用を含む場合は`if`文を使用する。

### 6-b. null合体演算子

nullの場合だけ既定値を使用するときは、`??`を使用できる。

```powershell
$Value = $InputValue ?? 'Default'
```

空文字列、`0`、`$false`はnullではないため、そのまま保持されることを理解して使用する。

### 6-c. null合体代入演算子

変数がnullの場合だけ値を設定するときは、`??=`を使用できる。

```powershell
$Value ??= 'Default'
```

### 6-d. null条件演算子

nullの可能性があるオブジェクトのメンバーへアクセスする場合は、`?.`を使用できる。

```powershell
$Name = $User?.Name
```

ただし、nullがエラーであるべき箇所では使用せず、明示的に検証してエラーとする。

### 6-e. パイプラインチェーン演算子

PowerShell 7では、`&&`および`||`を使用できる。

```powershell
Invoke-Build && Invoke-Test
Invoke-Build || Write-Error 'ビルドに失敗した。'
```

`&&`は左側のパイプラインが成功した場合に右側を実行する。

`||`は左側のパイプラインが失敗した場合に右側を実行する。

複雑なエラー処理、例外処理、後処理が必要な場合は、`try`／`catch`または明示的な条件分岐を使用する。

---

## 7. 並列処理

PowerShell 7では、`ForEach-Object -Parallel`を使用できる。

```powershell
$Items |
    ForEach-Object -Parallel {
        Invoke-ProcessItem -InputObject $_
    } -ThrottleLimit 5
```

### 7-a. 採用条件

次の場合に使用を検討する。

- 各処理が互いに独立している
- ネットワーク待ちやI/O待ちが多い
- 1件当たりの処理時間が十分に長い
- 順序が保証されなくても問題ない
- 共有状態を必要としない

単純で軽量な処理では、Runspaceの準備コストによって逐次処理より遅くなる場合がある。

### 7-b. ThrottleLimit

同時実行数は、`ThrottleLimit`で明示的に制御する。

```powershell
-Parallel {
    # 処理
} -ThrottleLimit 5
```

外部API、データベース、ファイルシステムなどへの負荷を考慮して値を決定する。

### 7-c. 外部変数

並列スクリプトブロックから外部変数を参照する場合は、`$using:`を使用する。

```powershell
$DestinationPath = '/data/output'

$Items |
    ForEach-Object -Parallel {
        Copy-Item `
            -LiteralPath $_.FullName `
            -Destination $using:DestinationPath
    }
```

### 7-d. 共有状態

通常のハッシュテーブルやリストを、複数の並列処理から無制御に変更しない。

共有状態が必要な場合は、次を検討する。

- スレッドセーフなコレクション
- 同期ハッシュテーブル
- 各処理で結果を返し、呼び出し側で集約する
- 並列処理を使用しない

### 7-e. 出力順序

`ForEach-Object -Parallel`の出力順序が、入力順序と一致することを前提にしない。

順序が必要な場合は、入力に識別子を付けて、処理後に並べ替える。

---

## 8. 文字コード

### 8-a. 既定文字コード

PowerShell 7では、テキスト出力の既定文字コードは原則としてBOMなしUTF-8である。

PowerShell 7専用コードでは、通常、UTF-8 BOMなしを標準とする。

改行コードはLFとする。

### 8-b. 明示指定

外部システム、Windows PowerShell 5.1、古いWindowsアプリケーション、CSV利用者などとの連携では、文字コードを明示する。

```powershell
Set-Content `
    -LiteralPath $Path `
    -Value $Content `
    -Encoding utf8NoBOM
```

BOMが必要な場合は次を使用する。

```powershell
-Encoding utf8BOM
```

### 8-c. `utf8`の意味

PowerShell 7の`utf8`は、BOMなしUTF-8を意味する。

Windows PowerShell 5.1の`UTF8`はBOM付きであり、意味が異なる。

共通ライブラリや移行コードでは、`utf8BOM`または`utf8NoBOM`を明示し、曖昧な`utf8`を避けてもよい。

### 8-d. ANSI

PowerShell 7.4以降では、`-Encoding ansi`を使用できる。

```powershell
Set-Content `
    -LiteralPath $Path `
    -Value $Content `
    -Encoding ansi
```

PowerShell 7.0から7.3も対象とするコードでは、`ansi`を使用しないか、バージョン分岐を行う。

---

## 9. ネイティブコマンド

PowerShell 7では、ネイティブコマンドへの引数渡しに関する動作が、Windows PowerShell 5.1から変更されている。

特に次をテストする。

- 空文字列
- 引用符
- 空白を含むパス
- バックスラッシュ
- JSON
- 正規表現
- OS固有シェルの引数
- Windowsネイティブコマンド
- POSIX系コマンド

### 9-a. PSNativeCommandArgumentPassing

対象バージョンで利用できる場合は、`$PSNativeCommandArgumentPassing`の影響を理解する。

この設定によって、ネイティブコマンドへの引数渡し方法が変わる。

ライブラリやモジュール内部で、このPreference変数を恒久的に変更しない。

一時的に変更する必要がある場合は、元の値を保存し、処理後に復元する。

```powershell
$PreviousArgumentPassing = $PSNativeCommandArgumentPassing

try {
    $PSNativeCommandArgumentPassing = 'Standard'

    & $Command @Arguments
}
finally {
    $PSNativeCommandArgumentPassing = $PreviousArgumentPassing
}
```

### 9-b. PSNativeCommandUseErrorActionPreference

対象バージョンで利用できる場合は、`$PSNativeCommandUseErrorActionPreference`によって、ネイティブコマンドの非ゼロ終了コードをPowerShellエラーとして扱うかを統一できる。

ただし、既存コードのエラー処理へ影響するため、プロジェクト単位で採用方針を決める。

採用しない場合は、従来どおり`$LASTEXITCODE`を明示的に確認する。

---

## 10. Windows PowerShellモジュール互換機能

Windows上のPowerShell 7では、Windows PowerShell 5.1専用モジュールを互換セッション経由で利用できる場合がある。

```powershell
Import-Module `
    -Name ScheduledTasks `
    -UseWindowsPowerShell
```

### 10-a. 使用条件

`-UseWindowsPowerShell`は、PowerShell 7ネイティブで読み込めないモジュールに限定して使用する。

可能であれば、次を優先する。

1. PowerShell 7対応版モジュールを使用する
2. 対応APIやコマンドレットへ置き換える
3. Windows PowerShell 5.1処理を別プロセスへ分離する
4. 最終手段として互換機能を使用する

### 10-b. 制限

互換機能は暗黙的リモート処理を使用するため、返されるオブジェクトは通常、逆シリアル化されたオブジェクトとなる。

したがって、次を前提にしない。

- 元の.NET型が保持される
- インスタンスメソッドを呼び出せる
- イベントを利用できる
- ライブオブジェクトとして変更できる
- ローカルPowerShell 7のオブジェクトと完全に同じ動作をする

互換セッションで一連の処理を完結させ、最終結果だけを返す方法も検討する。

---

## 11. モジュールマニフェスト

PowerShell 7専用モジュールでは、必要に応じて互換エディションを指定する。

```powershell
CompatiblePSEditions = @(
    'Core'
)
```

最低バージョンも指定する。

```powershell
PowerShellVersion = '7.4'
```

Windows PowerShell 5.1との共通モジュールにする場合は、実際に両方でテストしたうえで次のようにする。

```powershell
CompatiblePSEditions = @(
    'Desktop'
    'Core'
)
```

単に構文解析が成功するだけでは、互換性があると判断しない。

---

## 12. PowerShell 7固有レビュー項目

コードレビューでは、共通規約に加えて次を確認する。

- 最低PowerShell 7バージョンが明示されているか
- `pwsh`を対象としているか
- 使用する.NET APIが対象バージョンで利用できるか
- OS固有処理が分離されているか
- パス区切り文字やドライブ文字が不必要に固定されていないか
- ファイル名の大文字と小文字が一致しているか
- PowerShell 7構文が過度に複雑化していないか
- `ForEach-Object -Parallel`の必要性が検証されているか
- `ThrottleLimit`が適切か
- 並列処理で共有状態を安全に扱っているか
- 出力順序へ依存していないか
- 文字コードが連携先と一致しているか
- ネイティブコマンドの引数渡しが対象OSで検証されているか
- Windows PowerShell互換機能への依存が最小限か
- 逆シリアル化オブジェクトの制限を考慮しているか
- 使用するDSCの製品とバージョンが明示されているか
