#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_REL="${1:-CallbackTest.dpr}"
PROJECT_REL="${PROJECT_REL#./}"
PROJECT_PATH="$ROOT/$PROJECT_REL"
PROJECT_DIR="$(dirname "$PROJECT_PATH")"
PROJECT_FILE="$(basename "$PROJECT_PATH")"
PROJECT_NAME="$(basename "${PROJECT_REL%.dpr}")"
PLATFORM="${2:-${DELPHI_PLATFORM:-Win64}}"
PROJECT_DIR_WIN="$(wslpath -w "$PROJECT_DIR")"
CUSTOM_DEFINES="${DELPHI_DEFINES:-}"

BDS_VERSION="${BDS_VERSION:-23.0}"
SOURCE_DIR_WIN="$(wslpath -w "$ROOT/Source")"
HEADER_DIR_WIN="$(wslpath -w "$ROOT/Headers")"
SDL3_DIR_WIN="$(wslpath -w "$ROOT/SDL3/units")"
WINMD_API_DIR="${WINMD_API_DIR:-}"
MFPACK_DIR="${MFPACK_DIR:-}"
MFPACK_SRC_DIR=""
BIN_ROOT="$ROOT/Bin"
BUILD_DIR="$BIN_ROOT/$PLATFORM"
RUNTIME_ROOT="$ROOT/Runtime"

case "$PLATFORM" in
  Win32|win32)
    PLATFORM="Win32"
    PLATFORM_DIR="win32"
    DCC="${DCC32:-/mnt/c/Program Files (x86)/Embarcadero/Studio/${BDS_VERSION}/bin/dcc32.exe}"
    DELPHI_LIB="${DELPHI_LIB_WIN32:-c:\\program files (x86)\\embarcadero\\studio\\${BDS_VERSION}\\lib\\win32\\release}"
    ;;
  Win64|win64)
    PLATFORM="Win64"
    PLATFORM_DIR="win64"
    DCC="${DCC64:-/mnt/c/Program Files (x86)/Embarcadero/Studio/${BDS_VERSION}/bin/dcc64.exe}"
    DELPHI_LIB="${DELPHI_LIB_WIN64:-c:\\program files (x86)\\embarcadero\\studio\\${BDS_VERSION}\\lib\\win64\\release}"
    ;;
  *)
    printf 'Unsupported Delphi platform: %s\n' "$PLATFORM" >&2
    printf 'Use Win32 or Win64.\n' >&2
    exit 1
    ;;
esac

BUILD_DIR="$BIN_ROOT/$PLATFORM_DIR"
BUILD_DIR_WIN="${BUILD_DIR_WIN:-$(wslpath -w "$BUILD_DIR")}"
DEFINE_SET="PLATFORM_${PLATFORM}"

if [[ -n "$CUSTOM_DEFINES" ]]; then
  DEFINE_SET="${DEFINE_SET};${CUSTOM_DEFINES}"
fi

SEARCH_PATH_WIN="${PROJECT_DIR_WIN};${SOURCE_DIR_WIN};${HEADER_DIR_WIN};${SDL3_DIR_WIN};${DELPHI_LIB}"
INCLUDE_PATH_WIN="${PROJECT_DIR_WIN};${SOURCE_DIR_WIN};${HEADER_DIR_WIN};${SDL3_DIR_WIN}"

if [[ -z "$MFPACK_DIR" ]]; then
  if [[ -d "$ROOT/../MfPack/src" ]]; then
    MFPACK_DIR="$ROOT/../MfPack"
  elif [[ -d "$ROOT/../MfPack/MfPack/src" ]]; then
    MFPACK_DIR="$ROOT/../MfPack"
  fi
fi

if [[ -d "$MFPACK_DIR/src" ]]; then
  MFPACK_SRC_DIR="$MFPACK_DIR/src"
elif [[ -d "$MFPACK_DIR/MfPack/src" ]]; then
  MFPACK_SRC_DIR="$MFPACK_DIR/MfPack/src"
fi

if [[ -n "$MFPACK_SRC_DIR" ]]; then
  MFPACK_SRC_DIR_WIN="$(wslpath -w "$MFPACK_SRC_DIR")"
  SEARCH_PATH_WIN="${SEARCH_PATH_WIN};${MFPACK_SRC_DIR_WIN}"
  INCLUDE_PATH_WIN="${INCLUDE_PATH_WIN};${MFPACK_SRC_DIR_WIN}"
fi

if [[ -n "$WINMD_API_DIR" ]] && [[ -d "$WINMD_API_DIR" ]]; then
  WINMD_API_DIR_WIN="$(wslpath -w "$WINMD_API_DIR")"
  SEARCH_PATH_WIN="${SEARCH_PATH_WIN};${WINMD_API_DIR_WIN}"
  INCLUDE_PATH_WIN="${INCLUDE_PATH_WIN};${WINMD_API_DIR_WIN}"
fi

if [[ ! -f "$PROJECT_PATH" ]]; then
  printf 'Project not found: %s\n' "$PROJECT_REL" >&2
  exit 1
fi

if [[ ! -x "$DCC" ]]; then
  printf 'Compiler not found: %s\n' "$DCC" >&2
  printf 'Set DCC32/DCC64 or BDS_VERSION to match your local Delphi installation.\n' >&2
  exit 1
fi

mkdir -p "$BUILD_DIR"

cd "$PROJECT_DIR"
"$DCC" \
  -B \
  -U"$SEARCH_PATH_WIN" \
  -I"$INCLUDE_PATH_WIN" \
  -N0"$BUILD_DIR_WIN" \
  -NU"$BUILD_DIR_WIN" \
  -D"$DEFINE_SET" \
  -E"$BUILD_DIR_WIN" \
  "$PROJECT_FILE"

printf 'Built %s for %s in %s\n' "$PROJECT_NAME" "$PLATFORM" "$BUILD_DIR"
