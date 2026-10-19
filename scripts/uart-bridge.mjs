// Persistent PL011 UART bridge.
//   QEMU chardev socket  <-->  this process  <-->  log file + input socket
// The guest UART allows only one QEMU chardev client, so this bridge holds that
// single connection: it tees guest output to a log file and forwards input from
// a local unix socket back into the guest.
import net from "node:net";
import fs from "node:fs";

const QEMU_SOCK = process.env.NEO_UART_SOCK ?? "/tmp/neo-os-uart.sock";
const IN_SOCK = process.env.NEO_UART_IN_SOCK ?? "/tmp/neo-os-uart-in.sock";
const LOG = process.env.NEO_SERIAL_LOG ?? "/tmp/neo-os-serial.log";

fs.writeFileSync(LOG, "");
const logStream = fs.createWriteStream(LOG, { flags: "a" });

let qemu = null;
let reconnectTimer = null;

function connectQemu() {
  if (qemu && !qemu.destroyed) return;
  qemu = net.connect(QEMU_SOCK);
  qemu.on("data", (d) => logStream.write(d));
  qemu.on("error", scheduleReconnect);
  qemu.on("close", scheduleReconnect);
}
function scheduleReconnect() {
  qemu = null;
  if (reconnectTimer) return;
  reconnectTimer = setTimeout(() => { reconnectTimer = null; connectQemu(); }, 500);
}
connectQemu();

try { fs.unlinkSync(IN_SOCK); } catch { /* not present */ }
net.createServer((client) => {
  client.on("data", (d) => { if (qemu && qemu.writable) qemu.write(d); });
  client.on("error", () => client.destroy());
  client.on("end", () => client.end());
}).listen(IN_SOCK);

process.on("SIGTERM", () => process.exit(0));
process.on("SIGINT", () => process.exit(0));
