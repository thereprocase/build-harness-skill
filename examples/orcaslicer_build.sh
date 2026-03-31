#!/usr/bin/env bash
# build.sh — OrcaSlicer worktree build harness
#
# Usage:
#   ./build.sh [worktree] [target] [options]
#
# Worktrees (shortcuts):
#   v1       D:/ClauDe/orcaSlicer          (feature/concave-arrange)
#   v2       D:/ClauDe/orcaSlicer-v2       (feature/concave-arrange-v2)
#   snuggle  D:/ClauDe/orcaSlicer-snuggle  (feature/snuggle-radial)
#
# Targets:
#   lib      Build libslic3r only (fast incremental)
#   dll      Build OrcaSlicer DLL (lib + link)
#   gui      Build OrcaSlicer_app_gui (full app)
#   all      Build entire solution (default)
#
# Options:
#   --afk          Use all cores (no -m:4 limit)
#   --clean        Clean before building
#   --verbose      Use normal verbosity instead of minimal
#   --snapshot     Copy full Release dir to orcaPatch/builds/{hash}_{note}/
#   --note=TEXT    Descriptive note for snapshot folder (auto-generated if omitted)
#   --no-priority  Skip BelowNormal priority enforcement
#
# Examples:
#   ./build.sh snuggle lib                    # incremental libslic3r
#   ./build.sh snuggle dll --snapshot         # build DLL + snapshot
#   ./build.sh v1 all --afk                   # full build, all cores

set -euo pipefail

# ── MSBuild location ────────────────────────────────────────
MSBUILD=""

# Try vswhere first (most reliable)
VSWHERE="/c/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe"
if [[ -f "$VSWHERE" ]]; then
    VS_PATH=$("$VSWHERE" -latest -property installationPath 2>/dev/null || true)
    if [[ -n "$VS_PATH" ]]; then
        # Convert backslashes to forward slashes for bash
        VS_PATH=$(echo "$VS_PATH" | sed 's|\\|/|g' | sed 's|^\([A-Z]\):|/\L\1|')
        candidate="$VS_PATH/MSBuild/Current/Bin/MSBuild.exe"
        if [[ -f "$candidate" ]]; then
            MSBUILD="$candidate"
        fi
    fi
fi

# Fallback: check known paths
if [[ -z "$MSBUILD" ]]; then
    for base in "/c/Program Files (x86)/Microsoft Visual Studio/2022" "/c/Program Files/Microsoft Visual Studio/2022"; do
        for edition in BuildTools Community Professional Enterprise; do
            candidate="$base/$edition/MSBuild/Current/Bin/MSBuild.exe"
            if [[ -f "$candidate" ]]; then
                MSBUILD="$candidate"
                break 2
            fi
        done
    done
fi

if [[ -z "$MSBUILD" ]]; then
    echo "ERROR: MSBuild.exe not found. Install VS2022 Build Tools." >&2
    echo "  Checked vswhere and standard VS2022 install paths." >&2
    exit 1
fi

echo "MSBuild: $MSBUILD"

# ── Parse worktree argument ─────────────────────────────────
WORKTREE_ARG="${1:-snuggle}"
shift 2>/dev/null || true

case "$WORKTREE_ARG" in
    v1|concave)       WORKTREE="/d/ClauDe/orcaSlicer" ;;
    v2|concave-v2)    WORKTREE="/d/ClauDe/orcaSlicer-v2" ;;
    snuggle|radial)   WORKTREE="/d/ClauDe/orcaSlicer-snuggle" ;;
    /*)               WORKTREE="$WORKTREE_ARG" ;;
    *)
        echo "ERROR: Unknown worktree '$WORKTREE_ARG'. Use: v1, v2, snuggle, or an absolute path." >&2
        exit 1
        ;;
esac

SLN="$WORKTREE/build/OrcaSlicer.sln"
if [[ ! -f "$SLN" ]]; then
    echo "ERROR: Solution not found at $SLN" >&2
    echo "  Run CMake first: cd $WORKTREE/build && cmake .." >&2
    exit 1
fi

echo "Worktree: $WORKTREE"
echo "Branch: $(cd "$WORKTREE" && git branch --show-current 2>/dev/null || echo 'unknown')"
echo "Solution: $SLN"

# ── Parse target argument ───────────────────────────────────
TARGET_ARG="${1:-all}"
shift 2>/dev/null || true

case "$TARGET_ARG" in
    lib)   MSBUILD_TARGET="libslic3r" ;;
    dll)   MSBUILD_TARGET="OrcaSlicer" ;;
    gui)   MSBUILD_TARGET="OrcaSlicer_app_gui" ;;
    all)   MSBUILD_TARGET="" ;;
    *)
        echo "ERROR: Unknown target '$TARGET_ARG'. Use: lib, dll, gui, all." >&2
        exit 1
        ;;
esac

# ── Parse options ────────────────────────────────────────────
# MSYS2 doesn't mangle -m:4 (no leading /), but be consistent
PARALLEL="-m:4"
DO_CLEAN=false
VERBOSITY="minimal"
SNAPSHOT=false
SNAP_NOTE=""
ENFORCE_PRIORITY=true

for opt in "$@"; do
    case "$opt" in
        --afk)          PARALLEL="-m" ;;
        --clean)        DO_CLEAN=true ;;
        --note=*)       SNAP_NOTE="${opt#--note=}" ;;
        --verbose)      VERBOSITY="normal" ;;
        --snapshot)     SNAPSHOT=true ;;
        --no-priority)  ENFORCE_PRIORITY=false ;;
        *)
            echo "WARNING: Unknown option '$opt', ignoring." >&2
            ;;
    esac
done

echo ""
echo "Target: ${MSBUILD_TARGET:-all}"
echo "Parallel: $PARALLEL"
echo "Clean: $DO_CLEAN"
echo "Priority: $([ "$ENFORCE_PRIORITY" = true ] && echo 'BelowNormal (enforced)' || echo 'Normal')"
echo ""

# ── Priority watchdog ────────────────────────────────────────
WATCHDOG_PID=""

cleanup_watchdog() {
    if [[ -n "$WATCHDOG_PID" ]]; then
        kill "$WATCHDOG_PID" 2>/dev/null || true
        wait "$WATCHDOG_PID" 2>/dev/null || true
        WATCHDOG_PID=""
    fi
}

trap cleanup_watchdog INT TERM EXIT

if [[ "$ENFORCE_PRIORITY" = true ]]; then
    (
        sleep 1
        while true; do
            # Verify PowerShell is functional before relying on it
            if ! powershell -Command "1" &>/dev/null; then
                echo "WARNING: PowerShell unavailable, priority watchdog disabled" >&2
                break
            fi
            powershell -Command "
                Get-Process -Name msbuild,cl,link -ErrorAction SilentlyContinue |
                Where-Object { \$_.PriorityClass -ne 'BelowNormal' } |
                ForEach-Object {
                    \$_.PriorityClass = 'BelowNormal'
                }
            " 2>/dev/null
            sleep 3
            # Exit when no build processes remain
            if ! powershell -Command "if (-not (Get-Process -Name msbuild -ErrorAction SilentlyContinue)) { exit 1 }" 2>/dev/null; then
                break
            fi
        done
    ) &
    WATCHDOG_PID=$!
    echo "Priority watchdog started (PID $WATCHDOG_PID)"
fi

# ── Clean phase (separate invocation if requested) ───────────
# NOTE: Use -flag syntax, not /flag. MSYS2/Git Bash converts /t: to a path.
# MSBuild accepts both - and / prefixes on Windows.
if [[ "$DO_CLEAN" = true ]]; then
    echo "Cleaning..."
    CLEAN_CMD=("$MSBUILD" "$SLN" -p:Configuration=Release -t:Clean "-v:$VERBOSITY" "$PARALLEL")
    "${CLEAN_CMD[@]}" 2>&1 || true
    echo "Clean complete."
    echo ""
fi

# ── Build phase ──────────────────────────────────────────────
CMD=("$MSBUILD" "$SLN" -p:Configuration=Release "$PARALLEL" "-v:$VERBOSITY")
if [[ -n "${MSBUILD_TARGET:-}" ]]; then
    CMD+=("-t:$MSBUILD_TARGET")
fi

echo "Command: ${CMD[*]}"

BUILD_START=$(date +%s)
echo "Build started at $(date)"
echo "───────────────────────────────────────────"

BUILD_EXIT=0
"${CMD[@]}" 2>&1 || BUILD_EXIT=$?

BUILD_END=$(date +%s)
BUILD_DURATION=$((BUILD_END - BUILD_START))
echo "───────────────────────────────────────────"
echo "Build finished in ${BUILD_DURATION}s (exit code $BUILD_EXIT)"

# ── Kill watchdog (also handled by trap, but be explicit) ────
cleanup_watchdog

# ── Check result ─────────────────────────────────────────────
if [[ $BUILD_EXIT -ne 0 ]]; then
    echo ""
    echo "BUILD FAILED (exit code $BUILD_EXIT)"
    exit $BUILD_EXIT
fi

DLL="$WORKTREE/build/src/Release/OrcaSlicer.dll"
LIB="$WORKTREE/build/src/libslic3r/Release/libslic3r.lib"

echo ""
if [[ -f "$DLL" ]]; then
    DLL_MTIME=$(stat -c %Y "$DLL" 2>/dev/null || echo 0)
    if [[ $DLL_MTIME -lt $BUILD_START ]]; then
        echo "WARNING: DLL was NOT updated by this build (timestamp predates build start)"
        echo "  The build may have been a no-op. Check that your source changes are saved."
    fi
    echo "DLL: $DLL"
    echo "  Size: $(stat -c %s "$DLL" 2>/dev/null || echo 'unknown') bytes"
    echo "  Modified: $(stat -c '%y' "$DLL" 2>/dev/null || echo 'unknown')"
    echo "  MD5: $(md5sum "$DLL" 2>/dev/null | cut -d' ' -f1 || echo 'unknown')"
fi
if [[ -f "$LIB" ]]; then
    LIB_MTIME=$(stat -c %Y "$LIB" 2>/dev/null || echo 0)
    if [[ $LIB_MTIME -lt $BUILD_START ]]; then
        echo "WARNING: libslic3r.lib was NOT updated (timestamp predates build start)"
    fi
    echo "LIB: $LIB"
    echo "  Modified: $(stat -c '%y' "$LIB" 2>/dev/null || echo 'unknown')"
fi

# ── Snapshot ─────────────────────────────────────────────────
# Copies the full Release directory (all DLLs + resources) into
# D:\ClauDe\orcaPatch\builds\{hash}_{note}
# matching the established snapshot structure.
if [[ "$SNAPSHOT" = true && -f "$DLL" ]]; then
    GIT_HASH=$(cd "$WORKTREE" && git rev-parse --short=10 HEAD 2>/dev/null || echo "unknown")

    if [[ -z "$SNAP_NOTE" ]]; then
        # Auto-generate note from last commit message (first word after type prefix)
        SNAP_NOTE=$(cd "$WORKTREE" && git log --format=%s -1 2>/dev/null \
            | sed 's/^[^:]*: //' | tr ' ' '_' | tr -cd 'a-zA-Z0-9_' | head -c 40 || echo "snapshot")
    fi

    SNAP_DIR="/d/ClauDe/orcaPatch/builds/${GIT_HASH}_${SNAP_NOTE}"
    RELEASE_DIR="$WORKTREE/build/src/Release"

    if [[ -d "$SNAP_DIR" ]]; then
        echo "WARNING: Snapshot directory already exists: $SNAP_DIR"
        echo "  Overwriting..."
        rm -rf "$SNAP_DIR"
    fi

    echo ""
    echo "Snapshotting Release directory..."
    cp -r "$RELEASE_DIR" "$SNAP_DIR"

    # Verify the key artifact
    SRC_MD5=$(md5sum "$DLL" | cut -d' ' -f1)
    DST_MD5=$(md5sum "$SNAP_DIR/OrcaSlicer.dll" | cut -d' ' -f1)
    FILE_COUNT=$(ls "$SNAP_DIR" | wc -l)
    SNAP_SIZE=$(du -sh "$SNAP_DIR" | cut -f1)

    if [[ "$SRC_MD5" = "$DST_MD5" ]]; then
        echo "Snapshot OK: $SNAP_DIR"
        echo "  Commit: $GIT_HASH ($(cd "$WORKTREE" && git log --oneline -1 2>/dev/null || echo 'unknown'))"
        echo "  Files: $FILE_COUNT ($SNAP_SIZE)"
        echo "  DLL MD5: $SRC_MD5"
    else
        echo ""
        echo "SNAPSHOT FAILED: DLL MD5 mismatch!"
        echo "  Source: $SRC_MD5"
        echo "  Dest:   $DST_MD5"
        exit 1
    fi
fi

echo ""
echo "Done."
