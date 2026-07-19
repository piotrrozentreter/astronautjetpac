---
description: "Use when writing or modifying Motorola 68000 assembly for retro Amiga-style game code in HAS syntax. Enforces 68000-only instruction set, performance-first routines, and low-level game-loop conventions."
name: "Motorola 68000 Retro Amiga Assembly"
applyTo:
  - "**/*.s"
  - "**/*.asm"
  - "**/*.has"
  - "**/*.inc"
---
# Motorola 68000 Retro Amiga Assembly Rules

- Target only Motorola 68000 assembly. Always reject requests or snippets that use non-68000 instructions, addressing modes, register names, or syntax.
- Reject mixed-architecture output. If a request implies another architecture, restate the solution in Motorola 68000 terms only.
- Use HAS language syntax and conventions from this toolchain: /run/media/piotr/BACKUP/Rozen/Projects/highamigaassembler/.
- Optimize for game-loop hot paths first: input, entity updates, collision checks, and render preparation.
- Prefer deterministic timing and simple control flow over clever but opaque instruction tricks.
- Keep memory usage explicit. Document RAM/ROM assumptions and memory map constraints in comments when relevant.
- Keep labels short, readable, and consistent with existing project naming.
- Preserve existing assembler syntax and directive style already used by the project.
- Use Context7 documentation lookup when syntax, directives, or integration details are uncertain.
- For non-trivial routines, include brief comments for register/flag effects and clobbered state.

## Output Expectations

- Provide complete routines that can be assembled directly, not pseudo-assembly.
- Include integration notes when changing calling conventions, memory layout, or shared symbols.
- Include a short validation checklist for edge cases in timing-sensitive code.
