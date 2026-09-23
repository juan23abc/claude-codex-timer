#ifndef CLAUDE_TIMER_PTY_H
#define CLAUDE_TIMER_PTY_H
#include <sys/types.h>
pid_t ct_spawn_pty(const char *executable, char *const argv[], char *const envp[], const char *directory, int *master);
pid_t ct_spawn_pipe(const char *executable, char *const argv[], char *const envp[], const char *directory, int *reader);
int ct_child_exit_status(pid_t pid, int *status);
void ct_stop_pty(pid_t pid);
void ct_install_signal_handlers(void);
int ct_cancel_requested(void);
#endif
