param([string]$SsasServer='localhost',[string]$DatabaseName='Flight_SSAS',[string]$SqlServer='(local)',[string]$SqlDatabase='Flight_DW')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Initialize-SSASClient.ps1')
Initialize-FlightSSASClient
$sql=New-Object Data.SqlClient.SqlConnection("Data Source=$SqlServer;Initial Catalog=$SqlDatabase;Integrated Security=SSPI;TrustServerCertificate=True")
$sql.Open()
try {
    $cmd=$sql.CreateCommand()
    $cmd.CommandText='SELECT COUNT_BIG(*),SUM(CASE WHEN CANCELLED=0 THEN CAST(1 AS bigint) ELSE 0 END),SUM(CAST(CANCELLED AS bigint)),SUM(CASE WHEN CANCELLED=0 AND ARR_DELAY IS NOT NULL THEN CAST(1 AS bigint) ELSE 0 END),SUM(CASE WHEN CANCELLED=0 AND DEP_DELAY IS NOT NULL THEN CAST(1 AS bigint) ELSE 0 END) FROM dbo.FACT_FLIGHT'
    $reader=$cmd.ExecuteReader();[void]$reader.Read()
    $expected=@();for($i=0;$i-lt5;$i++){$expected+=,$reader.GetValue($i)}
    $reader.Close()
} finally {$sql.Close()}
if($expected[0]-le0){throw 'The source Fact is empty. Run SSIS first.'}
$server=New-Object Microsoft.AnalysisServices.Server
$server.Connect("Data Source=$SsasServer")
try {
    $db=$server.Databases.FindByName($DatabaseName)
    if(-not $db -or $db.State.ToString()-ne 'Processed'){throw 'The SSAS database must be Processed.'}
    foreach($dim in $db.Dimensions){if($dim.State.ToString()-ne 'Processed'){throw ('Unprocessed dimension: '+$dim.Name)}}
    $connection=New-Object Microsoft.AnalysisServices.AdomdClient.AdomdConnection("Data Source=$SsasServer;Initial Catalog=$DatabaseName")
    $connection.Open()
    try {
        $command=$connection.CreateCommand()
        $command.CommandText='SELECT {[Measures].[Total Flights],[Measures].[Operated Flights],[Measures].[Cancelled Flights],[Measures].[Arrival Observations],[Measures].[Departure Observations]} ON 0 FROM [FlightCube]'
        $set=$command.ExecuteCellSet()
        $actual=@();for($i=0;$i-lt5;$i++){$actual+=,$set.Cells[$i].Value;if($actual[$i]-ne$expected[$i]){throw "Cube/SQL mismatch at measure index $i"}}
    } finally {$connection.Close()}
    $report=@{passed=$true;verifiedUtc=[DateTime]::UtcNow.ToString('o');server=$server.Name;version=$server.Version;mode=$server.ServerMode.ToString();database=$DatabaseName;state=$db.State.ToString();databaseDimensions=$db.Dimensions.Count;cubeDimensions=$db.Cubes['FlightCube'].Dimensions.Count;baseMeasures=$db.Cubes['FlightCube'].MeasureGroups['FlightFacts'].Measures.Count;measureOrder=@('Total Flights','Operated Flights','Cancelled Flights','Arrival Observations','Departure Observations');sqlTotals=$expected;cubeTotals=$actual}
    $report|ConvertTo-Json -Depth 6|Set-Content -Encoding UTF8 (Join-Path $PSScriptRoot '..\results\runtime_validation.json')
    Write-Host 'PASS: all dimensions Processed; five cube totals match SQL exactly.'
} finally {$server.Disconnect()}
