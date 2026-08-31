import Toybox.Lang;

// Palette. The fr955 is an 8bpp MIP panel whose usable palette is 4 levels per
// channel (00/55/AA/FF), so every constant here is picked from that grid --
// anything else gets dithered and looks muddy in daylight.
module Colors {
    const BACKGROUND = 0x000000;
    const ARC_EMPTY = 0x555555;   // unfilled part of both arcs
    const TEXT = 0xAAAAAA;        // date, values, icons
    const BLUE = 0x00AAFF;        // Body Battery arc
    const RED = 0xFF0000;         // minutes, seconds, stress arc
    const GREEN = 0x00FF00;       // battery fill
    const LOW = 0xFF0000;         // battery fill below LOW_BATTERY_PCT
}
