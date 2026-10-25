<#
.SYNOPSIS
    One-click installer for Motion Explainer Video & Images Skill Suite
    (motion-explainer-video, motion-explainer-images, motion-design, review-loop).
.DESCRIPTION
    Installs motion-explainer-video, motion-explainer-images, motion-design, and review-loop into Antigravity,
    Claude Code, Cursor, and Codex skills directories.
.USAGE
    # Remote one-liner (PowerShell):
    irm https://raw.githubusercontent.com/JeffreyHo0520/motion-explainer-video/main/install.ps1 | iex

    # Local execution:
    .\install.ps1
    .\install.ps1 -Workspace
    .\install.ps1 -Dest "C:\custom\skills"
    .\install.ps1 -Force
#>
[CmdletBinding()]
param(
    [string]$Dest,
    [switch]$Workspace,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$repoUrl = "https://github.com/JeffreyHo0520/motion-explainer-video.git"
$isRemote = -not $PSScriptRoot -or ($PSScriptRoot -eq "")

if ($isRemote) {
    Write-Host ">>> [motion-explainer-video] Detected remote execution via web. Cloning temporary repository..." -ForegroundColor Cyan
    $tempDir = Join-Path $env:TEMP ("motion-explainer-video-" + [System.Guid]::NewGuid().ToString("N"))
    git clone --depth 1 $repoUrl $tempDir
    $scriptDir = $tempDir
} else {
    $scriptDir = $PSScriptRoot
}

try {
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host " 🎬 Installing Motion Explainer Suite (Video + Images)          " -ForegroundColor Cyan
    Write-Host "    - motion-explainer-video   (AI Video + Image + Voice Fix)   " -ForegroundColor Cyan
    Write-Host "    - motion-explainer-images  (Licensed Photos & Gen Images)   " -ForegroundColor Cyan
    Write-Host "    - motion-design            (Taste & Easing Hard Rules)       " -ForegroundColor Cyan
    Write-Host "    - review-loop              (Visual Contact Sheet Audit)     " -ForegroundColor Cyan
    Write-Host "=================================================================" -ForegroundColor Cyan

    $destDirs = @()
    if ($Dest) {
        $destDirs += $Dest
    } elseif ($Workspace) {
        $destDirs += Join-Path (Get-Location) ".agents\skills"
        $destDirs += Join-Path (Get-Location) ".gemini\skills"
        $destDirs += Join-Path (Get-Location) ".claude\skills"
    } else {
        $userHome = $env:USERPROFILE
        $destDirs += Join-Path $userHome ".gemini\config\skills"
        $codexSkills = if ($env:CODEX_HOME) { Join-Path $env:CODEX_HOME "skills" } else { Join-Path $userHome ".codex\skills" }
        $claudeSkills = Join-Path $userHome ".claude\skills"
        $agentsSkills = Join-Path $userHome ".agents\skills"
        $destDirs += $codexSkills
        $destDirs += $claudeSkills
        $destDirs += $agentsSkills
    }

    $skillsSourceDir = Join-Path $scriptDir "skills"
    $skillNames = @(
        "motion-explainer-video",
        "motion-explainer-images",
        "motion-design",
        "review-loop"
    )

    foreach ($skillsRoot in $destDirs) {
        if (-not (Test-Path $skillsRoot)) {
            New-Item -ItemType Directory -Path $skillsRoot -Force | Out-Null
        }

        Write-Host "`n>>> Target Skills Root: $skillsRoot" -ForegroundColor Yellow

        foreach ($skillName in $skillNames) {
            $srcSkillPath = Join-Path $skillsSourceDir $skillName
            $targetPath = Join-Path $skillsRoot $skillName

            if (-not (Test-Path $srcSkillPath)) {
                Write-Host "  [!] Source not found: $srcSkillPath" -ForegroundColor Red
                continue
            }

            if (Test-Path $targetPath) {
                if (-not $Force) {
                    Write-Host "  [-] $skillName already exists at: $targetPath (Use -Force to overwrite)" -ForegroundColor DarkGray
                    continue
                }
                $timestamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
                $backup = "$targetPath.backup.$timestamp"
                Move-Item -Path $targetPath -Destination $backup -Force
                Write-Host "  [*] Backed up previous $skillName to: $backup" -ForegroundColor DarkCyan
            }

            New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
            Copy-Item (Join-Path $srcSkillPath "*") -Destination $targetPath -Recurse -Force

            # Clean up __pycache__
            Get-ChildItem -Path $targetPath -Recurse -Directory -Filter "__pycache__" -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

            Write-Host "  [+] Installed $skillName successfully!" -ForegroundColor Green
        }
    }

    # Prerequisites Check
    Write-Host "`n-----------------------------------------------------------------" -ForegroundColor Cyan
    Write-Host "🔍 Environment Prerequisites Check:" -ForegroundColor Cyan
    Write-Host "-----------------------------------------------------------------" -ForegroundColor Cyan

    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
    if ($nodeCmd) {
        Write-Host "  [✓] Node.js is available: $(node --version)" -ForegroundColor Green
    } else {
        Write-Host "  [!] Node.js 22+ not found. Install via: winget install OpenJS.NodeJS.LTS" -ForegroundColor Yellow
    }

    $pyCmd = Get-Command python -ErrorAction SilentlyContinue
    if ($pyCmd) {
        Write-Host "  [✓] Python is available: $(python --version)" -ForegroundColor Green
    } else {
        Write-Host "  [!] Python not found. Install via: winget install Python.Python.3.11" -ForegroundColor Yellow
    }

    $ffCmd = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if ($ffCmd) {
        Write-Host "  [✓] ffmpeg is available." -ForegroundColor Green
    } else {
        Write-Host "  [!] ffmpeg not found. Install via: winget install Gyan.FFmpeg" -ForegroundColor Yellow
    }

    $hfCmd = Get-Command hyperframes -ErrorAction SilentlyContinue
    if ($hfCmd) {
        Write-Host "  [✓] HyperFrames CLI is available." -ForegroundColor Green
    } else {
        Write-Host "  [!] HyperFrames CLI not found. Install via: npm install -g hyperframes" -ForegroundColor Yellow
    }

    Write-Host "`n✨ Installation completed successfully! You can now use /motion-explainer-video or /motion-explainer-images in your AI agent." -ForegroundColor Green
}
finally {
    if ($isRemote -and (Test-Path $tempDir)) {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
