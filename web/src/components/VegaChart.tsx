import { useEffect, useRef } from "react";
import type { VisualizationSpec } from "vega-embed";

export function VegaChart({
  spec,
  ariaLabel,
  onDatumClick,
  interactiveMarkSelector,
  fitContainerWidth = false,
}: {
  spec: VisualizationSpec;
  ariaLabel: string;
  onDatumClick?: (datum: Record<string, unknown>) => void;
  interactiveMarkSelector?: string;
  fitContainerWidth?: boolean;
}) {
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;
    let disposed = false;
    let resizeObserver: ResizeObserver | null = null;
    let finalize: (() => void) | null = null;

    const initialWidth = Math.max(280, container.clientWidth - 32);
    const embeddedSpec = fitContainerWidth ? { ...spec, width: initialWidth } as VisualizationSpec : spec;
    void import("vega-embed").then(({ default: vegaEmbed }) => vegaEmbed(container, embeddedSpec, {
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
      if (interactiveMarkSelector) {
        container.querySelectorAll<SVGElement>(interactiveMarkSelector).forEach((mark) => {
          mark.classList.add("interactive-chart-mark");
          mark.setAttribute("role", "button");
          mark.setAttribute("tabindex", "0");
          mark.setAttribute("aria-keyshortcuts", "Enter Space");
          mark.addEventListener("keydown", (event) => {
            if (event.key === "Enter" || event.key === " ") {
              event.preventDefault();
              const sceneItem = (mark as SVGElement & { __data__?: { datum?: unknown } }).__data__;
              if (onDatumClick && sceneItem?.datum && typeof sceneItem.datum === "object") {
                onDatumClick(sceneItem.datum as Record<string, unknown>);
              } else {
                mark.dispatchEvent(new MouseEvent("click", { bubbles: true, view: window }));
              }
            }
          });
        });
      }
      let responsiveWidth = initialWidth;
      resizeObserver = new ResizeObserver(() => {
        if (fitContainerWidth) {
          const nextWidth = Math.max(280, container.clientWidth - 32);
          if (nextWidth !== responsiveWidth) {
            responsiveWidth = nextWidth;
            result.view.width(nextWidth);
          }
        }
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
  }, [fitContainerWidth, interactiveMarkSelector, onDatumClick, spec]);

  return <div ref={containerRef} className="chart" role={interactiveMarkSelector ? "region" : "img"} aria-label={ariaLabel} />;
}
