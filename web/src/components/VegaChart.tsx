import { useEffect, useRef } from "react";
import type { VisualizationSpec } from "vega-embed";

export function VegaChart({
  spec,
  ariaLabel,
  onDatumClick,
}: {
  spec: VisualizationSpec;
  ariaLabel: string;
  onDatumClick?: (datum: Record<string, unknown>) => void;
}) {
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;
    let disposed = false;
    let resizeObserver: ResizeObserver | null = null;
    let finalize: (() => void) | null = null;

    void import("vega-embed").then(({ default: vegaEmbed }) => vegaEmbed(container, spec, {
        renderer: "svg",
        actions: {
          export: { svg: true, png: true },
          source: false,
          compiled: false,
          editor: false,
        },
        tooltip: true,
      })).then((result) => {
      if (disposed) {
        result.finalize();
        return;
      }
      finalize = result.finalize;
      const actionSummary = container.querySelector<HTMLElement>(".vega-embed details > summary");
      actionSummary?.setAttribute("aria-label", "Export chart");
      actionSummary?.setAttribute("title", "Export chart");
      if (onDatumClick) {
        result.view.addEventListener("click", (_event, item) => {
          if (item?.datum && typeof item.datum === "object") {
            onDatumClick(item.datum as Record<string, unknown>);
          }
        });
      }
      resizeObserver = new ResizeObserver(() => {
        void result.view.resize().runAsync();
      });
      resizeObserver.observe(container);
    });

    return () => {
      disposed = true;
      resizeObserver?.disconnect();
      finalize?.();
      container.replaceChildren();
    };
  }, [onDatumClick, spec]);

  return <div ref={containerRef} className="chart" role="img" aria-label={ariaLabel} />;
}
