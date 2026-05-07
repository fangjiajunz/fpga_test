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

function Write-ReportLine {
    param(
        [string]$Label,
        [string]$Value
    )

    Write-Host ("  {0,-34} {1}" -f $Label, $Value)
}

function Get-SummaryValue {
    param(
        [string[]]$Lines,
        [string]$Label
    )

    $escapedLabel = [regex]::Escape($Label)
    foreach ($line in $Lines) {
        $match = [regex]::Match($line, "^\s*$escapedLabel\s*:\s*(.+?)\s*$")
        if ($match.Success) {
            return $match.Groups[1].Value
        }
    }

    return $null
}

function Write-CompileReportSummary {
    param(
        [string]$ProjectDirectory,
        [string]$RevisionName
    )

    $outputDir = Join-Path $ProjectDirectory "output_files"
    $fitSummaryPath = Join-Path $outputDir ($RevisionName + ".fit.summary")
    $staSummaryPath = Join-Path $outputDir ($RevisionName + ".sta.summary")
    $staReportPath = Join-Path $outputDir ($RevisionName + ".sta.rpt")
    $fitReportPath = Join-Path $outputDir ($RevisionName + ".fit.rpt")

    Write-Host ""
    Write-Host "================ Compile Report Summary ================"

    if (Test-Path $fitSummaryPath) {
        $fitLines = Get-Content -LiteralPath $fitSummaryPath

        Write-Host "Resource usage:"
        foreach ($label in @(
            "Family",
            "Device",
            "Total logic elements",
            "Total registers",
            "Total pins",
            "Total memory bits",
            "Embedded Multiplier 9-bit elements",
            "Total PLLs"
        )) {
            $value = Get-SummaryValue -Lines $fitLines -Label $label
            if ($value) {
                Write-ReportLine -Label $label -Value $value
            }
        }
    }
    else {
        Write-Host "Resource usage: not found $fitSummaryPath"
    }

    if (Test-Path $staSummaryPath) {
        $staLines = Get-Content -LiteralPath $staSummaryPath

        Write-Host "Timing slack:"
        $currentType = $null
        foreach ($line in $staLines) {
            $typeMatch = [regex]::Match($line, "^\s*Type\s*:\s*(.+?)\s*$")
            if ($typeMatch.Success) {
                $currentType = $typeMatch.Groups[1].Value
                continue
            }

            $slackMatch = [regex]::Match($line, "^\s*Slack\s*:\s*(.+?)\s*$")
            if ($slackMatch.Success -and $currentType) {
                Write-ReportLine -Label $currentType -Value ("Slack " + $slackMatch.Groups[1].Value + " ns")
                continue
            }

            $tnsMatch = [regex]::Match($line, "^\s*TNS\s*:\s*(.+?)\s*$")
            if ($tnsMatch.Success -and $currentType) {
                Write-ReportLine -Label ($currentType + " TNS") -Value ($tnsMatch.Groups[1].Value + " ns")
            }
        }

        $fmaxRows = @()
        $worstSlackLine = $null
        if (Test-Path $staReportPath) {
            $currentFmaxModel = $null
            foreach ($line in Get-Content -LiteralPath $staReportPath) {
                $fmaxHeaderMatch = [regex]::Match($line, ";\s*(.+? Model) Fmax Summary\s*;")
                if ($fmaxHeaderMatch.Success) {
                    $currentFmaxModel = $fmaxHeaderMatch.Groups[1].Value
                    continue
                }

                if ($currentFmaxModel) {
                    $fmaxRowMatch = [regex]::Match($line, ";\s*([^;]+?MHz)\s*;\s*([^;]+?)\s*;\s*([^;]+?)\s*;")
                    if ($fmaxRowMatch.Success) {
                        $clockName = $fmaxRowMatch.Groups[3].Value.Trim()
                        $fmaxValue = $fmaxRowMatch.Groups[1].Value.Trim()
                        $restrictedFmaxValue = $fmaxRowMatch.Groups[2].Value.Trim()
                        $fmaxRows += [pscustomobject]@{
                            Model = $currentFmaxModel
                            Clock = $clockName
                            Fmax = $fmaxValue
                            RestrictedFmax = $restrictedFmaxValue
                        }
                        $currentFmaxModel = $null
                    }
                    elseif ($line -match "^\s*$") {
                        $currentFmaxModel = $null
                    }
                }
            }

            $worstSlackLine = Select-String -LiteralPath $staReportPath -Pattern "Worst-case Slack" -SimpleMatch |
                Select-Object -First 1
        }

        if ($fmaxRows.Count -gt 0) {
            Write-Host "Fmax:"
            foreach ($row in $fmaxRows) {
                Write-ReportLine -Label ($row.Model + " " + $row.Clock) -Value ($row.Fmax + " (restricted " + $row.RestrictedFmax + ")")
            }
        }

        if ($worstSlackLine) {
            $cells = $worstSlackLine.Line.Trim(" ;") -split "\s*;\s*"
            if ($cells.Count -ge 6) {
                Write-Host "Worst-case slack:"
                Write-ReportLine -Label "Setup" -Value ($cells[1] + " ns")
                Write-ReportLine -Label "Hold" -Value ($cells[2] + " ns")
                Write-ReportLine -Label "Recovery" -Value $cells[3]
                Write-ReportLine -Label "Removal" -Value $cells[4]
                Write-ReportLine -Label "Minimum Pulse Width" -Value ($cells[5] + " ns")
            }
        }
    }
    else {
        Write-Host "Timing slack: not found $staSummaryPath"
    }

    Write-Host "Full reports:"
    if (Test-Path $fitReportPath) {
        Write-ReportLine -Label "Fitter" -Value $fitReportPath
    }
    if (Test-Path $staReportPath) {
        Write-ReportLine -Label "Timing" -Value $staReportPath
    }
    Write-Host "=============================================="
    Write-Host ""
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
        Write-CompileReportSummary -ProjectDirectory $projectDir -RevisionName $resolvedRevision
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
