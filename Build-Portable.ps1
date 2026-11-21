[CmdletBinding()]
param(
    [ValidatePattern('^[A-Fa-f0-9]{40}$')][string]$CertificateThumbprint,
    [string]$StagingDirectory = (Join-Path ([IO.Path]::GetTempPath()) ('OpsBeacon-stage-' + [guid]::NewGuid().ToString('N')))
)
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -lt 1) {
    throw 'Build with Windows PowerShell 5.1 (powershell.exe).'
}
# Signing is opt-in; certificate creation and trust changes are never performed.
$certificate = $null
if ($CertificateThumbprint) {
    $certificate = Get-Item -LiteralPath "Cert:\CurrentUser\My\$CertificateThumbprint" -ErrorAction Stop
    $now = Get-Date
    if (-not $certificate.HasPrivateKey -or $now -lt $certificate.NotBefore -or $now -ge $certificate.NotAfter) {
        throw 'The selected certificate must be currently valid and have a private key.'
    }
    if (@($certificate.EnhancedKeyUsageList | Where-Object ObjectId -eq '1.3.6.1.5.5.7.3.3').Count -eq 0) {
        throw 'The selected certificate must have the Code Signing enhanced key usage.'
    }
}
$stage = [IO.Path]::GetFullPath($StagingDirectory)
if (Test-Path -LiteralPath $stage) { throw 'StagingDirectory must be a new folder.' }
$root = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
if ($stage.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase) -or $stage -ieq $root) {
    throw 'Use a staging directory outside the source repository.'
}
$payload = Join-Path $stage 'OpsBeacon-Live'
New-Item -ItemType Directory -Path $payload -Force | Out-Null
# Root allowlist excludes local exports, configuration overrides and runtime data.
$rootFiles = @('Build-Portable.ps1','Start-OpsBeacon.ps1','Start-OpsBeacon.cmd',
    'Stop-OpsBeacon.ps1','Stop-OpsBeacon.cmd','config.json','server.psd1','README.md','VERIFICATION.md',
    'Assemt Summary at a glance 1-1.png','Assemt Summary at a glance 3-1.png')
foreach ($name in $rootFiles) {
    Copy-Item -LiteralPath (Join-Path $root $name) -Destination (Join-Path $payload $name)
}
foreach ($folder in @('src','public','tests')) {
    foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $root $folder) -Recurse -File)) {
        $relative = $file.FullName.Substring($root.Length + 1)
        if ($relative -match '(^|[\\/])(jobs|reports|logs|runtime|data|node_modules|\.git)([\\/]|$)' -or
            $file.Extension -in '.pfx','.p12','.pem','.key','.cer','.crt','.log','.zip' -or
            $file.Name -match '(?i)(results|report|runtime|launcher|\.status|\.request)\.json$') { continue }
        if ($file.Extension -notin '.ps1','.psm1','.psd1','.html','.css','.js','.mjs','.svg','.png','.ico','.txt','.md') { continue }
        $target = Join-Path $payload $relative
        New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $target
    }
}
# Vendor files are copied byte-for-byte and never re-signed.
$pode = Join-Path $root 'vendor/Pode/2.13.4'
if (-not (Test-Path -LiteralPath (Join-Path $pode 'Pode.psd1')) -or
    -not (Test-Path -LiteralPath (Join-Path $pode 'LICENSE.txt'))) { throw 'Bundled Pode 2.13.4 and license are required.' }
foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $root 'vendor') -Recurse -File)) {
    if ($file.Extension -in '.pfx','.p12','.pem','.key','.cer','.crt','.log' -or
        $file.FullName.Substring($root.Length + 1) -match '(^|[\\/])(jobs|reports|logs|runtime|data|\.git)([\\/]|$)') {
        throw "Unexpected sensitive/runtime file in vendor: $($file.Name). Remove it before packaging."
    }
    $target = Join-Path $payload $file.FullName.Substring($root.Length + 1)
    New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $target
}
$scripts = @(Get-ChildItem -LiteralPath $payload -Recurse -File | Where-Object {
    $_.Extension -in '.ps1','.psm1','.psd1' -and
    -not $_.FullName.StartsWith((Join-Path $payload 'vendor') + '\', [StringComparison]::OrdinalIgnoreCase)
})
if ($certificate) {
    foreach ($file in $scripts) {
        $signature = Set-AuthenticodeSignature -LiteralPath $file.FullName -Certificate $certificate -HashAlgorithm SHA256
        # Some Windows versions report an untrusted self-signed root as UnknownError.
        $untrustedRoot = $signature.Status -eq 'UnknownError' -and
            $signature.StatusMessage -match 'root certificate which is not trusted|0x800B0109'
        if ($signature.SignerCertificate.Thumbprint -ine $certificate.Thumbprint -or
            ($signature.Status -notin 'Valid','NotTrusted' -and -not $untrustedRoot)) {
            throw "Signing failed for $($file.Name): $($signature.Status) / $($signature.StatusMessage)"
        }
        if ($signature.Status -ne 'Valid') { Write-Warning "Signed $($file.Name), but local trust validation reports $($signature.Status): $($signature.StatusMessage)" }
    }
}
# Keep the final-byte hash manifest outside the ZIP for extracted verification.
$manifest = @(Get-ChildItem -LiteralPath $payload -Recurse -File | ForEach-Object {
    [pscustomobject]@{ path = $_.FullName.Substring($payload.Length + 1).Replace('\','/');
        sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
})
$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $stage 'staged-hashes.json') -Encoding UTF8
Add-Type -AssemblyName System.IO.Compression.FileSystem
$temporaryZip = Join-Path $stage 'OpsBeacon-Live-Portable.zip'
[IO.Compression.ZipFile]::CreateFromDirectory($payload, $temporaryZip, [IO.Compression.CompressionLevel]::Optimal, $true)
$destination = Join-Path $root 'OpsBeacon-Live-Portable.zip'
# Preserve the old ZIP on any staging/signing/compression failure.
$pending = Join-Path $root ('OpsBeacon-Portable-' + [guid]::NewGuid().ToString('N') + '.tmp')
try {
    Copy-Item -LiteralPath $temporaryZip -Destination $pending
    if (Test-Path -LiteralPath $destination) { [IO.File]::Replace($pending, $destination, [Management.Automation.Language.NullString]::Value) }
    else { [IO.File]::Move($pending, $destination) }
} finally { if (Test-Path -LiteralPath $pending) { Remove-Item -LiteralPath $pending -Force } }
[pscustomobject]@{ ZipPath = $destination; SHA256 = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash;
    StagingDirectory = $stage; CertificateThumbprint = $CertificateThumbprint; FirstPartyScriptCount = $scripts.Count }
