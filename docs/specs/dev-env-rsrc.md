# .dev-env-rsrc 環境構築仕様

## 1. 概要

`.dev-env-rsrc`は、`.dev-env`を生成するための構成管理リソースである。

PowerShell DSCを利用して、プロジェクト配下にポータブルな`.dev-env`を構築する。
DSCおよび`install.ps1`は、環境変数、レジストリ、Windowsサービス、PATHなどのOS設定を恒久的に変更しない。

---

## 2. ディレクトリ構成

```text
.dev-env-rsrc/
  configurations/
    initialize.ps1

  configuration-data/
    Development.psd1

  modules/
    DevEnvironment/

  assets/
    nginx/
      nginx-1.30.3.zip
      nginx.conf
      web-app.conf

    php/
      php-8.2.32-nts-Win32-vs16-x64.zip
      php.ini

    phpmyadmin/
      phpMyAdmin-5.2.2-all-languages.zip
      config.inc.php

    mysql/
      mysql-8.4.10-winx64.zip
      my.ini

    scripts/
      start.ps1
      stop.ps1
      status.ps1
      initialize-mysql.ps1

  outputs/
    localhost.mof
    logs/

  install.ps1
```

---

## 3. install.ps1

役割は以下である。

- 前提条件確認
- インストールログ開始
- Configurationコンパイル
- MOF生成
- DSC実行
- nginxドキュメントルート設定
- phpMyAdmin配置とnginxのアクセスポート設定
- MySQL初期化とデータベース作成
- 初期化処理が残したMySQLプロセスの停止
- インストールログ終了

利用者は次を実行する。

```powershell
.\.dev-env-rsrc\install.ps1
```

`install.ps1`は、配置先のプロジェクトルートを解決して`.dev-env`を生成する。

---

## 4. ログ

`install.ps1`はPowerShellの`Start-Transcript`を使用してログを保存する。

保存先は以下である。

```text
.dev-env-rsrc/outputs/logs/
```

ファイル名は以下の形式である。

```text
yyyyMMdd-HHmm_install.log
```

記録内容は、コンソール出力、Verbose出力、DSCログ、エラー、実行開始時刻、実行終了時刻である。

---

## 5. initialize.ps1

環境構築のエントリポイントとなるConfigurationである。

責務は以下である。

- ミドルウェアComposite Resourceの読み込み
- 全体の依存関係定義
- 実行時ディレクトリ作成
- start.ps1、stop.ps1、status.ps1の配置

`initialize-mysql.ps1`はインストール専用であり、`.dev-env`へ配置しない。

---

## 6. modules

ミドルウェアごとにComposite Resourceとして管理する。

```text
modules/
  DevEnvironment/
    DevEnvironment.psd1
    DSCResources/
      NginxEnvironment/
        NginxEnvironment.schema.psm1
      PhpEnvironment/
        PhpEnvironment.schema.psm1
      MySqlEnvironment/
        MySqlEnvironment.schema.psm1
```

---

## 7. Composite Resource

### NginxEnvironment

役割は以下である。

- nginx ZIP展開
- `nginx.conf`配置
- `web-app.conf`配置
- 設定ファイルのSHA-256による内容比較

`web-app.conf`はテンプレートとして管理する。`install.ps1`が
`<プロジェクトルート>/program/public`をドキュメントルートとして生成先へ反映する。

### PhpEnvironment

役割は以下である。

- PHP ZIP展開
- `php.ini`配置

### MySqlEnvironment

役割は以下である。

- MySQL ZIP展開
- `my.ini`配置
- `data`作成
- `logs`作成
- `temp`作成

### PhpMyAdminEnvironment

役割は以下である。

- phpMyAdmin ZIP展開
- ZIP内のバージョン付きルートディレクトリを除去
- `.dev-env/phpmyadmin`への配置
- `config.inc.php`配置

---

## 8. assets

ミドルウェア単位で管理する。各ディレクトリにはZIPと設定ファイルを配置する。

`assets/scripts/initialize-mysql.ps1`は、DSC適用後のMySQLデータディレクトリ初期化と
指定データベース作成に使用するインストール専用スクリプトである。

---

## 9. configuration-data

環境依存値を管理する。

```text
configuration-data/
  Development.psd1
```

主な設定値はプロジェクトルート、`.dev-env`の配置先、nginx・PHP・MySQLのポート番号、
`PhpMyAdminPort`、`MySqlDatabaseName`である。phpMyAdminのアクセスポートは`4000`とする。
`install.ps1`がプロジェクトルートと各配置先を絶対パスへ解決する。

---

## 10. outputs

生成物を保存する。

```text
outputs/
  localhost.mof
  logs/
```

生成物であり、Git管理対象外とする。

---

## 11. 構築処理

```text
install.ps1
      ↓
Start-Transcript
      ↓
initialize.ps1
      ↓
Configurationコンパイル
      ↓
localhost.mof生成
      ↓
Start-DscConfiguration
      ↓
ミドルウェア・設定ファイル・実行スクリプト配置
      ↓
nginxのドキュメントルート・phpMyAdminのアクセスポート設定
      ↓
MySQLデータディレクトリ初期化・データベース作成
      ↓
初期化MySQLプロセス停止
      ↓
Stop-Transcript
```

---

## 12. DSCとinstall.ps1の責務

DSCが行うことは以下である。

- ZIP展開
- 設定ファイル配置
- 設定ファイルの内容比較
- `runtime`作成
- start.ps1、stop.ps1、status.ps1配置

`install.ps1`が行うことは以下である。

- nginx設定の配置先依存パス生成
- phpMyAdminの配置とnginxの`4000`番ポート設定
- phpMyAdminのログインなし設定
- MySQL初期化
- 指定データベース作成
- 初期化処理後のMySQL停止

DSCおよび`install.ps1`が行わないことは以下である。

- nginx、PHP、MySQLのWindowsサービス登録
- レジストリ変更
- システム環境変数変更
- PATH変更
- Laravelセットアップ

---

## 13. ミドルウェアのZIPファイル

- [mysql](https://dev.mysql.com/downloads/mysql/)
- [php](https://www.php.net/downloads.php?os=windows)
- [nginx](https://nginx.org/en/download.html)
- [phpMyAdmin](https://www.phpmyadmin.net/downloads/)
