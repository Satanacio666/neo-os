#include <uefi.h>

typedef struct {
    uint64_t x[30];
    uint64_t lr;      // x30
    uint64_t elr_el1; // Exception Link Register (PC where exception occurred)
    uint64_t spsr_el1;// Saved Program Status Register
} __attribute__((packed)) trap_frame_t;

void arm64_sync_exception(trap_frame_t *frame) {
    uint64_t esr, far;
    asm volatile("mrs %0, esr_el1" : "=r"(esr));
    asm volatile("mrs %0, far_el1" : "=r"(far));

    uint32_t ec = (esr >> 26) & 0x3F; // Exception Class
    uint32_t iss = esr & 0x01FFFFFF;  // Instruction Specific Syndrome

    printf("\n!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");
    printf(" [CPU EXCEPTION] Synchronous Abort Trapped in Ring 0!\n");
    printf("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");
    printf(" Exception Class (EC): 0x%02X | ISS: 0x%08X\n", ec, iss);
    printf(" Faulting PC (ELR_EL1):  0x%p\n", frame->elr_el1);
    printf(" Fault Address (FAR_EL1): 0x%p\n", far);
    printf(" Saved Status (SPSR_EL1): 0x%p\n", frame->spsr_el1);

    const char *fault_name = "Unknown Abort";
    if (ec == 0x25) fault_name = "Data Abort (Memory access violation)";
    else if (ec == 0x21) fault_name = "Instruction Abort (Execution violation)";
    else if (ec == 0x26) fault_name = "SP Alignment Fault";
    else if (ec == 0x15) fault_name = "SVC Trap";

    printf(" Fault Type: %s\n", fault_name);
    printf("\n--- REGISTERS DUMP ---\n");
    for (int i = 0; i < 30; i += 2) {
        printf(" X%02d: 0x%p   X%02d: 0x%p\n",
               i, frame->x[i],
               i+1, frame->x[i+1]);
    }
    printf(" X30 (LR): 0x%p\n", frame->lr);
    printf("--------------------------------------------------------\n\n");

    while (1) {
        asm volatile("wfi");
    }
}

void arm64_unhandled_abort(trap_frame_t *frame) {
    printf("\n[CPU FATAL] Unhandled Exception Vector triggered! PC: 0x%p\n", frame->elr_el1);
    while (1) {
        asm volatile("wfi");
    }
}
