#include "smp.h"
#include "../../gui/render.h"
#include "../../kernel/symbols/symbols.h"
#include <uefi.h>

#define PSCI_0_2_FN64_CPU_ON 0xC4000003ULL

// GUID for EFI_MP_SERVICES_PROTOCOL
static efi_guid_t g_mp_services_guid = {
    0x3fdda605, 0xa76e, 0x4f46, { 0xad, 0x29, 0x12, 0xf4, 0x53, 0x1b, 0x3d, 0x08 }
};

typedef struct _EFI_MP_SERVICES_PROTOCOL {
    efi_status_t (EFIAPI *GetNumberOfProcessors)(
        struct _EFI_MP_SERVICES_PROTOCOL *This,
        uintn_t *NumberOfProcessors,
        uintn_t *NumberOfEnabledProcessors
    );
    efi_status_t (EFIAPI *GetProcessorInfo)(
        struct _EFI_MP_SERVICES_PROTOCOL *This,
        uintn_t ProcessorNumber,
        void *ProcessorInfoBuffer
    );
    efi_status_t (EFIAPI *StartupAllAPs)(
        struct _EFI_MP_SERVICES_PROTOCOL *This,
        void (EFIAPI *Procedure)(void *Buffer),
        boolean_t SingleThread,
        void *WaitEvent,
        uintn_t TimeoutInMicroSeconds,
        void *ProcedureArgument,
        void *FailedCpuList
    );
    efi_status_t (EFIAPI *StartupThisAP)(
        struct _EFI_MP_SERVICES_PROTOCOL *This,
        void (EFIAPI *Procedure)(void *Buffer),
        uintn_t ProcessorNumber,
        void *WaitEvent,
        uintn_t TimeoutInMicroSeconds,
        void *ProcedureArgument,
        boolean_t *Finished
    );
    efi_status_t (EFIAPI *SwitchBSP)(
        struct _EFI_MP_SERVICES_PROTOCOL *This,
        uintn_t ProcessorNumber,
        boolean_t EnableOldBSP
    );
    efi_status_t (EFIAPI *EnableDisableAP)(
        struct _EFI_MP_SERVICES_PROTOCOL *This,
        uintn_t ProcessorNumber,
        boolean_t EnableAP,
        uint32_t *HealthFlag
    );
    efi_status_t (EFIAPI *WhoAmI)(
        struct _EFI_MP_SERVICES_PROTOCOL *This,
        uintn_t *ProcessorNumber
    );
} EFI_MP_SERVICES_PROTOCOL;

mmu_config_t g_mmu_config = {0};
smp_state_t  g_smp = {0};

extern int64_t  psci_call_hvc(uint64_t func, uint64_t arg1, uint64_t arg2, uint64_t arg3);
extern int64_t  psci_call_smc(uint64_t func, uint64_t arg1, uint64_t arg2, uint64_t arg3);
extern uint64_t smp_get_mpidr(void);
extern uint64_t smp_get_sctlr(void);
extern uint64_t smp_get_tcr(void);
extern uint64_t smp_get_mair(void);
extern uint64_t smp_get_ttbr0(void);
extern uint64_t smp_get_vbar(void);
extern void     smp_entry(void);

uint32_t smp_get_core_count(void) {
    return g_smp.num_cores;
}

uint32_t smp_get_current_core(void) {
    uint64_t mpidr = smp_get_mpidr();
    return (uint32_t)(mpidr & 0xFF);
}

extern void uart_puts(const char *s);

void smp_secondary_core_worker(uint32_t core_id) {
    if (core_id >= SMP_MAX_CORES) return;

    g_smp.core_online[core_id] = 1;
    uart_puts("[SMP] Secondary Core online.\r\n");

    while (1) {
        g_smp.core_heartbeat[core_id]++;

        if (g_smp.jobs[core_id].pending) {
            smp_task_fn fn = g_smp.jobs[core_id].fn;
            void *arg = g_smp.jobs[core_id].arg;

            if (fn) {
                fn(arg);
            }

            g_smp.jobs[core_id].pending = 0;
            g_smp.jobs[core_id].completed = 1;
        }

        for (volatile int i = 0; i < 500; i++) {}
        asm volatile("wfe");
    }
}

static void EFIAPI uefi_ap_trampoline(void *Buffer) {
    (void)Buffer;
    uint32_t core_id = smp_get_current_core();
    smp_secondary_core_worker(core_id);
}

int smp_dispatch(uint32_t core_id, smp_task_fn fn, void *arg) {
    if (core_id == 0 || core_id >= SMP_MAX_CORES) return -1;
    if (!g_smp.core_online[core_id]) return -1;

    g_smp.jobs[core_id].fn = fn;
    g_smp.jobs[core_id].arg = arg;
    g_smp.jobs[core_id].completed = 0;
    g_smp.jobs[core_id].pending = 1;

    asm volatile("sev");
    return 0;
}

int smp_is_job_done(uint32_t core_id) {
    if (core_id >= SMP_MAX_CORES) return 1;
    return g_smp.jobs[core_id].completed;
}

void smp_init(void) {
    memset(&g_smp, 0, sizeof(g_smp));
    g_smp.num_cores = 4;
    g_smp.core_online[0] = 1;
    g_smp.online_cores = 1;

    // Capture MMU state of Boot Core 0
    g_mmu_config.sctlr = smp_get_sctlr();
    g_mmu_config.tcr   = smp_get_tcr();
    g_mmu_config.mair  = smp_get_mair();
    g_mmu_config.ttbr0 = smp_get_ttbr0();
    g_mmu_config.vbar  = smp_get_vbar();

    // Clean data cache to PoC so secondary cores without MMU see valid values
    asm volatile("dc cvac, %0" :: "r"(&g_mmu_config));
    asm volatile("dsb sy\nisb" ::: "memory");

    printf("[SMP] Boot Core 0 MPIDR: 0x%llX, SCTLR: 0x%llX\r\n",
           (unsigned long long)smp_get_mpidr(), (unsigned long long)g_mmu_config.sctlr);

    // 1. Try UEFI MP Services Protocol first
    EFI_MP_SERVICES_PROTOCOL *mp = NULL;
    efi_status_t status = BS->LocateProtocol(&g_mp_services_guid, NULL, (void**)&mp);
    if (!EFI_ERROR(status) && mp != NULL) {
        uintn_t num_procs = 0, enabled_procs = 0;
        mp->GetNumberOfProcessors(mp, &num_procs, &enabled_procs);
        printf("[SMP] Found EFI_MP_SERVICES_PROTOCOL: %llu processors (%llu enabled)\r\n",
               (unsigned long long)num_procs, (unsigned long long)enabled_procs);

        g_smp.num_cores = (uint32_t)num_procs;
        status = mp->StartupAllAPs(mp, uefi_ap_trampoline, 0, NULL, 0, NULL, NULL);
        if (!EFI_ERROR(status)) {
            printf("[SMP] StartupAllAPs invoked successfully.\r\n");
        }
    } else {
        printf("[SMP] EFI_MP_SERVICES_PROTOCOL not found, using ARM PSCI CPU_ON...\r\n");

        // 2. Direct ARM PSCI 0.2+ CPU_ON
        for (uint32_t i = 1; i < SMP_MAX_CORES; i++) {
            uint64_t target_cpu = (uint64_t)i; // MPIDR affinity 0 = i
            uint64_t entry_addr = (uint64_t)smp_entry;
            uint64_t context_id = (uint64_t)i;

            int64_t ret = psci_call_hvc(PSCI_0_2_FN64_CPU_ON, target_cpu, entry_addr, context_id);
            if (ret != 0) {
                // Try SMC conduit if HVC returned non-zero
                ret = psci_call_smc(PSCI_0_2_FN64_CPU_ON, target_cpu, entry_addr, context_id);
            }

            if (ret == 0) {
                printf("[SMP] PSCI CPU_ON Core %u dispatched (entry: 0x%llX)\r\n", i, (unsigned long long)entry_addr);
            } else {
                printf("[SMP] PSCI CPU_ON Core %u returned code %lld\r\n", i, (long long)ret);
            }
        }
    }

    // Brief delay to allow secondary cores to initialize
    for (volatile int d = 0; d < 2000000; d++) {}

    // Count how many cores responded
    uint32_t online_cnt = 0;
    for (uint32_t i = 0; i < SMP_MAX_CORES; i++) {
        if (g_smp.core_online[i]) online_cnt++;
    }
    g_smp.online_cores = online_cnt;
    printf("[SMP] Multiprocessing initialized: %u of %u cores active.\r\n",
           g_smp.online_cores, g_smp.num_cores);

    symbols_register("smp_get_core_count", (void*)smp_get_core_count, SYM_FUNC);
    symbols_register("smp_get_current_core", (void*)smp_get_current_core, SYM_FUNC);
    symbols_register("smp_print", (void*)smp_print_doldoc, SYM_FUNC);
}

void smp_print_doldoc(void) {
    doldoc_print("$FG,CYAN$--- ARMv8-A SMP MULTIPROCESSING TELEMETRY ---$FG$\n");
    doldoc_printf(" Cores Configured: %u | Active Online: %u\n", g_smp.num_cores, g_smp.online_cores);

    for (uint32_t i = 0; i < SMP_MAX_CORES; i++) {
        const char *state = g_smp.core_online[i] ? "$FG,GREEN$ONLINE$FG$" : "$FG,RED$OFFLINE$FG$";
        const char *role  = (i == 0) ? "(BSP / GUI Core)" : "(Worker Core)";
        doldoc_printf("  Core #%u %s: %s | Heartbeat Ticks: %llu\n",
                      i, role, state, (unsigned long long)g_smp.core_heartbeat[i]);
    }
    doldoc_print("$FG,CYAN$-----------------------------------------------$FG$\n");
}
