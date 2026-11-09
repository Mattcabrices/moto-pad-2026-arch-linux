/* Reboots into the bootloader (fastboot). No libc: built with -nostdlib for the initramfs. */
static long sys4(long n, long a, long b, long c, long d) {
  register long x8 __asm__("x8") = n;
  register long x0 __asm__("x0") = a;
  register long x1 __asm__("x1") = b;
  register long x2 __asm__("x2") = c;
  register long x3 __asm__("x3") = d;
  __asm__ volatile("svc 0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2), "r"(x3) : "memory");
  return x0;
}
void _start(void) {
  sys4(81, 0, 0, 0, 0); /* sync */
  sys4(142, 0xfee1dead, 0x28121969, 0xA1B2C3D4, (long)"bootloader"); /* reboot RESTART2 */
  for (;;) {}
}
