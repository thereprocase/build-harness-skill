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
3. Verify the script still exists at that path and probe it (e.g., `bash build.sh --help` or dry-run) to confirm it's functional
4. If it exists and is current: **use it directly** — skip to Phase 4 (Execute)
5. If it exists but is stale or broken: proceed to Phase 2 (Repair) instead of Phase 1

This phase is critical for post-compaction recovery. The memory file IS the continuity mechanism.

## Phase 1 — Workspace Discovery

Deploy a **Haiku-tier** agent to scan the workspace quickly and build context. The agent should:

### 1a. Identify the build system
Scan for project files and infer the build system:

| File | Build System |
|------|-------------|
| `CMakeLists.txt` | CMake (+ generator: Make, Ninja, MSBuild) |
| `Makefile`, `GNUmakefile` | Make |
| `*.sln`, `*.vcxproj` | MSBuild / Visual Studio |
| `Cargo.toml` | Cargo (Rust) |
| `go.mod` | Go |
| `package.json` | npm / yarn / pnpm (Node) |
| `pyproject.toml`, `setup.py` | pip / setuptools (Python) |
| `build.gradle`, `build.gradle.kts` | Gradle (Java/Kotlin) |
| `pom.xml` | Maven (Java) |
| `meson.build` | Meson |
| `BUILD`, `WORKSPACE` | Bazel |
| `justfile` | Just (task runner, often wraps another system) |
| `Makefile.am`, `configure.ac` | Autotools |
| `xmake.lua` | xmake |
| `SConstruct` | SCons |

Check for build output directories: `build/`, `cmake-build-*/`, `out/`, `target/`, `dist/`, `_build/`, `.build/`, `node_modules/`

### 1b. Discover the environment
- **OS**: Linux, macOS, Windows
- **Shell**: bash, zsh, fish, PowerShell. Note if running a compatibility layer (MSYS2, Cygwin, WSL)
- **Tool paths**: find the build tool binary. **Never assume it's on PATH.** Verify with `which`/`where`/`command -v`, and use platform-specific discovery when available:

| Platform | Discovery method |
|----------|-----------------|
| Windows (MSVC) | `vswhere.exe` for VS install path, then known MSBuild subdirectory |
| Windows (MSYS2/Cygwin) | `which` may miss Windows-native tools — also check `where` via `cmd.exe` |
| Linux/macOS | `which` / `command -v` is usually sufficient |
| Rust | `rustup which cargo` for toolchain-specific path |
| Node | `npx --yes which` or check `node_modules/.bin/` |

**Shell pitfalls by platform:**

| Shell | Pitfall |
|-------|---------|
| MSYS2 / Git Bash | Converts `/flag` to a Windows path. Use `-flag` for MSBuild switches, or set `MSYS2_ARG_CONV_EXCL` |
| Cygwin | Same path mangling as MSYS2 |
| WSL1 | Path translation quirks when calling Windows binaries |
| fish | No `set -euo pipefail` equivalent — use `fish_exit_status` or write harness in bash |

### 1c. Map the workspace structure
- Multiple worktrees? List them with branches.
- Multiple build configurations (Debug/Release/RelWithDebInfo)?
- Dependency builds? (deps/ directories with their own build)
- Output artifacts: what gets produced and where?

### 1d. Review build history and user preferences
- Check memory files for build-related feedback (priority, parallelism, snapshots)
- Check git log for build-related commits or build failure fix patterns
- Check for existing build scripts, CI configs (`.github/workflows/`, `Jenkinsfile`, `.gitlab-ci.yml`)
- Look for build log files that reveal past failures

### 1e. Produce a discovery report
```
Build System: [CMake/MSBuild/cargo/etc.]
Toolchain: [MSVC 2022/GCC 13/rustc 1.75/etc.]
Tool Path: [full path to build binary]
OS: [Linux/macOS/Windows]
Shell: [bash/zsh/powershell]
Shell Pitfalls: [if any]
Worktrees: [list with branches]
Configurations: [Release/Debug/etc.]
Output Artifacts: [what, where]
Known Preferences: [from memory]
```

## Phase 2 — Script Generation

Deploy a **Sonnet-tier** agent to write the build script. The script MUST handle:

### Required features (non-negotiable)
1. **Toolchain discovery** — find the build tool by reliable means, not PATH assumption
2. **Shell compatibility** — handle platform-specific flag syntax and path conventions
3. **Output capture** — all build output must be visible to the caller. No subprocess wrappers that swallow output.
4. **Error propagation** — non-zero exit codes must surface. Use `set -euo pipefail` (bash/zsh) with the `|| EXIT_CODE=$?` pattern to capture exit codes without triggering early termination before cleanup runs.
5. **Staleness detection** — compare artifact timestamps against build start time. Warn if nothing was updated. Use portable timestamp methods (`stat -c %Y` on Linux/MSYS2, `stat -f %m` on macOS, or `python3 -c "import os; print(int(os.path.getmtime(...)))"` for full portability).
6. **Argument parsing** — positional args for workspace/target, `--flags` for options. Sensible defaults.
7. **Echo the build command** before invoking it — invaluable for debugging flag issues.
8. **Help text** — usage block at the top of the script

### User-preference features (encode from memory/discovery)
1. **Process priority** — if user prefers low-priority builds, enforce on all child processes:
   - **Linux/macOS**: launch build with `nice -n 10` (covers all children automatically)
   - **Windows**: priority watchdog subshell that polls and lowers `msbuild`, `cl`, `link` via PowerShell
2. **Parallelism** — default to coexist level (e.g., `-j4`, `-m:4`), with `--afk` flag for full parallel
3. **Artifact snapshots** — copy output to a versioned directory with integrity verification (MD5/SHA256). Use `{hash}_{descriptive_note}` folder naming if the project has an established snapshot convention.
4. **Clean builds** — as a separate invocation before the build, never appended to the same command (MSBuild will run targets in append order, not sequentially)

### Priority watchdog (Windows-specific, when `nice` is not available)
- Self-test tooling (e.g., PowerShell) **once before entering the loop**, not every iteration
- Start as a background subshell with 1-second initial delay
- Poll every 3-5 seconds for build-related processes
- Parameterize the process name list for the build system in use (msbuild/cl/link, ninja/cmake, gcc/g++, etc.)
- Trap-based cleanup: `trap cleanup INT TERM EXIT` — no leaked processes on Ctrl-C
- Exit condition: stop when no build processes remain (poll twice with a short gap before exiting to avoid race with slow process startup)

### Build-system-specific notes

**CMake**: Use `cmake --build <dir> --config Release` rather than invoking the generator directly. This is portable across Make, Ninja, and MSBuild backends. Clean with `cmake --build <dir> --target clean`.

**Cargo**: Use `cargo build --release`. Target directory is `target/release/` by default but can be overridden with `--target-dir` for coexist builds. `cargo clean` is safe.

**Go**: `go build -o <output> ./cmd/...`. No separate clean needed (Go rebuilds as needed). Use `GOFLAGS=-trimpath` for reproducible builds.

**Node**: Detect package manager (`package-lock.json` → npm, `yarn.lock` → yarn, `pnpm-lock.yaml` → pnpm). Use `ci` not `install` for reproducible builds.

**Make**: `make -j$(nproc)` on Linux, `make -j$(sysctl -n hw.ncpu)` on macOS. Clean with `make clean`.

### Pre-build checks
- **Locked output files** (Windows): if the target binary is in use, the link step will fail. Check before building and warn the user.
- **Generated dependencies**: after a clean, verify that generated headers/configs exist before building. A stale generated file from a different config can cause silent corruption.

### Script structure template
```bash
#!/usr/bin/env bash
# build.sh — [Project] build harness
# Usage: ...
set -euo pipefail

# 1. Toolchain discovery (never assume PATH)
# 2. Argument parsing (workspace, target, options)
# 3. Validation (project file exists, workspace exists, output not locked)
# 4. Priority enforcement (nice on Linux/macOS, watchdog on Windows)
# 5. Clean phase (separate invocation, if requested)
# 6. Echo build command
# 7. Build phase (direct invocation, output to stdout/stderr)
# 8. Result checking (exit code, staleness, artifact existence)
# 9. Snapshot (if requested, with integrity verification)
# 10. Summary
```

## Phase 3 — Review Pipeline

After the script is written, run reviews in parallel:

### Gimli (Sonnet) — Build system review
- Will the toolchain invocation work in the target shell?
- Are there flag-mangling or path-conversion risks?
- Will priority enforcement catch all child processes?
- Is error handling correct under `set -euo pipefail`?
- Are there race conditions in the watchdog or staleness check?
- Is timestamp comparison portable for the target OS?

### Aragorn (Sonnet) — Security and robustness review
- Are paths properly quoted for spaces and special characters?
- Is the script injection-safe? (no unquoted `$vars` in commands)
- Will it handle unexpected process states gracefully?
- Does it avoid destructive operations without confirmation?

### Adversarial testing (Sonnet) — Shell and error-mode analysis
- What happens with missing tools, empty directories, wrong arguments?
- What happens if the build is already running?
- What happens on Ctrl-C at various points?
- How do `set -e`, traps, and `|| EXIT_CODE=$?` interact? (This requires Sonnet-level reasoning, not Haiku.)

If reviewers conflict, resolve by priority: security > correctness > ergonomics. Escalate to user if the conflict is a genuine trade-off.

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
3. If snapshot requested, verify integrity match
4. Report to user: what compiled, how long, any warnings
5. If build failed: read error output, diagnose, suggest fix

## Phase 5 — Persist

After the harness is created or updated:

### Save to memory
Create/update a reference memory file with:
- Script path
- Usage examples for common operations
- Workspace/worktree shortcuts
- Target shortcuts
- Known pitfalls and their mitigations
- Platform and shell the script was written for

### Update MEMORY.md index
Add a one-line pointer to the memory file.

### Keep the script updated
When the build environment changes (new worktree, new toolchain, new preferences), update the script in place and update the memory file. The script is a living document.

## Phase 6 — Interview (first time only)

After the first successful build with the harness, ask the user:

> The harness is working. A few questions to make it better:
> 1. Want notification on build completion? (sound, desktop toast, terminal bell)
> 2. Want automatic `git stash` before clean builds?
> 3. Want build timing history logged to a file?
> 4. Want the script to auto-detect which target to build based on changed files? (Note: this requires encoding the dependency graph for multi-layer builds — simple for single-target projects, complex for projects with lib→dll→app chains.)
> 5. Anything else that would make builds less annoying?

Save responses as feedback memories.

## Model Tier Allocation

| Activity | Tier | Why |
|----------|------|-----|
| Workspace scan | Haiku | Fast, mechanical file discovery |
| Script generation | Sonnet | Needs build system and platform knowledge |
| Build system review | Sonnet | Platform-specific expertise |
| Security review | Sonnet | Robustness analysis |
| Adversarial / error-mode testing | Sonnet | Shell error handling requires depth, not speed |
| Build execution | Direct (no agent) | Just a bash command |
| Error diagnosis | Sonnet | Needs build system context |
| Architecture review | Opus | Only if the build system is complex or unusual |

## Post-Compaction Recovery

The entire point of the memory system is that after compaction, the next session can:

1. Read MEMORY.md → find "Build harness" entry
2. Read the memory file → get script path and usage
3. Run the script directly

No rediscovery needed. No reinventing the wheel. The script and the memory are the continuity mechanism.

If the memory says the script exists but it doesn't (deleted, moved), fall back to Phase 1 and rebuild it. Update the memory when done.
