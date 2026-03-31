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

- **Toolchain discovery** — finds compilers via `vswhere.exe` (Windows) or standard paths, never assumes PATH
- **Shell compatibility** — handles MSYS2/Git Bash flag mangling (`-p:` not `/p:`)
- **Priority enforcement** — watchdog process keeps builds at BelowNormal/nice, catches child processes
- **Staleness detection** — warns when artifacts weren't actually updated by the build
- **Full artifact snapshots** — copies entire Release directory with `{hash}_{note}` naming and MD5 verification
- **Post-compaction recovery** — memory files let new sessions use existing harnesses immediately

## The Skill Workflow

The skill operates in six phases, each assigned an appropriate model tier:

| Phase | Activity | Model Tier |
|-------|----------|------------|
| 0 | Check memory for existing harness | Direct (no agent) |
| 1 | Workspace discovery (build system, toolchain, layout) | Haiku (fast scan) |
| 2 | Script generation | Sonnet (build expertise) |
| 3 | Review pipeline (Gimli + Aragorn + adversarial) | Sonnet + Haiku |
| 4 | Execute build with monitoring | Direct (bash) |
| 5 | Persist harness to memory | Direct (write) |
| 6 | Interview user about preferences (first time) | Direct (ask) |

Phase 0 is the key to surviving conversation compaction — the harness and its usage are stored in a memory file, so a fresh session can find and use it without rediscovery.

## Installation

Copy `SKILL.md` to your Claude Code skills directory:

```bash
mkdir -p ~/.claude/skills/build-harness
cp SKILL.md ~/.claude/skills/build-harness/
```

The skill auto-registers and triggers on build-related requests.

## Reference Implementation

See `examples/orcaslicer_build.sh` — a build harness for OrcaSlicer across three git worktrees with MSBuild on Windows.

```bash
# Incremental lib build (fastest, after editing one .cpp)
./build.sh snuggle lib

# Build DLL with full snapshot to builds/{hash}_{note}/
./build.sh snuggle dll --snapshot --note=radial_snuggle

# Clean rebuild, all cores (AFK only)
./build.sh v1 all --afk --clean

# Snapshot with auto-generated note from commit message
./build.sh v2 dll --snapshot
```

### Snapshot format

Snapshots copy the entire Release directory (all DLLs, resources, ~664MB) into a folder named `{10-char-hash}_{descriptive_note}`:

```
builds/
  bf2c3ddb85_radial_snuggle_clean/
    OrcaSlicer.dll
    TKBO.dll
    TKBRep.dll
    ...
    resources/
  a3c7b4b062_snuggle_adaptive/
    ...
```

The DLL is MD5-verified against the build output. The commit hash and message are printed so you know exactly what code produced the snapshot.

## Review History

The skill and reference implementation were reviewed by the [Lord of the Code](https://github.com/thereprocase) framework:

- **Gimli** (Sonnet, build systems) — 16 findings, 3 HIGH: watchdog self-test placement, Linux nice/renice gap, locked DLL check
- **Gandalf** (Sonnet, architecture) — 7 findings: Phase 0 probe step, model tier for adversarial testing, multi-build-system template gaps
- **Aragorn** (security/robustness) — scoped into Gimli's review

Key fixes applied:
- Clean phase runs as separate MSBuild invocation (not appended to target list)
- Watchdog has trap-based cleanup (no leaked processes on Ctrl-C)
- `BUILD_EXIT=$?` capture pattern prevents `set -e` from killing the script before cleanup
- MSYS2 flag mangling handled with `-` prefix (not `/`) for all MSBuild switches
- Staleness detection compares artifact timestamps against build start time
- Full Release directory snapshots with `{hash}_{note}` naming convention

## Known Limitations

- Priority watchdog is Windows-only (PowerShell). Linux/macOS should use `nice -n 10` on the build command instead.
- `stat -c` syntax is GNU (Linux/MSYS2). BSD (macOS) uses `stat -f`.
- No pre-build check for locked DLL/EXE (will fail at link time if OrcaSlicer is running).
- `vswhere` drive letter lowercasing uses GNU sed `\L` — won't work with BSD sed.

## License

MIT
