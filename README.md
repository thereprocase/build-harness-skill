# Build Harness Skill for Claude Code

A Claude Code skill that creates, maintains, and executes project-specific build scripts. Born from three failed OrcaSlicer build attempts on Windows — PATH issues, output capture failures, MSYS2 flag mangling — and refined through automated code review.

## What It Does

When you need to build a project, the skill:

1. **Discovers** your build system, toolchain, workspace layout, and past preferences
2. **Generates** a build script tailored to your project with rational defaults
3. **Reviews** the script using multiple specialized agents (build system, security, adversarial)
4. **Executes** builds with output capture, priority enforcement, and staleness detection
5. **Persists** the harness in memory so it survives conversation compaction

## Key Features

- **Toolchain discovery** — finds compilers by reliable means, never assumes PATH
- **Shell compatibility** — handles MSYS2/Git Bash flag mangling (`-p:` not `/p:`)
- **Priority enforcement** — watchdog process keeps builds at BelowNormal/nice
- **Staleness detection** — warns when artifacts weren't actually updated
- **Artifact snapshots** — copies output with MD5 verification
- **Post-compaction recovery** — memory files let new sessions use existing harnesses immediately

## Installation

Copy `SKILL.md` to your Claude Code skills directory:

```bash
mkdir -p ~/.claude/skills/build-harness
cp SKILL.md ~/.claude/skills/build-harness/
```

The skill auto-registers and triggers on build-related requests.

## Example

See `examples/orcaslicer_build.sh` for a reference implementation — a build harness for OrcaSlicer across three git worktrees with MSBuild on Windows.

```bash
# Incremental lib build
./build.sh snuggle lib

# Full DLL build with snapshot
./build.sh snuggle dll --snapshot

# AFK full rebuild
./build.sh v1 all --afk --clean
```

## Review History

The skill and reference implementation were reviewed by:
- **Gimli** (build system specialist) — 16 findings, 3 HIGH
- **Gandalf** (architecture) — 7 findings, 0 HIGH
- **Aragorn** (security/robustness) — included in Gimli's scope

Key fixes applied from reviews:
- Clean phase runs as separate MSBuild invocation (not appended to target)
- Watchdog has trap-based cleanup (no leaked processes on Ctrl-C)
- `BUILD_EXIT=$?` capture pattern prevents `set -e` from killing the script before cleanup
- MSYS2 flag mangling documented with `-` prefix solution

## License

MIT
