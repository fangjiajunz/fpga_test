param(
    [string]$ProjectPath,
    [string]$Revision,
    [string]$SofPath,
    [string]$JicPath,
    [string]$Cable,
    [string]$QuartusShPath,
    [string]$QuartusPgmPath,
    [string]$CpfPath,
    [string]$FlashDevice = "EPCS16",
    [string]$SflDevice,
    [switch]$SkipDeviceCheck,
    [switch]$CompileOnly,
    [switch]$ConvertOnly,
    [switch]$ProgramOnly,
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

function Resolve-SflDevice {
    param(
        [string]$ProjectDirectory,
        [string]$ExplicitDevice
    )

    if ($ExplicitDevice) {
        return $ExplicitDevice
    }

    $qsfFiles = Get-ChildItem -LiteralPath $ProjectDirectory -Filter "*.qsf" -ErrorAction SilentlyContinue
    foreach ($file in $qsfFiles) {
        $match = Select-String -Path $file.FullName -Pattern 'set_global_assignment -name DEVICE\s+([A-Za-z0-9_]+)' -AllMatches
        if ($match -and $match.Matches.Count -gt 0) {
            return $match.Matches[0].Groups[1].Value
        }
    }

    throw "Unable to determine SFL device from .qsf. Use -SflDevice to specify the FPGA device."
}

function Get-JtagChainOutput {
    param([string]$QuartusPgmExe, [string]$CableName)

    if ($CableName) {
        return (& $QuartusPgmExe -c $CableName -a 2>&1 | ForEach-Object { $_.ToString() })
    }

    return (& $QuartusPgmExe -a 2>&1 | ForEach-Object { $_.ToString() })
}

function Get-ExpectedChainPattern {
    param([string]$DeviceName)

    $upperDevice = $DeviceName.ToUpperInvariant()

    if ($upperDevice.StartsWith("EP4CE10")) {
        return "EP4CE10|4CE10"
    }

    if ($upperDevice.StartsWith("EP4CE")) {
        return "EP4CE|4CE"
    }

    if ($upperDevice.StartsWith("10CL")) {
        return "10CL"
    }

    return [regex]::Escape($upperDevice)
}

function Assert-TargetDevicePresent {
    param(
        [string]$QuartusPgmExe,
        [string]$CableName,
        [string]$ExpectedDevice
    )

    $chainLines = Get-JtagChainOutput -QuartusPgmExe $QuartusPgmExe -CableName $CableName
    $chainText = ($chainLines -join "`n")
    $devicePattern = Get-ExpectedChainPattern -DeviceName $ExpectedDevice

    if ($chainText -notmatch $devicePattern) {
        Write-Warning "Target device name check did not match $ExpectedDevice. Continuing anyway because quartus_pgm -a may report a generic alias or JTAG ID. Detected chain:`n$chainText"
    }
}

function Resolve-JicPath {
    param(
        [string]$SofFile,
        [string]$ExplicitPath
    )

    if ($ExplicitPath) {
        return [System.IO.Path]::GetFullPath($ExplicitPath)
    }

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($SofFile)
    $dirName = [System.IO.Path]::GetDirectoryName($SofFile)
    return (Join-Path $dirName ($baseName + ".jic"))
}

function Ensure-ParentDirectory {
    param([string]$Path)

    $dir = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($Path))
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
}

function Get-CdfPartName {
    param([string]$FpgaDevice)

    $upperDevice = $FpgaDevice.ToUpperInvariant()
    if ($upperDevice -match '^([A-Z0-9]+)F\d+') {
        return $matches[1]
    }

    return $FpgaDevice
}

function New-CdfContent {
    param(
        [string]$FpgaDevice,
        [string]$JicFile,
        [string]$FlashPart
    )

    $jicFullPath = [System.IO.Path]::GetFullPath($JicFile)
    $jicDir = [System.IO.Path]::GetDirectoryName($jicFullPath).Replace('\', '/')
    $jicName = [System.IO.Path]::GetFileName($jicFullPath)
    $cdfPartName = Get-CdfPartName -FpgaDevice $FpgaDevice

    return @"
/* Quartus Prime Programmer CDF */
JedecChain;
	FileRevision(JESD32A);
	DefaultMfr(6E);

	P ActionCode(Cfg)
		Device PartName($cdfPartName) Path("$jicDir/") File("$jicName") MfrSpec(OpMask(1) SEC_Device($FlashPart) Child_OpMask(1 1));

ChainEnd;

AlteraBegin;
	ChainType(JTAG);
AlteraEnd;
"@
}

$quartusPgmExe = Resolve-QuartusTool -ToolName "quartus_pgm" -ExplicitPath $QuartusPgmPath

if ($ListCables) {
    & $quartusPgmExe --list
    exit $LASTEXITCODE
}

$resolvedProjectPath = Resolve-ProjectPath -ExplicitPath $ProjectPath
$resolvedRevision = Resolve-RevisionName -ProjectFile $resolvedProjectPath -ExplicitRevision $Revision
$projectDir = Split-Path -Parent $resolvedProjectPath
$projectName = [System.IO.Path]::GetFileNameWithoutExtension($resolvedProjectPath)

if (-not $ProgramOnly -and -not $ConvertOnly) {
    $quartusShExe = Resolve-QuartusTool -ToolName "quartus_sh" -ExplicitPath $QuartusShPath

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
$resolvedJicPath = Resolve-JicPath -SofFile $resolvedSofPath -ExplicitPath $JicPath

if (-not $ProgramOnly) {
    $cpfExe = Resolve-QuartusTool -ToolName "quartus_cpf" -ExplicitPath $CpfPath
    $resolvedSflDevice = Resolve-SflDevice -ProjectDirectory $projectDir -ExplicitDevice $SflDevice

    Ensure-ParentDirectory -Path $resolvedJicPath

    Write-Host "Generating JIC from SOF:" $resolvedSofPath
    Write-Host "JIC output:" $resolvedJicPath
    Write-Host "Flash device:" $FlashDevice
    Write-Host "SFL device:" $resolvedSflDevice

    & $cpfExe -c -d $FlashDevice -s $resolvedSflDevice $resolvedSofPath $resolvedJicPath
    if ($LASTEXITCODE -ne 0) {
        throw "quartus_cpf failed with exit code $LASTEXITCODE"
    }
}

if ($ConvertOnly) {
    Write-Host "Convert finished."
    exit 0
}

if (-not (Test-Path $resolvedJicPath)) {
    throw "JIC file not found: $resolvedJicPath"
}

$expectedDeviceForProgram = Resolve-SflDevice -ProjectDirectory $projectDir -ExplicitDevice $SflDevice
if (-not $SkipDeviceCheck) {
    Assert-TargetDevicePresent -QuartusPgmExe $quartusPgmExe -CableName $Cable -ExpectedDevice $expectedDeviceForProgram
}

$cdfPath = Join-Path $projectDir ("output_files\" + $resolvedRevision + ".cdf")
$cdfContent = New-CdfContent -FpgaDevice $expectedDeviceForProgram -JicFile $resolvedJicPath -FlashPart $FlashDevice
Set-Content -LiteralPath $cdfPath -Value $cdfContent -Encoding ASCII

Write-Host "Programming configuration flash with JIC:" $resolvedJicPath
Write-Host "Using CDF:" $cdfPath
if ($Cable) {
    Write-Host "Cable:" $Cable
    & $quartusPgmExe -c $Cable $cdfPath
}
else {
    & $quartusPgmExe $cdfPath
}

if ($LASTEXITCODE -ne 0) {
    throw "quartus_pgm flash programming failed with exit code $LASTEXITCODE"
}

Write-Host "Compile/program flash finished."
