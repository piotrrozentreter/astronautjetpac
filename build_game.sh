#!/usr/bin/env bash
# build_game.sh
# Generic build helper for HAS game projects:
#   .has -> .s (hasc) -> .o (vasm) -> .exe (vlink)
#
# Usage:
#   ./build_game.sh [--cpu 68000|68020] <game_source.has|all> [output_name]
#
# Examples:
#   ./build_game.sh jetpac.has
#   ./build_game.sh --cpu 68020 jetpac.has
#   ./build_game.sh path/to/game.has custom_name
#   ./build_game.sh all
#
# Environment overrides:
#   HASC_CPU=68000|68020               CPU target (default: 68000, --cpu wins)
#   HASC_PYTHON=/path/to/python        Python used for hasc (default: auto)
#   HASC_ROOT=/path/to/highamigaassembler
#                                    Fallback compiler checkout used when
#                                    hasc is not installed in HASC_PYTHON.
#                                    Also used as lib source if project lib/
#                                    is missing.
#   VASM=/path/to/vasmm68k_mot         Assembler (default: auto)
#   VLINK=/path/to/vlink               Linker (default: vlink)
#   DISABLE_640x256=1                  Omit hires 640x256 screen buffers
#   DISABLE_HAM=1                      Omit HAM6 screen buffers
#
# Notes:
# - Source path can be relative to current directory, script directory, or root.
# - If script is in scripts/, root is parent directory; otherwise root is script dir.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Support both layouts:
# 1) project/scripts/build_game.sh  -> ROOT=project
# 2) project/build_game.sh          -> ROOT=project
if [[ "$(basename "$SCRIPT_DIR")" == "scripts" && -d "$SCRIPT_DIR/../lib" ]]; then
    ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
else
    ROOT="$SCRIPT_DIR"
fi

# Detect HAS (High Amiga Assembler) root directory.
# To use your own path, either:
#   1. Set the HASC_ROOT environment variable, or
#   2. Update the candidate paths below to include your installation
HASC_ROOT_DETECTED="${HASC_ROOT:-}"
if [[ -z "$HASC_ROOT_DETECTED" ]]; then
    for candidate in \
        "$ROOT/../highamigaassembler" \
        "$SCRIPT_DIR/../highamigaassembler" \
        "/run/media/piotr/BACKUP/Rozen/Projects/highamigaassembler"
    do
        if [[ -d "$candidate/hasc" ]]; then
            HASC_ROOT_DETECTED="$candidate"
            break
        fi
    done
fi

BUILD="$ROOT/build"
LIB_DIR="$ROOT/lib"
if [[ ! -d "$LIB_DIR" && -n "$HASC_ROOT_DETECTED" && -d "$HASC_ROOT_DETECTED/lib" ]]; then
    LIB_DIR="$HASC_ROOT_DETECTED/lib"
fi

usage() {
    cat <<'EOF'
Usage: ./build_game.sh [--cpu 68000|68020] <game_source.has|all> [output_name]

Examples:
    ./build_game.sh jetpac.has
    ./build_game.sh --cpu 68020 jetpac.has
    ./build_game.sh path/to/game.has custom_name
    ./build_game.sh all
EOF
}

CPU="${HASC_CPU:-68000}"
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --cpu)
            [[ $# -ge 2 ]] || { echo "ERROR: --cpu requires a value" >&2; exit 2; }
            CPU="$2"
            shift 2
            ;;
        --cpu=*)
            CPU="${1#*=}"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done
set -- ${POSITIONAL[@]+"${POSITIONAL[@]}"}

case "$CPU" in
    68000|68020) ;;
    *)
        echo "ERROR: unsupported CPU target '$CPU' (expected 68000 or 68020)" >&2
        exit 2
        ;;
esac

if [[ $# -lt 1 || $# -gt 2 ]]; then
    usage
    exit 2
fi

INPUT="$1"
OUT_NAME="${2:-}"

if [[ "$INPUT" == "all" ]]; then
    for module in jetpac.has frontpage.has; do
        echo "=== Building module: $module ==="
        "$0" --cpu "$CPU" "$module"
    done
    echo "All modules built successfully."
    exit 0
fi

if [[ -f "$INPUT" ]]; then
    SRC="$(cd "$(dirname "$INPUT")" && pwd)/$(basename "$INPUT")"
elif [[ -f "$SCRIPT_DIR/$INPUT" ]]; then
    SRC="$SCRIPT_DIR/$INPUT"
elif [[ -f "$ROOT/$INPUT" ]]; then
    SRC="$ROOT/$INPUT"
else
    echo "ERROR: .has source not found: $INPUT" >&2
    exit 1
fi

case "$SRC" in
    *.has) ;;
    *)
        echo "ERROR: source must be a .has file: $SRC" >&2
        exit 1
        ;;
esac

if [[ -x "$ROOT/.venv/bin/python" ]]; then
    PYTHON="${HASC_PYTHON:-$ROOT/.venv/bin/python}"
elif [[ -x "$ROOT/venv/bin/python" ]]; then
    PYTHON="${HASC_PYTHON:-$ROOT/venv/bin/python}"
elif command -v python3 &>/dev/null; then
    PYTHON="${HASC_PYTHON:-python3}"
else
    PYTHON="${HASC_PYTHON:-python}"
fi

VASM="${VASM:-vasmm68k_mot}"
if ! command -v "$VASM" &>/dev/null; then
    BUNDLED="$HOME/.vscode/extensions/prb28.amiga-assembly-1.8.13/resources/bin/linux/vasmm68k_mot"
    if [[ -x "$BUNDLED" ]]; then
        VASM="$BUNDLED"
    elif command -v vasm68000_mot &>/dev/null; then
        VASM="vasm68000_mot"
    else
        echo "ERROR: assembler not found. Set VASM=/path/to/vasmm68k_mot." >&2
        exit 1
    fi
fi

VLINK="${VLINK:-vlink}"
if ! command -v "$VLINK" &>/dev/null; then
    echo "ERROR: vlink not found. Set VLINK=/path/to/vlink." >&2
    exit 1
fi

# --- vbccm68k (C compiler for 68000) ----------------------------------------
# Resolve: VBCC_CC env > vbccm68k next to the assembler binary > PATH search.
VBCC_CC_BIN="${VBCC_CC:-}"
if [[ -z "$VBCC_CC_BIN" ]]; then
    VASM_PATH="$(command -v "$VASM" 2>/dev/null || true)"
    if [[ -n "$VASM_PATH" ]]; then
        VASM_DIR="$(dirname "$VASM_PATH")"
        for _cand in "$VASM_DIR/vbccm68k" "$VASM_DIR/vbccm68k.exe"; do
            if [[ -x "$_cand" ]]; then VBCC_CC_BIN="$_cand"; break; fi
        done
    fi
fi
if [[ -z "$VBCC_CC_BIN" ]]; then
    for _cand in vbccm68k vbccm68k.exe; do
        if command -v "$_cand" &>/dev/null; then VBCC_CC_BIN="$(command -v "$_cand")"; break; fi
    done
fi
if [[ -z "$VBCC_CC_BIN" ]]; then
    echo "ERROR: vbccm68k not found. Set VBCC_CC=/path/to/vbccm68k." >&2
    exit 1
fi

# Resolve vbcc include path: <vbcc_root>/targets/m68k-amigaos/include
# VBCC_ROOT env override, or auto-detected from compiler binary location.
VBCC_INCLUDE="${VBCC_ROOT:+$VBCC_ROOT/targets/m68k-amigaos/include}"
if [[ -z "$VBCC_INCLUDE" ]]; then
    _VBCC_BIN_DIR="$(dirname "$(realpath "$VBCC_CC_BIN" 2>/dev/null || echo "$VBCC_CC_BIN")")"
    _VBCC_ROOT_CAND="$(dirname "$_VBCC_BIN_DIR")"
    if [[ -d "$_VBCC_ROOT_CAND/targets/m68k-amigaos/include" ]]; then
        VBCC_INCLUDE="$_VBCC_ROOT_CAND/targets/m68k-amigaos/include"
    fi
fi
if [[ -z "$VBCC_INCLUDE" || ! -d "$VBCC_INCLUDE" ]]; then
    echo "WARNING: vbcc include directory not found; compiling without -I flag." >&2
    VBCC_INCLUDE=""
fi

mkdir -p "$BUILD"

BASE_NAME="$(basename "${SRC%.has}")"
TARGET_NAME="${OUT_NAME:-$BASE_NAME}"

OUT_S="$BUILD/$TARGET_NAME.s"
OUT_O="$BUILD/$TARGET_NAME.o"
OUT_EXE="$BUILD/$TARGET_NAME.exe"

# Candidate engine libraries used by game examples.
LIB_SOURCES=(
    "$LIB_DIR/gui.s"
    "$LIB_DIR/gui_keyboard.s"
    "$LIB_DIR/graphics.s"
    "$LIB_DIR/font8x8.s"
    "$LIB_DIR/helpers.s"
    "$LIB_DIR/takeover.s"
    "$LIB_DIR/wbstartup.s"
    "$LIB_DIR/input.s"
    "$LIB_DIR/keyboard.s"
    "$LIB_DIR/sprite.s"
    "$LIB_DIR/str.s"
    "$LIB_DIR/heap.s"
    "$LIB_DIR/math.s"
    "$LIB_DIR/bob.s"
    "$LIB_DIR/fileio.s"
    "$LIB_DIR/ptplayer.s"
    "$LIB_DIR/debug.s"
)

declare -A SYM_TO_LIB=()
for lib in "${LIB_SOURCES[@]}"; do
    [[ -f "$lib" ]] || continue
    while IFS= read -r sym; do
        [[ -z "$sym" ]] && continue
        [[ "$sym" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
        if [[ -z "${SYM_TO_LIB[$sym]:-}" ]]; then
            SYM_TO_LIB["$sym"]="$lib"
        fi
    done < <(
        grep -Eio '^[[:space:]]*xdef[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$lib" \
            | sed -E 's/^[[:space:]]*[xX][dD][eE][fF][[:space:]]+//' \
            | /usr/bin/sort -u
    )
done

mapfile -t EXTERN_SYMBOLS < <(
    grep -Eio '^[[:space:]]*extern[[:space:]]+(func|var)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$SRC" \
        | sed -E 's/^[[:space:]]*[eE][xX][tT][eE][rR][nN][[:space:]]+([fF][uU][nN][cC]|[vV][aA][rR])[[:space:]]+//' \
        | /usr/bin/sort -u
)

DEBUG_EXTERN_USED=0
for sym in "${EXTERN_SYMBOLS[@]}"; do
    case "$sym" in
        Debug*) DEBUG_EXTERN_USED=1; break ;;
    esac
done
if [[ $DEBUG_EXTERN_USED -eq 1 && ! -f "$LIB_DIR/debug.s" ]]; then
    echo "ERROR: $SRC declares Debug* externs, but required library '$LIB_DIR/debug.s' is missing." >&2
    echo "Install/update highamigaassembler libs to include debug.s, or remove Debug* extern usage from source." >&2
    exit 1
fi

declare -A WANT_LIB=()
for sym in "${EXTERN_SYMBOLS[@]}"; do
    lib="${SYM_TO_LIB[$sym]:-}"
    if [[ -n "$lib" ]]; then
        WANT_LIB["$lib"]=1
    fi
done

# Fallback: detect direct symbol mentions in source (e.g. inline asm jsr Name)
# even when there is no explicit `extern` declaration.
for sym in "${!SYM_TO_LIB[@]}"; do
    if grep -Eq "(^|[^A-Za-z0-9_])${sym}([^A-Za-z0-9_]|$)" "$SRC"; then
        WANT_LIB["${SYM_TO_LIB[$sym]}"]=1
    fi
done

# Lightweight dependency closure for frequent cross-library links.
changed=1
while [[ $changed -eq 1 ]]; do
    changed=0
    for lib in "${!WANT_LIB[@]}"; do
        case "$(basename "$lib")" in
            gui.s)
                for dep in "$LIB_DIR/gui_keyboard.s" "$LIB_DIR/graphics.s" "$LIB_DIR/input.s"; do
                    if [[ -z "${WANT_LIB[$dep]:-}" ]]; then WANT_LIB["$dep"]=1; changed=1; fi
                done
                ;;
            gui_keyboard.s)
                for dep in "$LIB_DIR/gui.s" "$LIB_DIR/keyboard.s"; do
                    if [[ -z "${WANT_LIB[$dep]:-}" ]]; then WANT_LIB["$dep"]=1; changed=1; fi
                done
                ;;
            graphics.s)
                for dep in "$LIB_DIR/helpers.s" "$LIB_DIR/sprite.s" "$LIB_DIR/takeover.s"; do
                    if [[ -z "${WANT_LIB[$dep]:-}" ]]; then WANT_LIB["$dep"]=1; changed=1; fi
                done
                ;;
            input.s|heap.s|str.s)
                dep="$LIB_DIR/helpers.s"
                if [[ -z "${WANT_LIB[$dep]:-}" ]]; then WANT_LIB["$dep"]=1; changed=1; fi
                ;;
            bob.s)
                for dep in "$LIB_DIR/graphics.s" "$LIB_DIR/helpers.s"; do
                    if [[ -z "${WANT_LIB[$dep]:-}" ]]; then WANT_LIB["$dep"]=1; changed=1; fi
                done
                ;;
            ptplayer.s)
                dep="$LIB_DIR/takeover.s"
                if [[ -z "${WANT_LIB[$dep]:-}" ]]; then WANT_LIB["$dep"]=1; changed=1; fi
                ;;
        esac
    done
done

ORDERED_LIBS=(
    "$LIB_DIR/helpers.s"
    "$LIB_DIR/takeover.s"
    "$LIB_DIR/wbstartup.s"
    "$LIB_DIR/graphics.s"
    "$LIB_DIR/font8x8.s"
    "$LIB_DIR/input.s"
    "$LIB_DIR/keyboard.s"
    "$LIB_DIR/sprite.s"
    "$LIB_DIR/gui.s"
    "$LIB_DIR/gui_keyboard.s"
    "$LIB_DIR/str.s"
    "$LIB_DIR/heap.s"
    "$LIB_DIR/math.s"
    "$LIB_DIR/bob.s"
    "$LIB_DIR/fileio.s"
    "$LIB_DIR/debug.s"
    "$LIB_DIR/ptplayer.s"
)

SELECTED_LIBS=()
for lib in "${ORDERED_LIBS[@]}"; do
    if [[ -n "${WANT_LIB[$lib]:-}" ]]; then
        SELECTED_LIBS+=("$lib")
    fi
done

echo "=== Build: $SRC ==="
echo "  Root  : $ROOT"
echo "  CPU   : $CPU"
echo "  Python: $PYTHON"
echo "  VASM  : $VASM"
echo "  VLINK : $VLINK"
echo "  VBCC  : $VBCC_CC_BIN"
echo "  Out   : ${OUT_EXE#$ROOT/}"

if [[ ${#SELECTED_LIBS[@]} -eq 0 ]]; then
    echo "  Libs  : (none auto-detected from extern declarations)"
else
    echo "  Libs  :"
    for lib in "${SELECTED_LIBS[@]}"; do
        echo "    - ${lib#$ROOT/}"
    done
fi

echo "[1/3] HAS compile..."
SRC_DIR="$(dirname "$SRC")"
SRC_FILE="$(basename "$SRC")"

# Prefer installed hasc; fallback to a local compiler checkout.
HASC_PYTHONPATH=""
if ! "$PYTHON" -c 'import hasc.cli' &>/dev/null; then
    HASC_CANDIDATES=(
        "$HASC_ROOT_DETECTED"
        "$ROOT/../highamigaassembler"
        "$SCRIPT_DIR/../highamigaassembler"
        "/run/media/piotr/BACKUP/Rozen/Projects/highamigaassembler"
    )
    for candidate in "${HASC_CANDIDATES[@]}"; do
        [[ -n "$candidate" ]] || continue
        if [[ -d "$candidate/hasc" ]]; then
            HASC_PYTHONPATH="$candidate"
            break
        fi
    done

    if [[ -z "$HASC_PYTHONPATH" ]]; then
        echo "ERROR: Python module 'hasc' is not available for $PYTHON." >&2
        echo "Install it in the selected environment, set HASC_PYTHON, or set HASC_ROOT=/path/to/highamigaassembler." >&2
        exit 1
    fi
fi

    # Fail fast with a clear dependency hint before launching hasc proper.
    if [[ -n "$HASC_PYTHONPATH" ]]; then
        if ! PYTHONPATH="$HASC_PYTHONPATH${PYTHONPATH:+:$PYTHONPATH}" "$PYTHON" -c 'import lark' &>/dev/null; then
            echo "ERROR: Missing Python dependency 'lark' for hasc ($PYTHON)." >&2
            if [[ -f "$ROOT/requirements-hasc.txt" ]]; then
                echo "Run: $PYTHON -m pip install -r $ROOT/requirements-hasc.txt" >&2
            else
                echo "Run: $PYTHON -m pip install lark" >&2
            fi
            exit 1
        fi
    else
        if ! "$PYTHON" -c 'import lark' &>/dev/null; then
            echo "ERROR: Missing Python dependency 'lark' for hasc ($PYTHON)." >&2
            if [[ -f "$ROOT/requirements-hasc.txt" ]]; then
                echo "Run: $PYTHON -m pip install -r $ROOT/requirements-hasc.txt" >&2
            else
                echo "Run: $PYTHON -m pip install lark" >&2
            fi
            exit 1
        fi
    fi

if [[ -n "$HASC_PYTHONPATH" ]]; then
    (cd "$SRC_DIR" && PYTHONPATH="$HASC_PYTHONPATH${PYTHONPATH:+:$PYTHONPATH}" "$PYTHON" -m hasc.cli "$SRC_FILE" --cpu "$CPU" -o "$OUT_S")
else
    (cd "$SRC_DIR" && "$PYTHON" -m hasc.cli "$SRC_FILE" --cpu "$CPU" -o "$OUT_S")
fi

echo "[2/3] Assemble objects..."
# PETSCII/screen-code space mapping: source char code vs. font glyph index used for it.
GFX_SPACE_CODE="${GFX_SPACE_CODE:-32}"
# font8x8.s glyph 0 (index = char - 32) is already blank, so space must map there.
GFX_SPACE_GLYPH="${GFX_SPACE_GLYPH:-0}"
DISABLE_640x256="${DISABLE_640x256:-0}"
DISABLE_HAM="${DISABLE_HAM:-0}"
HEAP_MEMORY="0"
case "$BASE_NAME" in
    jetpac)
        DISABLE_640x256=1
        DISABLE_HAM=1
        HEAP_MEMORY=141308
        ;;
    frontpage)
        DISABLE_640x256=1
        DISABLE_HAM=0
        ;;
esac
VASM_FLAGS=("-m$CPU" -quiet -Fhunk -kick1hunks -I "$LIB_DIR")
VASM_FLAGS+=( -D "GFX_SPACE_CODE=${GFX_SPACE_CODE}" )
VASM_FLAGS+=( -D "GFX_SPACE_GLYPH=${GFX_SPACE_GLYPH}" )
if [[ "$DISABLE_640x256" == "1" ]]; then
    VASM_FLAGS+=( -D "DISABLE_640x256=1" )
fi
if [[ "$DISABLE_HAM" == "1" ]]; then
    VASM_FLAGS+=( -D "DISABLE_HAM=1" )
fi
if [[ "$HEAP_MEMORY" != "0" ]]; then
    VASM_FLAGS+=( -D "HEAP_MEMORY=${HEAP_MEMORY}" )
fi
"$VASM" "${VASM_FLAGS[@]}" "$OUT_S" -o "$OUT_O"

OBJECTS=("$OUT_O")
for lib in "${SELECTED_LIBS[@]}"; do
    obj="$BUILD/$(basename "${lib%.s}").o"
    "$VASM" "${VASM_FLAGS[@]}" "$lib" -o "$obj"
    OBJECTS+=("$obj")
done

# Assemble all .s files from assets folder
ASSETS_DIR="$ROOT/assets"
if [[ -d "$ASSETS_DIR" ]]; then
    while IFS= read -r asset_file; do
        obj="$BUILD/$(basename "${asset_file%.s}").o"
        "$VASM" "${VASM_FLAGS[@]}" "$asset_file" -o "$obj"
        OBJECTS+=("$obj")
    done < <(/usr/bin/find "$ASSETS_DIR" -maxdepth 1 -name "*.s" -type f | /usr/bin/sort)
fi

# --- Compile star.c with vbccm68k ------------------------------------------
STAR_C="$ROOT/star.c"
STAR_S="$BUILD/star_c.s"
STAR_O="$BUILD/star.o"
if [[ -f "$STAR_C" ]]; then
    echo "  C compile: star.c"
    VBCC_ARGS=("-cpu=$CPU" -quiet "-o=$STAR_S")
    [[ -n "$VBCC_INCLUDE" ]] && VBCC_ARGS+=("-I=$VBCC_INCLUDE")
    VBCC_ARGS+=("$STAR_C")
    "$VBCC_CC_BIN" "${VBCC_ARGS[@]}"
    # Assemble the generated source; -nowarn=62 suppresses vbcc mnemonics warnings.
    VBCC_VASM_FLAGS=("-m$CPU" -quiet -Fhunk -kick1hunks -nowarn=62 -I "$LIB_DIR")
    VBCC_VASM_FLAGS+=( -D "GFX_SPACE_CODE=${GFX_SPACE_CODE}" )
    VBCC_VASM_FLAGS+=( -D "GFX_SPACE_GLYPH=${GFX_SPACE_GLYPH}" )
    if [[ "$DISABLE_640x256" == "1" ]]; then
        VBCC_VASM_FLAGS+=( -D "DISABLE_640x256=1" )
    fi
    if [[ "$DISABLE_HAM" == "1" ]]; then
        VBCC_VASM_FLAGS+=( -D "DISABLE_HAM=1" )
    fi
    if [[ "$HEAP_MEMORY" != "0" ]]; then
        VBCC_VASM_FLAGS+=( -D "HEAP_MEMORY=${HEAP_MEMORY}" )
    fi
    "$VASM" "${VBCC_VASM_FLAGS[@]}" "$STAR_S" -o "$STAR_O"
    OBJECTS+=("$STAR_O")
    echo "  star.o added to link"
else
    echo "WARNING: star.c not found at $STAR_C - skipping C star module" >&2
fi


echo "[3/3] Link..."
"$VLINK" -bamigahunk -Bstatic "${OBJECTS[@]}" -o "$OUT_EXE"

echo "Done: ${OUT_EXE#$ROOT/}"
