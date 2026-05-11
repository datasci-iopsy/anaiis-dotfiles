# Render a ggplot2 object to a self-contained HTML file via plotly or htmlwidgets.
#
# Usage (from within an R script that has a ggplot object named `p`):
#   source("render.R")
#   render_to_html(p, title = "My Chart", out = "index.html")
#
# Or run standalone to verify the template works:
#   Rscript render.R

render_to_html <- function(plot_obj, title = "Chart", out = "index.html") {
    if (!requireNamespace("htmlwidgets", quietly = TRUE)) {
        stop("htmlwidgets is required: install.packages('htmlwidgets')")
    }

    if (inherits(plot_obj, "gg")) {
        if (!requireNamespace("plotly", quietly = TRUE)) {
            stop("plotly is required for ggplot2 objects: install.packages('plotly')")
        }
        widget <- plotly::ggplotly(plot_obj)
    } else if (inherits(plot_obj, "plotly")) {
        widget <- plot_obj
    } else if (inherits(plot_obj, "htmlwidget")) {
        widget <- plot_obj
    } else {
        stop("Unsupported plot type. Pass a ggplot2, plotly, or htmlwidget object.")
    }

    htmlwidgets::saveWidget(widget, file = out, selfcontained = TRUE, title = title)
    size <- file.info(out)$size
    message(sprintf("wrote %s (%s bytes)", out, format(size, big.mark = ",")))
    invisible(out)
}

# Standalone smoke test: renders a minimal chart to verify the setup works.
if (!interactive() && identical(commandArgs(trailingOnly = FALSE)[1], "--vanilla") ||
        (!interactive() && !exists(".render_sourced"))) {
    if (!requireNamespace("ggplot2", quietly = TRUE)) {
        message("ggplot2 not available; skipping smoke render")
        quit(status = 0)
    }
    p <- ggplot2::ggplot(
        data.frame(x = 1:5, y = c(2, 4, 1, 5, 3)),
        ggplot2::aes(x = x, y = y)
    ) +
        ggplot2::geom_line() +
        ggplot2::geom_point() +
        ggplot2::labs(title = "Smoke test", x = "X", y = "Y")
    render_to_html(p, title = "Smoke test", out = "index.html")
}
