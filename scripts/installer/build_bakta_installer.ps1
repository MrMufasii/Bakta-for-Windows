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
# trim caches
Get-ChildItem $pyDir -Recurse -Directory -Filter '__pycache__' | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

# --- version + compile ---
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Info "Compiling installer with Inno Setup ..."
& $Iscc "/DPayloadDir=$payload" "/DOutputDir=$OutDir" "/DAppVersion=$BaktaVersion" $iss
if ($LASTEXITCODE -ne 0) { Die "ISCC failed" }
Info "Done -> $OutDir\Bakta-Windows-$BaktaVersion-Setup.exe"
