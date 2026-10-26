#ifndef NEO_SEED_FS_H
#define NEO_SEED_FS_H

#include <uefi.h>

/*
 * P2.2 — Bootstrap file access via the UEFI firmware's own FAT driver.
 *
 * The seed does NOT implement a filesystem or a block driver. It reads the
 * OS's own `.HC` sources from the FAT32 ESP using EFI_SIMPLE_FILE_SYSTEM_PROTOCOL,
 * exactly like the firmware's boot menu reads the boot loader. After the `.HC`
 * drivers load, they own the real hardware.
 */

int     seed_fs_init(void);
int64_t seed_read_file(const char *name, void *buf, size_t max_bytes);
/* E5 — leitura por caminho completo (o perfil mora em profiles\, fora de holyc\). */
int64_t seed_read_file_at(const char *path, void *buf, size_t max_bytes);

/*
 * P1.1 / P4.3 — Pre-carga da arvore `holyc\` para RAM.
 *
 * Precisa rodar ANTES do drop EL2->EL1: depois dele os Boot Services do
 * firmware nao podem mais ser chamados (o firmware foi inicializado em EL2).
 * Uma vez pre-carregado, seed_read_file() serve da RAM e nao toca no FAT.
 * Retorna o numero de arquivos carregados, ou -1.
 */
int     seed_preload_all(void);
int     seed_preload_count_get(void);

/*
 * P2.3 — Escrita no ESP pelo driver FAT do firmware.
 *
 * O seed não ganha um filesystem próprio: ele usa o mesmo driver FAT que o
 * firmware usa para ler o boot loader. Isto destrava:
 *   - P2.4 (cache de JIT): gravar o snapshot do código compilado;
 *   - P3.2 (RedSea sobre EFI_BLOCK_IO): validar ida e volta de dados.
 *
 * seed_write_file() apaga e recria o arquivo (garante tamanho exato, sem sobra
 * de uma versão maior anterior). Retorna os bytes gravados, ou -1.
 * seed_delete_file() remove; retorna 0 se removido, -1 se não existia.
 * seed_fnv1a() é o hash usado para validar o cache.
 */
int64_t seed_write_file(const char *name, const void *buf, size_t bytes);
int     seed_delete_file(const char *name);
uint32_t seed_fnv1a(const void *data, size_t bytes);

#endif // NEO_SEED_FS_H
