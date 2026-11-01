param(
    [string]$SsasServer='localhost',
    [string]$DatabaseName='Flight_SSAS',
    [string]$OutputDirectory=(Join-Path $PSScriptRoot '..\results')
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Initialize-SSASClient.ps1')
Initialize-FlightSSASClient
[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$manifest=([IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\queries\manifest.json'),[Text.Encoding]::UTF8)) | ConvertFrom-Json
$connection=New-Object Microsoft.AnalysisServices.AdomdClient.AdomdConnection("Data Source=$SsasServer;Initial Catalog=$DatabaseName;Connect Timeout=20")
$connection.Open()
$summary=@()
try {
    foreach($entry in $manifest) {
        $command=$connection.CreateCommand()
        $command.CommandTimeout=120
        $command.CommandText=[IO.File]::ReadAllText((Join-Path $PSScriptRoot ('..\queries\'+$entry.file)),[Text.Encoding]::UTF8)
        $set=$command.ExecuteCellSet()
        $columns=@($set.Axes[0].Positions | ForEach-Object {$_.Members[0].Caption})
        $rows=@(); $flat=@()
        for($r=0;$r -lt $set.Axes[1].Positions.Count;$r++) {
            $members=@($set.Axes[1].Positions[$r].Members | ForEach-Object { @{caption=$_.Caption;uniqueName=$_.UniqueName} })
            $values=[ordered]@{}; $formatted=[ordered]@{}; $flatRow=[ordered]@{}
            for($m=0;$m -lt $members.Count;$m++) { $flatRow['Row'+($m+1)]=$members[$m].caption }
            for($c=0;$c -lt $columns.Count;$c++) {
                $cell=$set.Cells[$c,$r]
                $value=$cell.Value
                if($value -is [Exception]) { throw $value }
                if($value -is [DBNull]) { $value=$null }
                $values[$columns[$c]]=$value
                $formatted[$columns[$c]]=$cell.FormattedValue
                $flatRow[$columns[$c]]=$value
            }
            $rows+=@{members=$members;values=$values;formatted=$formatted}
            $flat += [pscustomobject]$flatRow
        }
        $stem=[IO.Path]::GetFileNameWithoutExtension($entry.file)
        $result=@{query=$entry.number;title=$entry.title;columns=$columns;rowCount=$rows.Count;rows=$rows}
        [IO.File]::WriteAllText((Join-Path $OutputDirectory ($stem+'.json')),($result | ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
        if($flat.Count) { $flat | Export-Csv -NoTypeInformation -Encoding UTF8 -Path (Join-Path $OutputDirectory ($stem+'.csv')) }
        $summary += @{query=$entry.number;rows=$rows.Count;status='PASS'}
        Write-Host ('Query '+$entry.number+': '+$rows.Count+' rows')
        $command.Dispose()
    }
    [IO.File]::WriteAllText((Join-Path $OutputDirectory 'execution_summary.json'),($summary | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
} finally { $connection.Close(); $connection.Dispose() }
