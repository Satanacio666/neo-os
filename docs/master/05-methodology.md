# 05 — Methodology: test manually, always; debug via UART + QEMU protocols

**Rule:** no change is "done" until it passes `scripts/golden-boot.sh` **and** a manual UART/QEMU check of the new behavior. Never trust a build alone.

## The golden gate (run after every change)
```
scripts/golden-boot.sh
```
Rebuilds → boots the VM → asserts: shell active, all 32 subsystems, **0 exceptions**, **0 undefined identifiers** → runs the JIT battery → screenshots. Prints `GOLDEN BOOT: PASS|FAIL`.

## Control plane — UART (PL011 chardev socket)
- Guest UART output is teed to `/tmp/neo-os-serial.log`; input is a unix socket `/tmp/neo-os-uart-in.sock`.
- `scripts/uart-repl.py "cmd1" "cmd2"` sends lines and prints the resulting serial output.
- `scripts/run-jit-golden.py` runs `tests/jit_golden/cases.json` and diffs results.

## QEMU protocols for debugging
- **Monitor** (`-monitor unix:/tmp/neo-os-mon.sock`): `screendump` (visual truth), `sendkey` (drive input), `info registers`, `xp /Ni ADDR` (disassemble guest memory at a fault address), `info mtree`, `stop`/`cont`.
- **VNC + the `/neo-os` viewer**: live interactive view; click to capture keyboard; the UART panel tails/sends serial.
- **gdbstub** (`-s -S`): breakpoints/stepping when UART isn't enough.
- **Crash triage recipe:** read `ELR_EL1` from the guest's exception dump → map it to a function via the compile map (`Compiled function 'X' at 0xADDR (N instrs)`) → `xp /Ni` around it to see the exact faulting instruction.

## VM runner
```
scripts/run-viewer-vm.sh start|stop|restart|status
```
QEMU: `-M virt,gic-version=2 -cpu cortex-a72 -smp 4 -m 1024 -bios QEMU_EFI.fd -device ramfb -device virtio-gpu-device ... -vnc 127.0.0.1:0 -monitor unix:… -serial chardev:uart0`.

## Golden JIT battery
`tests/jit_golden/cases.json` — cases run over UART; the last command's `--> … (0xHEX)` is compared to `expect`. Add a case for every new capability. Current: **50 cases**.

## Symbol audit
`scripts/audit-symbols.sh` — static literal-zero emission sites + runtime undefined/late-bound report. Boot also prints `[SYMBOLS] …` (unresolved forward references).

## Persistence discipline (learned the hard way)
- Work inside the persisted workspace or **commit + bundle** after every green step:
  `git -C neo-os add -A && git commit -m "…" && git -C neo-os bundle create /home/user/project/neo-os.bundle --all`
- Never rely on `/tmp` or paths outside the project for anything that must survive.
