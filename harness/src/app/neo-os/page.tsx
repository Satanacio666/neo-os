import type { Metadata } from "next";
import Link from "next/link";
import { ArrowLeft, CircuitBoard } from "lucide-react";
import { Button } from "@/components/ui/button";
import { NeoViewer } from "@/components/neo-os/neo-viewer";
import { SerialConsole } from "@/components/neo-os/serial-console";
import { VmControls } from "@/components/neo-os/vm-controls";

export const metadata: Metadata = {
  title: "Console",
  description:
    "Drive the NeoOS Ring 0 AArch64 guest in the browser: live framebuffer streaming, keyboard and pointer input, UART console and VM control.",
};

export default function NeoOsPage() {
  return (
    <div className="dark">
      <div className="min-h-screen bg-background text-foreground">
        <div className="mx-auto flex max-w-[1440px] flex-col gap-4 p-4 md:p-6">
          <header className="flex flex-wrap items-center justify-between gap-3">
            <div className="flex items-center gap-3">
              <Button asChild size="sm" variant="ghost">
                <Link href="/">
                  <ArrowLeft className="size-4" />
                  Home
                </Link>
              </Button>
              <div className="flex items-center gap-2">
                <CircuitBoard className="size-5 text-primary" />
                <div>
                  <h1 className="text-base font-semibold tracking-tight">NeoOS console</h1>
                  <p className="text-xs text-muted-foreground">
                    Live QEMU AArch64 guest · dirty-rect RGBA stream · VNC input · UART over socket
                  </p>
                </div>
              </div>
            </div>
          </header>

          <div className="grid gap-4 lg:grid-cols-[1fr_400px]">
            <NeoViewer />
            <aside className="flex flex-col gap-4">
              <VmControls />
              <SerialConsole />
            </aside>
          </div>
        </div>
      </div>
    </div>
  );
}
