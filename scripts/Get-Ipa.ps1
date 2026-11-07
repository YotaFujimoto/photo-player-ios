param(
    [Parameter(Mandatory)][string]$RunId,
    [Parameter(Mandatory)][string]$Commit,
    [string]$Repository
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot
$ghCommand = Get-Command gh -ErrorAction SilentlyContinue
$gh = if ($ghCommand) { $ghCommand.Source } else { Join-Path $env:ProgramFiles 'GitHub CLI\gh.exe' }
if (-not (Test-Path -LiteralPath $gh)) { throw 'GitHub CLI is required.' }

function Invoke-Gh {
    param([string[]]$Arguments)
    $output = & $gh @Arguments
    if ($LASTEXITCODE -ne 0) { throw "gh failed: $($Arguments -join ' ')" }
    return $output
}

if (-not $Repository) {
    $Repository = Invoke-Gh -Arguments @('repo', 'view', '--json', 'nameWithOwner', '--jq', '.nameWithOwner')
}
$run = (Invoke-Gh -Arguments @('api', "repos/$Repository/actions/runs/$RunId")) | ConvertFrom-Json
if ($run.status -ne 'completed' -or $run.conclusion -ne 'success') { throw 'CI has not succeeded.' }
if ($run.head_sha -ne $Commit) { throw 'CI commit differs from requested commit.' }
if ($run.path -ne '.github/workflows/ios.yml') { throw 'Unexpected workflow.' }

$dist = Join-Path $projectRoot 'dist'
$incoming = Join-Path $dist ('incoming-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $incoming -Force | Out-Null
Invoke-Gh -Arguments @('run', 'download', $RunId, '--repo', $Repository, '--name', 'PhotoPlayer-device-ipa', '--dir', $incoming)
$ipa = Join-Path $incoming 'PhotoPlayer.ipa'
$metadataPath = Join-Path $incoming 'build-info.json'
$metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
if ($metadata.commit -ne $Commit -or $metadata.run_id -ne $RunId -or $metadata.run_attempt -ne [string]$run.run_attempt) {
    throw 'Artifact provenance differs from CI.'
}
$bundleId = 'io.github.photoplayer.p6a936d329b934a8ba532081564a51c07'
$config = Get-Content -LiteralPath (Join-Path $projectRoot 'Config\Version.xcconfig') -Raw
$expectedBuild = [regex]::Match($config, '(?m)^CURRENT_PROJECT_VERSION\s*=\s*(\d+)\s*$').Groups[1].Value
if ($metadata.bundle_id -ne $bundleId -or $metadata.build_number -ne $expectedBuild) { throw 'Identity/build mismatch.' }
if ($metadata.platform -ne 'iOS' -or $metadata.architecture -ne 'arm64' -or $metadata.configuration -ne 'Release' -or $metadata.unsigned -ne $true) {
    throw 'Expected unsigned arm64 iOS Release artifact.'
}
$sha = (Get-FileHash -LiteralPath $ipa -Algorithm SHA256).Hash.ToLowerInvariant()
if ($sha -ne $metadata.sha256) { throw 'IPA SHA-256 mismatch.' }

# Independently inspect the downloaded ZIP, plist, and Mach-O on Windows.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($ipa)
try {
    if ($zip.Entries.FullName -match '_CodeSignature|embedded\.mobileprovision') { throw 'Signed package found.' }
    $plistEntry = $zip.GetEntry('Payload/PhotoPlayer.app/Info.plist')
    if (-not $plistEntry) { throw 'Device app Info.plist is missing.' }
    $reader = [IO.StreamReader]::new($plistEntry.Open())
    try { [xml]$plist = $reader.ReadToEnd() } finally { $reader.Dispose() }
    function Get-PlistValue([string]$Key) {
        $node = $plist.SelectSingleNode("/plist/dict/key[text()='$Key']")
        if (-not $node) { throw "Missing plist key: $Key" }
        return $node.NextSibling
    }
    if ((Get-PlistValue 'CFBundleIdentifier').InnerText -ne $bundleId) { throw 'Downloaded Bundle ID mismatch.' }
    if ((Get-PlistValue 'CFBundleVersion').InnerText -ne $expectedBuild) { throw 'Downloaded build mismatch.' }
    if ((Get-PlistValue 'CFBundleSupportedPlatforms').InnerText -ne 'iPhoneOS' -or
        (Get-PlistValue 'DTPlatformName').InnerText -ne 'iphoneos') { throw 'Simulator bundle rejected.' }
    $executable = $zip.GetEntry('Payload/PhotoPlayer.app/PhotoPlayer')
    if (-not $executable) { throw 'Executable missing.' }
    $memory = [IO.MemoryStream]::new()
    $stream = $executable.Open()
    try { $stream.CopyTo($memory); $bytes = $memory.ToArray() } finally { $stream.Dispose(); $memory.Dispose() }
    function Read-UInt32([int]$Offset) { return [BitConverter]::ToUInt32($bytes, $Offset) }
    if ((Read-UInt32 0) -ne 0xFEEDFACFu -or (Read-UInt32 4) -ne 0x0100000C -or (Read-UInt32 12) -ne 2) {
        throw 'Not a thin arm64 Mach-O executable.'
    }
    $offset = 32
    $end = 32 + (Read-UInt32 20)
    $platforms = @()
    for ($i = 0; $i -lt (Read-UInt32 16); $i++) {
        if ($offset + 8 -gt $end) { throw 'Invalid Mach-O command.' }
        $command = Read-UInt32 $offset
        $size = Read-UInt32 ($offset + 4)
        if ($size -lt 8 -or $offset + $size -gt $end) { throw 'Invalid Mach-O command length.' }
        if ($command -eq 0x1D) { throw 'Executable has a code signature.' }
        if ($command -eq 0x32) { $platforms += Read-UInt32 ($offset + 8) }
        $offset += $size
    }
    if ($offset -ne $end -or $platforms.Count -ne 1 -or $platforms[0] -ne 2) { throw 'Non-device Mach-O rejected.' }
} finally { $zip.Dispose() }

$destination = Join-Path $dist 'PhotoPlayer.ipa'
if (Test-Path -LiteralPath $destination) {
    $previousHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
    $history = Join-Path $dist 'history'
    New-Item -ItemType Directory -Path $history -Force | Out-Null
    Copy-Item -LiteralPath $destination -Destination (Join-Path $history "$previousHash.ipa")
    $previousMetadata = Join-Path $dist 'build-info.json'
    if (Test-Path -LiteralPath $previousMetadata) {
        Copy-Item -LiteralPath $previousMetadata -Destination (Join-Path $history "$previousHash.json")
    }
}
Copy-Item -LiteralPath $ipa -Destination $destination -Force
Copy-Item -LiteralPath $metadataPath -Destination (Join-Path $dist 'build-info.json') -Force
Write-Output "Verified IPA: $destination"
Write-Output "Build: $expectedBuild; SHA-256: $sha"
Write-Output "CI: $($run.html_url)"
