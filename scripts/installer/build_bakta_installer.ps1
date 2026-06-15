<#
.SYNOPSIS
    Build a single one-click Windows installer for the native Bakta port.

.DESCRIPTION
    Stages a self-contained payload and compiles it into Bakta-Windows-<ver>-Setup.exe
    with Inno Setup. The payload bundles everything needed to run Bakta on a stock
    Windows machine with NO prerequisites (no WSL/Docker, no system Python/Perl):

        bin\      ported static tool stack (.exe) + tRNAscan-SE Perl + trnascan-lib
        perl\     bundled Strawberry Perl runtime (for tRNAscan-SE)
        python\   embedded Python with Bakta + all packages (built here)
        gui\      the WinForms front-end + console-less VBS launcher
        bakta-shell.bat, README-WINDOWS.txt, LICENSE

    The Bakta DATABASE is intentionally NOT bundled (~1.5 GB); the app downloads it.

.PARAMETER PythonVersion
    Embeddable Python to bundle. Default 3.12.8 (all Bakta dep wheels available).

.PARAMETER BaktaVersion
    Bakta version to pip-install into the embedded Python. Default 1.12.0.
#>
[CmdletBinding()]
param(
    [string]$SrcRoot       = '',
    [string]$OutDir        = '',
    [string]$PythonVersion = '3.12.8',
    [string]$BaktaVersion  = '1.12.0',
    [string]$Iscc          = ''
)

$ErrorActionPreference = 'Stop'
function Info($m) { Write-Host "[installer] $m" -ForegroundColor Cyan }
function Die($m)  { Write-Host "[installer] ERROR: $m" -ForegroundColor Red; exit 1 }

# Python helper injected into bakta/utils.py (ends with the 'def test_dependencies():'
# anchor so it is inserted immediately before that function).
$BaktaResolveHelper = @'
def resolve_amrfinderplus_db_path(amrfinderplus_db_path: Path) -> Path:
    """Return a database directory that AMRFinderPlus can actually traverse.

    On Windows the 'latest' entry created when the AMRFinderPlus database is downloaded
    is frequently a non-traversable reparse point (accessing it raises WinError 1920).
    AMRFinderPlus stages the database with an internal `robocopy`, which then retries the
    unreadable source forever (default /R:1000000 /W:30) and hangs Bakta indefinitely.
    When 'latest' is unusable, fall back to the newest real versioned database directory
    (e.g. 2026-05-15.1), which native tools copy without issue.
    """
    latest_path = amrfinderplus_db_path.joinpath('latest')
    try:
        if latest_path.joinpath('AMRProt.fa.phr').is_file():
            return latest_path
    except OSError:
        pass
    versioned = []
    try:
        for entry in amrfinderplus_db_path.iterdir():
            if entry.name == 'latest':
                continue
            try:
                if entry.joinpath('AMRProt.fa.phr').is_file():
                    versioned.append(entry)
            except OSError:
                continue
    except OSError:
        pass
    if versioned:
        return sorted(versioned, key=lambda path: path.name)[-1]
    return latest_path  # nothing better found; let AMRFinderPlus report the error


def test_dependencies():
'@

# Make the pip-installed Bakta tolerant of a broken Windows 'latest' symlink in the
# AMRFinderPlus database (which otherwise hangs AMRFinderPlus' internal robocopy forever).
# Self-asserting: dies loudly if the upstream anchors move, so a broken installer is never shipped.
function Patch-BaktaAmrfinder([string]$pyDir, [string]$pyExe) {
    Info "Patching Bakta for the Windows AMRFinderPlus 'latest' symlink hang ..."
    $sp     = Join-Path $pyDir 'Lib\site-packages\bakta'
    $utils  = Join-Path $sp 'utils.py'
    $expert = Join-Path $sp 'expert\amrfinder.py'
    foreach ($f in @($utils, $expert)) { if (-not (Test-Path $f)) { Die "patch: missing '$f'" } }
    $latestLine = "amrfinderplus_db_latest_path = amrfinderplus_db_path.joinpath('latest')"

    # --- utils.py: inject resolver, use it in the dependency check, and never block on stdin ---
    $u = [System.IO.File]::ReadAllText($utils)
    if ($u -notmatch 'resolve_amrfinderplus_db_path') {
        if ($u -notmatch 'def test_dependencies\(\):')          { Die "patch: anchor 'def test_dependencies():' not in utils.py" }
        if (-not $u.Contains($latestLine))                       { Die "patch: 'latest' line not in utils.py" }
        if (-not $u.Contains("], capture_output=True)"))         { Die "patch: capture_output anchor not in utils.py" }
        $u = $u.Replace("def test_dependencies():", $BaktaResolveHelper)
        $u = $u.Replace($latestLine, "amrfinderplus_db_latest_path = resolve_amrfinderplus_db_path(amrfinderplus_db_path)")
        $u = $u.Replace("], capture_output=True)", "], capture_output=True, stdin=sp.DEVNULL)")
        [System.IO.File]::WriteAllText($utils, $u)
    }
    if ([System.IO.File]::ReadAllText($utils) -notmatch 'resolve_amrfinderplus_db_path\(amrfinderplus_db_path\)') { Die "patch: utils.py did not apply" }

    # --- expert/amrfinder.py: import utils and resolve the DB dir the same way ---
    $e = [System.IO.File]::ReadAllText($expert)
    if ($e -notmatch 'bu\.resolve_amrfinderplus_db_path') {
        if ($e -notmatch 'import bakta\.features\.orf as orf')   { Die "patch: import anchor not in expert/amrfinder.py" }
        if (-not $e.Contains($latestLine))                       { Die "patch: 'latest' line not in expert/amrfinder.py" }
        $e = $e.Replace("import bakta.features.orf as orf", "import bakta.features.orf as orf`r`nimport bakta.utils as bu")
        $e = $e.Replace($latestLine, "amrfinderplus_db_latest_path = bu.resolve_amrfinderplus_db_path(amrfinderplus_db_path)")
        [System.IO.File]::WriteAllText($expert, $e)
    }
    if ([System.IO.File]::ReadAllText($expert) -notmatch 'bu\.resolve_amrfinderplus_db_path') { Die "patch: expert/amrfinder.py did not apply" }

    & $pyExe -m py_compile $utils $expert
    if ($LASTEXITCODE -ne 0) { Die "patch: py_compile failed after patching" }
    Info "AMRFinderPlus 'latest' patch applied + compiled OK."
}

$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path $MyInvocation.MyCommand.Path -Parent }
if (-not $SrcRoot) { $SrcRoot = Split-Path (Split-Path $here -Parent) -Parent }
if (-not $OutDir)  { $OutDir  = Join-Path $SrcRoot 'dist' }
$iss     = Join-Path $here 'bakta_windows.iss'
$work    = Join-Path $env:LOCALAPPDATA 'bakta-dist'
$payload = Join-Path $work 'payload'
$dl      = Join-Path $work 'dl'

# --- sanity: the ported tools + perl + gui must be present ---
foreach ($need in @('bin\tRNAscan-SE.exe','bin\cmscan.exe','bin\amrfinder.exe','bin\diamond.exe','perl\bin\perl.exe','gui\bakta-gui.ps1','LICENSE')) {
    if (-not (Test-Path (Join-Path $SrcRoot $need))) { Die "missing '$need' under '$SrcRoot'." }
}

# --- locate ISCC (Inno Setup 6) ---
if (-not $Iscc) {
    $cands = @(
        (Join-Path $env:LOCALAPPDATA 'InnoSetup6\ISCC.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
        'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
        'C:\Program Files\Inno Setup 6\ISCC.exe'
    )
    $Iscc = $cands | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $Iscc -or -not (Test-Path $Iscc)) {
    Die "ISCC.exe (Inno Setup 6) not found. Install from https://jrsoftware.org/isdl.php or pass -Iscc."
}

New-Item -ItemType Directory -Force -Path $dl | Out-Null

# --- embedded Python (download if needed) ---
$pyZip = Join-Path $dl "python-$PythonVersion-embed-amd64.zip"
if (-not (Test-Path $pyZip)) {
    $url = "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-embed-amd64.zip"
    Info "Downloading embeddable Python $PythonVersion ..."
    Invoke-WebRequest -Uri $url -OutFile $pyZip -UseBasicParsing
}
$getpip = Join-Path $dl 'get-pip.py'
if (-not (Test-Path $getpip)) {
    Info "Downloading get-pip.py ..."
    Invoke-WebRequest -Uri 'https://bootstrap.pypa.io/get-pip.py' -OutFile $getpip -UseBasicParsing
}

# --- stage payload from scratch ---
if (Test-Path $payload) { Remove-Item $payload -Recurse -Force }
New-Item -ItemType Directory -Force -Path $payload | Out-Null

Info "Staging bin\, perl\, gui\ ..."
Copy-Item (Join-Path $SrcRoot 'bin')  (Join-Path $payload 'bin')  -Recurse -Force
Copy-Item (Join-Path $SrcRoot 'perl') (Join-Path $payload 'perl') -Recurse -Force
Copy-Item (Join-Path $SrcRoot 'gui')  (Join-Path $payload 'gui')  -Recurse -Force
Copy-Item (Join-Path $SrcRoot 'LICENSE') (Join-Path $payload 'LICENSE') -Force
foreach ($f in @('bakta-shell.bat','README-WINDOWS.txt')) {
    $p = Join-Path $SrcRoot $f
    if (Test-Path $p) { Copy-Item $p (Join-Path $payload $f) -Force }
}
Get-ChildItem $payload -Recurse -Directory -Filter '__pycache__' | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

# --- embedded Python + Bakta ---
Info "Staging embedded Python $PythonVersion ..."
$pyDir = Join-Path $payload 'python'
New-Item -ItemType Directory -Force -Path $pyDir | Out-Null
Expand-Archive -Path $pyZip -DestinationPath $pyDir -Force
# Enable site-packages + imports from the app root in the ._pth.
$pth = Get-ChildItem $pyDir -Filter 'python*._pth' | Select-Object -First 1
$mm  = ($PythonVersion -split '\.')[0..1] -join ''
@("python$mm.zip", '.', 'Lib\site-packages', 'import site') | Set-Content -Path $pth.FullName -Encoding ascii

Info "Bootstrapping pip + installing Bakta $BaktaVersion (this pulls pyrodigal, pyhmmer, pyCirclize, ...) ..."
$py = Join-Path $pyDir 'python.exe'
& $py $getpip --no-warn-script-location
if ($LASTEXITCODE -ne 0) { Die "get-pip failed" }
& $py -m pip install --no-warn-script-location "bakta==$BaktaVersion"
if ($LASTEXITCODE -ne 0) { Die "pip install bakta failed" }

# Apply the native-Windows AMRFinderPlus fix to the freshly pip-installed Bakta.
Patch-BaktaAmrfinder $pyDir $py

# trim caches
Get-ChildItem $pyDir -Recurse -Directory -Filter '__pycache__' | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

# --- version + compile ---
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Info "Compiling installer with Inno Setup ..."
& $Iscc "/DPayloadDir=$payload" "/DOutputDir=$OutDir" "/DAppVersion=$BaktaVersion" $iss
if ($LASTEXITCODE -ne 0) { Die "ISCC failed" }
Info "Done -> $OutDir\Bakta-Windows-$BaktaVersion-Setup.exe"
