# スクリプト分析ツール

## 処理概要

- PSScriptAnalyzerを利用して、引数で指定したPowerShellのソースコードをチェックする。
- PSScriptAnalyzerがインストールされているかを処理の前にチェックして、なければインストールする。

```ps1
Install-Module -Name PSScriptAnalyzer -Force
```

- スクリプト名は、analyze-code.ps1
