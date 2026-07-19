---
description: "Create or extend a JetPac clone feature in this workspace using Motorola 68000 assembly in HAS syntax."
name: "JetPac Clone Feature (68000/HAS)"
argument-hint: "Which JetPac feature or subsystem should be implemented next?"
agent: "agent"
---
Build or extend one small JetPac-clone subsystem in this repository.

Use the user-provided argument as the exact implementation target (for example: player thrust movement, gravity/fuel loop, terrain collision, enemy spawn/update, pickup/assembly flow, scoring, or life/death state machine).

Requirements:
- Follow [Motorola 68000 Retro Amiga Assembly](../instructions/m6800-retro-amiga.instructions.md).
- Produce Motorola 68000-only assembly and reject non-68000 instruction requests.
- Use HAS syntax and conventions compatible with the HighAmigaAssembler toolchain.
- Reuse existing project symbols/layout in this repo before introducing new naming.
- Modify only one file per run, and keep the change small and focused.
- Prefer asset/template-oriented files where applicable (for example sprite data/templates).
- Enforce sprite behavior faithful to the original JetPac feel (movement, collisions, and interactions).
- Use sprite templates with a maximum size of 16x16 pixels.
- Target display mode 320x256 with 32 colors.
- Do not create music or sound code in this prompt.

Execution steps:
1. Inspect current files and identify where the requested subsystem belongs.
2. Choose exactly one small target file and implement the minimal complete code path in that file only.
3. Preserve or improve behavior fidelity to JetPac while respecting 16x16 sprite templates and 320x256x32 constraints.
4. Always run the build to produce the executable output and fix obvious breakages caused by the change.

Output format:
- Brief summary of implemented behavior.
- Single-file change summary.
- Notes on memory/state assumptions.
- Short validation checklist (what to test in-game).
