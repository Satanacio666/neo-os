#ifndef NEO_SHELL_H
#define NEO_SHELL_H

void shell_init(void);
void shell_poll(void);
void shell_run_command(const char *cmd);

#endif // NEO_SHELL_H
