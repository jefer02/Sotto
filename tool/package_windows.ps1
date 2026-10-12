<#
.SYNOPSIS
  Builds and packages Sotto for Windows: a portable zip (with the Visual C++ runtime) and, when Inno
  Setup is available, an installer. Outputs go to dist/ with SHA-256 checksums.

.EXAMPLE
  # Local build with your key from secrets.json (git-ignored):
  powershell -ExecutionPolicy Bypass -File tool\package_windows.ps1

.EXAMPLE
  # CI: the app was already built with the key passed by --dart-define.
  powershell -File tool\package_windows.ps1 -SkipBuild -RequireInstaller
#>
param(
  [string]$Version,
  [switch]$SkipBuild,
  [string]$DefineFile = 'secrets.json',
  [string]$Out = 'dist',
  [switch]$RequireInstaller
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

if (-not $Version) {
  $line = Select-String -Path pubspec.yaml -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)' | Select-Object -First 1
  if (-not $line) { throw 'No version in pubspec.yaml' }
  $Version = $line.Matches[0].Groups[1].Value
}
Write-Host "Sotto $Version"

if (-not $SkipBuild) {
  $buildArgs = @('build', 'windows', '--release')
  if (Test-Path $DefineFile) {
    # The key stays in the file; nothing is printed.
    $buildArgs += "--dart-define-from-file=$DefineFile"
    Write-Host "Building with the key from $DefineFile"
  } else {
    Write-Warning "$DefineFile not found: building without a built-in DeepSeek key."
  }
  & flutter @buildArgs
  if ($LASTEXITCODE -ne 0) { throw 'flutter build windows failed' }
}

$release = Join-Path $root 'build\windows\x64\runner\Release'
if (-not (Test-Path (Join-Path $release 'sotto.exe'))) { throw "No build at $release" }

New-Item -ItemType Directory -Force $Out | Out-Null
$out = (Resolve-Path $Out).Path
$name = "Sotto-$Version-windows-x64"
$staging = Join-Path $env:TEMP "sotto-package\$name"
$app = Join-Path $staging 'Sotto'
if (Test-Path $staging) { Remove-Item -Recurse -Force $staging }
New-Item -ItemType Directory -Force $app | Out-Null
Copy-Item -Recurse -Force (Join-Path $release '*') $app
# Link-time leftovers (sotto_native.lib) and debug symbols aren't needed to run.
Get-ChildItem $app -Recurse -Include *.lib, *.exp, *.pdb, *.ilk | Remove-Item -Force

# The Visual C++ runtime the runner and plugins link against, so Sotto starts on a clean machine
# without the VC++ Redistributable. Copied from this machine's System32 (x64).
$vcRuntime = @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')
foreach ($dll in $vcRuntime) {
  $src = Join-Path $env:WINDIR "System32\$dll"
  if (-not (Test-Path $src)) { throw "$dll not found in System32: install the VC++ 2015-2022 x64 redistributable" }
  Copy-Item -Force $src $app
}

# Every DLL a binary imports must be in the folder or be part of Windows itself.
$dumpbin = $null
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhere) {
  # -prerelease: Preview and Insiders installs count too.
  $vs = & $vswhere -latest -prerelease -products * -property installationPath
  if ($vs) {
    $dumpbin = Get-ChildItem -Path (Join-Path $vs 'VC\Tools\MSVC') -Recurse -Filter dumpbin.exe -ErrorAction SilentlyContinue |
      Where-Object { $_.FullName -match 'Hostx64\\x64' } | Select-Object -First 1 -ExpandProperty FullName
  }
}
if ($dumpbin) {
  $bundled = Get-ChildItem $app -Recurse -Include *.dll, *.exe | ForEach-Object { $_.Name.ToLower() }
  $missing = @{}
  foreach ($bin in Get-ChildItem $app -Recurse -Include *.dll, *.exe) {
    # Only load-time imports: delay-loaded DLLs (dartjni.dll's jvm.dll, built when a JDK is around)
    # load on first use, which Sotto never makes.
    $deps = @()
    $delayed = $false
    foreach ($l in & $dumpbin /nologo /dependents $bin.FullName) {
      if ($l -match 'delay load dependencies') { $delayed = $true; continue }
      if ($l -match 'following dependencies') { $delayed = $false; continue }
      if (-not $delayed -and $l -match '^\s+\S+\.dll\s*$') { $deps += $l.Trim().ToLower() }
    }
    foreach ($dep in $deps) {
      if ($bundled -contains $dep) { continue }
      if ($dep -like 'api-ms-win-*' -or $dep -like 'ext-ms-*') { continue }   # Windows API sets
      if (Test-Path (Join-Path $env:WINDIR "System32\$dep")) {
        # In System32 — but the VC++ runtime there isn't on every machine.
        if ($dep -match '^(msvcp|vcruntime|concrt|vccorlib|vcomp)') { $missing[$dep] = $bin.Name }
        continue
      }
      $missing[$dep] = $bin.Name
    }
  }
  if ($missing.Count -gt 0) {
    $missing.GetEnumerator() | ForEach-Object { Write-Warning "Not bundled: $($_.Key) (needed by $($_.Value))" }
    throw 'Missing DLLs: the package would not start on a clean machine.'
  }
  Write-Host 'Dependencies: every imported DLL is bundled or part of Windows.'
} else {
  Write-Warning 'dumpbin not found: skipped the dependency check.'
}

# Portable zip: a single "Sotto" folder inside. Entries are written one by one with forward
# slashes (Windows PowerShell's CreateFromDirectory writes backslashes, which other unzip tools
# reject).
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = Join-Path $out "$name.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
$archive = [System.IO.Compression.ZipFile]::Open($zip, [System.IO.Compression.ZipArchiveMode]::Create)
try {
  foreach ($file in Get-ChildItem $app -Recurse -File) {
    $entry = 'Sotto/' + $file.FullName.Substring($app.Length + 1).Replace('\', '/')
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
      $archive, $file.FullName, $entry, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
  }
} finally {
  $archive.Dispose()
}
Write-Host "Portable: $zip"

# Installer, when Inno Setup 6 is around.
$iscc = (Get-Command iscc.exe -ErrorAction SilentlyContinue).Source
if (-not $iscc) {
  # Any Inno Setup version (6, 7…), per-machine or per-user; Chocolatey's install isn't on PATH.
  $iscc = @("${env:ProgramFiles(x86)}", "$env:ProgramFiles", "$env:LOCALAPPDATA\Programs") |
    ForEach-Object { Get-ChildItem -Path $_ -Directory -Filter 'Inno Setup*' -ErrorAction SilentlyContinue } |
    Sort-Object Name -Descending |
    ForEach-Object { Join-Path $_.FullName 'ISCC.exe' } |
    Where-Object { Test-Path $_ } | Select-Object -First 1
}
if ($iscc) {
  & $iscc /Q "/DAppVersion=$Version" "/DSourceDir=$app" "/DOutputDir=$out" (Join-Path $root 'windows\installer\sotto.iss')
  if ($LASTEXITCODE -ne 0) { throw 'Inno Setup failed' }
  Write-Host "Installer: $(Join-Path $out "$name-setup.exe")"
} elseif ($RequireInstaller) {
  throw 'Inno Setup (ISCC.exe) not found'
} else {
  Write-Warning 'Inno Setup not found: skipped the installer.'
}

# Checksums for what this script produced.
$files = Get-ChildItem $out -File | Where-Object { $_.Name -like "$name*" -and $_.Extension -ne ".sha256" }
$sums = foreach ($f in $files) { '{0}  {1}' -f (Get-FileHash -Algorithm SHA256 $f.FullName).Hash.ToLower(), $f.Name }
Set-Content -Path (Join-Path $out "$name.sha256") -Value $sums -Encoding ascii
$sums | ForEach-Object { Write-Host $_ }
