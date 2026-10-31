param(
    [string]$SqlServer = '(local)',
    [string]$SqlDatabase = 'Flight_DW',
    [string]$ProjectDirectory = (Split-Path $PSScriptRoot -Parent)
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Initialize-SSASClient.ps1')
Initialize-FlightSSASClient
$ProjectDirectory = [IO.Path]::GetFullPath($ProjectDirectory)
$utf8 = New-Object Text.UTF8Encoding($false)
$bin = Join-Path $ProjectDirectory 'bin'
[void](New-Item -ItemType Directory -Path $bin -Force)

$db = New-Object Microsoft.AnalysisServices.Database
$db.ID = 'Flight_SSAS'; $db.Name = 'Flight_SSAS'
$db.Description = 'OLAP_SSIS_Flight: 2024 flight analysis; source rows are not synthesized.'
$db.Language = 1033
$ds = $db.DataSources.Add('Flight DW', 'Flight_DW')
$builder = New-Object System.Data.OleDb.OleDbConnectionStringBuilder
$builder['Provider']='MSOLEDBSQL'; $builder['Data Source']=$SqlServer
$builder['Initial Catalog']=$SqlDatabase; $builder['Integrated Security']='SSPI'
$builder['Trust Server Certificate']=$true
$ds.ConnectionString = $builder.ConnectionString
$ds.ImpersonationInfo = New-Object Microsoft.AnalysisServices.ImpersonationInfo
$ds.ImpersonationInfo.ImpersonationMode = [Microsoft.AnalysisServices.ImpersonationMode]::ImpersonateServiceAccount
$ds.Timeout = [TimeSpan]::FromMinutes(5)
$dsv = $db.DataSourceViews.Add('Flight DW', 'Flight_DW')
$dsv.DataSourceID = $ds.ID
$dsv.Schema = New-Object System.Data.DataSet 'FlightDW'
$dsv.Schema.Locale = [Globalization.CultureInfo]::GetCultureInfo('en-US')
$dsv.Schema.EnforceConstraints = $false
$connection = New-Object System.Data.SqlClient.SqlConnection
$connection.ConnectionString = "Data Source=$SqlServer;Initial Catalog=$SqlDatabase;Integrated Security=SSPI;TrustServerCertificate=True"
$connection.Open()
try {
    # Read schema only. All transformations remain Named Queries in the DSV.
    $primaryKeys = [ordered]@{DimDate='DATE_ID';DimCarrier='CARRIER_ID';DimAirport='AIRPORT_ID';DimTime='TIME_ID';DimCancellation='CANCELLATION_ID';DimRoute='ROUTE_KEY';DimStatus='STATUS_KEY';FactFlight='FLIGHT_ID'}
    foreach ($tableName in $primaryKeys.Keys) {
        $query = [IO.File]::ReadAllText((Join-Path $ProjectDirectory "model\$tableName.sql"), [Text.Encoding]::UTF8).Trim().TrimEnd(';')
        $adapter = New-Object System.Data.SqlClient.SqlDataAdapter("SELECT TOP (0) * FROM ($query) AS SchemaOnly", $connection)
        [void]$adapter.FillSchema($dsv.Schema, [Data.SchemaType]::Mapped, $tableName)
        $table = $dsv.Schema.Tables[$tableName]
        $table.PrimaryKey = [Data.DataColumn[]]@($table.Columns[$primaryKeys[$tableName]])
        $table.ExtendedProperties['TableType']='View'
        $table.ExtendedProperties['QueryDefinition']=$query
        $table.ExtendedProperties['FriendlyName']=$tableName
        $table.ExtendedProperties['DbTableName']=$tableName
        foreach ($column in $table.Columns) { $column.ExtendedProperties['DbColumnName']=$column.ColumnName }
        $adapter.Dispose()
    }
    $check = $connection.CreateCommand()
    $check.CommandText = 'SELECT COUNT(*) FROM (SELECT ORIGIN_AIRPORT_ID,DEST_AIRPORT_ID FROM dbo.FACT_FLIGHT GROUP BY ORIGIN_AIRPORT_ID,DEST_AIRPORT_ID HAVING MIN(DISTANCE)<>MAX(DISTANCE)) r'
    if ([int]$check.ExecuteScalar() -ne 0) { throw 'A route has multiple distances. Review the route grain before building.' }
    $check.CommandText = "SELECT COUNT(*) FROM dbo.DIM_AIRPORT WHERE CITY_NAME IS NULL OR LEN(RTRIM(CITY_NAME))<5 OR SUBSTRING(RTRIM(CITY_NAME),LEN(RTRIM(CITY_NAME))-3,2)<>', '"
    if ([int]$check.ExecuteScalar() -ne 0) { throw 'Airport city names must end in a valid comma and state/territory code.' }
    $referenceQuery=$dsv.Schema.Tables['DimAirport'].ExtendedProperties['QueryDefinition']
    $check.CommandText="SELECT (SELECT COUNT(*) FROM dbo.DIM_AIRPORT)-(SELECT COUNT(*) FROM ($referenceQuery) a)"
    if ([int]$check.ExecuteScalar() -ne 0) { throw 'An airport is missing from reference/airport_states.csv. Refresh the state lookup from the original dataset.' }
} finally { $connection.Close(); $connection.Dispose() }

foreach ($mapping in @(
    @('DimDate','DATE_ID','DATE_ID'),@('DimCarrier','CARRIER_ID','CARRIER_ID'),
    @('DimAirport','AIRPORT_ID','ORIGIN_AIRPORT_ID'),@('DimAirport','AIRPORT_ID','DEST_AIRPORT_ID'),
    @('DimTime','TIME_ID','DEP_TIME_ID'),@('DimCancellation','CANCELLATION_ID','CANCELLATION_ID'),
    @('DimRoute','ROUTE_KEY','ROUTE_KEY'),@('DimStatus','STATUS_KEY','CANCELLED')
)) {
    [void]$dsv.Schema.Relations.Add(('FK_'+$mapping[2]),$dsv.Schema.Tables[$mapping[0]].Columns[$mapping[1]],$dsv.Schema.Tables['FactFlight'].Columns[$mapping[2]],$false)
}

function New-DataItem([string]$table,[string]$column) {
    $c=$dsv.Schema.Tables[$table].Columns[$column]
    $type=switch ($c.DataType.FullName) {
        'System.Int16' {[Data.OleDb.OleDbType]::SmallInt}
        'System.Int32' {[Data.OleDb.OleDbType]::Integer}
        'System.Int64' {[Data.OleDb.OleDbType]::BigInt}
        'System.Double' {[Data.OleDb.OleDbType]::Double}
        'System.Decimal' {[Data.OleDb.OleDbType]::Decimal}
        'System.DateTime' {[Data.OleDb.OleDbType]::DBTimeStamp}
        default {[Data.OleDb.OleDbType]::WChar}
    }
    $item=New-Object Microsoft.AnalysisServices.DataItem($table,$column,$type)
    if ($type -eq [Data.OleDb.OleDbType]::WChar) { $item.DataSize=[Math]::Max(1,$c.MaxLength) }
    $item.NullProcessing=[Microsoft.AnalysisServices.NullProcessing]::Error
    return $item
}
function New-Dimension([string]$name,[string]$table) {
    $dim=$db.Dimensions.Add($name,$name)
    $dim.Source=New-Object Microsoft.AnalysisServices.DataSourceViewBinding($dsv.ID)
    $dim.StorageMode=[Microsoft.AnalysisServices.DimensionStorageMode]::Molap
    $dim.UnknownMember=[Microsoft.AnalysisServices.UnknownMemberBehavior]::None
    $dim.Description="Source: $table; strict dimension keys."
    return $dim
}
function Add-Attribute($dimension,[string]$table,[string]$name,[string[]]$keys,[string]$caption,[bool]$isKey=$false) {
    $attribute=$dimension.Attributes.Add($name,$name)
    if ($isKey) { $attribute.Usage=[Microsoft.AnalysisServices.AttributeUsage]::Key }
    foreach ($key in $keys) { [void]$attribute.KeyColumns.Add((New-DataItem $table $key)) }
    $attribute.NameColumn=New-DataItem $table $caption
    $attribute.OrderBy=[Microsoft.AnalysisServices.OrderBy]::Key
    return $attribute
}
function Add-Relationship($dimension,[string]$child,[string]$parent) {
    $relation=$dimension.Attributes[$child].AttributeRelationships.Add($parent)
    $relation.RelationshipType=[Microsoft.AnalysisServices.RelationshipType]::Rigid
}
function Add-Hierarchy($dimension,[string]$name,[string[]]$levels) {
    $hierarchy=$dimension.Hierarchies.Add($name,$name)
    foreach ($level in $levels) { $hierarchy.Levels.Add($level,$level).SourceAttributeID=$level }
}

$date=New-Dimension 'Date' 'DimDate'
$date.Type=[Microsoft.AnalysisServices.DimensionType]::Time
[void](Add-Attribute $date 'DimDate' 'Date' @('DATE_ID') 'DATE_CAPTION' $true)
[void](Add-Attribute $date 'DimDate' 'Year' @('YEAR_NUM') 'YEAR_CAPTION')
[void](Add-Attribute $date 'DimDate' 'Quarter' @('QUARTER_KEY') 'QUARTER_CAPTION')
[void](Add-Attribute $date 'DimDate' 'Month' @('MONTH_KEY') 'MONTH_CAPTION')
[void](Add-Attribute $date 'DimDate' 'Month Of Year' @('MONTH_NUM') 'MONTH_NUMBER_CAPTION')
[void](Add-Attribute $date 'DimDate' 'Day Of Week' @('WEEKDAY_NUM') 'WEEKDAY_NAME')
Add-Relationship $date 'Date' 'Month'; Add-Relationship $date 'Month' 'Quarter'; Add-Relationship $date 'Quarter' 'Year'
Add-Relationship $date 'Date' 'Month Of Year'; Add-Relationship $date 'Date' 'Day Of Week'
Add-Hierarchy $date 'Calendar' @('Year','Quarter','Month','Date')

$carrier=New-Dimension 'Carrier' 'DimCarrier'
[void](Add-Attribute $carrier 'DimCarrier' 'Carrier' @('CARRIER_ID') 'CARRIER_CODE' $true)
[void](Add-Attribute $carrier 'DimCarrier' 'Carrier Code' @('CARRIER_CODE') 'CARRIER_CODE')
[void](Add-Attribute $carrier 'DimCarrier' 'Carrier Name' @('CARRIER_CODE') 'CARRIER_NAME')
Add-Relationship $carrier 'Carrier' 'Carrier Code'; Add-Relationship $carrier 'Carrier Code' 'Carrier Name'
$carrier.Attributes['Carrier'].AttributeHierarchyVisible=$false
Add-Hierarchy $carrier 'Airlines' @('Carrier Name','Carrier Code')

$airport=New-Dimension 'Airport' 'DimAirport'
[void](Add-Attribute $airport 'DimAirport' 'Airport' @('AIRPORT_ID') 'AIRPORT_CODE' $true)
[void](Add-Attribute $airport 'DimAirport' 'Airport Code' @('AIRPORT_CODE') 'AIRPORT_CODE')
[void](Add-Attribute $airport 'DimAirport' 'City' @('STATE_CODE','CITY_LABEL') 'CITY_LABEL')
[void](Add-Attribute $airport 'DimAirport' 'State' @('STATE_CODE') 'STATE_CODE')
Add-Relationship $airport 'Airport' 'Airport Code'; Add-Relationship $airport 'Airport Code' 'City'; Add-Relationship $airport 'City' 'State'
$airport.Attributes['Airport'].AttributeHierarchyVisible=$false
Add-Hierarchy $airport 'Geography' @('State','City','Airport Code')

$time=New-Dimension 'Departure Time' 'DimTime'
[void](Add-Attribute $time 'DimTime' 'Scheduled Time' @('TIME_ID') 'TIME_CAPTION' $true)
[void](Add-Attribute $time 'DimTime' 'Hour' @('HOUR_NUM') 'HOUR_CAPTION')
[void](Add-Attribute $time 'DimTime' 'Time Band' @('TIME_BAND_KEY') 'TIME_BAND_NAME')
Add-Relationship $time 'Scheduled Time' 'Hour'; Add-Relationship $time 'Hour' 'Time Band'
Add-Hierarchy $time 'Daily Schedule' @('Time Band','Hour','Scheduled Time')

$cancellation=New-Dimension 'Cancellation' 'DimCancellation'
[void](Add-Attribute $cancellation 'DimCancellation' 'Cancellation' @('CANCELLATION_ID') 'CANCELLATION_CODE' $true)
[void](Add-Attribute $cancellation 'DimCancellation' 'Reason' @('CANCELLATION_CODE') 'CANCELLATION_REASON')
Add-Relationship $cancellation 'Cancellation' 'Reason'

$route=New-Dimension 'Route' 'DimRoute'
[void](Add-Attribute $route 'DimRoute' 'Route' @('ROUTE_KEY') 'ROUTE_NAME' $true)
foreach ($pair in @(@('Origin Code','ORIGIN_CODE'),@('Destination Code','DEST_CODE'),@('Distance Miles','DISTANCE_MILES'))) {
    $captionColumn=if($pair[0]-eq 'Distance Miles'){'DISTANCE_CAPTION'}else{$pair[1]}
    [void](Add-Attribute $route 'DimRoute' $pair[0] @($pair[1]) $captionColumn)
    Add-Relationship $route 'Route' $pair[0]
}
$status=New-Dimension 'Flight Status' 'DimStatus'
[void](Add-Attribute $status 'DimStatus' 'Status' @('STATUS_KEY') 'STATUS_NAME' $true)

$cube=$db.Cubes.Add('FlightCube','FlightCube')
$cube.Description='2024 sampled flights. Counts and delay denominators are documented in docs/SSAS_GUIDE.md.'
$cube.Source=New-Object Microsoft.AnalysisServices.DataSourceViewBinding($dsv.ID)
$cube.DefaultMeasure='[Measures].[Total Flights]'
$cube.StorageMode=[Microsoft.AnalysisServices.StorageMode]::Molap
$roles=@(
    @('Date','Date','Date','DATE_ID','Date'),@('Carrier','Carrier','Carrier','CARRIER_ID','Carrier'),
    @('Airport','Origin Airport','Origin Airport','ORIGIN_AIRPORT_ID','Airport'),
    @('Airport','Destination Airport','Destination Airport','DEST_AIRPORT_ID','Airport'),
    @('Departure Time','Departure Time','Departure Time','DEP_TIME_ID','Scheduled Time'),
    @('Cancellation','Cancellation','Cancellation','CANCELLATION_ID','Cancellation'),
    @('Route','Route','Route','ROUTE_KEY','Route'),@('Flight Status','Flight Status','Flight Status','CANCELLED','Status')
)
foreach($role in $roles) { [void]$cube.Dimensions.Add($role[0],$role[1],$role[2]) }
$mg=$cube.MeasureGroups.Add('Flight Facts','FlightFacts')
$mg.StorageMode=[Microsoft.AnalysisServices.StorageMode]::Molap
$mg.ProcessingMode=[Microsoft.AnalysisServices.ProcessingMode]::Regular
$measures=@(
    @('Total Flights','TOTAL_FLIGHTS','count'),@('Operated Flights','OPERATED_FLIGHTS','count'),
    @('Cancelled Flights','CANCELLED_FLIGHTS','count'),@('Departure Observations','DEPARTURE_OBSERVATIONS','count'),
    @('Arrival Observations','ARRIVAL_OBSERVATIONS','count'),@('Delayed Departures','DELAYED_DEPARTURES','count'),
    @('Departure Delay Minutes','DEPARTURE_LATE_MINUTES','minutes'),@('Arrival Late Minutes','ARRIVAL_LATE_MINUTES','minutes'),
    @('Departure Delay Sum','DEPARTURE_DELAY_VALUE','minutes'),@('Arrival Delay Sum','ARRIVAL_DELAY_VALUE','minutes'),
    @('Carrier Delay Minutes','CARRIER_DELAY','minutes'),@('Weather Delay Minutes','WEATHER_DELAY','minutes'),
    @('NAS Delay Minutes','NAS_DELAY','minutes'),@('Security Delay Minutes','SECURITY_DELAY','minutes'),
    @('Late Aircraft Delay Minutes','LATE_AIRCRAFT_DELAY','minutes'),@('Distance Miles Sum','DISTANCE','distance')
)
foreach ($spec in $measures) {
    $measure=$mg.Measures.Add($spec[0],$spec[0])
    $measure.AggregateFunction=[Microsoft.AnalysisServices.AggregationFunction]::Sum
    $measure.Source=New-DataItem 'FactFlight' $spec[1]
    $measure.Source.NullProcessing=[Microsoft.AnalysisServices.NullProcessing]::ZeroOrBlank
    $measure.FormatString=if($spec[2]-eq 'count'){'#,0'}else{'#,0.00'}
    $measure.DataType=if($spec[2]-eq 'count'){[Microsoft.AnalysisServices.MeasureDataType]::BigInt}else{[Microsoft.AnalysisServices.MeasureDataType]::Double}
    $measure.DisplayFolder=if($spec[2]-eq 'count'){'Flights'}elseif($spec[2]-eq 'distance'){'Distance'}else{'Delays'}
}
foreach ($role in $roles) {
    $regular=New-Object Microsoft.AnalysisServices.RegularMeasureGroupDimension($role[2])
    $attribute=New-Object Microsoft.AnalysisServices.MeasureGroupAttribute($role[4])
    $attribute.Type=[Microsoft.AnalysisServices.MeasureGroupAttributeType]::Granularity
    [void]$attribute.KeyColumns.Add((New-DataItem 'FactFlight' $role[3]))
    [void]$regular.Attributes.Add($attribute); [void]$mg.Dimensions.Add($regular)
}
$partition=$mg.Partitions.Add('All Flights','AllFlights')
$partition.StorageMode=[Microsoft.AnalysisServices.StorageMode]::Molap
$partition.Source=New-Object Microsoft.AnalysisServices.QueryBinding($ds.ID,$dsv.Schema.Tables['FactFlight'].ExtendedProperties['QueryDefinition'])
$script=$cube.MdxScripts.Add('Calculations','Calculations')
$command=New-Object Microsoft.AnalysisServices.Command
$command.Text=@'
CALCULATE;
CREATE MEMBER CURRENTCUBE.[Measures].[Average Arrival Delay] AS
 IIF([Measures].[Arrival Observations]=0,NULL,[Measures].[Arrival Delay Sum]/[Measures].[Arrival Observations]),
 FORMAT_STRING='#,0.00',DISPLAY_FOLDER='Rates and Averages',VISIBLE=1;
CREATE MEMBER CURRENTCUBE.[Measures].[Average Departure Delay] AS
 IIF([Measures].[Departure Observations]=0,NULL,[Measures].[Departure Delay Sum]/[Measures].[Departure Observations]),
 FORMAT_STRING='#,0.00',DISPLAY_FOLDER='Rates and Averages',VISIBLE=1;
CREATE MEMBER CURRENTCUBE.[Measures].[Cancellation Rate] AS
 IIF([Measures].[Total Flights]=0,NULL,[Measures].[Cancelled Flights]/[Measures].[Total Flights]),
 FORMAT_STRING='0.00%',DISPLAY_FOLDER='Rates and Averages',VISIBLE=1;
CREATE MEMBER CURRENTCUBE.[Measures].[Departure Delay Rate] AS
 IIF([Measures].[Departure Observations]=0,NULL,[Measures].[Delayed Departures]/[Measures].[Departure Observations]),
 FORMAT_STRING='0.00%',DISPLAY_FOLDER='Rates and Averages',VISIBLE=1;
CREATE MEMBER CURRENTCUBE.[Measures].[Route Distance Miles] AS
 IIF([Measures].[Total Flights]=0,NULL,[Measures].[Distance Miles Sum]/[Measures].[Total Flights]),
 FORMAT_STRING='#,0.00',DISPLAY_FOLDER='Distance',VISIBLE=1;
'@
[void]$script.Commands.Add($command)

function Save-MajorObject($object,[string]$path,[bool]$writeReadOnlyProperties=$false) {
    $settings=New-Object Xml.XmlWriterSettings
    $settings.Indent=$true; $settings.Encoding=$utf8
    $writer=[Xml.XmlWriter]::Create($path,$settings)
    try { [Microsoft.AnalysisServices.Utils]::Serialize($writer,$object,$writeReadOnlyProperties) } finally { $writer.Close() }
}
Save-MajorObject $db (Join-Path $bin 'Flight_SSAS.asdatabase')
Save-MajorObject $db (Join-Path $ProjectDirectory 'Flight_SSAS.database') $false
$metadata=New-Object Xml.XmlDocument
$metadata.Load((Join-Path $ProjectDirectory 'Flight_SSAS.database'))
foreach($node in @($metadata.DocumentElement.ChildNodes)) {
    if($node.LocalName -in @('Dimensions','Cubes','DataSources','DataSourceViews','Roles','Assemblies','MiningStructures')) { [void]$metadata.DocumentElement.RemoveChild($node) }
}
$metadata.Save((Join-Path $ProjectDirectory 'Flight_SSAS.database'))
Save-MajorObject $ds (Join-Path $ProjectDirectory 'Flight_DW.ds')
Save-MajorObject $dsv (Join-Path $ProjectDirectory 'Flight_DW.dsv')
foreach($dim in $db.Dimensions) { Save-MajorObject $dim (Join-Path $ProjectDirectory ($dim.ID+'.dim')) }
Save-MajorObject $cube (Join-Path $ProjectDirectory 'FlightCube.cube')

# SSDT stores partition metadata in a dependent .partitions file.
$cubeXml=New-Object Xml.XmlDocument
$cubeXml.Load((Join-Path $ProjectDirectory 'FlightCube.cube'))
$partitionXml=$cubeXml.CloneNode($true)
foreach($node in @($partitionXml.DocumentElement.ChildNodes)) {
    if($node.LocalName -notin @('ID','MeasureGroups')) { [void]$partitionXml.DocumentElement.RemoveChild($node) }
}
foreach($group in $partitionXml.DocumentElement['MeasureGroups'].ChildNodes) {
    foreach($node in @($group.ChildNodes)) { if($node.LocalName -notin @('ID','Partitions')){[void]$group.RemoveChild($node)} }
}
foreach($group in $cubeXml.DocumentElement['MeasureGroups'].ChildNodes) {
    if($group['Partitions']) { [void]$group.RemoveChild($group['Partitions']) }
}
$cubeXml.Save((Join-Path $ProjectDirectory 'FlightCube.cube'))
$partitionXml.Save((Join-Path $ProjectDirectory 'FlightCube.partitions'))

$project=New-Object Xml.XmlDocument
$project.LoadXml('<Project><ProductVersion>17.3.0.0</ProductVersion><SchemaVersion>9.0.2.10</SchemaVersion></Project>')
function Add-ProjectFile($parent,[string]$file) {
    $item=$project.CreateElement('ProjectItem')
    foreach($field in @('Name','FullPath')) { $element=$project.CreateElement($field);$element.InnerText=$file;[void]$item.AppendChild($element) }
    [void]$parent.AppendChild($item)
    return $item
}
$databaseNode=$project.CreateElement('Database')
foreach($field in @('Name','FullPath')) { $element=$project.CreateElement($field);$element.InnerText='Flight_SSAS.database';[void]$databaseNode.AppendChild($element) }
[void]$project.DocumentElement.AppendChild($databaseNode)
foreach($category in @('Cubes','Dimensions','DataSources','DataSourceViews','MiningModels','Roles','Assemblies','Miscellaneous')) {
    $node=$project.CreateElement($category);[void]$project.DocumentElement.AppendChild($node)
    switch($category) {
        'Cubes' {
            $item=Add-ProjectFile $node 'FlightCube.cube'
            $deps=$project.CreateElement('Dependencies');[void]$item.AppendChild($deps)
            [void](Add-ProjectFile $deps 'FlightCube.partitions')
        }
        'Dimensions' {foreach($dim in $db.Dimensions){[void](Add-ProjectFile $node ($dim.ID+'.dim'))}}
        'DataSources' {[void](Add-ProjectFile $node 'Flight_DW.ds')}
        'DataSourceViews' {[void](Add-ProjectFile $node 'Flight_DW.dsv')}
    }
}
$configuration=$project.CreateElement('Configurations')
$configuration.InnerXml='<Configuration><Name>Development</Name><Options><OutputPath>bin</OutputPath><ServerName>localhost</ServerName><DatabaseName>Flight_SSAS</DatabaseName></Options></Configuration>'
[void]$project.DocumentElement.AppendChild($configuration)
$project.Save((Join-Path $ProjectDirectory 'Flight_SSAS.dwproj'))
Write-Host ('Built: '+$db.Dimensions.Count+' database dimensions, '+$cube.Dimensions.Count+' cube dimensions, '+$mg.Measures.Count+' base measures and 5 calculated measures.')
