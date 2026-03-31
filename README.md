# Build Harness Skill for Claude Code

A Claude Code skill that creates, maintains, and executes project-specific build scripts. Platform-agnostic — works with any build system, OS, and shell. Born from real build failures, refined through automated code review.

## What It Does

When you need to build a project, the skill:

1. **Discovers** your build system, toolchain, workspace layout, and past preferences
2. **Generates** a build script tailored to your project with rational defaults
3. **Reviews** the script using multiple specialized agents (build system, security, adversarial)
4. **Executes** builds with output capture, priority enforcement, and staleness detection
5. **Persists** the harness in memory so it survives conversation compaction

## Supported Build Systems

CMake, MSBuild, Make, Cargo (Rust), Go, npm/yarn/pnpm, Gradle, Maven, Meson, Bazel, xmake, SCons, Autotools, and Just. The skill discovers which one you're using and generates appropriate commands.

## Supported Platforms

| Platform | Priority Enforcement | Timestamp Method | Notes |
|----------|---------------------|------------------|-------|
| Linux | `nice -n 10` (covers children) | `stat -c %Y` | Simplest path |
| macOS | `nice -n 10` | `stat -f %m` | BSD stat syntax |
| Windows (MSYS2/Git Bash) | PowerShell watchdog | `stat -c %Y` (GNU) | Use `-flag` not `/flag` for MSBuild |
| Windows (PowerShell) | Native priority | `(Get-Item).LastWriteTime` | Different script structure |

## Key Features

- **Toolchain discovery** — finds compilers via `vswhere` (Windows), `which`/`command -v`, or platform-specific methods. Never assumes PATH.
- **Shell compatibility** — handles MSYS2/Cygwin flag mangling, BSD vs GNU `stat`, fish shell limitations
- **Priority enforcement** — `nice` on Unix, PowerShell watchdog on Windows, with trap-based cleanup
- **Staleness detection** — warns when artifacts weren't actually updated by the build
- **Artifact snapshots** — copies output with integrity verification and configurable naming
- **Post-compaction recovery** — memory files let new sessions use existing harnesses without rediscovery

## The Skill Workflow

| Phase | Activity | Model Tier |
|-------|----------|------------|
| 0 | Check memory for existing harness | Direct |
| 1 | Workspace discovery (build system, toolchain, layout) | Haiku |
| 2 | Script generation | Sonnet |
| 3 | Review pipeline (build + security + adversarial) | Sonnet |
| 4 | Execute build with monitoring | Direct |
| 5 | Persist harness to memory | Direct |
| 6 | Interview user about preferences (first time) | Direct |

Phase 0 is the compaction survival mechanism — the harness and its usage are stored in a memory file, so a fresh session finds and uses it without rediscovery.

## Installation

Copy `SKILL.md` to your Claude Code skills directory:

```bash
mkdir -p ~/.claude/skills/build-harness
cp SKILL.md ~/.claude/skills/build-harness/
```

The skill auto-registers and triggers on build-related requests.

## Example

See `examples/orcaslicer_build.sh` for a Windows/MSBuild reference implementation — a build harness for OrcaSlicer across three git worktrees.

```bash
# Incremental lib build
./build.sh snuggle lib

# Full build with snapshot
./build.sh snuggle dll --snapshot --note=my_feature

# AFK full rebuild
./build.sh v1 all --afk --clean
```

## Review History

The skill was reviewed by:
- **Gimli** (build systems) — 16 findings including locked-file check, Linux nice/renice path, watchdog self-test placement
- **Gandalf** (architecture) — 7 findings including Phase 0 probe step, multi-build-system template gaps, reviewer conflict resolution

Findings were incorporated into the platform-agnostic rewrite.

## License

MIT
