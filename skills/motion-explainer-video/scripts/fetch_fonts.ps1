param(
    [string]$ProjectDir = "."
)

$ErrorActionPreference = "Stop"
$ResolvedProjectDir = (Resolve-Path $ProjectDir).Path
$Dest = Join-Path $ResolvedProjectDir "assets\fonts"
if (-not (Test-Path $Dest)) {
    New-Item -ItemType Directory -Path $Dest -Force | Out-Null
}

$TempDir = Join-Path $env:TEMP ("fetch_fonts_" + [System.Guid]::NewGuid().ToString().Substring(0, 8))
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

try {
    # 1. Fetch GenSeki Gothic Bold (源石黑體 粗體)
    $GensekiZip = Join-Path $TempDir "genseki.zip"
    $GensekiUrl = "https://github.com/ButTaiwan/genseki-font/releases/download/v2.100/GenSekiGothic2TW-otf.zip"
    $TargetGensekiOtf = Join-Path $Dest "GenSekiGothic2TW-B.otf"

    if (-not (Test-Path $TargetGensekiOtf)) {
        Write-Host "Downloading GenSeki Gothic (源石黑體)..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $GensekiUrl -OutFile $GensekiZip -UseBasicParsing
        
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($GensekiZip)
        try {
            foreach ($entry in $zip.Entries) {
                if ($entry.Name -eq "GenSekiGothic2TW-B.otf") {
                    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $TargetGensekiOtf, $true)
                }
                elseif ($entry.Name -eq "SIL_Open_Font_License_1.1.txt") {
                    $licensePath = Join-Path $Dest "OFL-GenSekiGothic.txt"
                    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $licensePath, $true)
                }
            }
        }
        finally {
            $zip.Dispose()
        }
    }

    # 2. Fetch Latin fonts from @fontsource via npm
    Write-Host "Installing font packages into temporary directory..." -ForegroundColor Cyan
    Push-Location $TempDir
    cmd.exe /c "npm init -y >nul 2>&1 && npm install --no-audit --no-fund @fontsource/newsreader@5.2.8 @fontsource/dm-mono@5.2.7 @fontsource/hanken-grotesk@5.2.8 >nul 2>&1"
    Pop-Location

    $F = Join-Path $TempDir "node_modules\@fontsource"

    if (Test-Path $F) {
        Copy-Item "$F\newsreader\files\newsreader-latin-400-normal.woff2" "$Dest\Newsreader-Regular.woff2" -Force -ErrorAction SilentlyContinue
        Copy-Item "$F\newsreader\files\newsreader-latin-400-italic.woff2" "$Dest\Newsreader-Italic.woff2" -Force -ErrorAction SilentlyContinue
        Copy-Item "$F\dm-mono\files\dm-mono-latin-400-normal.woff2" "$Dest\DMMono-Regular.woff2" -Force -ErrorAction SilentlyContinue
        Copy-Item "$F\dm-mono\files\dm-mono-latin-500-normal.woff2" "$Dest\DMMono-Medium.woff2" -Force -ErrorAction SilentlyContinue

        $weights = @(
            @{ Weight = "400"; Name = "Regular" },
            @{ Weight = "500"; Name = "Medium" },
            @{ Weight = "600"; Name = "SemiBold" },
            @{ Weight = "700"; Name = "Bold" }
        )

        foreach ($w in $weights) {
            Copy-Item "$F\hanken-grotesk\files\hanken-grotesk-latin-$($w.Weight)-normal.woff2" "$Dest\HankenGrotesk-$($w.Name).woff2" -Force -ErrorAction SilentlyContinue
        }
    }

    # 3. System / Google Fonts check for Noto CJK fonts
    $cjkFonts = @(
        @{ Name = "NotoSansTC-VF.ttf"; Url = "https://github.com/google/fonts/raw/main/ofl/notosanstc/NotoSansTC%5Bwght%5D.ttf" },
        @{ Name = "NotoSerifTC-VF.ttf"; Url = "https://github.com/google/fonts/raw/main/ofl/notoseriftc/NotoSerifTC%5Bwght%5D.ttf" }
    )
    $searchDirs = @(
        "C:\Windows\Fonts",
        "$env:LOCALAPPDATA\Microsoft\Windows\Fonts",
        "$env:USERPROFILE\.local\share\fonts"
    )

    foreach ($font in $cjkFonts) {
        $destFile = Join-Path $Dest $font.Name
        if (Test-Path $destFile) {
            continue
        }
        $found = $false
        foreach ($d in $searchDirs) {
            $p = Join-Path $d $font.Name
            if (Test-Path $p) {
                Copy-Item $p -Destination $destFile -Force
                $found = $true
                break
            }
        }
        if (-not $found) {
            try {
                Invoke-WebRequest -Uri $font.Url -OutFile $destFile -UseBasicParsing -TimeoutSec 15 -ErrorAction SilentlyContinue
            } catch {
                Write-Warning "$($font.Name) could not be fetched automatically. Please download from https://fonts.google.com/noto into $Dest"
            }
        }
    }

    Write-Host "Fonts successfully fetched into: $Dest" -ForegroundColor Green
    Get-ChildItem $Dest | Select-Object Name, Length
}
finally {
    if (Test-Path $TempDir) {
        Remove-Item -Recurse -Force $TempDir -ErrorAction SilentlyContinue
    }
}
