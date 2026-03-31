# Skill: Build Harness

Create, maintain, and execute project-specific build scripts that encode user preferences, handle toolchain discovery, enforce process priority, capture output, detect staleness, and snapshot artifacts. The harness survives conversation compaction through memory files.

## When to Trigger
- User says "build", "compile", "make", "rebuild", "build harness", "build script"
- User wants to compile a project and no existing harness is found
- User is frustrated with build failures, missing output, or priority issues
- After conversation compaction, when a build is needed and the harness exists in memory

## Phase 0 — Check for Existing Harness

Before doing anything else, check memory for a build harness reference:

1. Read the project's `MEMORY.md` index for any entry mentioning "build harness" or "build script"
2. If found, read the referenced memory file to get the script path and usage
3. Verify the script still exists at that path
4. If it exists and is current: **use it directly** — skip to Phase 4 (Execute)
5. If it exists but is stale or broken: proceed to Phase 2 (Repair) instead of Phase 1

This phase is critical for post-compaction recovery. The memory file IS the continuity mechanism.

## Phase 1 — Workspace Discovery

Deploy a **Haiku-tier** agent to scan the workspace quickly and build context. The agent should:

### 1a. Identify the build system
- Scan for: `CMakeLists.txt`, `Makefile`, `*.sln`, `*.vcxproj`, `package.json`, `Cargo.toml`, `go.mod`, `build.gradle`, `meson.build`, `*.pro`
- Check for build directories: `build/`, `out/`, `target/`, `dist/`, `node_modules/`
- Identify the toolchain: MSVC, GCC, Clang, Rust, Go, Node, etc.

### 1b. Discover the environment
- OS and shell (bash on Windows via MSYS2/Git Bash is common and has pitfalls)
- Tool paths: compiler, linker, build system binary. **Never assume PATH.** Always verify with `which` or full path discovery.
- For MSVC on Windows: use `vswhere.exe` first, then check known VS install paths. The `/` vs `-` flag prefix matters in MSYS2 bash.

### 1c. Map the workspace structure
- Multiple worktrees? List them with branches.
- Multiple build configurations (Debug/Release/RelWithDebInfo)?
- Dependency builds? (deps/ directories with their own build)
- Output artifacts: what gets produced and where? (.exe, .dll, .lib, .so, .wasm, etc.)

### 1d. Review build history and user preferences
- Check memory files for build-related feedback (priority, parallelism, snapshots)
- Check git log for build-related commits or build failure fix patterns
- Check for existing build scripts, Makefiles, CI configs
- Look for build log files that reveal past failures

### 1e. Produce a discovery report
Format:
```
Build System: [CMake/MSBuild/cargo/etc.]
Toolchain: [MSVC 2022/GCC 13/rustc 1.75/etc.]
Tool Path: [full path to build binary]
Shell: [bash/zsh/powershell] on [OS]
Shell Pitfalls: [MSYS2 path mangling, etc.]
Worktrees: [list with branches]
Configurations: [Release/Debug/etc.]
Output Artifacts: [what, where]
Known Preferences: [from memory]
```

## Phase 2 — Script Generation

Deploy a **Sonnet-tier** agent (Gimli, conceptually) to write the build script. The script MUST handle:

### Required features (non-negotiable)
1. **Toolchain discovery** — find the compiler/build tool by reliable means, not PATH assumption
2. **Shell compatibility** — handle MSYS2/Git Bash flag mangling (use `-flag` not `/flag` for MSBuild)
3. **Output capture** — all build output must be visible to the caller. No `start`, no `cmd.exe /c` wrappers that swallow output.
4. **Error propagation** — non-zero exit codes must surface. `set -euo pipefail` with correct handling of intentional failures.
5. **Staleness detection** — compare artifact timestamps against build start time. Warn if nothing was updated.
6. **Argument parsing** — positional args for workspace/target, `--flags` for options. Sensible defaults.
7. **Help text** — usage block at the top of the script

### User-preference features (encode from memory/discovery)
1. **Process priority** — if user prefers low-priority builds (BelowNormal/nice), implement a watchdog that enforces it on all child processes, not just the parent
2. **Parallelism** — default to coexist level (e.g., `-m:4`, `-j4`), with an `--afk` flag for full parallel
3. **Artifact snapshots** — copy output to a versioned directory with integrity verification (MD5/SHA256)
4. **Clean builds** — as a separate invocation before the build, never appended to the same command

### Priority watchdog requirements (when applicable)
- Start as a background subshell
- Poll every 3-5 seconds for build-related processes
- Self-test: verify its own tooling (e.g., PowerShell) works before entering the loop
- Trap-based cleanup: `trap cleanup INT TERM EXIT` — no leaked processes on Ctrl-C
- Exit condition: stop when no build processes remain
- Initial delay: 1 second (not 3+ — fast incremental builds may finish before the watchdog starts)

### Script structure template
```bash
#!/usr/bin/env bash
# build.sh — [Project] build harness
# Usage: ...
set -euo pipefail

# 1. Toolchain discovery (never assume PATH)
# 2. Argument parsing (workspace, target, options)
# 3. Validation (solution/project file exists, workspace exists)
# 4. Priority watchdog (if applicable, with trap cleanup)
# 5. Clean phase (separate invocation, if requested)
# 6. Build phase (direct invocation, output to stdout/stderr)
# 7. Result checking (exit code, staleness, artifact existence)
# 8. Snapshot (if requested, with integrity verification)
# 9. Summary
```

## Phase 3 — Review Pipeline

After the script is written, run reviews in parallel:

### Gimli (Sonnet) — Build system review
- Will the toolchain invocation work in the target shell?
- Are there flag-mangling risks? (MSYS2 `/` → path conversion)
- Will the watchdog catch all child processes?
- Is error handling correct under `set -euo pipefail`?
- Are there race conditions?

### Aragorn (Sonnet) — Security and robustness review
- Are paths properly quoted for spaces?
- Is the script injection-safe? (no unquoted `$vars` in commands)
- Will it handle unexpected process states gracefully?
- Does it avoid destructive operations without confirmation?

### Uruk-Hai (Haiku) — Adversarial testing
- What happens with missing tools, empty directories, wrong arguments?
- What happens if the build is already running?
- What happens on Ctrl-C at various points?

Apply fixes from all reviewers before proceeding.

## Phase 4 — Execute

Run the build using the harness:
```bash
bash /path/to/build.sh [workspace] [target] [options]
```

For background builds, use `run_in_background: true` on the Bash tool.

### Monitoring during build
- If running in foreground: output streams directly
- If running in background: the completion notification arrives automatically
- After completion: read the output file and check for errors, warnings, staleness

### Post-build checklist
1. Check exit code
2. Check staleness warnings
3. If snapshot requested, verify MD5 match
4. Report to user: what compiled, how long, any warnings
5. If build failed: read error output, diagnose, suggest fix

## Phase 5 — Persist

After the harness is created or updated:

### Save to memory
Create/update a reference memory file with:
- Script path
- Usage examples for common operations
- Worktree shortcuts
- Target shortcuts
- Known pitfalls and their mitigations

### Update MEMORY.md index
Add a one-line pointer to the memory file.

### Keep the script updated
When the build environment changes (new worktree, new toolchain, new preferences), update the script in place and update the memory file. The script is a living document.

## Phase 6 — Interview (first time only)

After the first successful build with the harness, ask the user:

> The harness is working. A few questions to make it better:
> 1. Want notification sounds or desktop toast on build completion?
> 2. Want automatic `git stash` before clean builds?
> 3. Want build timing history logged to a file?
> 4. Want the script to auto-detect which target to build based on changed files?
> 5. Anything else that would make builds less annoying?

Save responses as feedback memories.

## Model Tier Allocation

| Activity | Tier | Why |
|----------|------|-----|
| Workspace scan | Haiku | Fast, mechanical file discovery |
| Script generation | Sonnet | Balanced — needs build system knowledge |
| Gimli review | Sonnet | Build system expertise |
| Aragorn review | Sonnet | Security and robustness |
| Adversarial test | Haiku | Fast, numerous edge cases |
| Build execution | Direct (no agent) | Just a bash command |
| Error diagnosis | Sonnet | Needs context about build systems |
| Architecture review | Opus | Only if the build system is complex or unusual |

## Post-Compaction Recovery

The entire point of the memory system is that after compaction, the next session can:

1. Read MEMORY.md → find "Build harness" entry
2. Read the memory file → get script path and usage
3. Run the script directly

No rediscovery needed. No reinventing the wheel. The script and the memory are the continuity mechanism.

If the memory says the script exists but it doesn't (deleted, moved), fall back to Phase 1 and rebuild it. Update the memory when done.

## Reference Implementation

See `D:\ClauDe\orcaPatch\build.sh` — a build harness for OrcaSlicer across three git worktrees, featuring:
- MSBuild discovery via vswhere + fallback paths
- MSYS2-safe flag syntax (`-p:` not `/p:`)
- BelowNormal priority watchdog with trap cleanup
- Staleness detection (timestamp vs build start)
- MD5-verified DLL snapshots
- Coexist parallelism (`-m:4` default, `--afk` for full)

This was developed through three failed build attempts (PATH missing, output swallowed, flags mangled) before the harness got it right on the first try. The harness exists precisely to encode those lessons.
