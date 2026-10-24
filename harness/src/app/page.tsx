import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import {
  Activity,
  ArrowRight,
  Cpu,
  Gamepad2,
  HardDriveDownload,
  Layers,
  MemoryStick,
  Terminal,
} from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Separator } from "@/components/ui/separator";
import { LiveStatus } from "@/components/neo-os/live-status";

export const metadata: Metadata = {
  description:
    "NeoOS is a TempleOS-inspired, Ring 0 single address space operating system for AArch64 that boots natively via UEFI — with a HolyC JIT, software 3D engine, and a live browser console.",
};

const FEATURES = [
  {
    icon: Cpu,
    title: "HolyC 2.0 JIT",
    body: "A from-scratch compiler emitting native AArch64 machine code — arithmetic, control flow, switch, closures — run straight from the shell.",
  },
  {
    icon: MemoryStick,
    title: "Zero-RAM rendering",
    body: "Renders directly into the GOP framebuffer, eliminating the 3.14 MB backbuffer and its per-frame memcpy.",
  },
  {
    icon: Activity,
    title: "4-core SMP",
    body: "Secondary cores brought up over ARM PSCI, with a cooperative and preemptive scheduler plus spin-lock safe shared state.",
  },
  {
    icon: Gamepad2,
    title: "Software 3D engine",
    body: "Matrix pipeline, near-plane clipping, a 16.16 fixed-point rasterizer, Z-buffer, and GLXGears-style gear demos.",
  },
  {
    icon: Layers,
    title: "DolDoc window manager",
    body: "Overlapping windows with per-window dirty-rect swapping, drag/resize, and a rich DolDoc terminal.",
  },
  {
    icon: HardDriveDownload,
    title: "RedSea filesystem",
    body: "A 64-bit contiguous block filesystem with a directory navigator, code editor, and in-guest writeback.",
  },
];

const SCREENSHOTS = [
  { src: "/neo-os/bench3d_fixed.png", alt: "NeoOS dual-viewport 3D cube benchmark", caption: "3D cubes — flat-shaded + Z-buffered" },
  { src: "/neo-os/glxgears_fixed.png", alt: "NeoOS GLXGears-style 3-gear demo", caption: "GLXGears — 3 meshing gears" },
  { src: "/neo-os/dual_cubes_benchmarks_live.png", alt: "NeoOS benchmarks side by side", caption: "Dual benchmarks side by side" },
  { src: "/neo-os/interactive_shell.png", alt: "NeoOS interactive shell", caption: "Interactive DolDoc shell" },
  { src: "/neo-os/menu_live.png", alt: "NeoOS boot menu", caption: "Boot menu" },
  { src: "/neo-os/sixteen_phase_scorecard_live.png", alt: "NeoOS benchmark scorecard", caption: "16-phase benchmark scorecard" },
];

const COMMANDS = [
  ["run <script>", "Compile and run a HolyC script from RedSea"],
  ["jittest", "Run HolyC JIT self-tests on live AArch64 code"],
  ["gears", "Launch the 3D GLXGears involute gear demo"],
  ["bench3d", "Dual-viewport rotating cube benchmark"],
  ["top / tasks", "Live CPU, memory and task monitor"],
  ["zeroram <on|off|status>", "Toggle direct-VRAM zero-copy mode"],
  ["filer", "Open the RedSea directory file manager"],
  ["reboot", "Reset the system via UEFI ResetSystem"],
];

export default function Home() {
  return (
    <div className="dark">
      <div className="min-h-screen bg-background text-foreground">
        <div className="mx-auto flex max-w-6xl flex-col gap-16 px-6 py-16 md:py-24">
          <header className="flex flex-col gap-8">
            <div className="flex flex-wrap items-center justify-between gap-4">
              <span className="font-mono text-sm font-medium tracking-tight text-primary">NeoOS</span>
              <div className="flex items-center gap-3">
                <LiveStatus />
                <Button asChild size="sm" variant="ghost">
                  <a href="https://github.com/Carlos-Pina/neo-os" target="_blank" rel="noopener noreferrer">
                    Source
                  </a>
                </Button>
              </div>
            </div>

            <div className="flex max-w-3xl flex-col gap-6">
              <Badge variant="outline" className="w-fit font-mono text-xs">
                Ring 0 SASOS · AArch64 · UEFI
              </Badge>
              <h1 className="text-4xl font-semibold tracking-tight text-balance md:text-6xl">
                A single address space operating system, from scratch.
              </h1>
              <p className="max-w-2xl text-lg leading-8 text-muted-foreground">
                NeoOS is a TempleOS-inspired, Ring 0 operating system for AArch64 that boots natively
                via UEFI. No Linux. No userspace. The kernel, the HolyC JIT, the drivers and every app
                share one flat 64-bit address space — and it runs live in your browser.
              </p>
              <div className="flex flex-wrap items-center gap-3">
                <Button asChild size="lg">
                  <Link href="/neo-os">
                    Open the live console
                    <ArrowRight className="size-4" />
                  </Link>
                </Button>
                <Button asChild size="lg" variant="outline">
                  <a href="#architecture">Explore the architecture</a>
                </Button>
              </div>
            </div>
          </header>

          <section className="flex flex-col gap-6">
            <div className="flex flex-col gap-2">
              <h2 className="text-2xl font-semibold tracking-tight">Built from first principles</h2>
              <p className="max-w-2xl text-sm text-muted-foreground">
                Every subsystem is written from scratch for the bare-metal AArch64 target — no
                abstraction layers hiding the hardware.
              </p>
            </div>
            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
              {FEATURES.map((feature) => (
                <Card key={feature.title} className="gap-3 py-5">
                  <CardHeader className="gap-2">
                    <feature.icon className="size-5 text-primary" />
                    <CardTitle className="text-base">{feature.title}</CardTitle>
                  </CardHeader>
                  <CardContent>
                    <CardDescription className="leading-relaxed">{feature.body}</CardDescription>
                  </CardContent>
                </Card>
              ))}
            </div>
          </section>

          <section className="flex flex-col gap-6">
            <div className="flex flex-col gap-2">
              <h2 className="text-2xl font-semibold tracking-tight">Real QEMU framebuffer captures</h2>
              <p className="max-w-2xl text-sm text-muted-foreground">
                Every screenshot below is a live capture from the guest — no mocks.
              </p>
            </div>
            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
              {SCREENSHOTS.map((shot) => (
                <figure key={shot.src} className="overflow-hidden rounded-xl border bg-card">
                  <Image
                    src={shot.src}
                    alt={shot.alt}
                    width={1024}
                    height={768}
                    className="aspect-[4/3] w-full object-cover"
                  />
                  <figcaption className="border-t px-3 py-2 text-xs text-muted-foreground">
                    {shot.caption}
                  </figcaption>
                </figure>
              ))}
            </div>
          </section>

          <section id="architecture" className="flex flex-col gap-6">
            <div className="flex flex-col gap-2">
              <h2 className="text-2xl font-semibold tracking-tight">Architecture highlights</h2>
              <p className="max-w-2xl text-sm text-muted-foreground">
                From the UEFI entry point to JIT-compiled HolyC executing on Cortex-A72 cores.
              </p>
            </div>
            <div className="grid gap-4 lg:grid-cols-2">
              <Card className="py-5">
                <CardHeader>
                  <CardTitle className="text-base">Boot sequence</CardTitle>
                  <CardDescription>EFI_MAIN brings the system up in one pass.</CardDescription>
                </CardHeader>
                <CardContent>
                  <pre className="overflow-auto rounded-md bg-background/60 p-3 font-mono text-[11px] leading-relaxed text-muted-foreground">
{`UEFI Firmware
  └─ EFI_MAIN  (boot/main.c)
       ├─ GOP framebuffer setup
       ├─ Kernel heap init
       ├─ SMP: cores 1-3 via PSCI CPU_ON
       ├─ Window manager + DolDoc terminal
       ├─ Shell init
       ├─ jittest        (HolyC JIT self-tests)
       ├─ zeroram on     (direct-VRAM mode)
       ├─ bench3d        (3D cubes auto-start)
       └─ Main event loop`}
                  </pre>
                </CardContent>
              </Card>

              <Card className="py-5">
                <CardHeader>
                  <CardTitle className="text-base">HolyC JIT pipeline</CardTitle>
                  <CardDescription>Source text to executable AArch64 in one pass.</CardDescription>
                </CardHeader>
                <CardContent>
                  <pre className="overflow-auto rounded-md bg-background/60 p-3 font-mono text-[11px] leading-relaxed text-muted-foreground">
{`HolyC source
  └─ lexer      → tokens
  └─ parser     → recursive descent
       ternary, logical, equality,
       relational, bitwise, shift,
       additive, term, unary, primary
  └─ codegen    → uint32_t AArch64 words
       branch backpatching
       loop + switch contexts
  └─ mprotect(RWX) + icache flush
       └─ live call on Cortex-A72`}
                  </pre>
                </CardContent>
              </Card>
            </div>
          </section>

          <section className="flex flex-col gap-6">
            <div className="flex items-center gap-2">
              <Terminal className="size-5 text-primary" />
              <h2 className="text-2xl font-semibold tracking-tight">Shell commands</h2>
            </div>
            <div className="overflow-hidden rounded-xl border">
              <table className="w-full text-left text-sm">
                <thead className="bg-muted/40 text-xs uppercase tracking-wide text-muted-foreground">
                  <tr>
                    <th className="px-4 py-3 font-medium">Command</th>
                    <th className="px-4 py-3 font-medium">Description</th>
                  </tr>
                </thead>
                <tbody>
                  {COMMANDS.map(([cmd, desc]) => (
                    <tr key={cmd} className="border-t">
                      <td className="whitespace-nowrap px-4 py-3 font-mono text-xs text-foreground">{cmd}</td>
                      <td className="px-4 py-3 text-muted-foreground">{desc}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>

          <Separator />

          <section className="flex flex-col items-start gap-4">
            <h2 className="text-2xl font-semibold tracking-tight">Drive the guest yourself</h2>
            <p className="max-w-2xl text-sm text-muted-foreground">
              The live console streams the guest framebuffer over a dirty-rect binary channel, forwards
              your keyboard and pointer through VNC, and tails the UART over a socket — all in the
              browser.
            </p>
            <Button asChild size="lg">
              <Link href="/neo-os">
                Open the live console
                <ArrowRight className="size-4" />
              </Link>
            </Button>
          </section>

          <footer className="flex flex-wrap items-center justify-between gap-3 border-t pt-6 text-xs text-muted-foreground">
            <span>NeoOS — built from scratch. Ring 0. Real hardware. No gambiarras.</span>
            <span className="font-mono">MIT licensed</span>
          </footer>
        </div>
      </div>
    </div>
  );
}
