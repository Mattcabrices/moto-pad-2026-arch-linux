/* LD_PRELOAD helper: on SIGSEGV/SIGBUS/SIGABRT print the faulting address, a glibc backtrace (unwinder, not
 * frame pointers) and each frame's library + offset to stderr, then die. Used to debug labwc on the
 * Moto Pad where core dumps are not produced. Build: gcc -O1 -shared -fPIC -o segv-trace.so segv-trace.c */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <execinfo.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <ucontext.h>
#include <unistd.h>

static void handler(int sig, siginfo_t *si, void *uc_)
{
    ucontext_t *uc = uc_;
    char b[256];
    int n = snprintf(b, sizeof b, "\n*** segv-trace: signal %d addr %p pc %p lr %p\n", sig, si->si_addr,
                     (void *)uc->uc_mcontext.pc, (void *)uc->uc_mcontext.regs[30]);
    write(2, b, n);
    void *f[64];
    int k = backtrace(f, 64);
    void *extra[2] = { (void *)uc->uc_mcontext.pc, (void *)uc->uc_mcontext.regs[30] };
    for (int i = -2; i < k; i++) {
        void *a = i < 0 ? extra[i + 2] : f[i];
        Dl_info di;
        if (dladdr(a, &di) && di.dli_fname)
            n = snprintf(b, sizeof b, "  %s %p %s+0x%lx (%s)\n", i < 0 ? (i == -2 ? "pc" : "lr") : "bt", a, di.dli_fname,
                         (unsigned long)((char *)a - (char *)di.dli_fbase), di.dli_sname ? di.dli_sname : "?");
        else
            n = snprintf(b, sizeof b, "  %s %p ?\n", i < 0 ? (i == -2 ? "pc" : "lr") : "bt", a);
        write(2, b, n);
    }
    signal(sig, SIG_DFL);
    raise(sig);
}

__attribute__((constructor)) static void init(void)
{
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_sigaction = handler;
    sa.sa_flags = SA_SIGINFO | SA_RESETHAND;
    sigaction(SIGSEGV, &sa, NULL);
    sigaction(SIGBUS, &sa, NULL);
    sigaction(SIGABRT, &sa, NULL);
}
