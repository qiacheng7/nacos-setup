# Java management for Windows nacos-setup
. $PSScriptRoot\common.ps1

$script:JDK17OssBase    = "https://download.nacos.io/base"
$script:BundledJreCache = if ($env:NACOS_CACHE_DIR) { $env:NACOS_CACHE_DIR } else { Join-Path $env:USERPROFILE ".nacos\cache" }
$script:BundledJreRoot  = if ($env:NACOS_SETUP_BUNDLED_JRE_DIR) {
    $env:NACOS_SETUP_BUNDLED_JRE_DIR
} else {
    $userBase = if ($env:REAL_USER_PROFILE) { $env:REAL_USER_PROFILE } elseif ($env:USERPROFILE) { $env:USERPROFILE } else { "." }
    Join-Path $userBase "ai-infra\nacos\.bundled-jre-17"
}

function Write-DebugLog($msg) {
    if ($env:NACOS_DEBUG -eq "1") { Write-Info "[DEBUG] $msg" }
}

function Get-JavaVersion($javaCmd) {
    if (-not $javaCmd) { return 0 }

    $resolvedCmd = $javaCmd
    if (Test-Path $resolvedCmd) {
        $resolvedCmd = (Resolve-Path $resolvedCmd).Path
    } else {
        $cmdInfo = Get-Command $resolvedCmd -ErrorAction SilentlyContinue
        if ($cmdInfo -and $cmdInfo.Source) { $resolvedCmd = $cmdInfo.Source }
    }

    Write-DebugLog "Java command resolved to: $resolvedCmd"

    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    try {
        $outputText = (& cmd /c "`"$resolvedCmd`" -version 2>&1" | Out-String)
        $firstLine = ($outputText -split "`r?`n" | Select-Object -First 1)
        if ($firstLine) { Write-DebugLog "java -version: $firstLine" }

        if ($outputText -match 'version\s+"([0-9]+)') { return [int]$Matches[1] }
        if ($outputText -match 'version\s+"1\.([0-9]+)') { return [int]$Matches[1] }
        if ($outputText -match '"([0-9]+)\.[0-9]+') { return [int]$Matches[1] }

        $settingsText = (& cmd /c "`"$resolvedCmd`" -XshowSettings:properties -version 2>&1" | Out-String)
        $settingsLine = ($settingsText -split "`r?`n" | Where-Object { $_ -match '^\s*java\.version\s*=' } | Select-Object -First 1)
        if ($settingsLine) { Write-DebugLog "java.version: $settingsLine" }
        if ($settingsText -match '(?m)^\s*java\.version\s*=\s*([0-9]+)') { return [int]$Matches[1] }
        if ($settingsText -match '(?m)^\s*java\.version\s*=\s*1\.([0-9]+)') { return [int]$Matches[1] }
        if ($settingsText -match '(?m)^\s*java\.version\s*=\s*([0-9]+)\.[0-9]+') { return [int]$Matches[1] }
    } catch {
        Write-DebugLog "Get-JavaVersion error: $($_.Exception.Message)"
    } finally {
        $ErrorActionPreference = $oldEap
    }

    try {
        $fileVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($resolvedCmd).FileVersion
        if ($fileVersion) { Write-DebugLog "java.exe file version: $fileVersion" }
        if ($fileVersion -and $fileVersion -match '^([0-9]+)\.') { return [int]$Matches[1] }
    } catch {}
    return 0
}

function Find-JavaInPath {
    $java = Get-Command java -ErrorAction SilentlyContinue
    if ($java -is [System.Array]) { $java = $java | Select-Object -First 1 }
    if ($java) {
        if ($java.Source) { return $java.Source }
        if ($java.Path) { return $java.Path }
    }
    return $null
}

function Check-JavaRequirements($nacosVersion, $advancedMode) {
    $required = 8
    if ($nacosVersion) {
        $major = [int]($nacosVersion.Split('.')[0])
        if ($major -ge 3) {
            $required = 17
            Write-Info "Nacos $nacosVersion requires Java 17 or later"
        }
    }

    $javaCmd = $null
    $javaVersion = 0

    if ($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME "bin\java.exe"))) {
        $javaCmd = Join-Path $env:JAVA_HOME "bin\java.exe"
        $javaVersion = Get-JavaVersion $javaCmd
        Write-Info "Found Java from JAVA_HOME: $env:JAVA_HOME (version: $javaVersion)"
        if ($javaVersion -lt $required) { $javaCmd = $null }
    }

    if (-not $javaCmd) {
        $javaCmd = Find-JavaInPath
        if ($javaCmd) {
            $javaVersion = Get-JavaVersion $javaCmd
            Write-Info "Found Java in PATH (version: $javaVersion)"
            if ($javaVersion -lt $required) { $javaCmd = $null }
        }
    }

    if (-not $javaCmd) {
        Write-ErrorMsg "Java not found or version too old. Please install Java $required+"
        return $false
    }

    if ($javaVersion -lt 8) {
        Write-ErrorMsg "Java version must be 8 or later (found: $javaVersion)"
        return $false
    }

    Write-Info "Java version: $javaVersion - OK"
    return $true
}

function Get-JavaRuntimeOptions {
    try {
        $javaCmd = if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME "bin\java.exe" } else { "java" }
        $output = & $javaCmd -version 2>&1 | Select-Object -First 1
        if ($output -match 'version "([0-9]+)') {
            $major = [int]$Matches[1]
            if ($major -ge 9) {
                return "--add-opens java.base/java.io=ALL-UNNAMED --add-opens java.base/java.lang=ALL-UNNAMED --add-opens java.base/java.util=ALL-UNNAMED --add-opens java.base/java.util.concurrent=ALL-UNNAMED --add-opens java.base/sun.net.util=ALL-UNNAMED"
            }
        }
    } catch {}
    return ""
}

# ============================================================================
# Bundled JRE 17 support for Nacos 3.x when no Java 17+ is available
# ============================================================================

function Get-WindowsArch {
    $arch = $env:PROCESSOR_ARCHITECTURE
    switch ($arch) {
        "AMD64"   { return "amd64" }
        "ARM64"   { return "amd64" }  # Use AMD64 JDK via emulation on ARM64 Windows
        "x86"     { return $null }    # 32-bit not supported
        default   { return "amd64" }
    }
}

function Get-BundledJdkUrl {
    if ($env:NACOS_SETUP_JRE17_DOWNLOAD_URL) {
        return $env:NACOS_SETUP_JRE17_DOWNLOAD_URL
    }
    $arch = Get-WindowsArch
    if (-not $arch) {
        Write-Warn "32-bit Windows is not supported for bundled JDK"
        return $null
    }
    return "$script:JDK17OssBase/jdk17-windows-$arch.zip"
}

function Test-JdkZipArchive($zipPath) {
    if (-not (Test-Path -LiteralPath $zipPath)) { return $false }
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
        $full = (Resolve-Path -LiteralPath $zipPath).Path
        $zip = [System.IO.Compression.ZipFile]::OpenRead($full)
        $zip.Dispose()
        return $true
    } catch {
        Write-DebugLog "JDK zip validation failed: $($_.Exception.Message)"
        return $false
    }
}

function Clear-DirectoryContents($dir) {
    if (-not (Test-Path -LiteralPath $dir)) { return }
    Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

function Invoke-TarExtractJdk($zipFullPath, $destinationDir) {
    if (-not (Get-Command tar.exe -ErrorAction SilentlyContinue)) { return $false }
    Write-Info "Extracting JDK (tar; more reliable than Expand-Archive for large JDK zips)..."
    try {
        $p = Start-Process -FilePath "tar.exe" -ArgumentList @("-xf", $zipFullPath, "-C", $destinationDir) `
            -Wait -PassThru -NoNewWindow
        if ($p.ExitCode -ne 0) {
            Write-Warn "tar.exe failed with exit code $($p.ExitCode)"
            return $false
        }
        return $true
    } catch {
        Write-Warn "Could not run tar.exe: $($_.Exception.Message)"
        return $false
    }
}

# Expand-Archive on PS 5.1 can fail or misbehave on deep JDK layouts / long paths; prefer tar, then fallback.
function Expand-BundledJdkZip($zipPath, $destinationDir) {
    $zipFull = (Resolve-Path -LiteralPath $zipPath).Path
    Ensure-Directory $destinationDir

    if (Invoke-TarExtractJdk $zipFull $destinationDir) { return $true }

    Clear-DirectoryContents $destinationDir
    Write-Info "Extracting JDK (Expand-Archive)..."
    $prevProg = $ProgressPreference
    $ProgressPreference = "SilentlyContinue"
    try {
        Expand-Archive -LiteralPath $zipFull -DestinationPath $destinationDir -Force
        return $true
    } catch {
        Write-Warn "Expand-Archive failed: $($_.Exception.Message)"
    } finally {
        $ProgressPreference = $prevProg
    }

    $shortTmp = Join-Path $env:TEMP ("nacos-jre-" + [Guid]::NewGuid().ToString("N"))
    try {
        Clear-DirectoryContents $destinationDir
        Ensure-Directory $destinationDir
        Ensure-Directory $shortTmp
        Write-Info "Retrying extraction under short path (avoids Windows MAX_PATH issues): $shortTmp"
        if (Invoke-TarExtractJdk $zipFull $shortTmp) {
            Get-ChildItem -LiteralPath $shortTmp -Force | ForEach-Object {
                Move-Item -LiteralPath $_.FullName -Destination $destinationDir -Force
            }
            return $true
        }
        Clear-DirectoryContents $shortTmp
        Expand-Archive -LiteralPath $zipFull -DestinationPath $shortTmp -Force
        Get-ChildItem -LiteralPath $shortTmp -Force | ForEach-Object {
            Move-Item -LiteralPath $_.FullName -Destination $destinationDir -Force
        }
        return $true
    } catch {
        Write-Warn "Short-path extraction failed: $($_.Exception.Message)"
        return $false
    } finally {
        if (Test-Path -LiteralPath $shortTmp) {
            Remove-Item -LiteralPath $shortTmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Find-JavaBinaryInDir($root) {
    if (-not (Test-Path -LiteralPath $root)) { return $null }
    # Typical layout: <root>/jdk-17.../bin/java.exe — use LiteralPath for names containing '+'.
    $directBin = Join-Path $root "bin\java.exe"
    if (Test-Path -LiteralPath $directBin) { return (Resolve-Path -LiteralPath $directBin).Path }
    foreach ($d in Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue) {
        $cand = Join-Path $d.FullName "bin\java.exe"
        if (Test-Path -LiteralPath $cand) { return (Resolve-Path -LiteralPath $cand).Path }
    }
    $hits = Get-ChildItem -LiteralPath $root -Recurse -Filter "java.exe" -Depth 6 -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\bin\\java\.exe$' } | Select-Object -First 1
    if ($hits) { return $hits.FullName }
    return $null
}

function Apply-BundledJavaHomeFromDir($root) {
    $javaBin = Find-JavaBinaryInDir $root
    if (-not $javaBin) { return $false }
    $ver = Get-JavaVersion $javaBin
    if ($ver -lt 17) { return $false }
    $javaHome = Split-Path (Split-Path $javaBin -Parent) -Parent
    $env:JAVA_HOME = $javaHome
    $env:PATH = "$javaHome\bin;$env:PATH"
    Write-DebugLog "Set JAVA_HOME=$javaHome"
    return $true
}

function Test-BundledJrePresent {
    $root = $script:BundledJreRoot
    if (-not (Test-Path $root)) { return $false }
    return (Apply-BundledJavaHomeFromDir $root)
}

function Install-BundledJre17 {
    $url = Get-BundledJdkUrl
    if (-not $url) { return $false }

    $zipName  = [System.IO.Path]::GetFileName(($url -split '\?')[0])
    if (-not $zipName) { $zipName = "jdk17-windows-amd64.zip" }
    $cached   = Join-Path $script:BundledJreCache $zipName

    Ensure-Directory $script:BundledJreCache

    $needDownload = $true
    if ((Test-Path $cached) -and (Get-Item $cached).Length -gt 0) {
        Write-Info "Found cached JDK package: $cached"
        $needDownload = $false
    }

    if ($needDownload) {
        Write-Info "Downloading JDK 17: $url"
        $prevProgress = $ProgressPreference
        $ProgressPreference = "SilentlyContinue"
        try {
            if ($PSVersionTable.PSVersion.Major -lt 6) {
                Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $cached
            } else {
                Invoke-WebRequest -Uri $url -OutFile $cached
            }
        } catch {
            Write-Warn "Failed to download bundled JDK 17: $($_.Exception.Message)"
            Remove-Item $cached -ErrorAction SilentlyContinue
            return $false
        } finally {
            $ProgressPreference = $prevProgress
        }
    }

    if (-not (Test-JdkZipArchive $cached)) {
        Write-Warn "JDK zip is missing, incomplete, or not a valid archive: $cached"
        Write-Warn "Delete this file and run nacos-setup again to re-download, or replace it with a complete jdk17-windows-amd64.zip from OSS."
        Remove-Item -LiteralPath $cached -Force -ErrorAction SilentlyContinue
        return $false
    }

    $root = $script:BundledJreRoot
    if (Test-Path $root) { Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue }
    Ensure-Directory $root

    Write-Info "Extracting JDK 17 into $root..."
    if (-not (Expand-BundledJdkZip $cached $root)) {
        Write-Warn "Failed to extract JDK 17. Try: run as Administrator, check disk space, or extract $cached manually under $root"
        return $false
    }

    if (Apply-BundledJavaHomeFromDir $root) {
        Write-Info "Bundled JDK 17 ready: JAVA_HOME=$env:JAVA_HOME"
        return $true
    }
    Write-Warn "Extracted archive does not contain a usable Java 17 binary"
    return $false
}

# Prompt user (Y/n) for bundled JRE download.
# Returns $true if user accepts, $false if declined or non-interactive.
function Confirm-BundledJreInstall {
    $dl = Get-BundledJdkUrl
    $prompt = "Java 17+ not found. Download JDK 17 from OSS ($dl) and install under $($script:BundledJreRoot)? (Y/n): "
    try {
        $answer = Read-Host $prompt
        if ($answer -match '^[Nn]') { return $false }
        return $true
    } catch {
        return $false
    }
}

# Main entry: ensure Java 17+ is available for Nacos 3.x.
# Returns $true if Java 17+ is ready, $false if not (caller should exit).
function Ensure-BundledJava17ForNacosSetup($nacosVersion) {
    if ($env:NACOS_SETUP_SKIP_BUNDLED_JRE -in @("1","true","TRUE")) { return $true }

    $major = 0
    $ver = if ($nacosVersion) { $nacosVersion.Trim() } else { "" }
    if ($ver) {
        try { $major = [int](($ver.Split('.'))[0]) } catch { $major = 0 }
    }
    if ($major -lt 3) { return $true }  # Nacos 2.x needs only Java 8+

    # Check if Java 17+ already on system
    $javaCmd = $null
    if ($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME "bin\java.exe"))) {
        $javaCmd = Join-Path $env:JAVA_HOME "bin\java.exe"
    }
    if (-not $javaCmd) {
        $found = Get-Command java -ErrorAction SilentlyContinue
        if ($found) { $javaCmd = $found.Source }
    }
    if ($javaCmd -and (Get-JavaVersion $javaCmd) -ge 17) {
        Write-DebugLog "Java 17+ already available: $javaCmd"
        return $true
    }

    # Try reusing cached bundled JRE
    if (Test-BundledJrePresent) {
        Write-Info "Using existing bundled JRE at JAVA_HOME=$env:JAVA_HOME"
        return $true
    }

    Write-Info "Nacos $nacosVersion requires Java 17+. None found in JAVA_HOME or PATH."
    if (-not (Confirm-BundledJreInstall)) {
        Write-Info "Skipping bundled JDK installation. Exiting without starting Nacos setup."
        return $false
    }

    return (Install-BundledJre17)
}

# Bundled JDK 17 (interactive OSS download) for Nacos 3.x when needed, then verify Java.
function Invoke-JavaGateForNacosInstall($nacosVersion, $advancedMode) {
    if (Get-Command Ensure-BundledJava17ForNacosSetup -ErrorAction SilentlyContinue) {
        if (-not (Ensure-BundledJava17ForNacosSetup $nacosVersion)) {
            return $false
        }
    }
    return (Check-JavaRequirements $nacosVersion $advancedMode)
}
