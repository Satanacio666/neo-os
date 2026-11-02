# MMIO / IRQ Inventory — NeoOS P0.3

Fonte da verdade: `apps/HalPlatform.HC` (`CHalPlatform` / `HalPlatformInit`) e a
descoberta de firmware (ACPI `E3` / FDT `E4`), que sobrescreve os campos que
descreve. Dispositivos de placa (virtio-mmio) nao aparecem em ACPI e mantem o
default da tabela estatica.

## QEMU ARM64 Virt (default do gate)

| Recurso | MMIO / IRQ | Campo HAL | Nota |
|---|---|---|---|
| PL011 UART   | 0x09000000 | `g_plat_qemu.uart_base` | tipo descoberto (PL011) |
| GIC Distributor | 0x08000000 | `g_plat_qemu.gicd_base` | |
| GIC CPU Interface | 0x08010000 | `g_plat_qemu.gicc_base` | |
| GIC Redistributor | 0x080A0000 | `g_plat_qemu.gicr_base` | GICv3 |
| VirtIO MMIO | 0x0A000000 | `g_plat_qemu.virtio_base` | slots=32, stride=0x200 |
| Timer (PPI) | IRQ 27 | `g_plat_qemu.irq_timer` | CNTVCT_EL0 |
| UART intr. | IRQ 33 | `g_plat_qemu.irq_uart` | |

## Raspberry Pi 4 (BCM2711)

| Recurso | MMIO / IRQ | Campo HAL |
|---|---|---|
| PL011 | 0xFE201000 | `g_plat_rpi4.uart_base` |
| GICD | 0xFF841000 | `g_plat_rpi4.gicd_base` |
| GICC | 0xFF842000 | `g_plat_rpi4.gicc_base` |
| Timer | IRQ 30 | `g_plat_rpi4.irq_timer` |
| UART intr. | IRQ 153 | `g_plat_rpi4.irq_uart` |

## Raspberry Pi 5 (BCM2712/RP1)

| Recurso | MMIO / IRQ | Campo HAL |
|---|---|---|
| PL011 | 0x107D001000 | `g_plat_rpi5.uart_base` |
| GICD | 0x107D500000 | `g_plat_rpi5.gicd_base` |
| GICC | 0x107D580000 | `g_plat_rpi5.gicc_base` |
| Timer | IRQ 30 (nao confirmado, ver codigo) | `g_plat_rpi5.irq_timer` |
| UART intr. | IRQ 146 | `g_plat_rpi5.irq_uart` |

## Rockchip RK3399

| Recurso | MMIO / IRQ | Campo HAL |
|---|---|---|
| PL011 | 0xFF1A0000 | `g_plat_rk3399.uart_base` |
| GICD | 0xFEE00000 | `g_plat_rk3399.gicd_base` |
| GICC | 0xFEF00000 | `g_plat_rk3399.gicc_base` |
| Timer | IRQ 27 | `g_plat_rk3399.irq_timer` |
| UART intr. | IRQ 132 | `g_plat_rk3399.irq_uart` |

## Snapdragon 860 (SM8150 / Poco X3 Pro)

| Recurso | MMIO / IRQ | Campo HAL |
|---|---|---|
| PL011 | 0x00A90000 | `g_plat_sm8150.uart_base` |
| GICD | 0x17A00000 | `g_plat_sm8150.gicd_base` |
| GICC | 0x17C00000 | `g_plat_sm8150.gicc_base` |
| GICR | 0x17A60000 | `g_plat_sm8150.gicr_base` |
| Timer | IRQ 27 | `g_plat_sm8150.irq_timer` |
| UART intr. | IRQ 108 | `g_plat_sm8150.irq_uart` |

## Acessores canonicos (Layer B, agora cabeados)

- `HalGetUartBase()` / `hal_get_uart_base()` — base da UART (fallback 0x09000000)
- `HalGetGicdBase()` / `hal_get_gicd_base()` — 0x08000000
- `HalGetGiccBase()` / `hal_get_gicc_base()` — 0x08010000
- `HalGetVirtioBase()` / `hal_get_virtio_base()` — 0x0A000000
- `HalGetVirtioSlots()` — slots (fallback 32) — agora CABEADO em VirtioBlk/Input/GfxDevice
- `HalGetVirtioStride()` — stride (fallback 0x200) — agora CABEADO nos mesmos
- `HalGetTimerIrq()` / `HalGetUartIrq()` — IRQs de planta-forma

## Nota sobre a descoberta

A ordem de autoridade e': ACPI/FDT (firmware, quando presente) > tabela estatica.
A descoberta nunca zera a tabela inteira: so sobrescreve os campos que descreve,
e devolve-se ao fallback da tabela quando o campo vem zerado. Invariante da
universalidade: sem descoberta, o boot e' identico.
