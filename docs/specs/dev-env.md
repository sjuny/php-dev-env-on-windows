# .dev-env 稼働環境仕様

## 1. 概要

`.dev-env`は、本プロジェクト専用のPHP開発実行環境である。

OSへミドルウェアをインストールせず、プロジェクト配下だけで動作するポータブルな実行環境とする。

特徴は以下のとおりである。

- Windowsサービスを登録しない
- レジストリを変更しない
- システム環境変数を変更しない
- プロジェクト単位で独立した実行環境とする
- 起動・停止はPowerShellスクリプトから行う

---

## 2. ディレクトリ構成

```text
project-root/
  .dev-env/
    nginx/
    php/
    mysql/
    runtime/
    start.ps1
    stop.ps1
    status.ps1

  program/
    public/
```

`.dev-env`に`initialize-mysql.ps1`は配置しない。

---

## 3. nginx

### 配置先

```text
.dev-env/nginx/
```

### 内容

```text
nginx/
  nginx.exe
  conf/
    nginx.conf
    sites/
      web-app.conf
  logs/
  temp/
```

### 役割

- HTTPサーバ
- `program/public`の公開
- PHP-CGIへのFastCGI転送
- Windowsサービスとして動作しない

`web-app.conf`のドキュメントルートは、インストール時に
`<プロジェクトルート>/program/public`へ設定される。

---

## 4. PHP

### 配置先

```text
.dev-env/php/
```

### 内容

```text
php/
  php.exe
  php-cgi.exe
  php.ini
  ext/
```

### 役割

- PHP CLI
- PHP FastCGI
- Composer実行
- Artisan実行

---

## 5. MySQL

### 配置先

```text
.dev-env/mysql/
```

### 内容

```text
mysql/
  bin/
  lib/
  share/
  support-files/
  conf/
    my.ini
  data/
  logs/
  temp/
```

### 役割

- Laravel用データベース
- Windowsサービスとして動作しない
- データは`data`に保存

---

## 6. runtime

```text
.dev-env/runtime/
  nginx.pid
  php.pid
  mysql.pid
```

実行中プロセスのPIDを保存する。PIDファイルを使用して停止・状態確認を行う。

---

## 7. ログ

ミドルウェアのログは、各ミドルウェアのログディレクトリへ保存する。

```text
.dev-env/nginx/logs/
.dev-env/mysql/logs/
```

インストールログは`.dev-env-rsrc/outputs/logs`へ保存する。
`.dev-env/logs`は使用しない。

---

## 8. start.ps1

役割は以下である。

- 起動済みのnginx、PHP、MySQLを停止
- MySQL起動
- PHP-CGI起動
- nginx起動

起動順序は以下である。

```text
既存プロセス停止
      ↓
MySQL
      ↓
PHP-CGI
      ↓
nginx
```

---

## 9. stop.ps1

役割は以下である。

- nginx停止
- PHP-CGI停止
- MySQL停止

停止対象が既に停止していても、エラーにせず処理を継続する。

---

## 10. status.ps1

以下を表示する。

- MySQL状態
- PHP状態
- nginx状態
- HTTP疎通確認

MySQLはデータディレクトリ内のPIDファイル、PHPは`runtime/php.pid`、nginxはプロセス名で状態を確認する。

---

## 11. アプリケーションとの関係

Webアプリケーションの公開ソースは以下に配置する。

```text
project-root/program/public
```

`.dev-env`にはアプリケーションのソースを含めない。

---

## 12. 更新対象

DSCによって更新されるものは以下である。

- nginx
- PHP
- MySQL
- nginx設定ファイル
- PHP設定ファイル
- MySQL設定ファイル
- start.ps1
- stop.ps1
- status.ps1

更新されないものは以下である。

- mysql/data
- mysql/logs
- runtime
- `program/public`配下のソース
- インストール専用の`initialize-mysql.ps1`
