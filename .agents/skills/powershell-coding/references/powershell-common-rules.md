# PowerShell共通コーディング規約

本規約は、Windows PowerShell 5.1およびPowerShell 7で共通して適用するPowerShellコードの記述規則を定める。

## 1. 命名規則

### 1-a. 関数名

- 公開関数は、次の形式で命名する。

```powershell
# 凡例
Verb-Noun
# 例
Get-ApplicationConfig
```

### 1-b. 関数名の動詞

- 動詞には、PowerShellの承認済み動詞を使用する。
- 承認済み動詞は、次のコマンドで確認できる。

```powershell
Get-Verb
```

- 独自の動詞、意味が曖昧な動詞、動作を正確に表さない動詞は使用しない。

不適切な例：

```powershell
Fetch-ApplicationConfig
Delete-ApplicationCache
Make-ApplicationDirectory
```

適切な例：

```powershell
Get-ApplicationConfig
Remove-ApplicationCache
New-ApplicationDirectory
```

### 1-c. 関数名の名詞

- 関数名の名詞部分は、原則として単数形とし、複数形は使用しない。

```powershell
# 適切な例
Get-User
# 不適切な例
Get-Users
```

- 関数が複数のオブジェクトを返す場合でも、関数名の名詞は単数形とする。

### 1-d. 命名形式

識別子は次の形式に統一する。

- 関数名以外の名前の形式はPascalCaseとする。。
- PowerShellでは変数名の大文字と小文字は通常区別されないが、表記は統一する。

```powershell
パラメーター：`ComputerName`
変数：`$ApplicationPath`
定数相当の変数：`$DefaultTimeoutSeconds`
クラス：`ApplicationConfig`
列挙型：`ApplicationState`
モジュール：`ApplicationManagement`
```

---

## 2. 関数設計

### 2-a. 公開関数は高度な関数とする

外部から利用する公開関数は、原則として高度な関数として定義する。

```powershell
function Get-ApplicationConfig {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )

    # 処理
}
```

`[CmdletBinding()]`を指定することで、次の共通パラメーターなどを利用できる。

- `-Verbose`
- `-Debug`
- `-ErrorAction`
- `-WarningAction`
- `-InformationAction`
- `-ErrorVariable`
- `-WarningVariable`

### 2-b. 実行起点の関数

- スクリプト単体で動くプログラムの場合は、実行起点となるmain関数を定義し、そこに処理の全体の流れがわかるように処理を定義する。
- 関数名は`Invoke-Main`とする。
- `Invoke-Main`内では例外を捕捉し、エラー内容を表示する。
- `Invoke-Main`の呼び出し時は、1行だけとする。
- 他のモジュールから呼び出される関数を定義したスクリプトにはmain関数は不要。
- `Invoke-Main`は、returnではなく、exitで定数化されたステータスコードを呼び出し元に返却する。
  - 例：`exit SUCUCESS`

### 2-c. 関数やメソッドのコメント位置

- 関数のコメントは**必ず**、functionブロックの外側に記載する。
  - PowerShellのコメントベースヘルプ形式で関数のコメントは記載。

---

## 3. ShouldProcess

### 3-a. 状態変更関数

システム、ファイル、設定、サービスなどの状態を変更する公開関数は、原則として`ShouldProcess`に対応する。

```powershell
function Remove-ApplicationCache {
    [CmdletBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = 'Medium'
    )]
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )

    if ($PSCmdlet.ShouldProcess($Path, 'キャッシュを削除する')) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
}
```

これにより、次の共通パラメーターを利用できる。

```powershell
Remove-ApplicationCache -Path 'C:\App\cache' -WhatIf
Remove-ApplicationCache -Path 'C:\App\cache' -Confirm
```

### 3-b. ShouldProcessの対象

少なくとも次の処理では、`ShouldProcess`の適用を検討する。

- ファイルまたはディレクトリの作成、変更、削除
- レジストリの変更
- サービスの開始、停止、登録、削除
- プロセスの終了
- ユーザーや権限の変更
- システム設定の変更
- データベースレコードの更新または削除
- 外部システムへの更新要求

### 3-c. ShouldProcessの呼び出し

`SupportsShouldProcess = $true`を指定した関数では、実際の変更処理前に`$PSCmdlet.ShouldProcess()`を呼び出す。

属性だけを指定して、`ShouldProcess()`を呼び出さない実装は禁止する。これはPSScriptAnalyzerの検査対象でもある。

---

## 4. パラメーター設計

### 4-a. パラメーター名

パラメーター名は、既存のPowerShellコマンドレットで使用されている標準的な名称を優先する。

例：

```powershell
-Path
-LiteralPath
-Name
-ComputerName
-Credential
-Force
-Filter
-InputObject
-TimeoutSeconds
```

同じ意味に独自名称を付けない。

不適切な例：

```powershell
-FileLocation
-LoginInfo
-WaitTime
```

### 4-b. 必須パラメーター

省略できない値には`Mandatory`を指定する。

```powershell
[Parameter(Mandatory)]
[string]$Path
```

対話入力を前提とせず、非対話実行でも利用できる設計とする。

### 4-c. 型指定

入力値の種類が明確な場合は、適切な型を指定する。

```powershell
[string]$Path
[int]$TimeoutSeconds
[bool]$Force
[System.Management.Automation.PSCredential]$Credential
```

ただし、必要以上に具体的な型を指定し、利用可能な入力を不当に制限しない。

### 4-d. 検証属性

入力値の制約は、可能な限り検証属性で表現する。

```powershell
[ValidateNotNullOrEmpty()]
[string]$Path

[ValidateRange(1, 3600)]
[int]$TimeoutSeconds

[ValidateSet('Development', 'Staging', 'Production')]
[string]$Environment
```

検証可能な値を関数本体の複雑な`if`文だけで判定しない。

### 4-e. SwitchParameter

有効または無効を指定するオプションには、原則として`[switch]`を使用する。

```powershell
[switch]$Force
[switch]$PassThru
[switch]$Recurse
```

次のようなBoolean値の明示指定は、特別な理由がない限り避ける。

```powershell
[bool]$Force
```

### 4-f. パラメーターセット

異なる呼び出し方法を提供する場合は、パラメーターセットを使用する。

```powershell
function Get-Application {
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    param (
        [Parameter(
            Mandatory,
            ParameterSetName = 'ByName'
        )]
        [string]$Name,

        [Parameter(
            Mandatory,
            ParameterSetName = 'ById'
        )]
        [int]$Id
    )
}
```

相互に排他的なパラメーターの組み合わせを、関数内部の条件分岐だけで管理しない。

### 4-g. パイプライン入力

オブジェクトを連続して処理することが自然な関数は、パイプライン入力への対応を検討する。

```powershell
[Parameter(
    Mandatory,
    ValueFromPipeline
)]
[System.IO.FileInfo]$InputObject
```

プロパティ名による入力が適切な場合は、次を使用する。

```powershell
[Parameter(ValueFromPipelineByPropertyName)]
[string]$Name
```

すべての関数を機械的にパイプライン対応にする必要はない。

---

## 5. Begin、Process、End

パイプライン入力に対応する関数では、必要に応じて`begin`、`process`、`end`を使い分ける。

```powershell
function Get-FileHashSummary {
    [CmdletBinding()]
    param (
        [Parameter(
            Mandatory,
            ValueFromPipeline
        )]
        [System.IO.FileInfo]$InputObject
    )

    begin {
        $ProcessedCount = 0
    }

    process {
        $ProcessedCount++

        Get-FileHash -LiteralPath $InputObject.FullName
    }

    end {
        Write-Verbose "処理件数: $ProcessedCount"
    }
}
```

用途は次のとおりである。

| ブロック  | 用途                                   |
| --------- | -------------------------------------- |
| `begin`   | 初期化処理                             |
| `process` | パイプラインから受け取った各入力の処理 |
| `end`     | 終了処理、集計、リソース解放           |

パイプライン入力を受け取らない関数で、形式だけを整える目的で使用しない。

---

## 6. 出力設計

### 6-a. 成功出力

関数の通常の処理結果は、文字列ではなくオブジェクトとして返す。

適切な例：

```powershell
[pscustomobject]@{
    Name   = $Name
    Path   = $Path
    Status = $Status
}
```

不適切な例：

```powershell
"$Name : $Path : $Status"
```

オブジェクトとして返すことで、呼び出し側は次の処理を行える。

- フィルター
- ソート
- CSVやJSONへの変換
- プロパティの選択
- 表示形式の変更
- 他のコマンドへのパイプライン入力

### 6-b. 暗黙出力

成功出力を返すだけの場合、`Write-Output`を明示する必要はない。

```powershell
$result
```

次の記述も可能であるが、必須ではない。

```powershell
Write-Output -InputObject $result
```

### 6-c. 意図しない出力

PowerShellでは、代入、メソッド呼び出し、外部コマンドなどが意図せず成功ストリームへ出力される場合がある。

戻り値が不要な処理は、明示的に破棄する。

```powershell
$null = New-Item -ItemType Directory -Path $Path

[void]$List.Add($Item)

New-Item -ItemType Directory -Path $Path | Out-Null
```

原則として、代入または`[void]`による破棄を優先する。

### 6-d. Formatコマンド

再利用可能な関数やモジュール内部では、次のコマンドを通常出力へ使用しない。

- `Format-Table`
- `Format-List`
- `Format-Wide`
- `Format-Custom`

`Format-*`は表示専用の書式オブジェクトへ変換するため、後続処理で元のオブジェクトとして扱いにくくなる。

表示整形は、原則として呼び出し側へ委ねる。

### 6-e. OutputType

公開関数は、戻り値の型を示すために`OutputType`属性の指定を検討する。

```powershell
[OutputType([System.IO.FileInfo])]
```

ただし、`OutputType`はドキュメントおよびツール向けのメタデータであり、実行時に戻り値の型を強制するものではない。

---

## 7. 出力ストリームとログ

PowerShellの出力は、目的に応じてストリームを使い分ける。成功出力と診断メッセージを同じストリームへ混在させない。

PowerShellにはSuccess、Error、Warning、Verbose、Debug、Informationなどのストリームがある。

### 7-a. ストリームの用途

| コマンド                 | 用途                       |
| ------------------------ | -------------------------- |
| 暗黙出力／`Write-Output` | 呼び出し側へ返す処理結果   |
| `Write-Error`            | エラー情報                 |
| `Write-Warning`          | 処理を継続できる警告       |
| `Write-Verbose`          | 利用者向けの詳細な実行情報 |
| `Write-Debug`            | 開発者向けのデバッグ情報   |
| `Write-Information`      | 一般的な情報メッセージ     |
| `Write-Progress`         | 長時間処理の進捗           |
| `Write-Host`             | ホスト画面へ直接示すUI表示 |

### 7-b. Write-Verbose

詳細な処理状況は`Write-Verbose`へ出力する。

```powershell
Write-Verbose "設定ファイルを読み込む: $Path"
```

利用者は`-Verbose`で出力を制御できる。

```powershell
Get-ApplicationConfig -Path $Path -Verbose
```

### 7-c. Write-Debug

内部状態や開発者向けの診断情報は`Write-Debug`へ出力する。

```powershell
Write-Debug "取得した設定件数: $($Items.Count)"
```

機密情報をデバッグ出力へ含めない。

### 7-d. Write-Information

処理結果ではない一般情報には`Write-Information`を使用する。

```powershell
Write-Information 'アプリケーションの初期化を開始する。'
```

### 7-e. Write-Warning

処理を継続できるが、利用者の注意が必要な状態には`Write-Warning`を使用する。

```powershell
Write-Warning '設定ファイルが存在しないため、既定値を使用する。'
```

### 7-f. Write-Host

`Write-Host`は全面的に禁止しないが、再利用可能な処理結果、ログ、診断情報には使用しない。

`Write-Host`を使用できるのは、次のようなホスト画面向けUIに限定する。

- 対話型メニュー
- 色付きの画面表示
- 利用者へ直接示す操作案内
- 他のストリームへ流す必要がない表示

PowerShell 5.0以降、`Write-Host`はInformationストリームを利用するが、通常の`Write-Information`とは表示制御が異なるため、用途を区別する。

### 7-g. Preference変数

次のPreference変数の影響を理解する。

- `$ErrorActionPreference`
- `$WarningPreference`
- `$VerbosePreference`
- `$DebugPreference`
- `$InformationPreference`
- `$ProgressPreference`
- `$ConfirmPreference`
- `$WhatIfPreference`

共有モジュールまたはライブラリ関数の内部で、呼び出し元のPreference変数を恒久的に変更しない。

必要な場合は、コマンド単位の共通パラメーターを優先する。

```powershell
Get-Item -LiteralPath $Path -ErrorAction Stop
```

---

## 8. エラー処理

### 8-a. エラーを無視しない

エラーを意図せず継続させない。

処理を継続できない箇所では、終了エラーとして処理する。

```powershell
Get-Item -LiteralPath $Path -ErrorAction Stop
```

### 8-b. try、catch、finally

`try`と`catch`は、終了エラーを捕捉する。非終了エラーを確実に捕捉する必要がある場合は、対象コマンドに`-ErrorAction Stop`を指定する。

```powershell
try {
    $Item = Get-Item -LiteralPath $Path -ErrorAction Stop
}
catch {
    Write-Error -ErrorRecord $_
}
```

### 8-c. エラー情報を保持する

捕捉したエラーを再通知する場合は、元のエラー情報を失わないようにする。

```powershell
catch {
    Write-Error -ErrorRecord $_
}
```

処理を継続できない場合は再スローする。

```powershell
catch {
    Write-Error "設定ファイルの読み込みに失敗した: $Path"
    throw
}
```

`throw`だけを使用すると、捕捉した元の例外を再スローできる。

### 8-d. エラーメッセージ

エラーメッセージには、問題の特定に必要な情報を含める。

- 何の処理に失敗したか
- 対象は何か
- 必要に応じて、どの値が問題だったか
- 利用者が実施できる対処

ただし、次の情報は出力しない。

- パスワード
- APIキー
- アクセストークン
- 秘密鍵
- 接続文字列内の認証情報

### 8-e. finally

リソース解放や後処理が必要な場合は`finally`を使用する。

```powershell
$Stream = $null

try {
    $Stream = [System.IO.File]::OpenRead($Path)

    # 処理
}
finally {
    if ($null -ne $Stream) {
        $Stream.Dispose()
    }
}
```

`finally`は、処理の成功、失敗にかかわらず実行される。

---

## 9. セキュリティ

### 9-a. Invoke-Expression

`Invoke-Expression`は原則として使用禁止とする。

```powershell
Invoke-Expression $CommandText
```

文字列として組み立てたコードを実行すると、次の問題が発生しやすい。

- コードインジェクション
- クォート処理の不具合
- 静的解析の困難化
- デバッグの困難化
- 引数境界の消失

コマンド名が変数の場合は、呼び出し演算子を使用する。

```powershell
& $CommandName @Arguments
```

### 9-b. 資格情報

資格情報を受け取る場合は、原則として`PSCredential`を使用する。

```powershell
[Parameter(Mandatory)]
[System.Management.Automation.PSCredential]$Credential
```

### 9-c. SecureString

`SecureString`を使用しているだけで、すべての環境で秘密情報が安全になるとはみなさない。

保管方法、プロセス境界、OS、実行ユーザー、暗号化方法を含めて設計する。

### 9-d. 外部入力

次の外部入力は信頼しない。

- コマンドライン引数
- 環境変数
- 設定ファイル
- API応答
- CSV、JSON、XML
- ファイル名とパス
- 利用者入力

入力値を検証し、外部コマンド、SQL、パス、正規表現などへ安全に渡す。

### 9-e. 実行ポリシー

通常のアプリケーションスクリプトから、システムや利用者の実行ポリシーを恒久的に変更しない。

```powershell
Set-ExecutionPolicy
```

実行ポリシー変更が必要な場合は、導入手順または管理手順として分離する。

### 9-f. コード署名

組織内または外部へ配布するスクリプトについては、コード署名の適用を検討する。

特に次の場合は署名を推奨する。

- `AllSigned`環境で実行する
- 管理者権限で実行する
- 複数端末へ配布する
- インターネット経由で配布する
- システム設定を変更する

---

## 10. 可読性と書式

### 10-a. インデント

インデントはスペース4文字とする。

```powershell
if ($IsEnabled) {
    Start-Application

    if ($ShouldWait) {
        Wait-Application
    }
}
```

タブ文字とスペースを混在させない。

### 10-b. 波括弧

開始波括弧は、制御文または宣言と同じ行に記述する。

```powershell
if ($Condition) {
    # 処理
}
```

閉じ波括弧は独立した行に記述する。

### 10-c. 1行1文

原則として、1行に複数の処理を記述しない。

不適切な例：

```powershell
$Name = 'App'; $Path = 'C:\App'; Start-Application
```

適切な例：

```powershell
$Name = 'App'
$Path = 'C:\App'

Start-Application
```

### 10-d. 演算子周辺の空白

演算子の前後に空白を入れる。

```powershell
$Count = $Items.Count + 1

if ($Count -gt 0) {
    # 処理
}
```

### 10-e. 長いコマンド

長いコマンドは、パラメーター単位で改行する。

```powershell
Copy-Item `
    -LiteralPath $SourcePath `
    -Destination $DestinationPath `
    -Recurse `
    -Force
```

ただし、バックティックによる行継続は壊れやすいため、可能な限りスプラッティングを優先する。

```powershell
$CopyItemParameters = @{
    LiteralPath = $SourcePath
    Destination = $DestinationPath
    Recurse     = $true
    Force       = $true
}

Copy-Item @CopyItemParameters
```

### 10-f. バックティック

行継続を目的としたバックティックの使用は原則として避ける。

バックティックの直後に空白が入ると、行継続として機能しないためである。

次の自然な改行またはスプラッティングを使用する。

- 丸括弧
- 配列
- ハッシュテーブル
- スクリプトブロック
- パイプライン
- スプラッティング

### 10-g. スプラッティング

パラメーターが多い場合、条件によってパラメーターを変更する場合、または同一引数を再利用する場合は、スプラッティングを使用する。

```powershell
$Parameters = @{
    Path        = $Path
    Filter      = '*.log'
    ErrorAction = 'Stop'
}

Get-ChildItem @Parameters
```

### 10-h. エイリアス

保存するスクリプトおよびモジュールでは、コマンドエイリアスを使用しない。

使用しない例：

```powershell
gci
ls
cat
%
?
select
sort
```

正式なコマンド名を使用する。

```powershell
Get-ChildItem
Get-Content
ForEach-Object
Where-Object
Select-Object
Sort-Object
```

パラメーターの省略形も原則として使用しない。

```powershell
Get-ChildItem -Recurse
```

次のような省略は避ける。

```powershell
Get-ChildItem -r
```

### 10-i. コマンド引数

位置指定に依存せず、原則としてパラメーター名を明示する。

```powershell
Get-Content -LiteralPath $Path
```

次のような記述は避ける。

```powershell
Get-Content $Path
```

ただし、極めて一般的で意味が明確なコマンドについて、プロジェクトで例外を定めてもよい。

### 10-j. LiteralPathとPath

ワイルドカードとして解釈すべきでないパスには、`-LiteralPath`を使用する。

```powershell
Get-Item -LiteralPath $Path
Remove-Item -LiteralPath $Path
```

ワイルドカード検索を意図する場合にだけ`-Path`を使用する。

---

## 11. 変数とスコープ

### 11-a. 変数の初期化

変数は使用前に初期化する。

```powershell
$Items = @()
$Result = $null
$RetryCount = 0
```

### 11-b. 変数の範囲

変数の有効範囲は必要最小限にする。

関数内でのみ使用する値を、スクリプトスコープやグローバルスコープへ置かない。

### 11-c. Globalスコープ

`Global`スコープの使用は原則として禁止する。

```powershell
$Global:ApplicationPath = 'C:\App'
```

共有状態が必要な場合は、次の方法を検討する。

- 関数パラメーター
- 戻り値
- モジュールのスクリプトスコープ
- 設定オブジェクト
- クラスのプロパティ

### 11-d. Scriptスコープ

モジュール内で共有する内部状態には、必要に応じて`$script:`を使用できる。

```powershell
$script:ModuleConfiguration = $null
```

使用箇所と変更箇所を限定する。

### 11-e. 環境変数

環境変数は、PowerShellの環境変数プロバイダーを使用して参照する。

```powershell
$env:TEMP
$env:PATH
```

関数内部でプロセス外へ影響する環境変数変更を行う場合は、副作用を明記する。

---

## 12. 比較とnull判定

### 12-a. nullは左辺に置く

null判定では、`$null`を比較演算子の左辺に置く。

```powershell
if ($null -eq $Value) {
    # 処理
}
```

次の記述は避ける。

```powershell
if ($Value -eq $null) {
    # 処理
}
```

配列が左辺にある場合、PowerShellの比較演算子が配列要素を返す可能性があるためである。

### 12-b. 文字列の空判定

nullまたは空文字列を判定する場合は、意図を明確にする。

```powershell
if ([string]::IsNullOrEmpty($Value)) {
    # 処理
}
```

空白だけの文字列も無効とする場合は、次を使用する。

```powershell
if ([string]::IsNullOrWhiteSpace($Value)) {
    # 処理
}
```

### 12-c. 真偽値の比較

Boolean値を`$true`または`$false`と冗長に比較しない。

```powershell
if ($IsEnabled) {
    # 処理
}

if (-not $IsEnabled) {
    # 処理
}
```

---

## 13. コレクションとパイプライン

### 13-a. パイプラインを過度に複雑化しない

短く、処理の流れが明確な場合はパイプラインを使用する。

```powershell
Get-ChildItem -LiteralPath $LogPath -File |
    Where-Object LastWriteTime -lt $Threshold |
    Remove-Item -WhatIf
```

条件分岐、複数の副作用、複雑なエラー処理が含まれる場合は、`foreach`文などへ分割する。

### 13-b. ForEach-Objectとforeach

単純なパイプライン処理には`ForEach-Object`を使用できる。

複雑な処理、性能が重要な処理、途中での制御が必要な処理には`foreach`文を検討する。

### 13-c. +=による大量配列追加

大量の要素を配列へ追加する処理では、`+=`の反復使用を避ける。

```powershell
$Results = foreach ($Item in $Items) {
    Get-ItemResult -InputObject $Item
}
```

PowerShellの出力収集機能を利用する。

---

## 14. コメントベースヘルプ

公開関数および利用者が直接実行するスクリプトには、コメントベースヘルプを記述する。

最低限、次の項目を含める。

- `.SYNOPSIS`
- `.DESCRIPTION`
- `.PARAMETER`
- `.EXAMPLE`

必要に応じて次も記述する。

- `.INPUTS`
- `.OUTPUTS`
- `.NOTES`
- `.LINK`

例：

```powershell
function Get-ApplicationConfig {
    <#
    .SYNOPSIS
    アプリケーション設定を取得する。

    .DESCRIPTION
    指定されたJSONファイルを読み込み、
    アプリケーション設定オブジェクトとして返す。

    .PARAMETER Path
    読み込む設定ファイルのパス。

    .EXAMPLE
    Get-ApplicationConfig -Path 'C:\App\config.json'

    .OUTPUTS
    System.Management.Automation.PSCustomObject
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )
}
```

`.EXAMPLE`は、公開関数ごとに最低1件記述する。

---

## 15. 実行要件

実行に必要な条件は、`#Requires`で明示する。

例：

```powershell
#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
#Requires -RunAsAdministrator
```

ただし、Windows PowerShell 5.1とPowerShell 7の両方で実行する共通コードでは、必要以上に高いPowerShellバージョンを指定しない。

`#Requires -RunAsAdministrator`は、本当にスクリプト全体で管理者権限が必要な場合だけ使用する。

---

## 16. モジュール設計

### 16-a. 公開APIと内部実装

公開関数と内部関数を区別する。

公開する必要がない補助関数は、モジュール外へ公開しない。

一般的な構成例：

```text
ApplicationManagement/
├── ApplicationManagement.psd1
├── ApplicationManagement.psm1
├── Public/
│   ├── Get-Application.ps1
│   └── Set-Application.ps1
└── Private/
    ├── Read-ApplicationConfig.ps1
    └── Test-ApplicationPath.ps1
```

`Public`／`Private`構成はPowerShellが要求する標準構造ではなく、プロジェクト上の整理方法として採用する。

### 16-b. モジュールマニフェスト

配布または再利用するモジュールには、原則としてモジュールマニフェストを作成する。

モジュールマニフェストでは、モジュールの属性、前提条件、互換性、読み込み方法、公開要素などを定義できる。

主に次を定義する。

```powershell
@{
    RootModule        = 'ApplicationManagement.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '00000000-0000-0000-0000-000000000000'
    Author            = 'Example'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-Application'
        'Set-Application'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
```

### 16-c. 公開要素

公開する関数、コマンドレット、変数、エイリアスを明示する。

ワイルドカードによる無制限な公開は避ける。

```powershell
FunctionsToExport = @(
    'Get-Application'
    'Set-Application'
)
```

### 16-d. Export-ModuleMember

スクリプトモジュールでは、公開する関数を`Export-ModuleMember`で明示できる。

```powershell
Export-ModuleMember -Function @(
    'Get-Application'
    'Set-Application'
)
```

マニフェストと`Export-ModuleMember`の両方を使用する場合は、公開対象が一致するよう管理する。

### 16-e. モジュールインポート時の副作用

モジュールのインポート時に、次の処理を無断で実行しない。

- ファイルの作成や削除
- ネットワーク通信
- サービスの開始や停止
- システム設定の変更
- 大量のログ出力
- 長時間処理

モジュール読み込み時には、関数、クラス、変数などの定義と必要最小限の初期化だけを行う。

---

### 17-a. ファイル名

スクリプトファイル名は、その主要な処理を表す名前にする。

```text
Install-Application.ps1
Start-Application.ps1
ApplicationManagement.psm1
ApplicationManagement.psd1
```

汎用的すぎる名前は避ける。

```text
script.ps1
main.ps1
common.ps1
util.ps1
```

ただし、プロジェクトの明確なエントリーポイントとして`main.ps1`などを採用する場合は、役割を設計書で定義する。

---

## 18. 外部コマンド

### 18-a. 引数を文字列結合しない

外部コマンドの引数を、実行コード全体の文字列として組み立てない。

不適切な例：

```powershell
$Command = "tool.exe --path `"$Path`" --name `"$Name`""
Invoke-Expression $Command
```

引数を分離して渡す。

```powershell
$Arguments = @(
    '--path'
    $Path
    '--name'
    $Name
)

& 'tool.exe' @Arguments
```

### 18-b. 終了コード

外部コマンドの成功または失敗を判定する場合は、終了コードを確認する。

```powershell
& 'tool.exe' @Arguments

if ($LASTEXITCODE -ne 0) {
    throw "tool.exeが終了コード$LASTEXITCODEで失敗した。"
}
```

終了コードの意味は、対象コマンドの仕様に従う。

### 18-c. 標準出力と標準エラー

外部コマンドの標準出力と標準エラーを、PowerShellの成功出力およびエラー処理と同一視しない。

必要に応じて、外部コマンドを専用関数でラップし、次を統一する。

- 引数の渡し方
- 終了コードの確認
- 標準出力の解析
- 標準エラーの記録
- タイムアウト
- リトライ

---

## 19. 設定ファイル

プロジェクト固有の設定は、設定ファイルとして管理する。

```text
PSScriptAnalyzerSettings.psd1
```

例：

```powershell
@{
    Severity = @(
        'Error'
        'Warning'
    )

    IncludeRules = @(
        'PSAvoidUsingCmdletAliases'
        'PSAvoidUsingPlainTextForPassword'
        'PSAvoidUsingInvokeExpression'
        'PSUseApprovedVerbs'
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
```
