@{
    AllNodes = @(
        @{
            NodeName = 'localhost'
            # パスはinstall.ps1でプロジェクトの絶対パスへ解決する。
            ProjectRoot = '.'
            EnvironmentRoot = '.dev-env'
            AssetRoot = '.dev-env-rsrc\assets'
            OutputRoot = '.dev-env-rsrc\outputs'
            NginxPort = 80
            PhpCgiPort = 9000
            MySqlPort = 3306
            MySqlDatabaseName = 'laravel'
            PhpMyAdminPort = 4000
        }
        @{
            NodeName = '*'
        }
    )
}
