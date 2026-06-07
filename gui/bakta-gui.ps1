# Bakta for Windows - graphical front-end for non-technical users.
# Pure PowerShell + WinForms (.NET Framework, present on every Windows 10/11) - no
# extra runtime. It drives the bundled Bakta (embedded Python + bin\ tools + perl\).
# Launched console-less via Bakta-GUI.vbs. Run with -SelfTest to build the UI and exit.
param([switch]$SelfTest)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# --- locate the bundled Bakta (installed layout: <app>\gui, <app>\python, <app>\bin, <app>\perl) ---
$app    = Split-Path $PSScriptRoot -Parent
$python = Join-Path $app 'python\python.exe'
$bin    = Join-Path $app 'bin'
$blast  = Join-Path $bin 'blast\ncbi-blast-2.17.0+\bin'
$perlbin= Join-Path $app 'perl\bin'
if (-not (Test-Path $python)) { $python = 'python' }   # dev fallback: system / venv Python

# Prepend the bundled tool dirs so bakta finds every helper (.exe).
$env:PATH = "$bin;$blast;$perlbin;" + $env:PATH

# --- persisted settings (remember the DB folder) ---
$cfgDir  = Join-Path $env:APPDATA 'BaktaForWindows'
$cfgFile = Join-Path $cfgDir 'settings.txt'
function Get-SavedDb { if (Test-Path $cfgFile) { (Get-Content $cfgFile -ErrorAction SilentlyContinue | Select-Object -First 1) } else { '' } }
function Save-Db($p) { try { New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null; Set-Content -Path $cfgFile -Value $p -Encoding ascii } catch {} }

# --- palette ---
$NAVY  = [System.Drawing.Color]::FromArgb(27,42,74)
$BLUE  = [System.Drawing.Color]::FromArgb(47,109,181)
$BG    = [System.Drawing.Color]::FromArgb(245,246,248)
$INK   = [System.Drawing.Color]::FromArgb(33,37,41)
$UIFONT = New-Object System.Drawing.Font('Segoe UI', 9.75)

$cpu = [Environment]::ProcessorCount
$defThreads = [math]::Min([math]::Max($cpu,1), 64)

# ---------------------------------------------------------------- form
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Bakta for Windows'
$form.Size = New-Object System.Drawing.Size(700, 660)
$form.MinimumSize = New-Object System.Drawing.Size(600, 600)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $BG
$form.Font = $UIFONT
try { $form.Icon = [System.Drawing.SystemIcons]::Application } catch {}

# header strip
$header = New-Object System.Windows.Forms.Panel
$header.Size = New-Object System.Drawing.Size(700, 58); $header.Location = New-Object System.Drawing.Point(0,0)
$header.BackColor = $NAVY; $header.Anchor = 'Top,Left,Right'
$title = New-Object System.Windows.Forms.Label
$title.Text = 'Bakta for Windows'; $title.ForeColor = [System.Drawing.Color]::White
$title.Font = New-Object System.Drawing.Font('Segoe UI', 15, [System.Drawing.FontStyle]::Bold)
$title.Location = New-Object System.Drawing.Point(16, 8); $title.AutoSize = $true
$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = 'rapid, standardized bacterial genome annotation - native Windows, no setup'
$subtitle.ForeColor = [System.Drawing.Color]::FromArgb(190,205,225)
$subtitle.Location = New-Object System.Drawing.Point(18, 36); $subtitle.AutoSize = $true
$header.Controls.AddRange(@($title, $subtitle)); $form.Controls.Add($header)

# helpers
function New-Label($text, $x, $y) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text; $l.Location = New-Object System.Drawing.Point($x, $y); $l.AutoSize = $true; $l.ForeColor = $INK
    return $l
}
function New-TextBox($x, $y, $w) {
    $t = New-Object System.Windows.Forms.TextBox
    $t.Location = New-Object System.Drawing.Point($x, $y); $t.Size = New-Object System.Drawing.Size($w, 24)
    $t.Anchor = 'Top,Left,Right'; return $t
}
function New-Button($text, $x, $y, $w) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text; $b.Location = New-Object System.Drawing.Point($x, $y); $b.Size = New-Object System.Drawing.Size($w, 25)
    $b.FlatStyle = 'Flat'; $b.BackColor = [System.Drawing.Color]::White; return $b
}

$lblGenome = New-Label 'Genome assembly (FASTA: .fasta / .fa / .fna, optionally .gz)' 16 74; $form.Controls.Add($lblGenome)
$txtGenome = New-TextBox 16 96 552; $form.Controls.Add($txtGenome)
$btnGenome = New-Button 'Browse...' 574 95 96; $btnGenome.Anchor='Top,Right'; $form.Controls.Add($btnGenome)

$lblOut = New-Label 'Output folder' 16 128; $form.Controls.Add($lblOut)
$txtOut = New-TextBox 16 150 552; $form.Controls.Add($txtOut)
$btnOut = New-Button 'Browse...' 574 149 96; $btnOut.Anchor='Top,Right'; $form.Controls.Add($btnOut)

$lblDb = New-Label 'Bakta database folder (contains bakta.db + amrfinderplus-db)' 16 182; $form.Controls.Add($lblDb)
$txtDb = New-TextBox 16 204 432; $txtDb.Text = (Get-SavedDb); $form.Controls.Add($txtDb)
$btnDb = New-Button 'Browse...' 454 203 110; $btnDb.Anchor='Top,Right'; $form.Controls.Add($btnDb)
$btnGetDb = New-Button 'Download light DB...' 568 203 102; $btnGetDb.Anchor='Top,Right'; $form.Controls.Add($btnGetDb)

# options row
$lblPrefix = New-Label 'Output name (prefix)' 16 238; $form.Controls.Add($lblPrefix)
$txtPrefix = New-Object System.Windows.Forms.TextBox
$txtPrefix.Location = New-Object System.Drawing.Point(16, 260); $txtPrefix.Size = New-Object System.Drawing.Size(150, 24)
$txtPrefix.Text = 'result'; $form.Controls.Add($txtPrefix)

$lblT = New-Label 'Threads' 190 238; $form.Controls.Add($lblT)
$numT = New-Object System.Windows.Forms.NumericUpDown
$numT.Location = New-Object System.Drawing.Point(190, 260); $numT.Size = New-Object System.Drawing.Size(70, 24)
$numT.Minimum = 1; $numT.Maximum = 256; $numT.Value = $defThreads; $form.Controls.Add($numT)

$chkComplete = New-Object System.Windows.Forms.CheckBox
$chkComplete.Text = 'Complete replicons (--complete)'; $chkComplete.Location = New-Object System.Drawing.Point(285, 261)
$chkComplete.AutoSize = $true; $form.Controls.Add($chkComplete)

$chkKeep = New-Object System.Windows.Forms.CheckBox
$chkKeep.Text = 'Keep contig headers'; $chkKeep.Location = New-Object System.Drawing.Point(510, 261)
$chkKeep.AutoSize = $true; $form.Controls.Add($chkKeep)

# taxonomy (optional)
$lblGenus = New-Label 'Genus (optional)' 16 294; $form.Controls.Add($lblGenus)
$txtGenus = New-Object System.Windows.Forms.TextBox
$txtGenus.Location = New-Object System.Drawing.Point(16, 316); $txtGenus.Size = New-Object System.Drawing.Size(180, 24); $form.Controls.Add($txtGenus)
$lblSpecies = New-Label 'Species (optional)' 210 294; $form.Controls.Add($lblSpecies)
$txtSpecies = New-Object System.Windows.Forms.TextBox
$txtSpecies.Location = New-Object System.Drawing.Point(210, 316); $txtSpecies.Size = New-Object System.Drawing.Size(180, 24); $form.Controls.Add($txtSpecies)
$lblStrain = New-Label 'Strain (optional)' 404 294; $form.Controls.Add($lblStrain)
$txtStrain = New-Object System.Windows.Forms.TextBox
$txtStrain.Location = New-Object System.Drawing.Point(404, 316); $txtStrain.Size = New-Object System.Drawing.Size(180, 24); $form.Controls.Add($txtStrain)

# run / open buttons
$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = 'Run annotation'; $btnRun.Location = New-Object System.Drawing.Point(16, 354)
$btnRun.Size = New-Object System.Drawing.Size(160, 34); $btnRun.FlatStyle = 'Flat'
$btnRun.BackColor = $BLUE; $btnRun.ForeColor = [System.Drawing.Color]::White
$btnRun.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($btnRun)
$btnOpen = New-Button 'Open output folder' 186 358 150; $btnOpen.Enabled = $false; $form.Controls.Add($btnOpen)
$btnPlot = New-Button 'View genome plot' 346 358 150; $btnPlot.Enabled = $false; $form.Controls.Add($btnPlot)

# progress + status
$prog = New-Object System.Windows.Forms.ProgressBar
$prog.Location = New-Object System.Drawing.Point(16, 398); $prog.Size = New-Object System.Drawing.Size(654, 8)
$prog.Style = 'Marquee'; $prog.MarqueeAnimationSpeed = 0; $prog.Anchor='Top,Left,Right'; $form.Controls.Add($prog)
$status = New-Label 'Ready.' 16 410; $status.Anchor='Top,Left'; $status.ForeColor = $NAVY; $form.Controls.Add($status)

# log
$log = New-Object System.Windows.Forms.TextBox
$log.Location = New-Object System.Drawing.Point(16, 434); $log.Size = New-Object System.Drawing.Size(654, 168)
$log.Multiline = $true; $log.ReadOnly = $true; $log.ScrollBars = 'Vertical'; $log.WordWrap = $false
$log.BackColor = [System.Drawing.Color]::FromArgb(30,30,30); $log.ForeColor = [System.Drawing.Color]::FromArgb(212,212,212)
$log.Font = New-Object System.Drawing.Font('Consolas', 9); $log.Anchor = 'Top,Bottom,Left,Right'
$form.Controls.Add($log)

# ---------------------------------------------------------------- behaviour
$script:proc = $null; $script:logPath = $null; $script:logPos = 0; $script:outDir = $null; $script:prefix = 'result'

$btnGenome.Add_Click({
    $d = New-Object System.Windows.Forms.OpenFileDialog
    $d.Filter = 'Genome FASTA (*.fasta;*.fa;*.fna;*.gz)|*.fasta;*.fa;*.fna;*.fasta.gz;*.fa.gz;*.fna.gz|All files (*.*)|*.*'
    if ($d.ShowDialog() -eq 'OK') { $txtGenome.Text = $d.FileName }
})
$btnOut.Add_Click({ $d = New-Object System.Windows.Forms.FolderBrowserDialog; if ($d.ShowDialog() -eq 'OK') { $txtOut.Text = $d.SelectedPath } })
$btnDb.Add_Click({ $d = New-Object System.Windows.Forms.FolderBrowserDialog; $d.Description='Select the Bakta database folder (db-light or db)'; if ($d.ShowDialog() -eq 'OK') { $txtDb.Text = $d.SelectedPath; Save-Db $d.SelectedPath } })
$btnOpen.Add_Click({ if ($script:outDir -and (Test-Path $script:outDir)) { Start-Process explorer.exe $script:outDir } })
$btnPlot.Add_Click({
    $png = Join-Path $script:outDir ($script:prefix + '.png')
    if (Test-Path $png) { Start-Process $png } else { [System.Windows.Forms.MessageBox]::Show('No genome plot found.','Bakta') }
})

$btnGetDb.Add_Click({
    $d = New-Object System.Windows.Forms.FolderBrowserDialog
    $d.Description = 'Choose where to download the Bakta light database (~1.5 GB download, ~3 GB extracted)'
    if ($d.ShowDialog() -ne 'OK') { return }
    $dest = $d.SelectedPath
    $msg = "Download the Bakta LIGHT database into:`n$dest`n`nThis is ~1.5 GB and runs in a console window. Continue?"
    if ([System.Windows.Forms.MessageBox]::Show($msg,'Bakta','YesNo') -ne 'Yes') { return }
    # bakta_db downloads + extracts + runs amrfinder_update; show it in its own console.
    Start-Process -FilePath $python -ArgumentList @('-m','bakta.db','download','--output',('"'+$dest+'"'),'--type','light')
    [System.Windows.Forms.MessageBox]::Show("After it finishes, set the database folder to:`n$dest\db-light",'Bakta')
})

function Read-NewLog {
    if (-not $script:logPath -or -not (Test-Path $script:logPath)) { return '' }
    try {
        $fs = [System.IO.File]::Open($script:logPath, 'Open', 'Read', 'ReadWrite')
        [void]$fs.Seek($script:logPos, 'Begin')
        $sr = New-Object System.IO.StreamReader($fs)
        $new = $sr.ReadToEnd(); $script:logPos = $fs.Position
        $sr.Close(); $fs.Close(); return $new
    } catch { return '' }
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 800
$timer.Add_Tick({
    $new = Read-NewLog
    if ($new.Length) { $log.AppendText($new) }
    if ($script:proc -and $script:proc.HasExited) {
        $timer.Stop(); $log.AppendText((Read-NewLog)); $prog.MarqueeAnimationSpeed = 0; $btnRun.Enabled = $true
        if ($script:proc.ExitCode -eq 0) {
            $status.Text = "Done. Results in $script:outDir"
            $status.ForeColor = [System.Drawing.Color]::FromArgb(20,120,60)
            $btnOpen.Enabled = $true
            $btnPlot.Enabled = (Test-Path (Join-Path $script:outDir ($script:prefix + '.png')))
        } else {
            $status.Text = "Bakta failed (exit $($script:proc.ExitCode)). See the log."
            $status.ForeColor = [System.Drawing.Color]::FromArgb(170,30,30)
            $btnOpen.Enabled = (Test-Path $script:outDir)
        }
    }
})

$btnRun.Add_Click({
    $genome = $txtGenome.Text.Trim(); $out = $txtOut.Text.Trim(); $db = $txtDb.Text.Trim()
    $prefix = $txtPrefix.Text.Trim(); if (-not $prefix) { $prefix = 'result' }
    if (-not $genome -or -not (Test-Path $genome)) { [System.Windows.Forms.MessageBox]::Show('Please choose a valid genome FASTA file.','Bakta'); return }
    if (-not $out) { [System.Windows.Forms.MessageBox]::Show('Please choose an output folder.','Bakta'); return }
    if (-not $db -or -not (Test-Path (Join-Path $db 'bakta.db'))) { [System.Windows.Forms.MessageBox]::Show("Please choose a valid Bakta database folder (must contain bakta.db).`nUse 'Download light DB...' if you don't have one yet.",'Bakta'); return }
    New-Item -ItemType Directory -Force -Path $out | Out-Null
    Save-Db $db

    $q = { param($s) '"' + $s + '"' }
    $parts = New-Object System.Collections.ArrayList
    [void]$parts.Add('-m'); [void]$parts.Add('bakta.main')
    [void]$parts.Add('--db');     [void]$parts.Add((& $q $db))
    [void]$parts.Add('--output'); [void]$parts.Add((& $q $out))
    [void]$parts.Add('--prefix'); [void]$parts.Add($prefix)
    [void]$parts.Add('--threads');[void]$parts.Add([string]$numT.Value)
    [void]$parts.Add('--force')
    if ($txtGenus.Text.Trim())   { [void]$parts.Add('--genus');   [void]$parts.Add((& $q $txtGenus.Text.Trim())) }
    if ($txtSpecies.Text.Trim()) { [void]$parts.Add('--species'); [void]$parts.Add((& $q $txtSpecies.Text.Trim())) }
    if ($txtStrain.Text.Trim())  { [void]$parts.Add('--strain');  [void]$parts.Add((& $q $txtStrain.Text.Trim())) }
    if ($chkComplete.Checked)    { [void]$parts.Add('--complete') }
    if ($chkKeep.Checked)        { [void]$parts.Add('--keep-contig-headers') }
    [void]$parts.Add((& $q $genome))
    $argline = ($parts -join ' ')

    $script:outDir = $out; $script:prefix = $prefix
    $script:logPath = Join-Path $out ($prefix + '.log')
    $conOut = Join-Path $out 'gui_console.out.log'; $conErr = Join-Path $out 'gui_console.err.log'
    if (Test-Path $script:logPath) { Remove-Item $script:logPath -Force -ErrorAction SilentlyContinue }
    $script:logPos = 0; $log.Clear()
    $log.AppendText("> " + (& $q $python) + " " + $argline + "`r`n`r`n")
    $btnRun.Enabled = $false; $btnOpen.Enabled = $false; $btnPlot.Enabled = $false
    $prog.MarqueeAnimationSpeed = 30
    $status.Text = 'Running... (full annotation usually takes 1-5 minutes for a bacterial genome)'
    $status.ForeColor = $NAVY
    try {
        $script:proc = Start-Process -FilePath $python -ArgumentList $argline `
            -NoNewWindow -PassThru -RedirectStandardOutput $conOut -RedirectStandardError $conErr
        $timer.Start()
    } catch {
        $prog.MarqueeAnimationSpeed = 0; $btnRun.Enabled = $true
        $status.Text = "Could not start Bakta: $($_.Exception.Message)"
        $status.ForeColor = [System.Drawing.Color]::FromArgb(170,30,30)
    }
})

if ($SelfTest) { Write-Output 'SELFTEST OK'; return }
[void]$form.ShowDialog()
