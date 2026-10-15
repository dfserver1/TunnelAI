#!/usr/bin/env pwsh
<#
  Nuevo-Diagrama.ps1 — generates architecture diagrams in Mermaid (.mmd / inside Markdown).
  Mermaid renders NATIVELY on GitHub, GitLab, Notion and VS Code: nothing to install.
  Usage:
    Nuevo-Diagrama.ps1 -Tipo flujo   -Titulo "Authentication flow"
    Nuevo-Diagrama.ps1 -Tipo capas   -Titulo "Architecture" -Salida ARCHITECTURE.md
    Nuevo-Diagrama.ps1 -Tipo secuencia
    Nuevo-Diagrama.ps1 -Tipo c4
    Nuevo-Diagrama.ps1 -Tipo componentes
    Nuevo-Diagrama.ps1 -Ruta diagram.mmd -Validar     # validates basic syntax
#>

param(
  [ValidateSet('flujo','capas','secuencia','c4','componentes')][string]$Tipo = 'flujo',
  [string]$Titulo = "Project architecture",
  [string]$Salida,
  [string]$Ruta,
  [switch]$Validar
)

function Get-Plantilla {
  param([string]$Tipo, [string]$Titulo)
  switch ($Tipo) {
    'flujo' { @"
flowchart TD
    A[User / Client] -->|HTTPS| B[API / Entrypoint]
    B --> C{Application service}
    C -->|read/write| D[(Database)]
    C -->|events| E[(Queue / Bus)]
    C -->|calls| F[External service]
    D -.->|cache| G[(Redis)]
    E --> H[Background worker]
"@ }
    'capas' { @"
flowchart TB
    subgraph Presentation
        WEB[Web / SPA]
        API[REST API]
    end
    subgraph Application
        SVC[Domain services]
        VAL[Validation]
    end
    subgraph Data
        DB[(Database)]
        FILES[(Storage)]
    end
    WEB --> API --> SVC --> DB
    SVC --> FILES
    API --> VAL
"@ }
    'secuencia' { @"
sequenceDiagram
    actor U as User
    participant W as Web
    participant A as API
    participant D as Database
    U->>W: Action
    W->>A: HTTP request
    A->>D: Query
    D-->>A: Result
    A-->>W: JSON response
    W-->>U: Updated screen
"@ }
    'c4' { @"
flowchart LR
    subgraph System[$Titulo]
        WEB[Web]
        API[API]
        DB[(Database)]
        API --> DB
        WEB --> API
    end
    USER[User] --> WEB
    EXT[External service] --> API
"@ }
    'componentes' { @"
flowchart LR
    subgraph Module A
        A1[Component A1]
        A2[Component A2]
        A1 --> A2
    end
    subgraph Module B
        B1[Component B1]
    end
    A2 --> B1
    B1 -->|event| A1
"@ }
  }
}

function Test-MermaidBasico {
  param([string]$Texto)
  $errores = @()
  $abre = ($Texto.ToCharArray() | Where-Object { $_ -eq '[' }).Count
  $cierra = ($Texto.ToCharArray() | Where-Object { $_ -eq ']' }).Count
  if ($abre -ne $cierra) { $errores += "Unbalanced [ ] brackets ($abre vs $cierra)" }
  $pa = ($Texto.ToCharArray() | Where-Object { $_ -eq '(' }).Count
  $pc = ($Texto.ToCharArray() | Where-Object { $_ -eq ')' }).Count
  if ($pa -ne $pc) { $errores += "Unbalanced ( ) parentheses ($pa vs $pc)" }
  $llaveA = ($Texto.ToCharArray() | Where-Object { $_ -eq '{' }).Count
  $llaveC = ($Texto.ToCharArray() | Where-Object { $_ -eq '}' }).Count
  if ($llaveA -ne $llaveC) { $errores += "Unbalanced { } braces ($llaveA vs $llaveC)" }
  if ($Texto -notmatch '(flowchart|graph|sequenceDiagram|classDiagram)') { $errores += "Missing diagram declaration (flowchart TD, sequenceDiagram…)" }
  return $errores
}

# markdown code fences built from characters (literal backticks break PowerShell)
$bt = [string][char]96
$fence3 = $bt * 3
$fence6 = $bt * 6

# ── validate an existing file ─────────────────────────────────────────────────
if ($Validar) {
  if (-not $Ruta -or -not (Test-Path -LiteralPath $Ruta)) { Write-Error "Provide -Ruta <file.mmd or .md> to validate"; exit 2 }
  $txt = Get-Content -LiteralPath $Ruta -Raw
  # if it's Markdown, extract the ```mermaid blocks
  $bloques = [regex]::Matches($txt, '(?s)```mermaid(.*?)```')
  if ($bloques.Count -gt 0) {
    $n = 0; $fallos = 0
    foreach ($b in $bloques) {
      $n++
      $errs = Test-MermaidBasico -Texto $b.Groups[1].Value
      if ($errs.Count) { $fallos++; Write-Host "✗ Mermaid block #$n : $($errs -join '; ')" -ForegroundColor Red }
      else { Write-Host "✓ Mermaid block #$n OK" -ForegroundColor Green }
    }
    Write-Host "$n block(s), $fallos with problems" -ForegroundColor Cyan
    exit $(if ($fallos) { 1 } else { 0 })
  }
  $errs = Test-MermaidBasico -Texto $txt
  if ($errs.Count) { Write-Host "✗ $($errs -join '; ')" -ForegroundColor Red; exit 1 }
  Write-Host "✓ Valid diagram" -ForegroundColor Green
  exit 0
}

# ── generate ───────────────────────────────────────────────────────────────────
$diagrama = Get-Plantilla -Tipo $Tipo -Titulo $Titulo
$errs = Test-MermaidBasico -Texto $diagrama
if ($errs.Count) { Write-Error "Invalid template: $($errs -join '; ')"; exit 3 }

if ($Salida) {
  $md = @"
# $Titulo

> Diagram generated with TunnelAI — edit it and it renders by itself on GitHub/GitLab/VS Code.

$($fence6)mermaid
$diagrama
$($fence6)

## How to read it
- Replace the example nodes with the real components of the project.
- Add a legend if you use colors or styles.
- Diagrams live in the repo: they are versioned with the code.

## Legend
| Shape | Meaning |
|---|---|
| `[ ]` rectangle | component / service |
| `[( )]` cylinder | storage (DB, queues, files) |
| `{ }` diamond | decision |
| `-->` arrow | call / flow |
| `-.->` dotted | weak relationship (events, cache) |
"@
  $md | Set-Content -LiteralPath $Salida -Encoding UTF8
  Write-Output "DIAGRAM CREATED: $Salida"
  Write-Output "Tip: validate it with .\Nuevo-Diagrama.ps1 -Validar -Ruta `"$Salida`""
}
else {
  Write-Output "$fence3 mermaid"
  Write-Output $diagrama
  Write-Output $fence3
}
