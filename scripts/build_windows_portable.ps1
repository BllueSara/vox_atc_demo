# Builds a self-contained VoxATC Windows portable package (no install required).
# Output: dist/VoxATC-Windows/ and dist/VoxATC-Windows.zip

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$DistDir = Join-Path $ProjectRoot "dist\VoxATC-Windows"
$ReleaseDir = Join-Path $ProjectRoot "build\windows\x64\runner\Release"
$RuntimeDir = Join-Path $DistDir "runtime"
$PythonDir = Join-Path $RuntimeDir "python"
$FfmpegDir = Join-Path $RuntimeDir "ffmpeg\bin"
$CacheDir = Join-Path $RuntimeDir "cache\huggingface"
$PythonVersion = "3.12.9"
$PythonZip = "python-$PythonVersion-embed-amd64.zip"
$PythonUrl = "https://www.python.org/ftp/python/$PythonVersion/$PythonZip"
$FfmpegUrl = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"

function Write-Step($Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Ensure-Directory($Path) {
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Download-File($Url, $Destination) {
    if (Test-Path $Destination) { return }
    Write-Host "Downloading $Url"
    Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
}

function Ensure-EmbeddedPython {
    Ensure-Directory $PythonDir
    $pythonExe = Join-Path $PythonDir "python.exe"
    if (Test-Path $pythonExe) {
        Write-Host "Embedded Python already present."
        return
    }

    $tempDir = Join-Path $env:TEMP "vox_atc_python_$PythonVersion"
    Ensure-Directory $tempDir
    $zipPath = Join-Path $tempDir $PythonZip
    Download-File $PythonUrl $zipPath
    Expand-Archive -Path $zipPath -DestinationPath $PythonDir -Force

    $pthFile = Get-ChildItem $PythonDir -Filter "python*._pth" | Select-Object -First 1
    if ($pthFile) {
        $lines = Get-Content $pthFile.FullName
        if ($lines -notcontains "Lib\site-packages") {
            $lines += "Lib\site-packages"
        }
        if ($lines -notcontains "import site") {
            $lines += "import site"
        }
        Set-Content -Path $pthFile.FullName -Value $lines
    }

    Ensure-Directory (Join-Path $PythonDir "Lib\site-packages")
    $getPip = Join-Path $tempDir "get-pip.py"
    Download-File "https://bootstrap.pypa.io/get-pip.py" $getPip
    & $pythonExe $getPip --no-warn-script-location | Out-Host
}

function Ensure-FasterWhisper {
    $pythonExe = Join-Path $PythonDir "python.exe"
    if (-not (Test-Path $pythonExe)) {
        throw "Embedded Python missing at $pythonExe"
    }

    $check = & $pythonExe -c "from faster_whisper import WhisperModel; print('OK')" 2>&1
    if ($LASTEXITCODE -eq 0 -and "$check" -match "OK") {
        Write-Host "faster-whisper already installed."
        return
    }

    Write-Host "Installing faster-whisper (this may take a few minutes)..."
    & $pythonExe -m pip install faster-whisper --no-warn-script-location | Out-Host
}

function Materialize-WhisperModel {
    $modelOut = Join-Path $RuntimeDir "models\small.en"
    $modelBin = Join-Path $modelOut "model.bin"
    if (Test-Path $modelBin) {
        Write-Host "Bundled Whisper model already materialized."
        return
    }

    $snapshotRoot = Join-Path $CacheDir "hub\models--Systran--faster-whisper-small.en\snapshots"
    if (-not (Test-Path $snapshotRoot)) {
        throw "Whisper HF cache missing - run Ensure-WhisperModel first."
    }

    $snapshotDir = Get-ChildItem $snapshotRoot -Directory | Select-Object -First 1
    if (-not $snapshotDir) {
        throw "Whisper snapshot directory missing under $snapshotRoot"
    }

    Ensure-Directory $modelOut
    Write-Host "Materializing Whisper model to $modelOut ..."
    foreach ($file in Get-ChildItem $snapshotDir.FullName -Force) {
        $dest = Join-Path $modelOut $file.Name
        if ($file.LinkType -eq "SymbolicLink") {
            $target = $file.Target
            if ($target -is [array]) { $target = $target[0] }
            if (-not [System.IO.Path]::IsPathRooted($target)) {
                $target = Join-Path $snapshotDir.FullName $target
            }
            Copy-Item -LiteralPath $target -Destination $dest -Force
        } else {
            Copy-Item -LiteralPath $file.FullName -Destination $dest -Force
        }
    }
}

function Ensure-VcRuntimeDlls {
    $required = @(
        "msvcp140.dll",
        "msvcp140_1.dll",
        "msvcp140_2.dll",
        "vcomp140.dll",
        "vcruntime140.dll",
        "vcruntime140_1.dll"
    )
    $searchRoots = @(
        $PythonDir,
        "$env:SystemRoot\System32",
        "$env:SystemRoot\SysWOW64"
    )

    foreach ($dll in $required) {
        $target = Join-Path $PythonDir $dll
        if (Test-Path $target) { continue }

        foreach ($root in $searchRoots) {
            $source = Join-Path $root $dll
            if (Test-Path $source) {
                Write-Host "Bundling VC runtime DLL: $dll"
                Copy-Item -LiteralPath $source -Destination $target -Force
                break
            }
        }
    }

    $ct2Dir = Join-Path $PythonDir "Lib\site-packages\ctranslate2"
    if (Test-Path $ct2Dir) {
        foreach ($dll in $required) {
            $source = Join-Path $PythonDir $dll
            $target = Join-Path $ct2Dir $dll
            if ((Test-Path $source) -and -not (Test-Path $target)) {
                Copy-Item -LiteralPath $source -Destination $target -Force
            }
        }
    }
}

function Ensure-VcRedistInstaller {
    $installer = Join-Path $RuntimeDir "vc_redist.x64.exe"
    if (Test-Path $installer) {
        Write-Host "VC++ redistributable installer already present."
        return
    }

    $url = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
    Write-Host "Downloading Visual C++ Redistributable..."
    Download-File $url $installer
}

function Write-VcRedistLauncher {
    $batPath = Join-Path $RuntimeDir "Install_VC_Runtime.bat"
    @(
        '@echo off',
        'cd /d "%~dp0"',
        'echo Installing Microsoft Visual C++ 2015-2022 Redistributable (x64)...',
        'if not exist "%~dp0vc_redist.x64.exe" (',
        '  echo ERROR: vc_redist.x64.exe not found.',
        '  pause',
        '  exit /b 1',
        ')',
        '"%~dp0vc_redist.x64.exe" /install /quiet /norestart',
        'echo Done. You can close this window and restart VoxATC.',
        'pause'
    ) | Set-Content -Path $batPath -Encoding ASCII
}

function Write-Launcher {
    $batPath = Join-Path $DistDir "Start VoxATC.bat"
    @(
        '@echo off',
        'cd /d "%~dp0"',
        'set "PATH=%~dp0runtime\python;%~dp0runtime\python\Lib\site-packages\onnxruntime\capi;%~dp0runtime\python\Lib\site-packages\ctranslate2;%PATH%"',
        'set "PYTHONNOUSERSITE=1"',
        'set "CT2_FORCE_CPU_ISA=GENERIC"',
        'start "" "%~dp0vox_atc_demo.exe"'
    ) | Set-Content -Path $batPath -Encoding ASCII
}

function Ensure-WhisperModel {
    $pythonExe = Join-Path $PythonDir "python.exe"
    Ensure-Directory $CacheDir
    $env:HF_HOME = $CacheDir
    $env:HUGGINGFACE_HUB_CACHE = Join-Path $CacheDir "hub"
    $env:HF_HUB_DISABLE_SYMLINKS = "1"

    $modelDir = Join-Path $env:HUGGINGFACE_HUB_CACHE "models--Systran--faster-whisper-small.en"
    if (Test-Path $modelDir) {
        Write-Host "Whisper model already cached."
        Materialize-WhisperModel
        return
    }

    Write-Host "Pre-downloading Whisper small.en model (~150 MB)..."
    $script = @'
import sys
from faster_whisper import WhisperModel
sys.stderr.write("Downloading model...\n")
WhisperModel("small.en", device="cpu", compute_type="int8")
sys.stderr.write("Model ready.\n")
'@
    & $pythonExe -c $script 2>&1 | Out-Host
    Materialize-WhisperModel
}

function Ensure-Ffmpeg {
    Ensure-Directory $FfmpegDir
    $ffmpegExe = Join-Path $FfmpegDir "ffmpeg.exe"
    if (Test-Path $ffmpegExe) {
        Write-Host "Bundled ffmpeg already present."
        return
    }

    $localCandidates = @(
        "C:\ffmpeg\bin\ffmpeg.exe",
        "$env:LOCALAPPDATA\Microsoft\WinGet\Links\ffmpeg.exe"
    )
    foreach ($candidate in $localCandidates) {
        if (Test-Path $candidate) {
            Write-Host "Copying ffmpeg from $candidate"
            Copy-Item -Path (Join-Path (Split-Path $candidate -Parent) "*") -Destination $FfmpegDir -Recurse -Force
            return
        }
    }

    $tempDir = Join-Path $env:TEMP "vox_atc_ffmpeg"
    Ensure-Directory $tempDir
    $zipPath = Join-Path $tempDir "ffmpeg.zip"
    Download-File $FfmpegUrl $zipPath
    Expand-Archive -Path $zipPath -DestinationPath $tempDir -Force
    $extractedBin = Get-ChildItem $tempDir -Recurse -Filter "ffmpeg.exe" |
        Where-Object { $_.DirectoryName -match "\\bin$" } |
        Select-Object -First 1
    if (-not $extractedBin) {
        throw "Could not find ffmpeg.exe in downloaded archive."
    }
    Copy-Item (Join-Path $extractedBin.DirectoryName "*") $FfmpegDir -Force
}

function Copy-FlutterRelease {
    Ensure-Directory $DistDir
    Copy-Item (Join-Path $ReleaseDir "vox_atc_demo.exe") $DistDir -Force
    Copy-Item (Join-Path $ReleaseDir "flutter_windows.dll") $DistDir -Force

    $dataSrc = Join-Path $ReleaseDir "data"
    $dataDst = Join-Path $DistDir "data"
    if (Test-Path $dataDst) { Remove-Item $dataDst -Recurse -Force }
    Copy-Item $dataSrc $dataDst -Recurse -Force
}

function Copy-PythonScript {
    $scriptSrc = Join-Path $ProjectRoot "python\whisper_server.py"
    $scriptDstDir = Join-Path $DistDir "python"
    Ensure-Directory $scriptDstDir
    Copy-Item $scriptSrc (Join-Path $scriptDstDir "whisper_server.py") -Force
}

function Write-Readme {
    $readme = @"
VoxATC - Windows (Portable)
===========================

No installation required. No Python, ffmpeg, or internet needed after setup.

How to run:
1. Extract this entire folder anywhere (e.g. Desktop\VoxATC-Windows)
2. Double-click "Start VoxATC.bat" (or vox_atc_demo.exe)
3. Wait ~30 seconds on first launch while Whisper loads
4. Status should show "Ready - hold Space or Hold to Talk"

If Whisper fails with a native crash / exit code -1073741819:
- Run runtime\Install_VC_Runtime.bat once, then restart VoxATC.

Requirements:
- Windows 10/11 (64-bit)
- Microphone

Do NOT delete these folders:
- data\
- python\
- runtime\

Folder size note: includes Whisper AI model (~150MB), Python, and ffmpeg.
"@
    Set-Content -Path (Join-Path $DistDir "README.txt") -Value $readme -Encoding UTF8
}

function New-PortableZip {
    $zipPath = Join-Path (Split-Path $DistDir -Parent) "VoxATC-Windows.zip"
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Write-Host "Creating $zipPath ..."
    Compress-Archive -Path $DistDir -DestinationPath $zipPath -CompressionLevel Optimal
    return $zipPath
}

Push-Location $ProjectRoot
try {
    Write-Step "Building Flutter release"
    flutter build windows --release

    Write-Step "Preparing runtime (Python + Whisper + ffmpeg)"
    Ensure-EmbeddedPython
    Ensure-FasterWhisper
    Ensure-WhisperModel
    Ensure-Ffmpeg
    Ensure-VcRuntimeDlls
    Ensure-VcRedistInstaller

    Write-Step "Assembling portable folder"
    Copy-FlutterRelease
    Copy-PythonScript
    Materialize-WhisperModel
    Write-VcRedistLauncher
    Write-Readme
    Write-Launcher

    Write-Step "Creating ZIP archive"
    $zip = New-PortableZip

    $sizeMb = [math]::Round((Get-ChildItem $DistDir -Recurse | Measure-Object Length -Sum).Sum / 1MB, 1)
    Write-Host ""
    Write-Host "Done." -ForegroundColor Green
    Write-Host "Folder: $DistDir ($sizeMb MB)"
    Write-Host "ZIP:    $zip"
}
finally {
    Pop-Location
}
