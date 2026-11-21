function Write-BeaconJobStatus {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Value)
    # Replace the whole status atomically so concurrent polling never sees partial JSON.
    $temporary="$Path.$([guid]::NewGuid().ToString('N')).tmp"
    [IO.File]::WriteAllText($temporary,($Value | ConvertTo-Json -Depth 75),(New-Object Text.UTF8Encoding($false)))
    # NullString is required by Windows PowerShell 5.1; plain $null becomes an
    # empty backup filename when calling File.Replace and causes an exception.
    if([IO.File]::Exists($Path)){[IO.File]::Replace($temporary,$Path,[NullString]::Value)}else{[IO.File]::Move($temporary,$Path)}
}
Export-ModuleMember -Function Write-BeaconJobStatus
