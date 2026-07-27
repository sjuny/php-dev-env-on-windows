@{
    RootModule = 'DevEnvironment.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'f75d77a5-7d1e-46b7-93e0-9b1c23eaeaf4'
    Author = 'Project'
    Description = 'PHP開発環境用のDSC Composite Resourceである。'
    DscResourcesToExport = @(
        'NginxEnvironment',
        'PhpEnvironment',
        'MySqlEnvironment',
        'PhpMyAdminEnvironment'
    )
}
