[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$StagingDirectory,
    [Parameter(Mandatory=$true)][string]$ExtractedRoot,
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Fa-f0-9]{40}$')][string]$CertificateThumbprint,
    [string]$ResultsPath
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
$checks = New-Object 'Collections.Generic.List[object]'
function Check([string]$Name, [bool]$Passed) {
    $checks.Add([pscustomobject]@{name=$Name;passed=$Passed})
    if (-not $Passed) { throw "FAILED: $Name" }
}
$manifest = Get-Content -LiteralPath (Join-Path $StagingDirectory 'staged-hashes.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$stageRoot = Join-Path $StagingDirectory 'OpsBeacon-Live'
$extracted = @(Get-ChildItem -LiteralPath $ExtractedRoot -Recurse -File)
Check 'Extracted file count matches final stage' ($extracted.Count -eq $manifest.Count)
foreach ($entry in $manifest) {
    $stageFile = Join-Path $stageRoot $entry.path
    $file = Join-Path $ExtractedRoot $entry.path
    Check "Staged and extracted SHA256: $($entry.path)" ((Test-Path -LiteralPath $file) -and
        (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -eq $entry.sha256 -and
        (Get-FileHash -LiteralPath $stageFile -Algorithm SHA256).Hash -eq $entry.sha256)
}
$sourceRoot = Split-Path -Parent $PSScriptRoot
$vendor = @($manifest | Where-Object path -like 'vendor/*')
foreach ($entry in $vendor) {
    Check "Vendor bytes/signatures preserved: $($entry.path)" ((Get-FileHash -LiteralPath (Join-Path $sourceRoot $entry.path) -Algorithm SHA256).Hash -eq $entry.sha256)
}
Check 'Bundled Pode and license' ((Test-Path -LiteralPath (Join-Path $ExtractedRoot 'vendor/Pode/2.13.4/Pode.psd1')) -and
    (Test-Path -LiteralPath (Join-Path $ExtractedRoot 'vendor/Pode/2.13.4/LICENSE.txt')))
Check 'README graphics included' ((Test-Path -LiteralPath (Join-Path $ExtractedRoot 'Assemt Summary at a glance 1-1.png')) -and
    (Test-Path -LiteralPath (Join-Path $ExtractedRoot 'Assemt Summary at a glance 3-1.png')))
$unwanted = @($manifest | Where-Object {
    $_.path -match '(^|/)(jobs|reports|logs|runtime|data|\.git|\.vscode)(/|$)|\.(pfx|p12|pem|key|cer|crt|log|zip)$|results\.json$'
})
Check 'No certificates, keys, jobs, reports, logs, runtime data or local tasks' ($unwanted.Count -eq 0)
$scripts = @($extracted | Where-Object { $_.Extension -in '.ps1','.psm1','.psd1' -and
    -not $_.FullName.StartsWith((Join-Path $ExtractedRoot 'vendor') + '\', [StringComparison]::OrdinalIgnoreCase) })
Check 'First-party build, launchers and tests included' ($scripts.Count -gt 0 -and
    (Test-Path -LiteralPath (Join-Path $ExtractedRoot 'Build-Portable.ps1')) -and
    (Test-Path -LiteralPath (Join-Path $ExtractedRoot 'Start-OpsBeacon.ps1')) -and
    (Test-Path -LiteralPath (Join-Path $ExtractedRoot 'Stop-OpsBeacon.ps1')) -and
    (Test-Path -LiteralPath (Join-Path $ExtractedRoot 'tests/Portable-Checks.ps1')))
$signatures = foreach ($file in $scripts) {
    $signature = Get-AuthenticodeSignature -LiteralPath $file.FullName
    Check "Signer thumbprint: $($file.Name)" ($signature.SignerCertificate.Thumbprint -ieq $CertificateThumbprint)
    $untrustedRoot = $signature.Status -eq 'UnknownError' -and
        $signature.StatusMessage -match 'root certificate which is not trusted|0x800B0109'
    Check "Authenticode content status: $($file.Name)" ($signature.Status -in 'Valid','NotTrusted' -or $untrustedRoot)
    # Verify the embedded CMS signature mathematically, without changing trust.
    $content = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
    $block = [regex]::Match($content, '(?s)# SIG # Begin signature block\r?\n(.*?)# SIG # End signature block')
    Check "Authenticode block present: $($file.Name)" $block.Success
    $base64 = ($block.Groups[1].Value -replace '(?m)^#\s?', '') -replace '\s', ''
    $cms = New-Object Security.Cryptography.Pkcs.SignedCms
    $cms.Decode([Convert]::FromBase64String($base64))
    $cms.CheckSignature($true)
    Check "SHA256 CMS signature: $($file.Name)" ($cms.SignerInfos.Count -eq 1 -and
        $cms.SignerInfos[0].DigestAlgorithm.Value -eq '2.16.840.1.101.3.4.2.1' -and
        $cms.SignerInfos[0].Certificate.Thumbprint -ieq $CertificateThumbprint)
    [pscustomobject]@{path=$file.FullName.Substring($ExtractedRoot.Length+1);status=[string]$signature.Status;
        message=$signature.StatusMessage;thumbprint=$signature.SignerCertificate.Thumbprint}
}
$result = [pscustomobject]@{files=$manifest.Count;vendorFiles=$vendor.Count;firstPartyScripts=$scripts.Count;
    checks=$checks.Count;passed=@($checks | Where-Object passed -eq $true).Count;
    trustedSignatures=@($signatures | Where-Object status -eq 'Valid').Count;signatures=@($signatures)}
if ($ResultsPath) { $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ResultsPath -Encoding UTF8 }
$result
