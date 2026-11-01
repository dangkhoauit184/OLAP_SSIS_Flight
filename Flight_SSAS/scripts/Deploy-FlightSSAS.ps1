param(
    [string]$SsasServer = 'localhost',
    [string]$DatabaseName = 'Flight_SSAS',
    [string]$SqlServer = '(local)',
    [string]$SqlDatabase = 'Flight_DW',
    [switch]$SkipBuild
)
$ErrorActionPreference = 'Stop'
if ($DatabaseName -notmatch '^Flight_SSAS(?:_Test_[A-Za-z0-9_]+)?$') {
    throw 'This script only deploys Flight_SSAS or a Flight_SSAS_Test_* database.'
}
. (Join-Path $PSScriptRoot 'Initialize-SSASClient.ps1')
Initialize-FlightSSASClient
if (-not $SkipBuild) {
    & (Join-Path $PSScriptRoot 'Build-FlightProject.ps1') -SqlServer $SqlServer -SqlDatabase $SqlDatabase
}
$modelPath = Join-Path $PSScriptRoot '..\bin\Flight_SSAS.asdatabase'
if (-not (Test-Path $modelPath)) { throw 'Build the model first.' }
$server = New-Object Microsoft.AnalysisServices.Server
try {
    $server.Connect("Data Source=$SsasServer;Connect Timeout=20")
    if ($server.ServerMode.ToString() -ne 'Multidimensional') { throw 'The target SSAS instance must run in Multidimensional mode.' }
    $existing=$server.Databases.FindByName($DatabaseName)
    if ($existing -and $existing.Description -notlike 'OLAP_SSIS_Flight:*') {
        throw 'Refusing to replace a database that was not created by this project.'
    }
    $model = New-Object Xml.XmlDocument
    $model.Load($modelPath)
    $model.DocumentElement['ID'].InnerText=$DatabaseName
    $model.DocumentElement['Name'].InnerText=$DatabaseName
    # Utils.Serialize also includes read-only timestamps/states used by SSDT files.
    # They are not part of an XMLA Alter definition accepted by the server.
    $readOnlyNames=@('CreatedTimestamp','LastSchemaUpdate','LastProcessed','LastUpdate','State','CurrentStorageMode','ProcessingState')
    foreach($node in @($model.SelectNodes('//*'))) {
        if($readOnlyNames -contains $node.LocalName) { [void]$node.ParentNode.RemoveChild($node) }
    }
    $safeName=[Security.SecurityElement]::Escape($DatabaseName)
    $xmla='<Alter xmlns="http://schemas.microsoft.com/analysisservices/2003/engine" AllowCreate="true" ObjectExpansion="ExpandFull"><Object><DatabaseID>'+$safeName+'</DatabaseID></Object><ObjectDefinition>'+$model.DocumentElement.OuterXml+'</ObjectDefinition></Alter>'
    $result=$server.Execute($xmla)
    $errors = @()
    foreach($response in $result) {
        foreach($message in $response.Messages) {
            if($message.GetType().Name -eq 'XmlaError') {
                $errors += ($message.Description + ' [code ' + $message.ErrorCode + ', source ' + $message.Source + ']')
            }
        }
    }
    if ($errors.Count) { throw ($errors -join "`n") }
    $server.Refresh()
    $database=$server.Databases.FindByName($DatabaseName)
    $database.Process([Microsoft.AnalysisServices.ProcessType]::ProcessFull)
    Write-Host "Deployed and processed $DatabaseName on $SsasServer."
} finally { if($server.Connected){$server.Disconnect()} }
