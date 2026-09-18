import QtQuick
import qs.Common

// The circular utilisation indicator, drawn in the taskbar Pill. Geometry is
// passed in rather than derived, because the Pill's rings can differ in size.
// The Popout draws Windows as bars, not rings.
Canvas {
    id: ring

    property real percent: 0
    property var pace: null
    property bool showPaceTick: false
    // False when there is no current reading to draw (missing credentials, or an
    // unavailable endpoint). The track still draws, so the Source keeps its slot,
    // but no arc and no pace tick, so no fabricated value is shown.
    property bool hasReading: true
    property real ringRadius: width * 0.375
    property real ringWidth: width * 0.125

    renderStrategy: Canvas.Cooperative
    onPercentChanged: requestPaint()
    onPaceChanged: requestPaint()
    onWidthChanged: requestPaint()
    onShowPaceTickChanged: requestPaint()
    onHasReadingChanged: requestPaint()

    function progressColor(pct) {
        if (pct > 80)
            return Theme.error;
        if (pct > 50)
            return Theme.warning;
        return Theme.primary;
    }

    // The pace tick is a short radial mark at the linear-burn position.
    function drawPaceTick(ctx, cx, cy, r, lw, p) {
        if (!showPaceTick || !p || p.status === "unknown")
            return;
        var a = -Math.PI / 2 + 2 * Math.PI * Math.min(Math.max(p.timeFrac, 0), 1);
        var ri = r - lw / 2 - 1, ro = r + lw / 2 + 1;
        ctx.beginPath();
        ctx.moveTo(cx + ri * Math.cos(a), cy + ri * Math.sin(a));
        ctx.lineTo(cx + ro * Math.cos(a), cy + ro * Math.sin(a));
        ctx.lineWidth = 2;
        ctx.lineCap = "butt";
        ctx.strokeStyle = Theme.surfaceText;
        ctx.stroke();
    }

    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();
        var cx = width / 2, cy = height / 2;
        var r = ringRadius, lw = ringWidth;

        ctx.beginPath();
        ctx.arc(cx, cy, r, 0, 2 * Math.PI);
        ctx.lineWidth = lw;
        ctx.strokeStyle = Theme.surfaceVariant;
        ctx.stroke();

        var pct = percent / 100;
        if (hasReading && pct > 0) {
            ctx.beginPath();
            ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * Math.min(pct, 1));
            ctx.lineWidth = lw;
            ctx.strokeStyle = progressColor(percent);
            ctx.lineCap = "round";
            ctx.stroke();
        }

        if (hasReading)
            drawPaceTick(ctx, cx, cy, r, lw, pace);
    }
}
