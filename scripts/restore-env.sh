#!/usr/bin/env bash
# ==============================================================================
# scripts/restore-env.sh — idempotent NeoOS sandbox environment restore.
# ------------------------------------------------------------------------------
# The sandbox resets without warning: it deletes /home/user/neo-os (which lives
# OUTSIDE the persistent /home/user/project tree) and wipes the cross toolchain.
# This script rebuilds the environment in one shot and is safe to run any number
# of times:
#   1. installs the AArch64 cross toolchain + QEMU + FAT tools (only if missing);
#   2. puts mkfs.vfat on PATH (the Makefile needs it);
#   3. clones /home/user/neo-os from the delivery bundle if the repo is gone;
#   4. verifies the bundle and reports HEAD (warns if it differs from the expected
#      revision passed in $NEO_EXPECTED_HEAD);
#   5. re-applies the sandbox hygiene guards (swap + oom protection) if present;
#   6. builds (`make all`).
#
# Usage:
#   bash scripts/restore-env.sh
#   NEO_EXPECTED_HEAD=<sha> bash scripts/restore-env.sh
# ==============================================================================
set -u

ROOT="${NEO_REPO:-/home/user/neo-os}"
BUNDLE="${NEO_BUNDLE:-/home/user/project/neo-os.bundle}"
HYGIENE="${NEO_HYGIENE:-/home/user/project/scripts/sandbox-hygiene.sh}"
PKGS="gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu dosfstools mtools qemu-system-arm qemu-efi-aarch64 python3-pil"

SUDO=""
if [ "$(id -u)" != "0" ]; then SUDO="sudo"; fi

echo "== restore-env: checking toolchain =="
need=0
for t in aarch64-linux-gnu-gcc aarch64-linux-gnu-ld aarch64-linux-gnu-as \
         aarch64-linux-gnu-objcopy qemu-system-aarch64 mcopy mmd dd; do
  command -v "$t" >/dev/null 2>&1 || { echo "   missing: $t"; need=1; }
done
python3 -c "import PIL" >/dev/null 2>&1 || { echo "   missing: python3-PIL"; need=1; }
if [ "$need" = 1 ]; then
  echo "   installing: $PKGS"
  $SUDO apt-get update -qq || true
  $SUDO apt-get install -y $PKGS || { echo "FATAL: apt-get failed"; exit 1; }
else
  echo "   toolchain present"
fi

# The Makefile locates mkfs.vfat/mkfs.fat; make sure one is on PATH.
if [ ! -e /usr/local/bin/mkfs.vfat ] && [ ! -e /usr/local/bin/mkfs.fat ]; then
  vfat="$(command -v mkfs.vfat 2>/dev/null || command -v mkfs.fat 2>/dev/null || true)"
  [ -z "$vfat" ] && [ -x /sbin/mkfs.vfat ] && vfat=/sbin/mkfs.vfat
  [ -z "$vfat" ] && [ -x /usr/sbin/mkfs.vfat ] && vfat=/usr/sbin/mkfs.vfat
  if [ -n "$vfat" ]; then
    $SUDO ln -sf "$vfat" /usr/local/bin/mkfs.vfat
    echo "   linked mkfs.vfat -> $vfat"
  fi
fi

echo "== restore-env: checking repository =="
if [ ! -d "$ROOT/.git" ]; then
  if [ ! -f "$BUNDLE" ]; then
    echo "FATAL: $ROOT is missing and no bundle at $BUNDLE"
    exit 1
  fi
  echo "   repo missing — cloning from bundle"
  git clone -b main "$BUNDLE" "$ROOT" || { echo "FATAL: clone failed"; exit 1; }
else
  echo "   repo present at $ROOT"
fi

cd "$ROOT" || exit 1
if [ -f "$BUNDLE" ]; then
  if git bundle verify "$BUNDLE" >/dev/null 2>&1; then
    echo "   bundle verify: OK"
  else
    echo "   WARN: bundle verify failed ($BUNDLE)"
  fi
fi

HEAD_SHA="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
echo "   HEAD: $HEAD_SHA"
if [ -n "${NEO_EXPECTED_HEAD:-}" ] && [ "$HEAD_SHA" != "$NEO_EXPECTED_HEAD" ]; then
  echo "   WARN: HEAD != expected $NEO_EXPECTED_HEAD"
fi

if [ -f "$HYGIENE" ]; then
  echo "== restore-env: sandbox hygiene =="
  bash "$HYGIENE" 2>&1 | tail -4 || true
fi

echo "== restore-env: build =="
make all || { echo "FATAL: build failed"; exit 1; }

echo "restore-env: OK ($(git rev-parse --short HEAD))"
