/* SPDX-License-Identifier: MIT */
/*
 * The toolchain's smoke test. test/run.sh builds this with cl65, puts it
 * on a disk image with c1541 and boots it in x64sc from the disk, through
 * the 1541's own ROM (true drive emulation), so getting here at all says
 * cc65, c1541, VICE and the KERNAL, BASIC and drive ROMs work. It then
 * checks the screen and the character ROM, and tells VICE how it went by
 * writing to the debug cartridge at $D7FF (-debugcart), which makes that
 * byte x64sc's exit code: 0 passed, 2 the screen, 3 the character ROM
 * (1 is x64sc's own, for -limitcycles running out).
 */
#include <conio.h>
#include <peekpoke.h>

#define SCREEN   0x0400
#define CHARROM  0xD000
#define DEBUGCART 0xD7FF

int main(void)
{
    unsigned char ok = 0;
    unsigned char rom0, rom1;

    clrscr();
    cputs("hello");                 /* screen codes 8 5 12 12 15 */
    if (PEEK(SCREEN) != 8 || PEEK(SCREEN + 4) != 15)
        ok = 2;

    /* '@', character 0: $3C $66 in chargen-901225-01. */
    __asm__("sei");
    POKE(0x01, 0x33);
    rom0 = PEEK(CHARROM);
    rom1 = PEEK(CHARROM + 1);
    POKE(0x01, 0x37);
    __asm__("cli");
    if (ok == 0 && (rom0 != 0x3C || rom1 != 0x66))
        ok = 3;

    POKE(DEBUGCART, ok);
    for (;;)
        ;
    return 0;
}
