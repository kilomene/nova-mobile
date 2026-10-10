# NOVA Mobile — Unity 6 Port

Native Android battle-royale game, ported from the Godot 4.3 project (`../project/`,
the finished spec — read-only). Unity 6 (6000.0.x LTS), C#, Built-in Render Pipeline.

## Structure

- `Assets/_Nova/CONVENTIONS.md` — coding conventions + cross-system contracts (read first)
- `Assets/_Nova/Scripts/<System>/` — game systems
- `Assets/_Nova/Shaders/` — ShaderLab shaders
- `ProjectSettings/` — Android (landscape, `com.novamobile.game`, IL2CPP, ARM64)

## Rules

- Nobody builds the APK by hand — the `game-ci` GitHub Actions workflow builds it.
- No Unity Editor in this environment: all C# must be complete and compile-clean by care.
- Mobile-first: pooled objects, no per-frame allocation in hot paths.
