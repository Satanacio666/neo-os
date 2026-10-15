#ifndef NEO_SHELL_H
#define NEO_SHELL_H

typedef void (*holyc_shell_run_cmd_t)(const char *cmd);
typedef void (*holyc_shell_poll_t)(void);

void shell_register_holyc(holyc_shell_run_cmd_t run_cmd, holyc_shell_poll_t poll_fn);
void shell_init(void);
void shell_poll(void);
void shell_run_command(const char *cmd);
void shell_task_recover(void);

#endif // NEO_SHELL_H
