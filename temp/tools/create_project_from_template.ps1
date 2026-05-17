param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectName,

    [string]$DestinationRoot = "..",
    [string]$TopEntity = "top",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Test-ProjectName {
    param([string]$Name)

    if ($Name -notmatch '^[A-Za-z0-9_]+$') {
        throw "ProjectName can contain only letters, digits, and underscores."
    }
}

function Copy-TemplateTree {
    param(
        [string]$SourceRoot,
        [string]$DestinationRootPath
    )

    $skipDirs = @(
        ".git",
        "prj\db",
        "prj\incremental_db",
        "prj\output_files",
        "prj\simulation"
    )

    $preserveDirs = @(
        "ip",
        "ipcore",
        "prj\ip",
        "prj\ipcore"
    )

    $skipFiles = @(
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
        "*.qarlog"
    )

    Get-ChildItem -LiteralPath $SourceRoot -Recurse -Force | ForEach-Object {
        $relativePath = $_.FullName.Substring($SourceRoot.Length).TrimStart("\")
        $isPreservedIpPath = $false

        foreach ($dir in $preserveDirs) {
            if ($relativePath -eq $dir -or $relativePath.StartsWith($dir + "\")) {
                $isPreservedIpPath = $true
                break
            }
        }

        if (-not $isPreservedIpPath) {
            foreach ($dir in $skipDirs) {
                if ($relativePath -eq $dir -or $relativePath.StartsWith($dir + "\")) {
                    return
                }
            }
        }

        if (-not $_.PSIsContainer -and -not $isPreservedIpPath) {
            foreach ($pattern in $skipFiles) {
                if ($_.Name -like $pattern) {
                    return
                }
            }
        }

        $targetPath = Join-Path $DestinationRootPath $relativePath

        if ($_.PSIsContainer) {
            if (-not (Test-Path $targetPath)) {
                New-Item -ItemType Directory -Path $targetPath | Out-Null
            }
        }
        else {
            $targetDir = Split-Path -Parent $targetPath
            if (-not (Test-Path $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir | Out-Null
            }
            Copy-Item -LiteralPath $_.FullName -Destination $targetPath -Force
        }
    }
}

function Rename-QuartusProject {
    param(
        [string]$ProjectRoot,
        [string]$Name,
        [string]$Entity
    )

    $prjDir = Join-Path $ProjectRoot "prj"
    $oldQpf = Get-ChildItem -LiteralPath $prjDir -Filter "*.qpf" | Select-Object -First 1
    $oldQsf = Get-ChildItem -LiteralPath $prjDir -Filter "*.qsf" | Select-Object -First 1

    if (-not $oldQpf -or -not $oldQsf) {
        throw "Cannot find .qpf/.qsf under: $prjDir"
    }

    $newQpf = Join-Path $prjDir ($Name + ".qpf")
    $newQsf = Join-Path $prjDir ($Name + ".qsf")

    if ($oldQpf.FullName -ne $newQpf) {
        Rename-Item -LiteralPath $oldQpf.FullName -NewName ($Name + ".qpf")
    }

    if ($oldQsf.FullName -ne $newQsf) {
        Rename-Item -LiteralPath $oldQsf.FullName -NewName ($Name + ".qsf")
    }

    $qpfText = Get-Content -LiteralPath $newQpf -Raw
    $qpfText = $qpfText -replace 'PROJECT_REVISION\s*=\s*"[^"]+"', ('PROJECT_REVISION = "' + $Name + '"')
    Set-Content -LiteralPath $newQpf -Value $qpfText -Encoding Ascii

    $qsfText = Get-Content -LiteralPath $newQsf -Raw
    $qsfText = $qsfText -replace 'set_global_assignment -name TOP_LEVEL_ENTITY\s+\S+', ('set_global_assignment -name TOP_LEVEL_ENTITY ' + $Entity)
    Set-Content -LiteralPath $newQsf -Value $qsfText -Encoding Ascii
}

function Initialize-GitRepository {
    param([string]$ProjectRoot)

    $gitDir = Join-Path $ProjectRoot ".git"
    if (Test-Path -LiteralPath $gitDir) {
        Write-Host "Git repository already exists:" $ProjectRoot
        return
    }

    $gitCommand = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitCommand) {
        Write-Warning "git not found in PATH. Skipping repository initialization."
        return
    }

    & $gitCommand.Source -C $ProjectRoot init | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "git init failed for: $ProjectRoot"
    }

    Write-Host "Initialized git repository:" $ProjectRoot
}

Test-ProjectName -Name $ProjectName

$templateRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if ([System.IO.Path]::IsPathRooted($DestinationRoot)) {
    $destinationRootFull = [System.IO.Path]::GetFullPath($DestinationRoot)
}
else {
    $destinationRootFull = [System.IO.Path]::GetFullPath((Join-Path $templateRoot $DestinationRoot))
}
$newProjectRoot = Join-Path $destinationRootFull $ProjectName

if (Test-Path $newProjectRoot) {
    if (-not $Force) {
        throw "Destination already exists: $newProjectRoot. Use -Force to overwrite files."
    }
}
else {
    New-Item -ItemType Directory -Path $newProjectRoot | Out-Null
}

Copy-TemplateTree -SourceRoot $templateRoot -DestinationRootPath $newProjectRoot
Rename-QuartusProject -ProjectRoot $newProjectRoot -Name $ProjectName -Entity $TopEntity

Write-Host "Created project:" $newProjectRoot
Write-Host "Quartus project:" (Join-Path $newProjectRoot ("prj\" + $ProjectName + ".qpf"))
Write-Host "Top entity:" $TopEntity
Write-Host "Git repository initialization: skipped"
