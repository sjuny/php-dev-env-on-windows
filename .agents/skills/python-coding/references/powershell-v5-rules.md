# PowerShellv5系固有コーディング規約

## 1. 実行環境

### 1-a. 実行ファイル

Windows PowerShell 5.1を明示的に起動する場合は、次の実行ファイルを使用する。

```powershell
powershell.exe
```

PowerShell 7の実行ファイルである`pwsh.exe`と混同しない。

### 1-b. バージョン指定

Windows PowerShell 5.1専用スクリプトでは、必要に応じて実行要件を指定する。

```powershell
#Requires -Version 5.1
```

ただし、`#Requires -Version 5.1`は「5.1以上」を意味するため、それだけではPowerShell 7での実行を除外できない。

Windows PowerShell 5.1でのみ実行可能とする必要がある場合は、エディションを確認する。

```powershell
if ($PSVersionTable.PSEdition -ne 'Desktop') {
    throw 'このスクリプトはWindows PowerShell 5.1専用である。'
}
```

必要に応じて、バージョンも確認する。

```powershell
if (
    $PSVersionTable.PSEdition -ne 'Desktop' -or
    $PSVersionTable.PSVersion.Major -ne 5
) {
    throw 'このスクリプトはWindows PowerShell 5.1専用である。'
}
```

---

## 2. .NET Frameworkへの依存

Windows PowerShell 5.1は.NET Framework上で動作する。

.NET型やメソッドを直接使用する場合は、.NET Frameworkで利用可能なAPIだけを使用する。

```powershell
[System.IO.File]::ReadAllText($Path)
```

PowerShell 7が使用する.NETで追加されたAPIやオーバーロードを、Windows PowerShell 5.1用コードへ使用しない。

.NET APIを直接使用するコードについては、Windows PowerShell 5.1環境で実行テストを行う。

---

## 3. PowerShell 7構文の使用禁止

Windows PowerShell 5.1用コードでは、PowerShell 7以降に追加された構文や機能を使用しない。

### 3-a. 三項演算子

次の三項演算子は使用できない。

```powershell
$Message = $IsEnabled ? 'Enabled' : 'Disabled'
```

`if`文を使用する。

```powershell
if ($IsEnabled) {
    $Message = 'Enabled'
}
else {
    $Message = 'Disabled'
}
```

### 3-b. null合体演算子

次の`??`は使用できない。

```powershell
$Value = $InputValue ?? 'Default'
```

明示的にnullを判定する。

```powershell
if ($null -eq $InputValue) {
    $Value = 'Default'
}
else {
    $Value = $InputValue
}
```

### 3-c. null合体代入演算子

次の`??=`は使用できない。

```powershell
$Value ??= 'Default'
```

代わりに明示的な条件分岐を使用する。

### 3-d. null条件演算子

次の`?.`は使用できない。

```powershell
$Name = $User?.Name
```

null判定を明示する。

```powershell
if ($null -ne $User) {
    $Name = $User.Name
}
```

### 3-e. パイプラインチェーン演算子

次の`&&`および`||`は使用できない。

```powershell
Invoke-Build && Invoke-Test
Invoke-Build || Write-Error 'ビルドに失敗した。'
```

`if`、`$?`または終了コードを使用する。

```powershell
Invoke-Build

if ($?) {
    Invoke-Test
}
```

外部コマンドの場合は、原則として`$LASTEXITCODE`を確認する。

```powershell
& 'build.exe'

if ($LASTEXITCODE -eq 0) {
    Invoke-Test
}
else {
    throw "build.exeが終了コード$LASTEXITCODEで失敗した。"
}
```

---

## 4. 並列処理

Windows PowerShell 5.1では、`ForEach-Object -Parallel`を使用できない。

```powershell
# Windows PowerShell 5.1では使用禁止
$Items | ForEach-Object -Parallel {
    Invoke-ProcessItem -InputObject $_
}
```

並列処理が必要な場合は、要件に応じて次を使用する。

- `Start-Job`
- `Invoke-Command -AsJob`
- Runspace
- ThreadJobモジュール
- ワークフロー。ただし、新規設計では原則として採用しない

並列処理方式は、呼び出し側の状態、変数、モジュール、資格情報が自動的に共有されないことを前提に設計する。

---

## 5. 文字コード

### 5-a. スクリプトファイル

Windows PowerShell 5.1で実行するスクリプトに日本語などの非ASCII文字を含める場合は、原則としてUTF-8 BOMで保存する。

BOMなしUTF-8は、Windows PowerShell 5.1によってシステムのANSIコードページとして解釈される場合がある。

対象には次を含む。

- `.ps1`
- `.psm1`
- `.psd1`
- コメント
- コメントベースヘルプ
- 文字列リテラル

改行コードはLFとする。

### 5-b. ファイル出力

Windows PowerShell 5.1では、コマンドレットによって既定の文字コードが異なるため、ファイル出力時は原則として`-Encoding`を明示する。

```powershell
Set-Content `
    -LiteralPath $Path `
    -Value $Content `
    -Encoding UTF8
```

ただし、Windows PowerShell 5.1の`UTF8`は、UTF-8 BOM付きである。

### 5-c. リダイレクト演算子

Windows PowerShell 5.1の`>`および`>>`は、基本的に`Out-File`と同様に動作し、既定でUTF-16LEを使用する。

文字コード要件があるファイルでは、リダイレクト演算子を使用せず、`Set-Content`、`Add-Content`または`Out-File -Encoding`を使用する。

### 5-d. 追記処理

既存ファイルへ追記する場合は、既存ファイルと同じ文字コードを使用する。

特に`Out-File -Append`および`>>`は、既存ファイルの文字コードへ自動的に一致しない場合があるため注意する。

---

## 6. モジュール互換性

### 6-a. 対象エディション

Windows PowerShell 5.1専用モジュールのマニフェストでは、必要に応じて互換エディションを指定する。

```powershell
CompatiblePSEditions = @(
    'Desktop'
)
```

### 6-b. 最低バージョン

Windows PowerShell 5.1を最低要件とする場合は、マニフェストへ指定する。

```powershell
PowerShellVersion = '5.1'
```

ただし、`PowerShellVersion`だけではPowerShell 7への読み込みを禁止できない。Desktop専用である場合は`CompatiblePSEditions`も使用する。

### 6-c. Windows標準モジュール

Windows標準モジュールを使用する場合は、対象Windowsバージョンとエディションで利用可能かを確認する。

特に次を確認する。

- モジュールがインストールされているか
- 対象コマンドレットが存在するか
- WindowsクライアントとWindows Serverで差がないか
- 必要なWindows機能や役割が有効か
- 32ビットと64ビットで動作差がないか

---

## 7. WMIとCIM

既存システムとの互換性が必要な場合を除き、新規コードではWMIコマンドレットよりCIMコマンドレットを優先する。

優先する例：

```powershell
Get-CimInstance -ClassName Win32_OperatingSystem
```

新規コードで原則として避ける例：

```powershell
Get-WmiObject -Class Win32_OperatingSystem
```

ただし、対象機能や既存環境がWMI固有の動作へ依存する場合は、その理由を記録する。

---

## 8. ネイティブコマンド

Windows PowerShell 5.1では、ネイティブコマンドへ渡す引数が文字列として再構成されるため、空文字列、引用符、末尾のバックスラッシュなどが意図どおり渡らない場合がある。

次の引数を含む場合は、対象コマンドで実際に検証する。

- 空文字列
- 空白を含むパス
- 引用符を含む値
- 末尾が`\`のパス
- 複数階層の引用符
- JSON
- 正規表現
- コマンドライン式

複雑なネイティブコマンド呼び出しは専用関数へ集約する。

```powershell
function Invoke-NativeTool {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter()]
        [string[]]$ArgumentList
    )

    & $FilePath @ArgumentList

    if ($LASTEXITCODE -ne 0) {
        throw "$FilePathが終了コード$LASTEXITCODEで失敗した。"
    }
}
```

---

## 9. 32ビットと64ビット

Windows PowerShell 5.1には、32ビット版と64ビット版が存在する。

次に依存するコードでは、実行プロセスのビット数を確認する。

- レジストリビュー
- COMコンポーネント
- ネイティブDLL
- ODBCドライバー
- システムディレクトリ
- 外部実行ファイル

確認例：

```powershell
[Environment]::Is64BitProcess
[Environment]::Is64BitOperatingSystem
```

64ビット環境を前提とするスクリプトは、起動時に検証する。

```powershell
if (-not [Environment]::Is64BitProcess) {
    throw 'このスクリプトは64ビット版Windows PowerShellで実行する必要がある。'
}
```

---

## 10. Windows PowerShell 5.1固有レビュー項目

コードレビューでは、共通規約に加えて次を確認する。

- `powershell.exe`を対象としているか
- `PSEdition`が`Desktop`であることを前提としているか
- PowerShell 7専用構文が含まれていないか
- `ForEach-Object -Parallel`を使用していないか
- `$IsWindows`などPowerShell 7系自動変数を使用していないか
- .NET Frameworkで利用できないAPIを使用していないか
- 非ASCII文字を含むファイルが適切な文字コードか
- ファイル出力の文字コードが明示されているか
- ネイティブコマンドの引数が実環境で検証されているか
- DSCコードがDSC 1.1を対象としているか
- 32ビットと64ビットの影響を考慮しているか
