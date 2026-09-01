import Toybox.ActivityMonitor;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

class MindFaceView extends WatchUi.WatchFace {

    // Arc geometry, in degrees. 0 is 3 o'clock and angles grow anticlockwise.
    private const ARC_INSET = 5;
    private const ARC_WIDTH = 5;
    private const TOP_ARC_START = 140;
    private const TOP_ARC_END = 40;
    private const BOTTOM_ARC_START = 220;
    private const BOTTOM_ARC_END = 320;

    private const OUTLINE_WIDTH = 2;   // stroke of the hollow hour digits
    private const LOW_BATTERY_PCT = 10;
    private const TIME_WIDTH_RATIO = 0.92;   // how much width the time claims
    private const SEC_GAP_RATIO = 0.06;      // minutes-to-seconds gap, of font height
    private const SEC_SIZE_RATIO = 0.50;     // seconds height, of the big digits
    private const MIN_GAP_RATIO = 0.10;      // tightest hours-to-minutes gap
    private const MAX_GAP_RATIO = 0.22;      // widest hours-to-minutes gap
    private const GAP_RATIO = 0.015;         // gap between rows, of screen height
    private const TIME_GAP_RATIO = 0.006;    // tighter gap on either side of the time
    private const ICON_ROW_GAP = 10;         // battery / weekday / bluetooth spacing

    // Sizes for the date and the small labels, as a share of screen height.
    // These land between FONT_XTINY (21px) and FONT_TINY (29px), which the
    // bitmap ladder cannot do -- hence the vector face.
    private const DATE_SIZE_RATIO = 0.115;
    private const LABEL_SIZE_RATIO = 0.108;
    private const LABEL_FACE = "RobotoCondensedBold";

    // Vector faces the firmware carries. Index comes from the TimeFont setting,
    // and the order here must match the list in resources/settings/settings.xml.
    private const FACES = [
        "BionicBold",
        "PridiSemiBoldGarmin",
        "RobotoBlack",
        "RobotoCondensedBold",
        "RobotoCondensedRegularItalic"
    ] as Array<String>;

    // Geometry, filled in by onLayout.
    private var _w as Number = 260;
    private var _h as Number = 260;
    private var _cx as Number = 130;
    private var _cy as Number = 130;
    private var _arcRadius as Number = 125;
    private var _bbY as Number = 40;
    private var _dateY as Number = 66;
    private var _timeY as Number = 124;
    private var _iconsY as Number = 173;
    private var _recoveryY as Number = 204;

    private var _timeFont as Graphics.FontType = Graphics.FONT_NUMBER_HOT;
    private var _secFont as Graphics.FontType = Graphics.FONT_NUMBER_MILD;
    private var _dateFont as Graphics.FontType = Graphics.FONT_TINY;
    private var _labelFont as Graphics.FontType = Graphics.FONT_XTINY;
    private var _timeHeight as Number = 0;
    private var _timeDescent as Number = 0;
    private var _secHeight as Number = 0;
    private var _secDescent as Number = 0;
    private var _secWidth as Number = 0;

    // Clip rectangle for the seconds, recomputed on every full update.
    private var _secX as Number = 0;
    private var _secY as Number = 0;

    // Digits 0-9 pre-rendered side by side in cells of _secDigitW. The seconds
    // are repainted once a second all day, and that path is metered against the
    // device power budget, so it blits from here instead of rasterising the
    // vector face twice per tick.
    private var _secAtlas as Graphics.BufferedBitmap? = null;
    private var _secDigitW as Number = 0;

    // The hollow hours cost nine passes of the largest font on the face for a
    // picture that changes once an hour, so they are kept rendered here.
    private var _hourBuf as Graphics.BufferedBitmap? = null;
    private var _hourText as String = "";

    // Centre of the phone icon, recomputed on every full update.
    private var _phoneIconX as Number = 130;

    // Settings.
    private var _showSeconds as Boolean = true;
    private var _minuteColor as Number = Colors.RED;
    private var _faceIndex as Number = 0;

    private var _bodyBattery as Number? = null;
    private var _bodyBatteryMinute as Number = -1;
    private var _hasBodyBattery as Boolean = false;

    // Set when a setting that feeds onLayout changes, so the fonts get rebuilt
    // on the next update rather than only when the view is first laid out.
    private var _layoutDirty as Boolean = false;

    function initialize() {
        WatchFace.initialize();
        _hasBodyBattery = (Toybox has :SensorHistory)
            && (Toybox.SensorHistory has :getBodyBatteryHistory);
        loadSettings();
    }

    function loadSettings() as Void {
        _showSeconds = readBool("ShowSeconds", true);

        var color = readNumber("MinuteColor", Colors.RED);
        if (color != _minuteColor) {
            _minuteColor = color;
            _layoutDirty = true;      // the seconds atlas is drawn in this colour
        }

        var face = readNumber("TimeFont", 0);
        if (face < 0 || face >= FACES.size()) {
            face = 0;
        }
        if (face != _faceIndex) {
            _faceIndex = face;
            _layoutDirty = true;
        }
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _w = dc.getWidth();
        _h = dc.getHeight();
        _cx = _w / 2;
        _cy = _h / 2;
        _arcRadius = _cx - ARC_INSET;

        _timeY = _cy;                        // the time sits dead centre

        // Every row is separated by the same gap, so the rows are placed from
        // their own heights rather than from hand-picked fractions of the
        // screen. The same gap also keeps the outermost rows off the arcs.
        var gap = (_h * GAP_RATIO).toNumber();
        var timeGap = (_h * TIME_GAP_RATIO).toNumber();
        var edge = ARC_INSET + ARC_WIDTH + gap;

        _dateFont = vectorFont(dc, LABEL_FACE, (_h * DATE_SIZE_RATIO).toNumber(), Graphics.FONT_TINY);
        _labelFont = vectorFont(dc, LABEL_FACE, (_h * LABEL_SIZE_RATIO).toNumber(), Graphics.FONT_XTINY);

        var bbH = rowHeight(dc, _labelFont);
        var dateH = dc.getFontHeight(_dateFont);
        var iconsH = rowHeight(dc, _labelFont);
        var recoveryH = rowHeight(dc, _labelFont);

        // What is left for the digits once the neighbours and the gaps are
        // taken out, on whichever side is tighter -- doubled, because the time
        // is centred and so spends the same height above and below.
        var above = _timeY - edge - bbH - dateH - gap - timeGap;
        var below = (_h - edge) - _timeY - iconsH - recoveryH - gap - timeGap;
        var timeBudget = 2 * (above < below ? above : below);

        buildTimeFonts(dc, timeBudget);

        // Height is not the only limit: at this size a wide face can overrun
        // the panel, so if the row does not fit across, scale it back down.
        var available = (_w * TIME_WIDTH_RATIO).toNumber();
        var needed = timeRowWidth(dc);
        if (needed > available) {
            buildTimeFonts(dc, (timeBudget * available) / needed);
        }

        // Rows hang off the time, which may have ended up shorter than the
        // budget; measuring from the real height keeps the gaps equal either way.
        _dateY = _timeY - _timeHeight / 2 - timeGap - dateH / 2;
        _bbY = _dateY - dateH / 2 - gap - bbH / 2;
        _iconsY = _timeY + _timeHeight / 2 + timeGap + iconsH / 2;
        _recoveryY = _iconsY + iconsH / 2 + gap + recoveryH / 2;

        // Both caches are keyed to the fonts just picked, so they go stale here.
        _hourBuf = null;
        _hourText = "";
        buildSecondsAtlas();
    }

    // A row is as tall as the taller of its icon and its text.
    private function rowHeight(dc as Graphics.Dc, font as Graphics.FontType) as Number {
        var text = dc.getFontHeight(font);
        return text > Icons.ICON_H ? text : Icons.ICON_H;
    }

    function onShow() as Void {
    }

    // Nothing is drawn differently between power modes, and the system schedules
    // the next update on the mode change itself -- so asking for one here would
    // only repaint the frame that is already on the panel.
    function onExitSleep() as Void {
    }

    function onEnterSleep() as Void {
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }

        if (_layoutDirty) {
            onLayout(dc);
            _layoutDirty = false;
        }

        refreshBodyBattery(System.getClockTime().min);

        dc.setColor(Colors.BACKGROUND, Colors.BACKGROUND);
        dc.clear();

        drawTopArc(dc);
        drawBottomArc(dc);
        drawBodyBatteryRow(dc);
        drawDate(dc);
        drawTime(dc);
        drawIconRow(dc);
        drawRecoveryRow(dc);

        if (_showSeconds) {
            drawSeconds(dc);
        }
    }

    // Once per second in low power. Only the seconds may be touched here, and
    // only inside their clip -- going over the time budget makes the system
    // drop partial updates for this watch face entirely.
    function onPartialUpdate(dc as Graphics.Dc) as Void {
        if (_showSeconds) {
            // Atlas cells carry their own background, so only the text fallback
            // has to blank the old digits first.
            if (_secAtlas == null) {
                dc.setClip(_secX, _secY, _secWidth, _secHeight);
                dc.setColor(Colors.BACKGROUND, Colors.BACKGROUND);
                dc.clear();
            }
            drawSeconds(dc);
            dc.clearClip();
        }

        if (phoneSyncing()) {
            dc.setClip(_phoneIconX - Icons.ICON_W / 2, _iconsY - Icons.ICON_H / 2,
                Icons.ICON_W, Icons.ICON_H);
            dc.setColor(Colors.BACKGROUND, Colors.BACKGROUND);
            dc.clear();
            drawPhoneIcon(dc);
            dc.clearClip();
        }
    }

    // -- drawing ------------------------------------------------------------

    private function drawTopArc(dc as Graphics.Dc) as Void {
        var bb = _bodyBattery;
        drawGauge(dc, Graphics.ARC_CLOCKWISE, TOP_ARC_START, TOP_ARC_END,
            bb == null ? 0.0 : bb / 100.0, Colors.BLUE);
    }

    private function drawBottomArc(dc as Graphics.Dc) as Void {
        var stress = stressScore();
        drawGauge(dc, Graphics.ARC_COUNTER_CLOCKWISE, BOTTOM_ARC_START, BOTTOM_ARC_END,
            stress == null ? 0.0 : stress / 100.0, Colors.RED);
    }

    private function drawGauge(dc as Graphics.Dc, direction as Graphics.ArcDirection, startDeg as Number, endDeg as Number, fraction as Float, color as Number) as Void {
        dc.setPenWidth(ARC_WIDTH);
        dc.setColor(Colors.ARC_EMPTY, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(_cx, _cy, _arcRadius, direction, startDeg, endDeg);

        if (fraction <= 0.0) {
            return;
        }
        if (fraction > 1.0) {
            fraction = 1.0;
        }

        // Clockwise arcs run from a larger angle down to a smaller one.
        var sweep = (endDeg - startDeg) * fraction;
        var filledEnd = (startDeg + sweep).toNumber();
        if (filledEnd == startDeg) {
            return;
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(_cx, _cy, _arcRadius, direction, startDeg, filledEnd);
    }

    private function drawBodyBatteryRow(dc as Graphics.Dc) as Void {
        var bb = _bodyBattery;
        var text = bb == null ? "--" : bb.format("%d");
        var textW = dc.getTextWidthInPixels(text, _labelFont);
        var total = Icons.ICON_W + 4 + textW;
        var left = _cx - total / 2;

        Icons.bodyBattery(dc, left + Icons.ICON_W / 2, _bbY, Colors.TEXT);

        dc.setColor(Colors.TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(left + Icons.ICON_W + 4, _bbY, _labelFont, text,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawDate(dc as Graphics.Dc) as Void {
        var now = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var text = Lang.format("$1$.$2$.$3$", [
            now.day.format("%02d"),
            now.month.format("%02d"),
            (now.year % 100).format("%02d")
        ]);

        dc.setColor(Colors.TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _dateY, _dateFont, text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawTime(dc as Graphics.Dc) as Void {
        // Always 24-hour with a leading zero, regardless of the device setting
        // -- same reason the date is dd.mm.yy: that is the format wanted here.
        var clock = System.getClockTime();
        var hh = clock.hour.format("%02d");
        var mm = clock.min.format("%02d");

        var wHH = dc.getTextWidthInPixels(hh, _timeFont);
        var wMM = dc.getTextWidthInPixels(mm, _timeFont);

        // No colon. Hours, minutes and seconds are spread until the whole group
        // spans TIME_WIDTH_RATIO of the panel; whatever width the digits do not
        // use becomes the gap between hours and minutes. The seconds stay
        // tucked up against the minutes so the group reads as one block.
        var secGap = (_timeHeight * SEC_GAP_RATIO).toNumber();
        var secPart = _showSeconds ? secGap + _secWidth : 0;

        var gap = (_w * TIME_WIDTH_RATIO).toNumber() - wHH - wMM - secPart;
        var minGap = (_timeHeight * MIN_GAP_RATIO).toNumber();
        var maxGap = (_timeHeight * MAX_GAP_RATIO).toNumber();
        if (gap < minGap) {
            gap = minGap;
        } else if (gap > maxGap) {
            // Otherwise a smaller font leaves so much slack that the hours and
            // the minutes stop reading as one time.
            gap = maxGap;
        }

        var left = _cx - (wHH + gap + wMM + secPart) / 2;
        var secX = left + wHH + gap + wMM + secGap;

        drawHours(dc, left, hh, wHH);

        dc.setColor(_minuteColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(left + wHH + gap, _timeY, _timeFont, mm,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        // Seconds share the baseline of the big digits, so hours, minutes and
        // seconds all end flush at the bottom.
        var baseline = _timeY + _timeHeight / 2 - _timeDescent;
        _secX = secX;
        _secY = baseline + _secDescent - _secHeight;
    }

    // Hours: hollow, drawn as a ring of offset copies with the interior punched
    // back out in the background colour. That is nine passes of the largest
    // font on the face, so it is kept in a buffer and re-rendered on the hour.
    private function drawHours(dc as Graphics.Dc, left as Number, hh as String, wHH as Number) as Void {
        var t = OUTLINE_WIDTH;

        // The width follows from the font and the string, and onLayout clears
        // _hourText whenever the fonts change, so the hour alone keys the cache.
        if (!hh.equals(_hourText)) {
            buildHourBuffer(hh, wHH + 2 * t);
        }

        var buf = _hourBuf;
        if (buf == null) {
            drawOutlinedText(dc, left, _timeY, _timeFont, hh, Colors.TEXT);
            return;
        }
        dc.drawBitmap(left - t, _timeY - _timeHeight / 2 - t, buf);
    }

    private function buildHourBuffer(hh as String, width as Number) as Void {
        // Recorded even when the buffer cannot be had, so a device without them
        // is not asked again on every frame -- only when the hour changes.
        _hourText = hh;

        var t = OUTLINE_WIDTH;
        var height = _timeHeight + 2 * t;
        var buffer = newBuffer(width, height);
        _hourBuf = buffer;
        if (buffer == null) {
            return;
        }

        var bufDc = buffer.getDc();
        if (bufDc has :setAntiAlias) {
            bufDc.setAntiAlias(true);
        }
        bufDc.setColor(Colors.BACKGROUND, Colors.BACKGROUND);
        bufDc.clear();
        drawOutlinedText(bufDc, t, height / 2, _timeFont, hh, Colors.TEXT);
    }

    private function drawSeconds(dc as Graphics.Dc) as Void {
        var sec = System.getClockTime().sec;
        var atlas = _secAtlas;

        if (atlas == null) {
            dc.setColor(_minuteColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_secX, _secY, _secFont, sec.format("%02d"), Graphics.TEXT_JUSTIFY_LEFT);
            return;
        }

        drawDigit(dc, _secX, sec / 10, atlas);
        drawDigit(dc, _secX + _secDigitW, sec % 10, atlas);

        // Each digit clips to its own cell, so the clip has to be dropped again
        // -- the full update clears the whole screen right after this.
        dc.clearClip();
    }

    // One cell of the atlas: clip to where the digit belongs on screen, then
    // slide the whole strip so that the wanted cell lands inside the clip.
    private function drawDigit(dc as Graphics.Dc, x as Number, digit as Number, atlas as Graphics.BufferedBitmap) as Void {
        dc.setClip(x, _secY, _secDigitW, _secHeight);
        dc.drawBitmap(x - digit * _secDigitW, _secY, atlas);
    }

    private function buildSecondsAtlas() as Void {
        _secAtlas = null;

        _secDigitW = _secWidth / 2;
        // Keep the measured width in step with the cells, so the layout and the
        // clip agree on where the seconds end.
        _secWidth = _secDigitW * 2;

        var atlas = newBuffer(_secDigitW * 10, _secHeight);
        if (atlas == null) {
            return;
        }

        var bufDc = atlas.getDc();
        if (bufDc has :setAntiAlias) {
            bufDc.setAntiAlias(true);
        }
        bufDc.setColor(Colors.BACKGROUND, Colors.BACKGROUND);
        bufDc.clear();
        bufDc.setColor(_minuteColor, Graphics.COLOR_TRANSPARENT);

        // Centred in its own cell: the cells are a fixed width, so a digit must
        // not be placed by its own advance width.
        for (var d = 0; d < 10; d++) {
            bufDc.drawText(d * _secDigitW + _secDigitW / 2, 0, _secFont, d.toString(),
                Graphics.TEXT_JUSTIFY_CENTER);
        }
        _secAtlas = atlas;
    }

    // Buffers are drawn into off the hot paths and live in the device graphics
    // pool rather than the app heap. A device without them, or a pool with no
    // room left, just leaves the caller drawing directly.
    private function newBuffer(width as Number, height as Number) as Graphics.BufferedBitmap? {
        if (width <= 0 || height <= 0) {
            return null;
        }

        var options = { :width => width, :height => height };
        try {
            if (Graphics has :createBufferedBitmap) {
                return Graphics.createBufferedBitmap(options).get() as Graphics.BufferedBitmap?;
            }
            if (Graphics has :BufferedBitmap) {
                return new Graphics.BufferedBitmap(options);
            }
        } catch (ex) {
            return null;
        }
        return null;
    }

    private function drawOutlinedText(dc as Graphics.Dc, x as Number, y as Number, font as Graphics.FontType, text as String, color as Number) as Void {
        var justify = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        var t = OUTLINE_WIDTH;

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        for (var dx = -t; dx <= t; dx += t) {
            for (var dy = -t; dy <= t; dy += t) {
                if (dx != 0 || dy != 0) {
                    dc.drawText(x + dx, y + dy, font, text, justify);
                }
            }
        }

        dc.setColor(Colors.BACKGROUND, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, text, justify);
    }

    private function drawIconRow(dc as Graphics.Dc) as Void {
        var pct = System.getSystemStats().battery;
        var fillColor = pct < LOW_BATTERY_PCT ? Colors.LOW : Colors.GREEN;

        var weekday = weekdayName(Gregorian.info(Time.now(), Time.FORMAT_SHORT).day_of_week);
        var textW = dc.getTextWidthInPixels(weekday, _labelFont);

        // Laid out left to right by inked width, so the two gaps come out equal.
        var gap = ICON_ROW_GAP;
        var total = Icons.BATTERY_W + gap + textW + gap + Icons.BLUETOOTH_W;
        var x = _cx - total / 2;

        Icons.battery(dc, x + Icons.BATTERY_LEFT, _iconsY, Colors.TEXT, fillColor, pct / 100.0);
        x += Icons.BATTERY_W + gap;

        dc.setColor(Colors.TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, _iconsY, _labelFont, weekday,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        x += textW + gap;

        _phoneIconX = x + Icons.BLUETOOTH_LEFT;
        drawPhoneIcon(dc);

        // TODO: headphone-connection icon once a source for it is settled --
        // Connect IQ exposes no API for the paired audio device.
    }

    private function drawPhoneIcon(dc as Graphics.Dc) as Void {
        if (phoneSyncing()) {
            // Spun by the wall clock so the arrows turn once per second while
            // the seconds are being repainted anyway.
            var phase = (System.getClockTime().sec * 30) % 360;
            Icons.syncArrows(dc, _phoneIconX, _iconsY, Colors.TEXT, phase);
        } else {
            var connected = System.getDeviceSettings().phoneConnected;
            Icons.bluetooth(dc, _phoneIconX, _iconsY,
                connected ? Colors.TEXT : Colors.ARC_EMPTY);
        }
    }

    // Deliberately not localised: these stay English whatever the watch
    // language is, the same way the date stays dd.mm.yy.
    private function weekdayName(dayOfWeek as Number) as String {
        var names = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"] as Array<String>;
        return names[(dayOfWeek - 1) % 7];
    }

    // Connect IQ has no API for "the watch is syncing with Garmin Connect right
    // now" -- DeviceSettings only reports whether a phone is connected, and
    // Communications.SyncDelegate covers an app's own sync, not the system one.
    // The spinning-arrows state is wired up and ready for a source to appear.
    private function phoneSyncing() as Boolean {
        return false;
    }

    private function drawRecoveryRow(dc as Graphics.Dc) as Void {
        var info = ActivityMonitor.getInfo();
        if (!(info has :timeToRecovery) || info.timeToRecovery == null) {
            return;
        }

        var hours = info.timeToRecovery as Number;
        var text = hours.format("%d") + WatchUi.loadResource(Rez.Strings.HourShort);
        var textW = dc.getTextWidthInPixels(text, _labelFont);
        var total = Icons.ICON_W + 4 + textW;
        var left = _cx - total / 2;

        Icons.recovery(dc, left + Icons.ICON_W / 2, _recoveryY, Colors.TEXT);

        dc.setColor(Colors.TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(left + Icons.ICON_W + 4, _recoveryY, _labelFont, text,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // -- data ---------------------------------------------------------------

    // Hold the last good value: the history can come back empty for a poll or
    // two, and without this the reading blinks out. Body Battery moves on a
    // scale of minutes, while onUpdate runs every second whenever the wrist is
    // raised, so the history is only opened when the minute turns.
    private function refreshBodyBattery(minute as Number) as Void {
        if (minute == _bodyBatteryMinute) {
            return;
        }
        _bodyBatteryMinute = minute;

        var value = readBodyBattery();
        if (value != null) {
            _bodyBattery = value;
        }
    }

    private function readBodyBattery() as Number? {
        if (!_hasBodyBattery) {
            return null;
        }
        var iterator = Toybox.SensorHistory.getBodyBatteryHistory({
            :period => 4,
            :order => Toybox.SensorHistory.ORDER_NEWEST_FIRST
        });
        if (iterator == null) {
            return null;
        }

        // The newest sample can carry no data while the watch is writing
        // history, so fall back through the few behind it.
        for (var i = 0; i < 4; i++) {
            var sample = iterator.next();
            if (sample == null) {
                return null;
            }
            if (sample.data != null) {
                return sample.data.toNumber();
            }
        }
        return null;
    }

    private function stressScore() as Number? {
        var info = ActivityMonitor.getInfo();
        if (!(info has :stressScore) || info.stressScore == null) {
            return null;
        }
        return info.stressScore as Number;
    }

    // -- helpers ------------------------------------------------------------

    // Pick the time and seconds fonts for a given digit height, and cache the
    // metrics the layout needs.
    private function buildTimeFonts(dc as Graphics.Dc, budget as Number) as Void {
        _timeFont = timeFace(dc, budget, Graphics.FONT_NUMBER_HOT);
        _timeHeight = dc.getFontHeight(_timeFont);
        _timeDescent = Graphics.getFontDescent(_timeFont);

        _secFont = timeFace(dc, (_timeHeight * SEC_SIZE_RATIO).toNumber(), Graphics.FONT_XTINY);
        _secHeight = dc.getFontHeight(_secFont);
        _secDescent = Graphics.getFontDescent(_secFont);
        _secWidth = dc.getTextWidthInPixels("00", _secFont);
    }

    // Width of the whole time row at its tightest: both pairs of digits, the
    // smallest gap between them, and the seconds with their own gap.
    private function timeRowWidth(dc as Graphics.Dc) as Number {
        var digits = 2 * dc.getTextWidthInPixels("00", _timeFont);
        var gaps = (_timeHeight * MIN_GAP_RATIO).toNumber();
        if (_showSeconds) {
            gaps += (_timeHeight * SEC_GAP_RATIO).toNumber();
            return digits + gaps + _secWidth;
        }
        return digits + gaps;
    }

    private function timeFace(dc as Graphics.Dc, budget as Number, fallback as Graphics.FontType) as Graphics.FontType {
        return vectorFont(dc, FACES[_faceIndex], budget, fallback);
    }

    // Vector faces can be sized to the pixel, which is the only way to land
    // between the fixed steps of the bitmap font ladder. Devices without vector
    // fonts fall back to the nearest bitmap size -- still a working watch face.
    private function vectorFont(dc as Graphics.Dc, face as String, budget as Number, fallback as Graphics.FontType) as Graphics.FontType {
        if (!(Graphics has :getVectorFont)) {
            return fallback;
        }

        var font = Graphics.getVectorFont({ :face => face, :size => budget });
        if (font == null) {
            return fallback;
        }

        // The requested size is an em size, so the rendered height overshoots
        // the budget; ask again at the scaled-down size.
        var height = dc.getFontHeight(font);
        if (height > budget) {
            var scaled = (budget * budget) / height;
            var refit = Graphics.getVectorFont({ :face => face, :size => scaled });
            if (refit != null) {
                font = refit;
            }
        }
        return font;
    }

    private function readBool(key as String, fallback as Boolean) as Boolean {
        var value = Application.Properties.getValue(key);
        return value instanceof Lang.Boolean ? value : fallback;
    }

    private function readNumber(key as String, fallback as Number) as Number {
        var value = Application.Properties.getValue(key);
        return value instanceof Lang.Number ? value : fallback;
    }
}
