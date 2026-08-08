$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = $ScriptDir

$UvCmd = if ($IsWindows) { "uv.exe" } else { "uv" }

function Get-Uv {
    if (Get-Command $UvCmd -ErrorAction SilentlyContinue) {
        return
    }

    $TempFile = [System.IO.Path]::GetTempFileName() + ".ps1"
    try {
        Write-Host "Installing uv..."
        Invoke-WebRequest -Uri "https://astral.sh/uv/install.ps1" -OutFile $TempFile
        & $TempFile
    }
    finally {
        Remove-Item $TempFile -ErrorAction SilentlyContinue
    }
}

function Invoke-MapToolkit {
    param (
        [string[]]$Arguments
    )

    Get-Uv

    Push-Location $ProjectRoot
    try {
        & uv run python main.py @Arguments
    }
    finally {
        Pop-Location
    }
}

try {
    Invoke-MapToolkit -Arguments $args
    exit $LASTEXITCODE
}
catch {
    Write-Host ""
    Write-Host "===== Maptoolkit FAILED =====" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
