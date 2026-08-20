param(
    [string]$Source = "jetpac.has",
    [string]$OutputName = "",
    [switch]$AllModules
)

# Environment overrides:
#   GFX_SPACE_CODE=32, GFX_SPACE_GLYPH=0
#   DISABLE_640x256=1       Omit hires 640x256 screen buffers
#   DISABLE_HAM=1           Omit HAM6 screen buffers

$ErrorActionPreference = "Stop"

if ($AllModules -or $Source -eq "all") {
    $ScriptPath = $MyInvocation.MyCommand.Path
    $Modules = @("jetpac.has", "frontpage.has")
    foreach ($module in $Modules) {
        Write-Host "=== Building module: $module ==="
        & $ScriptPath -Source $module
        if ($LASTEXITCODE -ne 0) {
            throw "Build failed for module $module with exit code $LASTEXITCODE"
        }
    }
    Write-Host "All modules built successfully."
    return
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = $ScriptDir
$BuildDir = Join-Path $Root "build"
$DefaultHascRoot = "C:\Users\prozentreter\Documents\highamigaassembler"
$HascRoot = if ($env:HASC_ROOT) { $env:HASC_ROOT } else { $DefaultHascRoot }
$LibDir = Join-Path $Root "lib"
if (-not (Test-Path $LibDir) -and (Test-Path (Join-Path $HascRoot "lib"))) {
    $LibDir = Join-Path $HascRoot "lib"
}

function Resolve-ExistingPath {
    param([string[]]$Candidates)
    foreach ($candidate in $Candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return $null
}

$SourcePath = Resolve-ExistingPath @(
    $Source,
    (Join-Path $ScriptDir $Source),
    (Join-Path $Root $Source)
)
if (-not $SourcePath) {
    throw "Source .has file not found: $Source"
}
if ([IO.Path]::GetExtension($SourcePath).ToLowerInvariant() -ne ".has") {
    throw "Source must be a .has file: $SourcePath"
}

if (-not $OutputName) {
    $OutputName = [IO.Path]::GetFileNameWithoutExtension($SourcePath)
}

$Python = if ($env:HASC_PYTHON) {
    $env:HASC_PYTHON
} else {
    Resolve-ExistingPath @(
        (Join-Path $HascRoot ".venv\Scripts\python.exe"),
        (Join-Path $Root ".venv\Scripts\python.exe"),
        "python"
    )
}
if (-not $Python) {
    throw "Python interpreter not found. Set HASC_PYTHON or install Python."
}

$Vasm = if ($env:VASM) { $env:VASM } else { "vasmm68k_mot" }
try {
    Get-Command $Vasm -ErrorAction Stop | Out-Null
} catch {
    throw "Assembler not found. Set VASM to the path of vasmm68k_mot."
}

$Vlink = if ($env:VLINK) { $env:VLINK } else { "vlink" }
try {
    Get-Command $Vlink -ErrorAction Stop | Out-Null
} catch {
    throw "Linker not found. Set VLINK to the path of vlink."
}

# --- vbccm68k (C compiler for 68000) ----------------------------------------
# Resolve compiler: VBCC_CC env override > vbccm68k on PATH > auto-detect next
# to the assembler binary (common bundled layout bin/vasmm68k_mot + bin/vbccm68k).
$VbccCC = $null
if ($env:VBCC_CC) {
    $VbccCC = $env:VBCC_CC
} else {
    $vasmPath = (Get-Command $Vasm -ErrorAction SilentlyContinue).Source
    if ($vasmPath) {
        $candidate = Join-Path (Split-Path -Parent $vasmPath) "vbccm68k.exe"
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $VbccCC = $candidate
        }
    }
    if (-not $VbccCC) {
        $found = Get-Command "vbccm68k.exe" -ErrorAction SilentlyContinue
        if ($found) { $VbccCC = $found.Source }
    }
    if (-not $VbccCC) {
        $found = Get-Command "vbccm68k" -ErrorAction SilentlyContinue
        if ($found) { $VbccCC = $found.Source }
    }
}
if (-not $VbccCC) {
    throw "vbccm68k not found. Set VBCC_CC to the path of vbccm68k.exe."
}

# Resolve vbcc include path: <vbcc_root>/targets/m68k-amigaos/include
# VBCC_ROOT env override, or auto-detected one directory above the compiler binary.
$VbccInclude = $null
if ($env:VBCC_ROOT) {
    $VbccInclude = Join-Path $env:VBCC_ROOT "targets\m68k-amigaos\include"
} else {
    $VbccBinDir = Split-Path -Parent $VbccCC
    $candidate  = Join-Path (Split-Path -Parent $VbccBinDir) "targets\m68k-amigaos\include"
    if (Test-Path $candidate -PathType Container) {
        $VbccInclude = $candidate
    }
}
if (-not $VbccInclude -or -not (Test-Path $VbccInclude -PathType Container)) {
    Write-Warning "vbcc include directory not found; compiling without -I flag."
    $VbccInclude = $null
}

$OutS = Join-Path $BuildDir ($OutputName + ".s")
$OutO = Join-Path $BuildDir ($OutputName + ".o")
$OutExe = Join-Path $BuildDir ($OutputName + ".exe")

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

$LibSources = @(
    "gui.s",
    "gui_keyboard.s",
    "graphics.s",
    "font8x8.s",
    "helpers.s",
    "takeover.s",
    "wbstartup.s",
    "input.s",
    "keyboard.s",
    "sprite.s",
    "str.s",
    "heap.s",
    "math.s",
    "bob.s",
    "fileio.s",
    "ptplayer.s",
    "debug.s"
) | ForEach-Object { Join-Path $LibDir $_ }

$SymToLib = @{}
foreach ($lib in $LibSources) {
    if (-not (Test-Path $lib)) { continue }
    foreach ($line in Get-Content $lib) {
        if ($line -match '^\s*xdef\s+([A-Za-z_][A-Za-z0-9_]*)') {
            $sym = $Matches[1]
            if (-not $SymToLib.ContainsKey($sym)) {
                $SymToLib[$sym] = $lib
            }
        }
    }
}

$ExternSymbols = @()
foreach ($line in Get-Content $SourcePath) {
    if ($line -match '^\s*extern\s+(func|var)\s+([A-Za-z_][A-Za-z0-9_]*)') {
        $ExternSymbols += $Matches[2]
    }
}
$ExternSymbols = $ExternSymbols | Sort-Object -Unique

$DebugExternUsed = $ExternSymbols | Where-Object { $_ -like "Debug*" } | Select-Object -First 1
if ($DebugExternUsed -and -not (Test-Path (Join-Path $LibDir "debug.s"))) {
    throw "$SourcePath declares Debug* externs, but required library '$LibDir\debug.s' is missing. Install/update highamigaassembler libs to include debug.s, or remove Debug* extern usage from source."
}

$WantLib = @{}
foreach ($sym in $ExternSymbols) {
    if ($SymToLib.ContainsKey($sym)) {
        $WantLib[$SymToLib[$sym]] = $true
    }
}

$SourceText = Get-Content $SourcePath -Raw
foreach ($sym in $SymToLib.Keys) {
    if ($SourceText -match "(^|[^A-Za-z0-9_])$([regex]::Escape($sym))([^A-Za-z0-9_]|$)") {
        $WantLib[$SymToLib[$sym]] = $true
    }
}

$changed = $true
while ($changed) {
    $changed = $false
    foreach ($lib in @($WantLib.Keys)) {
        $name = [IO.Path]::GetFileName($lib)
        $deps = @()
        switch ($name) {
            "gui.s" { $deps = @("gui_keyboard.s", "graphics.s", "input.s") }
            "gui_keyboard.s" { $deps = @("gui.s", "keyboard.s") }
            "graphics.s" { $deps = @("helpers.s", "sprite.s", "takeover.s") }
            { $_ -in @("input.s", "heap.s", "str.s") } { $deps = @("helpers.s") }
            "bob.s" { $deps = @("graphics.s", "helpers.s") }
            "ptplayer.s" { $deps = @("takeover.s") }
        }

        foreach ($depName in $deps) {
            $depPath = Join-Path $LibDir $depName
            if ((Test-Path $depPath) -and (-not $WantLib.ContainsKey($depPath))) {
                $WantLib[$depPath] = $true
                $changed = $true
            }
        }
    }
}

$OrderedLibs = @(
    "helpers.s",
    "takeover.s",
    "wbstartup.s",
    "graphics.s",
    "font8x8.s",
    "input.s",
    "keyboard.s",
    "sprite.s",
    "gui.s",
    "gui_keyboard.s",
    "str.s",
    "heap.s",
    "math.s",
    "bob.s",
    "fileio.s",
    "debug.s",
    "ptplayer.s"
) | ForEach-Object { Join-Path $LibDir $_ }
$SelectedLibs = $OrderedLibs | Where-Object { $WantLib.ContainsKey($_) }

Write-Host "=== Build: $SourcePath ==="
Write-Host "  Root  : $Root"
Write-Host "  Python: $Python"
Write-Host "  HASC  : $HascRoot"
Write-Host "  VASM  : $Vasm"
Write-Host "  VLINK : $Vlink"
Write-Host "  VBCC  : $VbccCC"
Write-Host "  Out   : $OutExe"
if ($SelectedLibs.Count -gt 0) {
    Write-Host "  Libs  :"
    foreach ($lib in $SelectedLibs) {
        Write-Host "    - $lib"
    }
}

$SourceDir = Split-Path -Parent $SourcePath
$SourceFile = Split-Path -Leaf $SourcePath
$oldLocation = Get-Location
try {
    Set-Location $SourceDir
    $env:PYTHONPATH = $HascRoot
    & $Python -m hasc.cli $SourceFile -o $OutS
    if ($LASTEXITCODE -ne 0) {
        throw "HAS compile failed with exit code $LASTEXITCODE"
    }
} finally {
    Set-Location $oldLocation
}

# PETSCII/screen-code space mapping: source char code vs. font glyph index used for it.
$GfxSpaceCode = if ($env:GFX_SPACE_CODE) { $env:GFX_SPACE_CODE } else { "32" }
# font8x8.s glyph 0 (index = char - 32) is already blank, so space must map there.
$GfxSpaceGlyph = if ($env:GFX_SPACE_GLYPH) { $env:GFX_SPACE_GLYPH } else { "0" }
$Disable640x256 = if ($env:DISABLE_640x256 -eq "1") { $true } else { $false }
$DisableHam = if ($env:DISABLE_HAM -eq "1") { $true } else { $false }
$HeapMemory = 0
$SourceBaseName = [IO.Path]::GetFileNameWithoutExtension($SourcePath)
switch ($SourceBaseName.ToLowerInvariant()) {
    "jetpac" {
        $Disable640x256 = $true
        $DisableHam = $true
        $HeapMemory = 131072
    }
    "frontpage" {
        $Disable640x256 = $true
        $DisableHam = $false
    }
}
$VasmArgs = @("-m68000", "-Fhunk", "-kick1hunks", "-nowarn=62", "-quiet", "-I", $LibDir)
$VasmArgs += @("-D", "GFX_SPACE_CODE=$GfxSpaceCode", "-D", "GFX_SPACE_GLYPH=$GfxSpaceGlyph")
if ($Disable640x256) {
    $VasmArgs += @("-D", "DISABLE_640x256=1")
}
if ($DisableHam) {
    $VasmArgs += @("-D", "DISABLE_HAM=1")
}
if ($HeapMemory -ne 0) {
    $VasmArgs += @("-D", "HEAP_MEMORY=$HeapMemory")
}
& $Vasm @VasmArgs $OutS "-o" $OutO
if ($LASTEXITCODE -ne 0) {
    throw "Assembly of main source failed with exit code $LASTEXITCODE"
}

$Objects = [System.Collections.Generic.List[string]]::new()
$Objects.Add($OutO)
foreach ($lib in $SelectedLibs) {
    $obj = Join-Path $BuildDir (([IO.Path]::GetFileNameWithoutExtension($lib)) + ".o")
    & $Vasm @VasmArgs $lib "-o" $obj
    if ($LASTEXITCODE -ne 0) {
        throw "Assembly failed for library $lib with exit code $LASTEXITCODE"
    }
    $Objects.Add($obj)
}

$AssetsDir = Join-Path $Root "assets"
if (Test-Path $AssetsDir) {
    Get-ChildItem -Path $AssetsDir -Filter *.s | Sort-Object Name | ForEach-Object {
        $obj = Join-Path $BuildDir ($_.BaseName + ".o")
        & $Vasm @VasmArgs $_.FullName "-o" $obj
        if ($LASTEXITCODE -ne 0) {
            throw "Assembly failed for asset $($_.FullName) with exit code $LASTEXITCODE"
        }
        $Objects.Add($obj)
    }
}

# --- Compile star.c with vbccm68k ----------------------------------------
$StarC   = Join-Path $Root "star.c"
$StarS   = Join-Path $BuildDir "star_c.s"
$StarO   = Join-Path $BuildDir "star.o"
if (Test-Path $StarC) {
    Write-Host "  C compile: star.c"
    $VbccArgs = @("-cpu=68000", "-quiet", "-o=$StarS")
    if ($VbccInclude) { $VbccArgs += "-I=$VbccInclude" }
    $VbccArgs += $StarC
    & $VbccCC @VbccArgs
    if ($LASTEXITCODE -ne 0) {
        throw "vbccm68k compilation of star.c failed with exit code $LASTEXITCODE"
    }
    # Assemble the generated source; skip -kick1hunks to stay compatible with
    # the opt/idnt directives that vbccm68k emits, add -nowarn=62 as per vbcc config.
    $VbccVasmArgs = @("-m68000", "-Fhunk", "-nowarn=62", "-quiet", "-I", $LibDir)
    $VbccVasmArgs += @("-D", "GFX_SPACE_CODE=$GfxSpaceCode", "-D", "GFX_SPACE_GLYPH=$GfxSpaceGlyph")
    if ($Disable640x256) {
        $VbccVasmArgs += @("-D", "DISABLE_640x256=1")
    }
    if ($DisableHam) {
        $VbccVasmArgs += @("-D", "DISABLE_HAM=1")
    }
    if ($HeapMemory -ne 0) {
        $VbccVasmArgs += @("-D", "HEAP_MEMORY=$HeapMemory")
    }
    & $Vasm @VbccVasmArgs $StarS "-o" $StarO
    if ($LASTEXITCODE -ne 0) {
        throw "Assembly of star_c.s failed with exit code $LASTEXITCODE"
    }
    $Objects.Add($StarO)
    Write-Host "  star.o added to link"
} else {
    Write-Warning "star.c not found at $StarC - skipping C star module"
}


& $Vlink "-bamigahunk" "-Bstatic" @($Objects.ToArray()) "-o" $OutExe
if ($LASTEXITCODE -ne 0) {
    throw "Link failed with exit code $LASTEXITCODE"
}

Write-Host "Done: $OutExe"