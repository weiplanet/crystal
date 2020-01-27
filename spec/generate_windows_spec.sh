#! /usr/bin/env bash
set +x

# This script iterates through each spec file and tries to cross compiler and
# run it on win32 platform.
#
# * `failed codegen` annotates specs that error in the compiler.
#   This is mostly caused by some API not being ported to win32 (either the spec
#   target itself or some tools used by the spec).
# * `failed linking` annotats specs that compile but don't link (at least not on
#   basis of the libraries from *Porting to Windows* guide).
#   Most failers are caused by missing libraries (libxml2, libyaml, libgmp,
#   libllvm, libz, libssl), but there also seem to be some incompatibilities
#   with the existing libraries.
# * `failed to run` annotates specs that compile and link but don't properly
#   execute.
#
# PREREQUISITES:
#
# This script requires a working win32 build environment as described in
# the [*Porting to Windows* guide]()https://github.com/crystal-lang/crystal/wiki/Porting-to-Windows
#
# * LINKER points to a program that executes the linker command on win32 platform
# but does not run the compiled binary.
# * RUNNER points to a program that executes the compiled binary on win32 platform.
# When running on WSL, this can just be a shell because WSL can run win32
# binaries directly. When using a remote win32 environment, the program needs to
# make sure it reuses the previously compiled program.
#
# The defaults for both tools work on WSL, the linker only requires
# MSVC_BUILD_TOOLS to be set appropriately.
#
# USAGE:
#
# For std spec:
# $ spec/generate_windows_spec.cr > spec/win32_std_spec.cr
# For compiler spec:
# $ spec/generate_windows_spec.cr compiler > spec/win32_compiler_spec.cr

SPEC_SUITE=${1:-std}
LINKER=${LINKER:-crystal-windows-wsl}
RUNNER=${RUNNER:-/bin/sh -c}

function crystal-windows-wsl {
  cmd.exe /S /c "${MSVC_BUILD_TOOLS} amd64 && cd /D %CD% && ${*//\"/} user32.lib"
  return $?
}

if [ "$LINKER" == "crystal-windows-wsl" ] && [ -z "$MSVC_BUILD_TOOLS" ]; then
  echo "Missing environemnt variable MSVC_BUILD_TOOLS" >&2
  exit 1
fi

if [ -f "bin/crystal" ]; then
  CRYSTAL_BIN=${CRYSTAL_BIN:-bin/crystal}
else
  CRYSTAL_BIN=${CRYSTAL_BIN:-crystal}
fi

command="$0 $*"
echo "# This file is autogenerated by \`${command% }\`"
echo "# $(date --rfc-3339 seconds)"
echo

for spec in $(find "spec/$SPEC_SUITE" -type f -iname "*_spec.cr" | sort); do
  require="require \"./${spec##spec/}\""

  if ! linker_command=$($CRYSTAL_BIN build --cross-compile --target x86_64--windows-msvc "$spec" 2>/dev/null); then
    echo "# $require (failed codegen)"
    continue
  fi

  if ! $LINKER "$linker_command" >/dev/null 2>/dev/null; then
    echo "# $require (failed linking)"
    continue
  fi

  binary_path="./$(echo "$linker_command" | grep -oP '(?<="/Fe)(.*)(?=")').exe"

  $RUNNER "$binary_path" > /dev/null; exit=$?

  if [ $exit -eq 0 ] || [ $exit -eq 1 ]; then
    echo "$require"
  else
    echo "# $require (failed to run)"
  fi
done