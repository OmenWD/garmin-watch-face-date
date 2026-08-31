import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

// Icons are drawn with primitives rather than shipped as bitmaps: they are
// simple enough, they cost no resource memory, and they can be recoloured for
// free (a bitmap would need one copy per colour).
//
// Every function takes the icon centre and draws within ICON_W x ICON_H.
module Icons {

    const ICON_W = 20;
    const ICON_H = 20;

    // Actual inked width of each glyph, and how far its left edge sits from the
    // centre it is drawn about. Laying a row out by these rather than by ICON_W
    // is what makes the gaps between them look equal.
    const BATTERY_W = 19;
    const BATTERY_LEFT = 8;
    const BLUETOOTH_W = 12;
    const BLUETOOTH_LEFT = 6;

    // Battery outline with a fill level. `level` is 0.0 .. 1.0. The shell and
    // the fill are coloured separately: the shell stays neutral while the fill
    // carries the charge state.
    function battery(dc as Graphics.Dc, cx as Number, cy as Number, shellColor as Number, fillColor as Number, level as Float) as Void {
        var w = 17;
        var h = 9;
        var x = cx - w / 2;
        var y = cy - h / 2;

        dc.setColor(shellColor, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawRectangle(x, y, w, h);
        // Terminal nub on the right.
        dc.fillRectangle(x + w, cy - 2, 2, 4);

        var inner = w - 4;
        var filled = Math.round(inner * level).toNumber();
        if (filled > 0) {
            dc.setColor(fillColor, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x + 2, y + 2, filled, h - 4);
        }
    }

    // Bare lightning bolt -- the Body Battery mark, without a battery outline.
    function bodyBattery(dc as Graphics.Dc, cx as Number, cy as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([
            [cx + 4, cy - 9],
            [cx - 6, cy + 2],
            [cx - 1, cy + 2],
            [cx - 4, cy + 9],
            [cx + 6, cy - 2],
            [cx + 1, cy - 2]
        ] as Array<[Numeric, Numeric]>);
    }

    // Bluetooth rune -- what the stock face shows for the phone link. Five
    // strokes: the stem, two long diagonals crossing it to form the X, and the
    // two short edges from the tips out to the right corners.
    //
    // The lost-connection state is carried by `color` alone, not by a strike:
    // every straight strike runs close in angle to one of the four diagonals
    // and reads as a sixth stroke of the rune rather than as a cancellation.
    function bluetooth(dc as Graphics.Dc, cx as Number, cy as Number, color as Number) as Void {
        var top = cy - 8;
        var bottom = cy + 8;
        var right = cx + 5;
        var left = cx - 5;
        var upper = cy - 3;
        var lower = cy + 3;

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);

        dc.drawLine(cx, top, cx, bottom);
        dc.drawLine(left, upper, right, lower);
        dc.drawLine(left, lower, right, upper);
        dc.drawLine(cx, top, right, upper);
        dc.drawLine(cx, bottom, right, lower);
    }

    // Two chasing arrows. `phase` in degrees spins the pair, so calling this
    // once a second with a moving phase animates the sync state.
    function syncArrows(dc as Graphics.Dc, cx as Number, cy as Number, color as Number, phase as Number) as Void {
        var r = 8;

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);

        for (var i = 0; i < 2; i++) {
            var start = (phase + i * 180) % 360;
            var end = (start + 130) % 360;
            dc.drawArc(cx, cy, r, Graphics.ARC_COUNTER_CLOCKWISE, start, end);

            // Arrowhead on the leading end of each arc.
            var rad = Math.toRadians(end);
            var tx = cx + Math.round(r * Math.cos(rad)).toNumber();
            var ty = cy - Math.round(r * Math.sin(rad)).toNumber();
            var nx = Math.round(4 * Math.sin(rad)).toNumber();
            var ny = Math.round(4 * Math.cos(rad)).toNumber();
            dc.fillPolygon([
                [tx - nx, ty - ny],
                [tx + nx, ty + ny],
                [tx - ny * 2 - nx, ty + nx * 2 - ny]
            ] as Array<[Numeric, Numeric]>);
        }
    }

    // "History" mark for the recovery row: a clock face whose ring is broken on
    // the left, with an arrow pointing down out of the break.
    function recovery(dc as Graphics.Dc, cx as Number, cy as Number, color as Number) as Void {
        var r = 8;

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        // Clockwise from 190 back round to 215 leaves the gap on the left.
        dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, 190, 215);

        // Hands, pointing at 12 and roughly at 4.
        dc.drawLine(cx, cy, cx, cy - 5);
        dc.drawLine(cx, cy, cx + 4, cy + 3);

        // Arrowhead filling the gap, pointing down.
        dc.fillPolygon([
            [cx - r - 3, cy - 1],
            [cx - r + 3, cy - 1],
            [cx - r, cy + 5]
        ] as Array<[Numeric, Numeric]>);
    }
}
