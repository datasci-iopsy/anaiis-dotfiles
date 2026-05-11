/**
 * Hydrates .chart-mount divs with Plotly figures.
 *
 * Two modes (checked per div):
 *   - Inline: reads from <script type="application/json" id="fig-<id>"> (single-file output)
 *   - External: fetches data-fig attribute URL (multi-file served output)
 *
 * Sets data-plotly-rendered="true" on the div after successful render.
 * Sets data-plotly-error="<message>" on failure so tests can distinguish render errors.
 */
(function () {
    "use strict";

    function renderChart(div) {
        var id = div.id.replace(/^chart-/, "");
        var inlineEl = document.getElementById("fig-" + id);

        var promise;
        if (inlineEl) {
            promise = Promise.resolve(JSON.parse(inlineEl.textContent));
        } else {
            var figUrl = div.getAttribute("data-fig");
            if (!figUrl) {
                div.setAttribute("data-plotly-error", "no data-fig attribute and no inline fig-" + id);
                return;
            }
            promise = fetch(figUrl).then(function (r) {
                if (!r.ok) throw new Error("HTTP " + r.status + " fetching " + figUrl);
                return r.json();
            });
        }

        promise
            .then(function (fig) {
                return Plotly.newPlot(div, fig.data, fig.layout, { responsive: true });
            })
            .then(function () {
                div.setAttribute("data-plotly-rendered", "true");
            })
            .catch(function (err) {
                div.setAttribute("data-plotly-error", String(err));
                console.error("[bootstrap] chart " + id + " failed:", err);
            });
    }

    document.addEventListener("DOMContentLoaded", function () {
        var mounts = document.querySelectorAll(".chart-mount");
        Array.prototype.forEach.call(mounts, renderChart);
    });
})();
