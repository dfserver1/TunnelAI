#!/usr/bin/env pwsh
<#
  HTML-a-PDF.ps1 — converts HTML/Markdown to PDF without installing anything.
  Engine 1: Microsoft Edge (headless) — ships with Windows 10/11.
  Engine 2: Google Chrome if installed.
  Usage:
    HTML-a-PDF.ps1 -Ruta report.html
    HTML-a-PDF.ps1 -Ruta report.html -Salida report.pdf -Esperar 3000
#>

param(
  [Parameter(Mandatory=$true)][string]$Ruta,
  [string]$Salida,
  [int]$Esperar = 1500
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $Ruta)) { Write-Error "Not found: $Ruta"; exit 2 }
$src = (Resolve-Path -LiteralPath $Ruta).Path
if (-not $Salida) { $Salida = "$([System.IO.Path]::ChangeExtension($src, 'pdf'))" }

function Get-Navegador {
  $candidatos = @(
    (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
    (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
    (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe')
  )
  foreach ($c in $candidatos) { if (Test-Path -LiteralPath $c) { return $c } }
  return $null
}

$exe = Get-Navegador
if (-not $exe) {
  Write-Error "No PDF engine: Edge or Chrome not found. Install Edge or use another converter."
  exit 3
}

$perfil = Join-Path $env:TEMP "htmlapdf-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Path $perfil -Force | Out-Null
try {
  $srcUrl = "file:///$($src -replace '\\','/')"
  $argString = "--headless=new --disable-gpu --no-sandbox --no-first-run --user-data-dir=`"$perfil`" --virtual-time-budget=$Esperar --print-to-pdf=`"$Salida`" --no-pdf-header-footer `"$srcUrl`""
  Start-Process -FilePath $exe -ArgumentList $argString -Wait -WindowStyle Hidden
} finally {
  Remove-Item $perfil -Recurse -Force -ErrorAction SilentlyContinue
}

if (Test-Path -LiteralPath $Salida) {
  $kb = [int]((Get-Item -LiteralPath $Salida).Length / 1KB)
  Write-Output "PDF CREATED: $Salida ($kb KB)"
} else {
  Write-Error "The PDF was not generated. Check the HTML is valid."
  exit 4
}
