param(
    [string]$ProjectDir,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Resolve-ProjectDir {
    param([string]$ExplicitDir)

    if ($ExplicitDir) {
        if (Test-Path $ExplicitDir) {
            return (Resolve-Path $ExplicitDir).Path
        }
        throw "Project directory not found: $ExplicitDir"
    }

    return (Resolve-Path (Join-Path $PSScriptRoot "..\prj")).Path
}

function Add-ExistingPath {
    param(
        [System.Collections.Generic.List[object]]$Items,
        [string]$Path,
        [string]$Type
    )

    if (Test-Path $Path) {
        $resolved = (Resolve-Path $Path).Path
        [void]$Items.Add([pscustomobject]@{
            Path = $resolved
            Type = $Type
        })
    }
}

$resolvedProjectDir = Resolve-ProjectDir -ExplicitDir $ProjectDir
$itemsToClean = New-Object System.Collections.Generic.List[object]

@(
    "db",
    "incremental_db",
    "output_files",
    "simulation"
) | ForEach-Object {
    Add-ExistingPath -Items $itemsToClean -Path (Join-Path $resolvedProjectDir $_) -Type "Directory"
}

$filePatterns = @(
    "*.rpt",
    "*.summary",
    "*.done",
    "*.pin",
    "*.sof",
    "*.pof",
    "*.jic",
    "*.jdi",
    "*.smsg",
    "*.qws",
    "*.qdf",
    "*.qar",
    "*.qarlog",
    "*.sld"
)

foreach ($pattern in $filePatterns) {
    Get-ChildItem -LiteralPath $resolvedProjectDir -Filter $pattern -File -ErrorAction SilentlyContinue | ForEach-Object {
        [void]$itemsToClean.Add([pscustomobject]@{
            Path = $_.FullName
            Type = "File"
        })
    }
}

$itemsToClean = $itemsToClean | Sort-Object Path -Unique

Write-Host "Project directory:" $resolvedProjectDir

if (-not $itemsToClean -or $itemsToClean.Count -eq 0) {
    Write-Host "No generated files found."
    exit 0
}

Write-Host "Generated items to clean:"
$itemsToClean | ForEach-Object {
    Write-Host ("[" + $_.Type + "] " + $_.Path)
}

if (-not $Force) {
    Write-Host ""
    Write-Host "Dry run only. Add -Force to delete these items."
    exit 0
}

foreach ($item in $itemsToClean) {
    Remove-Item -LiteralPath $item.Path -Recurse -Force
}

Write-Host ""
Write-Host "Clean finished."
