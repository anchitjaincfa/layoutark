#requires -Version 5.1
<#
.SYNOPSIS
  Creates a local-only inventory of Microsoft Publisher (.pub) files.

.DESCRIPTION
  Recursively examines file-system metadata without opening file contents. Directory
  reparse points are recorded as skipped and are never traversed. No network requests,
  Publisher automation, conversion, or export are performed.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateCount(1, 32)]
    [string[]] $Root = @([Environment]::GetFolderPath('UserProfile')),

    [string] $JsonPath = (Join-Path (Get-Location) 'layoutark-manifest.json'),
    [string] $CsvPath = (Join-Path (Get-Location) 'layoutark-files.csv'),

    [ValidateSet('profile', 'names', 'none')]
    [string] $Redaction = 'profile',

    [string] $HostLabel = $env:COMPUTERNAME
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:ScannerVersion = '1.0.0'

function ConvertTo-LayoutArkIsoUtc {
    param([datetime] $Value)
    return $Value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ', [Globalization.CultureInfo]::InvariantCulture)
}

function Get-LayoutArkSha256 {
    param([Parameter(Mandatory = $true)][string] $Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Protect-LayoutArkPath {
    param([AllowNull()][string] $Path, [string] $Mode, [string] $ProfilePath)
    if ([string]::IsNullOrEmpty($Path) -or $Mode -eq 'none') { return $Path }
    $profileFull = if ($ProfilePath) { [IO.Path]::GetFullPath($ProfilePath).TrimEnd('\', '/') } else { '' }
    if ($Mode -eq 'profile' -and $profileFull -and $Path.StartsWith($profileFull, [StringComparison]::OrdinalIgnoreCase)) {
        return '%USERPROFILE%' + $Path.Substring($profileFull.Length)
    }
    if ($Mode -eq 'names') {
        $root = [IO.Path]::GetPathRoot($Path)
        $leaf = Split-Path -Leaf $Path
        return $root + '<redacted-' + (Get-LayoutArkSha256 $Path).Substring(0, 12) + '>\' + $leaf
    }
    return $Path
}

function Get-LayoutArkCloudState {
    param([Parameter(Mandatory = $true)][IO.FileAttributes] $Attributes)
    # FILE_ATTRIBUTE_OFFLINE, RECALL_ON_OPEN, UNPINNED, and RECALL_ON_DATA_ACCESS.
    $placeholderMask = [int64]0x1000 -bor [int64]0x40000 -bor [int64]0x100000 -bor [int64]0x400000
    if (([int64]$Attributes -band $placeholderMask) -ne 0) { return 'placeholder' }
    if ($env:OS -eq 'Windows_NT') { return 'local' }
    return 'unknown'
}

function Add-LayoutArkError {
    param([hashtable] $Errors, [string] $Kind, [string] $Sample)
    if (-not $Errors.ContainsKey($Kind)) {
        $Errors[$Kind] = [ordered]@{ count = 0; samples = [Collections.Generic.List[string]]::new() }
    }
    $Errors[$Kind].count++
    if ($Sample -and $Errors[$Kind].samples.Count -lt 5 -and -not $Errors[$Kind].samples.Contains($Sample)) {
        $Errors[$Kind].samples.Add($Sample)
    }
}

function Get-LayoutArkRootKind {
    param([string] $Path, [string] $ProfilePath)
    if ($ProfilePath -and $Path.TrimEnd('\') -eq $ProfilePath.TrimEnd('\')) { return 'profile' }
    if ([IO.Path]::GetPathRoot($Path).TrimEnd('\') -eq $Path.TrimEnd('\')) { return 'drive' }
    return 'custom'
}

$started = [datetime]::UtcNow
$profile = [Environment]::GetFolderPath('UserProfile')
$errors = @{}
$files = [Collections.Generic.List[object]]::new()
$rootRecords = [Collections.Generic.List[object]]::new()

for ($rootIndex = 0; $rootIndex -lt $Root.Count; $rootIndex++) {
    $inputRoot = $Root[$rootIndex]
    try { $fullRoot = [IO.Path]::GetFullPath($inputRoot).TrimEnd('\', '/') }
    catch {
        Add-LayoutArkError $errors 'invalid-root' (Protect-LayoutArkPath $inputRoot $Redaction $profile)
        continue
    }
    $rootRecords.Add([ordered]@{
        index = $rootIndex
        path = Protect-LayoutArkPath $fullRoot $Redaction $profile
        kind = Get-LayoutArkRootKind $fullRoot $profile
    })
    if (-not [IO.Directory]::Exists($fullRoot)) {
        Add-LayoutArkError $errors 'missing-root' (Protect-LayoutArkPath $fullRoot $Redaction $profile)
        continue
    }

    $pending = [Collections.Generic.Stack[string]]::new()
    $pending.Push($fullRoot)
    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        try { $entries = [IO.Directory]::EnumerateFileSystemEntries($directory) }
        catch {
            Add-LayoutArkError $errors 'directory-access' (Protect-LayoutArkPath $directory $Redaction $profile)
            continue
        }
        foreach ($entry in $entries) {
            try {
                $attributes = [IO.File]::GetAttributes($entry)
                if (($attributes -band [IO.FileAttributes]::Directory) -ne 0) {
                    if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                        Add-LayoutArkError $errors 'reparse-point-skipped' (Protect-LayoutArkPath $entry $Redaction $profile)
                    }
                    else { $pending.Push($entry) }
                    continue
                }
                if (-not $entry.EndsWith('.pub', [StringComparison]::OrdinalIgnoreCase)) { continue }
                $info = [IO.FileInfo]::new($entry)
                $relative = $entry.Substring($fullRoot.Length).TrimStart('\', '/') -replace '\\', '/'
                $files.Add([ordered]@{
                    id = Get-LayoutArkSha256 (('{0}|{1}' -f $rootIndex, $relative.ToLowerInvariant()))
                    root = $rootIndex
                    relPath = $relative
                    name = $info.Name
                    sizeBytes = [int64]$info.Length
                    modifiedUtc = ConvertTo-LayoutArkIsoUtc $info.LastWriteTimeUtc
                    createdUtc = ConvertTo-LayoutArkIsoUtc $info.CreationTimeUtc
                    cloudState = Get-LayoutArkCloudState $attributes
                    readOnly = (($attributes -band [IO.FileAttributes]::ReadOnly) -ne 0)
                    pathLength = $entry.Length
                })
            }
            catch {
                Add-LayoutArkError $errors 'entry-metadata' (Protect-LayoutArkPath $entry $Redaction $profile)
            }
        }
    }
}

$errorRecords = @($errors.Keys | Sort-Object | ForEach-Object {
    [ordered]@{ kind = $_; count = $errors[$_].count; samples = @($errors[$_].samples) }
})
$finished = [datetime]::UtcNow
$manifest = [ordered]@{
    schema = 'layoutark.manifest'
    version = 1
    generator = [ordered]@{ name = 'layoutark-scan'; version = $script:ScannerVersion }
    generatedAt = ConvertTo-LayoutArkIsoUtc $finished
    host = [ordered]@{
        psEdition = if ($PSVersionTable.PSEdition) { $PSVersionTable.PSEdition } else { 'Desktop' }
        psVersion = $PSVersionTable.PSVersion.ToString()
        os = [Environment]::OSVersion.VersionString
        hostLabel = if ($HostLabel) { $HostLabel } else { 'unknown' }
        publisher = [ordered]@{ detected = 'unknown'; version = $null; via = 'not-probed' }
    }
    roots = @($rootRecords)
    scan = [ordered]@{
        startedAt = ConvertTo-LayoutArkIsoUtc $started
        finishedAt = ConvertTo-LayoutArkIsoUtc $finished
        complete = (($errorRecords | Where-Object { $_.kind -in @('invalid-root', 'missing-root', 'directory-access', 'entry-metadata') }).Count -eq 0)
        fileCount = $files.Count
        errors = $errorRecords
        redaction = $Redaction
    }
    files = @($files | Sort-Object root, relPath)
}

foreach ($output in @($JsonPath, $CsvPath)) {
    $parent = Split-Path -Parent ([IO.Path]::GetFullPath($output))
    if (-not [IO.Directory]::Exists($parent)) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
}
$utf8NoBom = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText([IO.Path]::GetFullPath($JsonPath), ($manifest | ConvertTo-Json -Depth 8), $utf8NoBom)

$csvRows = @($manifest.files | ForEach-Object {
    [pscustomobject][ordered]@{
        id = $_.id; root = $_.root; relPath = $_.relPath; name = $_.name
        sizeBytes = $_.sizeBytes; modifiedUtc = $_.modifiedUtc; createdUtc = $_.createdUtc
        cloudState = $_.cloudState; readOnly = $_.readOnly; pathLength = $_.pathLength
    }
})
$csvText = if ($csvRows.Count -gt 0) { ($csvRows | ConvertTo-Csv -NoTypeInformation) -join "`r`n" } else {
    '"id","root","relPath","name","sizeBytes","modifiedUtc","createdUtc","cloudState","readOnly","pathLength"'
}
[IO.File]::WriteAllText([IO.Path]::GetFullPath($CsvPath), $csvText + "`r`n", $utf8NoBom)
Write-Output $manifest
