#!/usr/bin/env pwsh
<#
  OCR.ps1 — extracts text from images (OCR) using Windows, nothing to install.
  Engine 1: Windows.Media.Ocr (WinRT, offline, bundled with Windows 10/11).
  Engine 2: tesseract, if installed (winget install UB-Mannheim.TesseractOCR).

  Usage:
    OCR.ps1 -Ruta invoice.png                    # text from a single image
    OCR.ps1 -Ruta scan.jpg -Idioma es-ES         # forced language
    OCR.ps1 -Carpeta .\scans -Salida text.txt    # whole folder + save
    OCR.ps1 -Ruta img.png -Json                  # structured output (lines + words)

  Languages: auto (tries es-ES, en-US) or any BCP-47 tag installed in Windows.
  The AI uses this tool via run_command and receives the text on stdout.
#>

param(
  [string]$Ruta,
  [string]$Carpeta,
  [string]$Idioma = 'auto',
  [string]$Salida,
  [switch]$Json
)

$ErrorActionPreference = "Stop"

# ── load and PRIME the WinRT projection (in 5.1 the short forms only work
#    after referencing the projected form: [Type,Assembly,ContentType=WindowsRuntime])
function Initialize-WinRT {
  try { Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction SilentlyContinue } catch {}
  try { [void][Windows.Media.Ocr.OcrEngine,Windows.Media,ContentType=WindowsRuntime] } catch {}
  try { [void][Windows.Globalization.Language,Windows.Globalization,ContentType=WindowsRuntime] } catch {}
  try { [void][Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime] } catch {}
  try { [void][Windows.Graphics.Imaging.BitmapDecoder,Windows.Graphics.Imaging,ContentType=WindowsRuntime] } catch {}
}
Initialize-WinRT

# ── If WinRT types still aren't available (pwsh 7 doesn't project them), relaunch with Windows PowerShell 5.1.
if ($PSVersionTable.PSEdition -eq 'Core') {
  $winrtOk = $false
  try { [void][Windows.Media.Ocr.OcrEngine]; $winrtOk = $true } catch {}
  if (-not $winrtOk) {
    $ps51 = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $ps51) {
      $reArgs = @()
      if ($Ruta)    { $reArgs += @('-Ruta', $Ruta) }
      if ($Carpeta) { $reArgs += @('-Carpeta', $Carpeta) }
      if ($Idioma -and $Idioma -ne 'auto') { $reArgs += @('-Idioma', $Idioma) }
      if ($Salida)  { $reArgs += @('-Salida', $Salida) }
      if ($Json)    { $reArgs += '-Json' }
      & $ps51 -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @reArgs
      exit $LASTEXITCODE
    }
  }
}

# ── pattern to consume WinRT async operations from PowerShell ───────────────
function Await($WinRtTask, [type]$ResultType) {
  $asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() |
    Where-Object { $_.Name -eq 'AsTask' -and $_.IsGenericMethodDefinition -and
                   $_.GetParameters().Count -eq 1 -and
                   $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } |
    Select-Object -First 1
  if (-not $asTask) { throw 'Could not find AsTask<TResult>(IAsyncOperation<TResult>)' }
  $netTask = $asTask.MakeGenericMethod($ResultType).Invoke($null, @($WinRtTask))
  $netTask.Wait(-1) | Out-Null
  return $netTask.Result
}

function Get-OcrEngine {
  param([string]$Idioma)
  $candidatos = if ($Idioma -eq 'auto') { @('es-ES','en-US') } else { @($Idioma) }
  foreach ($tag in $candidatos) {
    try {
      $lang = New-Object Windows.Globalization.Language $tag
      $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($lang)
      if ($engine) { return $engine }
    } catch {}
  }
  return $null
}

function Invoke-OcrWindows {
  param([string]$Archivo, $Engine)
  $file    = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($Archivo)) ([Windows.Storage.StorageFile])
  $stream  = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
  $decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
  $bitmap  = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
  $result  = Await ($Engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
  return $result
}

function Invoke-OcrTesseract {
  param([string]$Archivo)
  $out = [System.IO.Path]::GetTempFileName()
  & tesseract $Archivo $out 2>$null | Out-Null
  $txt = if (Test-Path "$out.txt") { Get-Content "$out.txt" -Raw } else { '' }
  Remove-Item "$out.txt","$out" -Force -ErrorAction SilentlyContinue
  return $txt
}

# ── resolve the list of files ────────────────────────────────────────────────
$archivos = @()
if ($Ruta) {
  if (-not (Test-Path -LiteralPath $Ruta)) { Write-Error "Not found: $Ruta"; exit 2 }
  $archivos += (Resolve-Path -LiteralPath $Ruta).Path
} elseif ($Carpeta) {
  if (-not (Test-Path -LiteralPath $Carpeta)) { Write-Error "Folder not found: $Carpeta"; exit 2 }
  Get-ChildItem -LiteralPath $Carpeta -File |
    Where-Object { $_.Extension -in '.png','.jpg','.jpeg','.bmp','.tif','.tiff','.gif' } |
    ForEach-Object { $archivos += $_.FullName }
} else {
  Write-Error "Provide -Ruta <image> or -Carpeta <folder>"; exit 2
}
if ($archivos.Count -eq 0) { Write-Error "No images to process"; exit 3 }

# ── engine ───────────────────────────────────────────────────────────────────
$engine = Get-OcrEngine -Idioma $Idioma
$motor  = if ($engine) { 'Windows.Media.Ocr' } elseif (Get-Command tesseract -ErrorAction SilentlyContinue) { 'tesseract' } else { $null }
if (-not $motor) {
  Write-Error "No OCR engine: neither Windows.Media.Ocr nor tesseract. Install tesseract: winget install UB-Mannheim.TesseractOCR"
  exit 4
}

$resultados = @()
foreach ($a in $archivos) {
  if ($engine) {
    $r = Invoke-OcrWindows -Archivo $a -Engine $engine
    $lineas = @()
    foreach ($line in $r.Lines) {
      $palabras = @()
      foreach ($w in $line.Words) { $palabras += [pscustomobject]@{ texto = $w.Text } }
      $lineas += [pscustomobject]@{ texto = $line.Text; palabras = $palabras }
    }
    if ($Json) {
      $resultados += [pscustomobject]@{ archivo = (Split-Path $a -Leaf); motor = $motor; lineas = $lineas }
    } else {
      $resultados += ($r.Lines | ForEach-Object { $_.Text }) -join "`n"
    }
  } else {
    $txt = Invoke-OcrTesseract -Archivo $a
    if ($Json) { $resultados += [pscustomobject]@{ archivo = (Split-Path $a -Leaf); motor = $motor; texto = $txt } }
    else      { $resultados += $txt }
  }
}

# ── output ───────────────────────────────────────────────────────────────────
if ($Json) {
  $salidaTxt = $resultados | ConvertTo-Json -Depth 8
} else {
  $salidaTxt = ($resultados -join "`n`n").Trim()
}
if ($Salida) {
  $salidaTxt | Set-Content -LiteralPath $Salida -Encoding UTF8
  Write-Output "SAVED: $Salida ($($salidaTxt.Length) characters, engine $motor)"
}
$salidaTxt
