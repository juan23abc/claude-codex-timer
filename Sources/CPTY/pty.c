#include "CPTY.h"
#include <util.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <errno.h>

static volatile sig_atomic_t cancelled = 0;
static void cancel_run(int signal) { cancelled = 1; }
void ct_install_signal_handlers(void) {
    struct sigaction action = {0};
    action.sa_handler = cancel_run;
    sigemptyset(&action.sa_mask);
    sigaction(SIGTERM, &action, NULL);
    sigaction(SIGINT, &action, NULL);
}
int ct_cancel_requested(void) { return cancelled; }

pid_t ct_spawn_pipe(const char *executable, char *const argv[], char *const envp[], const char *directory, int *reader) {
    int descriptors[2];
    if (pipe(descriptors) < 0) return -1;
    fcntl(descriptors[0], F_SETFD, FD_CLOEXEC);
    pid_t pid = fork();
    if (pid == 0) {
        close(descriptors[0]);
        if (setsid() < 0) _exit(126);
        int input = open("/dev/null", O_RDONLY);
        if (input < 0 || dup2(input, STDIN_FILENO) < 0 || dup2(descriptors[1], STDOUT_FILENO) < 0 || dup2(descriptors[1], STDERR_FILENO) < 0) _exit(126);
        if (input > 2) close(input);
        if (descriptors[1] > 2) close(descriptors[1]);
        if (chdir(directory) < 0) _exit(126);
        execve(executable, argv, envp);
        _exit(127);
    }
    close(descriptors[1]);
    if (pid < 0) { close(descriptors[0]); return -1; }
    *reader = descriptors[0];
    fcntl(*reader, F_SETFL, O_NONBLOCK);
    return pid;
}

int ct_child_exit_status(pid_t pid, int *status) {
    siginfo_t info = {0};
    // Observe without reaping, preserving ownership until group cleanup.
    if (waitid(P_PID, (id_t)pid, &info, WEXITED | WNOHANG | WNOWAIT) < 0 || info.si_pid == 0) return 0;
    *status = info.si_code == CLD_EXITED ? info.si_status : 128 + info.si_status;
    return 1;
}

pid_t ct_spawn_pty(const char *executable, char *const argv[], char *const envp[], const char *directory, int *master) {
    int slave;
    struct winsize size = {32, 100, 0, 0};
    if (openpty(master, &slave, NULL, NULL, &size) < 0) return -1;
    fcntl(*master, F_SETFD, FD_CLOEXEC);
    pid_t pid = fork();
    if (pid == 0) {
        // Only C / async-signal-safe operations between fork and exec.
        close(*master);
        if (setsid() < 0 || ioctl(slave, TIOCSCTTY, 0) < 0) _exit(126);
        for (int fd = 0; fd < 3; ++fd) if (dup2(slave, fd) < 0) _exit(126);
        if (slave > 2) close(slave);
        if (chdir(directory) < 0) _exit(126);
        execve(executable, argv, envp);
        _exit(127);
    }
    close(slave);
    if (pid < 0) { close(*master); return -1; }
    fcntl(*master, F_SETFL, O_NONBLOCK);
    return pid;
}

void ct_stop_pty(pid_t pid) {
    // Reap only here: keeping the child until cleanup prevents PID reuse.
    kill(-pid, SIGTERM);
    kill(pid, SIGTERM);
    for (int i = 0; i < 20; ++i) {
        int status;
        pid_t result = waitpid(pid, &status, WNOHANG);
        if (result == pid || (result < 0 && errno == ECHILD)) {
            kill(-pid, SIGKILL); // Any descendants in the owned session.
            return;
        }
        usleep(50000);
    }
    kill(-pid, SIGKILL);
    kill(pid, SIGKILL);
    // A kernel-stalled process must not wedge the scheduler indefinitely.
    for (int i = 0; i < 40; ++i) {
        pid_t result = waitpid(pid, NULL, WNOHANG);
        if (result == pid || (result < 0 && errno == ECHILD)) return;
        usleep(50000);
    }
}
