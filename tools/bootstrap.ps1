# tools/bootstrap.ps1
#
# Windows counterpart of tools/bootstrap.sh. Installs generated QuestieTDB artifacts into a
# developer's AddOns folder. A downloader, not a build tool — no Lua, no toolchain.
#
# All flavors are downloaded, so switching test clients needs no re-bootstrap.
#
# Usage:
#   .\tools\bootstrap.ps1 -AddOns "C:\Program Files\World of Warcraft\_classic_era_\Interface\AddOns"
#   .\tools\bootstrap.ps1 -AddOns ... -Tag build-a1b2c3d      # pin an exact release

param(
    [Parameter(Mandatory = $true)][string] $AddOns,
    [string] $Tag = "latest",
    [string] $Repo = "Questie/QuestieTDB"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -PathType Container $AddOns)) {
    throw "'$AddOns' is not a directory. Point this at Interface\AddOns."
}

$base = if ($Tag -eq "latest") {
    "https://github.com/$Repo/releases/latest/download"
} else {
    "https://github.com/$Repo/releases/download/$Tag"
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("questietdb-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $work | Out-Null

try {
    Write-Host "bootstrap: fetching manifest from $base"
    $manifestPath = Join-Path $work "release.json"
    Invoke-WebRequest -Uri "$base/release.json" -OutFile $manifestPath -UseBasicParsing
    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json

    Write-Host "bootstrap: release built from $($manifest.producerCommit), contract version $($manifest.contractVersion)"

    if (-not $manifest.artifacts -or $manifest.artifacts.Count -eq 0) {
        throw "manifest listed no artifacts"
    }

    foreach ($artifact in $manifest.artifacts) {
        Write-Host "bootstrap: downloading $($artifact.file)"
        $path = Join-Path $work $artifact.file
        Invoke-WebRequest -Uri "$base/$($artifact.file)" -OutFile $path -UseBasicParsing

        # Checksums are verified before installing, not after. A truncated download that
        # overwrites a working install is worse than no install.
        $actual = (Get-FileHash -Algorithm SHA256 -Path $path).Hash.ToLower()
        if ($actual -ne $artifact.sha256.ToLower()) {
            throw "checksum mismatch for $($artifact.file) - refusing to install"
        }
    }

    $target = Join-Path $AddOns "QuestieTDB"
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    Write-Host "bootstrap: all checksums verified, installing into $target"

    # Remove only the generated TOCs. Everything else may be a working clone.
    Get-ChildItem -Path $target -Filter "QuestieTDB_*.toc" -ErrorAction SilentlyContinue |
        Remove-Item -Force

    $extract = Join-Path $work "extract"
    foreach ($artifact in $manifest.artifacts) {
        Expand-Archive -Path (Join-Path $work $artifact.file) -DestinationPath $extract -Force
    }
    Copy-Item -Path (Join-Path $extract "QuestieTDB\*") -Destination $target -Recurse -Force

    Write-Host "bootstrap: installed. Suffixed TOCs present:"
    Get-ChildItem -Path $target -Filter "QuestieTDB_*.toc" | ForEach-Object { Write-Host "  $($_.Name)" }
    Write-Host "bootstrap: the client will now use Baked mode. Delete those TOCs to return to Source mode."
}
finally {
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
