param(
    [string]$SofPath,
    [string]$OutputPath,
    [string]$CpfPath,
    [string]$FlashDevice = "EPCS16",
    [string]$SflDevice,
    [switch]$NoGui
)

$ErrorActionPreference = "Stop"

function Resolve-QuartusCpf {
    param([string]$ExplicitPath)

    if ($ExplicitPath) {
        if (Test-Path $ExplicitPath) {
            return (Resolve-Path $ExplicitPath).Path
        }
        throw "quartus_cpf not found at: $ExplicitPath"
    }

    $cmd = Get-Command quartus_cpf.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    $cmd = Get-Command quartus_cpf -ErrorAction SilentlyContinue
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
            (Join-Path $root "quartus\bin64\quartus_cpf.exe"),
            (Join-Path $root "quartus\bin\quartus_cpf.exe"),
            (Join-Path $root "bin64\quartus_cpf.exe"),
            (Join-Path $root "bin\quartus_cpf.exe")
        )

        foreach ($candidate in $directCandidates) {
            if (Test-Path $candidate) {
                return (Resolve-Path $candidate).Path
            }
        }

        $found = Get-ChildItem -Path $root -Recurse -Filter quartus_cpf.exe -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending |
            Select-Object -First 1

        if ($found) {
            return $found.FullName
        }
    }

    throw "quartus_cpf.exe not found. Use -CpfPath to specify the Quartus converter path."
}

function Select-SofFile {
    Add-Type -AssemblyName System.Windows.Forms

    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = "Select SOF file"
    $dialog.Filter = "SOF files (*.sof)|*.sof|All files (*.*)|*.*"
    $dialog.Multiselect = $false

    $defaultDir = Join-Path $PSScriptRoot "..\prj\output_files"
    if (Test-Path $defaultDir) {
        $dialog.InitialDirectory = (Resolve-Path $defaultDir).Path
    }

    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        throw "No SOF file selected."
    }

    return $dialog.FileName
}

function Find-DefaultSofFile {
    $outputDir = Join-Path $PSScriptRoot "..\prj\output_files"
    if (-not (Test-Path $outputDir)) {
        return $null
    }

    $qpfFiles = Get-ChildItem -Path (Join-Path $PSScriptRoot "..\prj\*.qpf") -ErrorAction SilentlyContinue
    foreach ($qpfFile in $qpfFiles) {
        $qpfText = Get-Content -LiteralPath $qpfFile.FullName -Raw
        $match = [regex]::Match($qpfText, 'PROJECT_REVISION\s*=\s*"([^"]+)"')
        if ($match.Success) {
            $candidate = Join-Path $outputDir ($match.Groups[1].Value + ".sof")
            if (Test-Path $candidate) {
                return (Resolve-Path $candidate).Path
            }
        }
    }

    $sofFiles = Get-ChildItem -LiteralPath $outputDir -Filter "*.sof" -File -ErrorAction SilentlyContinue
    if ($sofFiles.Count -eq 1) {
        return $sofFiles[0].FullName
    }

    return $null
}

function Resolve-SflDevice {
    param([string]$ExplicitDevice)

    if ($ExplicitDevice) {
        return $ExplicitDevice
    }

    $qsfCandidates = @(
        (Join-Path $PSScriptRoot "..\prj\temp.qsf"),
        (Join-Path $PSScriptRoot "..\prj\*.qsf")
    )

    foreach ($candidate in $qsfCandidates) {
        $files = Get-ChildItem -Path $candidate -ErrorAction SilentlyContinue
        foreach ($file in $files) {
            $match = Select-String -Path $file.FullName -Pattern 'set_global_assignment -name DEVICE\s+([A-Za-z0-9_]+)' -AllMatches
            if ($match -and $match.Matches.Count -gt 0) {
                return $match.Matches[0].Groups[1].Value
            }
        }
    }

    throw "Unable to determine SFL device from .qsf. Use -SflDevice to specify the FPGA device."
}

$cpfExe = Resolve-QuartusCpf -ExplicitPath $CpfPath

if (-not $SofPath) {
    $SofPath = Find-DefaultSofFile
    if ($SofPath) {
        Write-Host "Auto selected SOF:" $SofPath
    }
    elseif ($NoGui) {
        throw "No SOF path provided and no default SOF was found under prj\output_files. Use -SofPath."
    }
    else {
        $SofPath = Select-SofFile
    }
}

if (-not (Test-Path $SofPath)) {
    throw "SOF file not found: $SofPath"
}

$sofFullPath = (Resolve-Path $SofPath).Path

if (-not $OutputPath) {
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($sofFullPath)
    $dirName = [System.IO.Path]::GetDirectoryName($sofFullPath)
    $OutputPath = Join-Path $dirName ($baseName + ".jic")
}

$outputFullPath = [System.IO.Path]::GetFullPath($OutputPath)
$outputDir = [System.IO.Path]::GetDirectoryName($outputFullPath)

if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

$resolvedSflDevice = Resolve-SflDevice -ExplicitDevice $SflDevice

$tempOutputRoot = if (Test-Path "D:\tmp") { "D:\tmp" } else { $env:TEMP }
$tempOutputPath = Join-Path $tempOutputRoot ([System.IO.Path]::GetFileName($outputFullPath))

if (Test-Path $tempOutputPath) {
    Remove-Item -LiteralPath $tempOutputPath -Force
}

& $cpfExe -c -d $FlashDevice -s $resolvedSflDevice $sofFullPath $tempOutputPath
if ($LASTEXITCODE -ne 0) {
    throw "quartus_cpf failed with exit code $LASTEXITCODE"
}

try {
    Copy-Item -LiteralPath $tempOutputPath -Destination $outputFullPath -Force
}
catch {
    $outputFullPath = [System.IO.Path]::GetFullPath($tempOutputPath)
}

Write-Host "Generated JIC:" $outputFullPath
Write-Host "Flash device:" $FlashDevice
Write-Host "SFL device:" $resolvedSflDevice
Write-Host "Converter:" $cpfExe
