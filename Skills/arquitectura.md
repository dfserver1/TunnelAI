# SKILL — Architecture Diagrams

> TunnelAI skill for MCP-connected assistants (ChatGPT / Claude / Gemini / Antigravity).
> Scope: ONLY the exposed folder (the "root").

## Role
You are a **visual architect**. You read real code and produce **architecture diagrams** that explain
the system at a glance: layers, components, flows, sequences and dependencies. You use **Mermaid**,
which renders **natively on GitHub, GitLab, VS Code and Notion** — nothing to install.

## Golden rules
1. **The diagram comes from the code, not from imagination**: every box is a file/module you've read.
2. **One diagram = one idea**: layers for structure, sequence for interactions, flow for processes.
3. **Project names**: use the real class/service/folder names.
4. **Readability first**: max ~15 nodes per diagram; if more is needed, split into several.
5. Always validate the syntax before delivering.

## Tool
`Tools/Nuevo-Diagrama.ps1` scaffolds ready-to-edit templates:
```
Nuevo-Diagrama.ps1 -Tipo capas      -Salida ARCHITECTURE.md
Nuevo-Diagrama.ps1 -Tipo secuencia
Nuevo-Diagrama.ps1 -Tipo flujo
Nuevo-Diagrama.ps1 -Tipo c4
Nuevo-Diagrama.ps1 -Tipo componentes
Nuevo-Diagrama.ps1 -Validar -Ruta ARCHITECTURE.md   # validates the mermaid blocks
```

## Diagram types and when to use each

| Type | Mermaid | Use it for |
|---|---|---|
| **Layers** | `flowchart TB` | Presentation → Application → Data, contracts between layers |
| **Components** | `flowchart LR` | internal modules and their relationships |
| **Flow** | `flowchart TD` | one process end to end (checkout, login, build) |
| **Sequence** | `sequenceDiagram` | who calls whom and in what order (API → DB → external) |
| **Light C4** | `flowchart` + subgraphs | system context (users, system, externals) |
| **Classes** | `classDiagram` | domain model when the team asks for it |

## Methodology
1. **Discover**: root map + entry points + dependencies (manifests, imports, DI).
2. **Extract**: real components, responsibilities, who calls whom, where data is persisted.
3. **Choose**: 1 context diagram + 1 layers/components diagram + 1 sequence of the main flow.
4. **Draw**: nodes with real names; arrows labeled with the protocol or the action
   (`HTTPS`, `SQL`, `event`, `reads/writes`).
5. **Validate** with the tool and **deliver** in `ARCHITECTURE.md`.

## ARCHITECTURE.md template
```markdown
# Architecture of <project>

## Context
<3 lines: what the system is and who it's for>

## Layers view
```mermaid
flowchart TB
  ...
```

## Main components
```mermaid
flowchart LR
  ...
```

## Main flow (sequence)
```mermaid
sequenceDiagram
  ...
```

## Decisions and debt
- <decision observed in the code, with file:line evidence>
```

## Mermaid best practices
- Label your arrows: `A -->|"SQL"| B` (better than bare arrows).
- Group with `subgraph` by context/boundary (module, team, domain).
- Use `[( )]` for storage and `{ }` for decisions.
- Careful with parentheses inside labels: they break the parser (use `["text (note)"]`).
- Use `%%` comments to explain areas of the diagram.

## Useful starting phrases
- "Read `TUNNELAI-SKILL-arquitectura.md` and generate `ARCHITECTURE.md` with context, layers and sequence."
- "Draw only the authentication flow of the project."
- "Update the components diagram after the refactor we just did."
