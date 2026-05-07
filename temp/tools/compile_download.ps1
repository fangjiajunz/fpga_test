param(
    [string]$ProjectPath,
    [string]$Revision,
    [string]$SofPath,
    [string]$Cable,
    [string]$QuartusShPath,
    [string]$QuartusPgmPath,
    [switch]$CompileOnly,
    [switch]$DownloadOnly,
    [switch]$ListCables
)

$ErrorActionPreference = "Stop"

function Resolve-QuartusTool {
    param(
        [string]$ToolName,
        [string]$ExplicitPath
    )

    if ($ExplicitPath) {
        if (Test-Path $ExplicitPath) {
            return (Resolve-Path $ExplicitPath).Path
        }
        throw "$ToolName not found at: $ExplicitPath"
    }

    $cmd = Get-Command ($ToolName + ".exe") -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    $cmd = Get-Command $ToolName -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    $searchRoots = New-Object System.Collections.Generic.List[string]

    $uninstallKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    foreach ($key in $uninstallKeys) {
        if (-not (Test-Path $key)) {
            continue
        }

        Get-ChildItem $key -ErrorAction SilentlyContinue | ForEach-Object {
            $item = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($null -ne $item -and $item.DisplayName -match "Quartus|Intel FPGA|Altera") {
                if ($item.InstallLocation) {
                    [void]$searchRoots.Add($item.InstallLocation)
                }
            }
        }
    }

    @(
        "C:\intelFPGA",
        "C:\intelFPGA_lite",
        "C:\altera",
        "D:\intelFPGA",
        "D:\intelFPGA_lite",
        "D:\altera",
        "D:\interfpga\Quartus"
    ) | ForEach-Object {
        [void]$searchRoots.Add($_)
    }

    foreach ($root in $searchRoots) {
        if (-not (Test-Path $root)) {
            continue
        }

        $directCandidates = @(
            (Join-Path $root ("quartus\bin64\" + $ToolName + ".exe")),
            (Join-Path $root ("quartus\bin\" + $ToolName + ".exe")),
            (Join-Path $root ("bin64\" + $ToolName + ".exe")),
            (Join-Path $root ("bin\" + $ToolName + ".exe"))
        )

        foreach ($candidate in $directCandidates) {
            if (Test-Path $candidate) {
                return (Resolve-Path $candidate).Path
            }
        }

        $found = Get-ChildItem -Path $root -Recurse -Filter ($ToolName + ".exe") -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending |
            Select-Object -First 1

        if ($found) {
            return $found.FullName
        }
    }

    throw "$ToolName.exe not found. Use the explicit path parameter to specify it."
}

function Resolve-ProjectPath {
    param([string]$ExplicitPath)

    if ($ExplicitPath) {
        if (Test-Path $ExplicitPath) {
            return (Resolve-Path $ExplicitPath).Path
        }
        throw "Quartus project file not found: $ExplicitPath"
    }

    $prjDir = Join-Path $PSScriptRoot "..\prj"
    $qpfFiles = Get-ChildItem -LiteralPath $prjDir -Filter "*.qpf" -ErrorAction SilentlyContinue

    if ($qpfFiles.Count -eq 0) {
        throw "No .qpf file found under: $prjDir"
    }

    if ($qpfFiles.Count -gt 1) {
        throw "Multiple .qpf files found. Use -ProjectPath to specify one."
    }

    return $qpfFiles[0].FullName
}

function Resolve-RevisionName {
    param(
        [string]$ProjectFile,
        [string]$ExplicitRevision
    )

    if ($ExplicitRevision) {
        return $ExplicitRevision
    }

    $projectText = Get-Content -LiteralPath $ProjectFile -Raw
    $match = [regex]::Match($projectText, 'PROJECT_REVISION\s*=\s*"([^"]+)"')
    if ($match.Success) {
        return $match.Groups[1].Value
    }

    return [System.IO.Path]::GetFileNameWithoutExtension($ProjectFile)
}

function Resolve-SofPath {
    param(
        [string]$ProjectFile,
        [string]$RevisionName,
        [string]$ExplicitPath
    )

    if ($ExplicitPath) {
        if (Test-Path $ExplicitPath) {
            return (Resolve-Path $ExplicitPath).Path
        }
        throw "SOF file not found: $ExplicitPath"
    }

    $projectDir = Split-Path -Parent $ProjectFile
    $candidate = Join-Path $projectDir ("output_files\" + $RevisionName + ".sof")
    if (Test-Path $candidate) {
        return (Resolve-Path $candidate).Path
    }

    throw "SOF file not found: $candidate. Run compile first or use -SofPath."
}

$quartusShExe = Resolve-QuartusTool -ToolName "quartus_sh" -ExplicitPath $QuartusShPath
$quartusPgmExe = Resolve-QuartusTool -ToolName "quartus_pgm" -ExplicitPath $QuartusPgmPath

if ($ListCables) {
    & $quartusPgmExe --list
    exit $LASTEXITCODE
}

$resolvedProjectPath = Resolve-ProjectPath -ExplicitPath $ProjectPath
$resolvedRevision = Resolve-RevisionName -ProjectFile $resolvedProjectPath -ExplicitRevision $Revision
$projectDir = Split-Path -Parent $resolvedProjectPath
$projectName = [System.IO.Path]::GetFileNameWithoutExtension($resolvedProjectPath)

if (-not $DownloadOnly) {
    Push-Location $projectDir
    try {
        Write-Host "Compiling project:" $resolvedProjectPath
        Write-Host "Revision:" $resolvedRevision
        & $quartusShExe --flow compile $projectName -c $resolvedRevision
        if ($LASTEXITCODE -ne 0) {
            throw "quartus_sh compile failed with exit code $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }
}

if ($CompileOnly) {
    Write-Host "Compile finished."
    exit 0
}

$resolvedSofPath = Resolve-SofPath -ProjectFile $resolvedProjectPath -RevisionName $resolvedRevision -ExplicitPath $SofPath
$operation = "p;$resolvedSofPath"

Write-Host "Downloading SOF:" $resolvedSofPath
if ($Cable) {
    Write-Host "Cable:" $Cable
    & $quartusPgmExe -m JTAG -c $Cable -o $operation
}
else {
    & $quartusPgmExe -m JTAG -o $operation
}

if ($LASTEXITCODE -ne 0) {
    throw "quartus_pgm download failed with exit code $LASTEXITCODE"
}

Write-Host "Compile/download finished."
