[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression
$destination=Join-Path $PSScriptRoot 'OpsBeacon-Live-Portable.zip'
$stream=[IO.File]::Open($destination,[IO.FileMode]::Create)
$zip=New-Object IO.Compression.ZipArchive($stream,[IO.Compression.ZipArchiveMode]::Create)
try{
    $files=@(Get-ChildItem -LiteralPath $PSScriptRoot -File | Where-Object Extension -in '.ps1','.psd1','.cmd','.json','.md' | Where-Object Name -ne 'runtime.json')
    foreach($folder in @('src','public','vendor','.vscode','tests')){$files+=@(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot $folder) -File -Recurse | Where-Object Name -notlike '*results.json')}
    foreach($file in $files){
        $relative=$file.FullName.Substring($PSScriptRoot.Length+1).Replace('\','/')
        $entry=$zip.CreateEntry("OpsBeacon-Live/$relative",[IO.Compression.CompressionLevel]::Optimal)
        $inputStream=[IO.File]::OpenRead($file.FullName);$entryStream=$entry.Open()
        try{$inputStream.CopyTo($entryStream)}finally{$entryStream.Dispose();$inputStream.Dispose()}
    }
}finally{$zip.Dispose();$stream.Dispose()}
Get-Item -LiteralPath $destination | Select-Object Name,Length
