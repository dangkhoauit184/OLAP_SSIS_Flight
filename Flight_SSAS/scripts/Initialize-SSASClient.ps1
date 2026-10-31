$ErrorActionPreference = 'Stop'
function Initialize-FlightSSASClient {
    # Side-by-side SDK: do not replace Visual Studio's installed assemblies.
    $version = '19.118.3'
    $root = $env:FLIGHT_SSAS_CLIENTS
    if (-not $root) { $root = Join-Path $PSScriptRoot '..\.packages' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    foreach ($package in @('microsoft.analysisservices', 'microsoft.analysisservices.adomdclient')) {
        $destination = Join-Path $root $package
        if (-not (Test-Path (Join-Path $destination 'lib\net472'))) {
            [void](New-Item -ItemType Directory -Path $root -Force)
            $archive = Join-Path $root ($package + '.' + $version + '.nupkg')
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -UseBasicParsing -Uri "https://api.nuget.org/v3-flatcontainer/$package/$version/$package.$version.nupkg" -OutFile $archive
            [IO.Compression.ZipFile]::ExtractToDirectory($archive, $destination)
        }
    }
    $amo = Join-Path $root 'microsoft.analysisservices\lib\net472'
    foreach ($name in @('Microsoft.AnalysisServices.Core.dll', 'Microsoft.AnalysisServices.dll')) {
        [void][Reflection.Assembly]::LoadFrom((Join-Path $amo $name))
    }
    [void][Reflection.Assembly]::LoadFrom((Join-Path $root 'microsoft.analysisservices.adomdclient\lib\net472\Microsoft.AnalysisServices.AdomdClient.dll'))
}
