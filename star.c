/*
 * star.c - Star field for Amiga 320x256x5-bitplane line-interleaved screen.
 *
 * Screen layout (mode 0, SetGraphicsMode(0)):
 *   - 320 x 256 pixels, 5 bitplanes (32 colours)
 *   - Line-interleaved: each scanline holds all 5 plane rows back-to-back
 *   - Row stride  = NUM_PLANES * BYTES_PER_ROW = 5 * 40 = 200 bytes
 *   - Plane stride within a row = BYTES_PER_ROW = 40 bytes
 *   - Pixel (x, y) in plane p:  screen + y*200 + p*40 + x/8
 *   - Bit position within byte:  0x80 >> (x & 7)
 *   - Colour index c (0-31): bit p of c drives bitplane p
 *
 * Functions exported (both _name and name variants):
 *   stars_init(screen)    - scatter 50 random stars with random colours
 *   stars_animate(screen) - randomise the colour of every star in-place
 *
 * Compile:
 *   vbccm68k -cpu=68000 -I<vbcc>/targets/m68k-amigaos/include star.c -o=star_c.s
 *   vasmm68k_mot -m68000 -Fhunk -kick1hunks star_c.s -o star.o
 */

#define SCREEN_WIDTH    320
#define SCREEN_HEIGHT   256
#define NUM_PLANES      5
#define BYTES_PER_ROW   (SCREEN_WIDTH / 8)            /* 40  */
#define ROW_STRIDE      (NUM_PLANES * BYTES_PER_ROW)  /* 200 */
#define NUM_STARS       20

typedef unsigned char  u8;
typedef unsigned short u16;
typedef unsigned long  u32;

/* ---- Simple LCG PRNG (no stdlib needed) --------------------------------- */
static u32 star_seed = 0xDEADBEEFUL;

static u16 star_rand(void)
{
    star_seed = star_seed * 1664525UL + 1013904223UL;
    return (u16)(star_seed >> 16);
}

/* ---- Star table ---------------------------------------------------------- */
static u16 star_x[NUM_STARS];
static u16 star_y[NUM_STARS];
static u8  star_color[NUM_STARS];

/* ---- Internal pixel plotter --------------------------------------------- */
/*
 * plot_pixel - set a single pixel to a 5-bit colour index.
 * screen : base of the video buffer (gfx_current_screen_ptr)
 * x, y   : pixel coordinates (0-based)
 * color  : colour register index 0-31 (0 = background / erase)
 *
 * Inlined and unrolled for performance (5 bitplanes fixed).
 */
static inline void plot_pixel(u8 *screen, u16 x, u16 y, u8 color)
{
    int byte_off = (int)y * ROW_STRIDE + (int)(x >> 3);
    u8  bit_mask = 0x80u >> (x & 7u);
    u8 *bp = screen + byte_off;

    /* Unrolled bitplane loop (NUM_PLANES = 5) */
    if (color & 1)  *bp |= bit_mask; else *bp &= ~bit_mask;
    bp += BYTES_PER_ROW;
    if (color & 2)  *bp |= bit_mask; else *bp &= ~bit_mask;
    bp += BYTES_PER_ROW;
    if (color & 4)  *bp |= bit_mask; else *bp &= ~bit_mask;
    bp += BYTES_PER_ROW;
    if (color & 8)  *bp |= bit_mask; else *bp &= ~bit_mask;
    bp += BYTES_PER_ROW;
    if (color & 16) *bp |= bit_mask; else *bp &= ~bit_mask;
}

/* ---- Public API ---------------------------------------------------------- */

/*
 * stars_init - place NUM_STARS randomly positioned stars on the screen.
 * screen : pointer to the active video buffer (gfx_current_screen_ptr)
 *
 * Stores the generated positions and colour indices in module-level arrays
 * so that stars_animate can later erase and redraw them efficiently.
 * Colour 0 (background) is never used; indices are chosen in the range 1-31.
 */
void stars_init(u8 *screen)
{
    int i;
    for (i = 0; i < NUM_STARS; i++) {
        /* Map [0,65535] → [0, SCREEN_WIDTH-1]  via multiply+shift (uses mulu.w,
         * no software-division helper required on 68000).
         * x = (rand * 320) >> 16  →  [0, 319]
         * y = rand >> 8           →  [0, 255] (SCREEN_HEIGHT is exactly 256) */
        star_x[i]     = (u16)(((u32)star_rand() * (u32)SCREEN_WIDTH) >> 16);
        star_y[i]     = (u16)(star_rand() >> 8);
        star_color[i] = (u8)((star_rand() & 30u) + 1u); /* 1..31 */
        plot_pixel(screen, star_x[i], star_y[i], star_color[i]);
    }
}

/*
 * stars_animate - assign each existing star a new random colour index.
 * screen : pointer to the active video buffer (gfx_current_screen_ptr)
 *
 * Each star is given a new random colour (1-31) and redrawn in place.
 * plot_pixel() fully overwrites all five bitplanes, so an explicit erase
 * pass would only duplicate work.
 */
void stars_animate(u8 *screen)
{
    int i;
    for (i = 0; i < NUM_STARS; i++) {
        star_color[i] = (u8)((star_rand() & 30u) + 1u);        /* recolour */
        plot_pixel(screen, star_x[i], star_y[i], star_color[i]); /* redraw */
    }
}
