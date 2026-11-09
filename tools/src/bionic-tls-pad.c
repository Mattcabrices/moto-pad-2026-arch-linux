/* Moto Pad (archpad): reserve the bionic TLS slots in glibc processes that use libhybris.
 *
 * Android code (libEGL, the Mali blob) reads and writes fixed slots relative to the thread pointer
 * (tpidr_el0): TLS_SLOT_OPENGL (+24), TLS_SLOT_OPENGL_API (+32), TLS_SLOT_STACK_GUARD (+40), ... up to +72.
 * On glibc (aarch64, TLS variant I) the first static TLS block starts right after the 16-byte TCB, so those
 * writes land in real thread-local variables. In a program without TLS of its own, that is libc's, and the
 * current-locale pointer gets overwritten: the next sscanf() crashes (seen with es2gears_wayland).
 *
 * LD_PRELOAD this library: preloaded objects get their static TLS right after the executable's, so this
 * padding takes tp+16.. when the executable has no TLS (the common case) and absorbs the slot writes.
 * It cannot help an executable that has TLS of its own; a glibc with reserved bionic slots would. */
__attribute__((tls_model("initial-exec"), used)) __thread char archpad_bionic_tls_slots[256];
