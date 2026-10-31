param(
    [string]$SqlServer='(local)',
    [string]$SqlDatabase='Flight_DW',
    [string]$ProjectDirectory=(Split-Path $PSScriptRoot -Parent)
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Initialize-SSASClient.ps1')
Initialize-FlightSSASClient
$ProjectDirectory=[IO.Path]::GetFullPath($ProjectDirectory)
$project=New-Object Xml.XmlDocument
$project.Load((Join-Path $ProjectDirectory 'Flight_SSAS.dwproj'))
function Read-ModelObject([string]$relativePath) {
    $path=[IO.Path]::GetFullPath((Join-Path $ProjectDirectory $relativePath))
    if(-not $path.StartsWith($ProjectDirectory+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Project item must remain inside Flight_SSAS.'}
    if([IO.Path]::GetExtension($path)-eq '.partitions') {
        # SSDT partition files intentionally omit names on the Cube/MG stubs.
        $partial=New-Object Xml.XmlDocument
        $partial.Load($path)
        foreach($node in $partial.SelectNodes('//*[local-name()="Cube" or local-name()="MeasureGroup"]')) {
            if(-not $node['Name']) {
                $name=$partial.CreateElement('Name',$node.NamespaceURI)
                $name.InnerText=$node['ID'].InnerText
                [void]$node.InsertAfter($name,$node['ID'])
            }
        }
        $reader=New-Object Xml.XmlNodeReader($partial)
    } else { $reader=[Xml.XmlReader]::Create($path) }
    $type=switch([IO.Path]::GetExtension($path)) {
        '.database' {'Database'}
        '.ds' {'RelationalDataSource'}
        '.dsv' {'DataSourceView'}
        '.dim' {'Dimension'}
        '.cube' {'Cube'}
        '.partitions' {'Cube'}
        default {throw 'Unsupported project item type.'}
    }
    $object=New-Object ('Microsoft.AnalysisServices.'+$type)
    try {return [Microsoft.AnalysisServices.Utils]::Deserialize($reader,$object)} catch {throw "Cannot read project item '$relativePath': $($_.Exception.Message)"} finally {$reader.Close()}
}
$db=Read-ModelObject $project.Project.Database.FullPath
foreach($entry in $project.Project.DataSources.ProjectItem) {
    $source=Read-ModelObject $entry.FullPath
    $builder=New-Object Data.OleDb.OleDbConnectionStringBuilder($source.ConnectionString)
    $builder['Data Source']=$SqlServer;$builder['Initial Catalog']=$SqlDatabase
    $source.ConnectionString=$builder.ConnectionString
    [void]$db.DataSources.Add($source)
}
foreach($entry in $project.Project.DataSourceViews.ProjectItem){[void]$db.DataSourceViews.Add((Read-ModelObject $entry.FullPath))}
foreach($entry in $project.Project.Dimensions.ProjectItem){[void]$db.Dimensions.Add((Read-ModelObject $entry.FullPath))}
foreach($entry in $project.Project.Cubes.ProjectItem){
    $cube=Read-ModelObject $entry.FullPath
    foreach($dependency in $entry.Dependencies.ProjectItem){
        if($dependency.FullPath -like '*.partitions') {
            $partitions=Read-ModelObject $dependency.FullPath
            foreach($group in $partitions.MeasureGroups){
                foreach($partition in $group.Partitions){[void]$cube.MeasureGroups[$group.ID].Partitions.Add($partition.Clone())}
            }
        }
    }
    [void]$db.Cubes.Add($cube)
}
if($db.Dimensions.Count -ne @($project.Project.Dimensions.ProjectItem).Count -or $db.Cubes.Count -ne @($project.Project.Cubes.ProjectItem).Count -or $db.Cubes['FlightCube'].MeasureGroups['FlightFacts'].Partitions.Count -lt 1){throw 'Incomplete Flight project references.'}
$bin=Join-Path $ProjectDirectory 'bin'
[void](New-Item -ItemType Directory -Path $bin -Force)
$settings=New-Object Xml.XmlWriterSettings
$settings.Indent=$true;$settings.Encoding=New-Object Text.UTF8Encoding($false)
$writer=[Xml.XmlWriter]::Create((Join-Path $bin 'Flight_SSAS.asdatabase'),$settings)
try{[Microsoft.AnalysisServices.Utils]::Serialize($writer,$db,$false)}finally{$writer.Close()}
Write-Host 'Built the existing .dwproj/.ds/.dsv/.dim/.cube/.partitions files without regenerating or overwriting their source.'
