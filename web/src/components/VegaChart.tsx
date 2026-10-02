import { useEffect, useRef } from "react";
import type { VisualizationSpec } from "vega-embed";
import type { HighlightSelection } from "../state/highlights";

export interface ChartHighlight {
  selection: HighlightSelection;
  markSelector: string;
  getId: (datum: Record<string, unknown>) => string | null;
}

function markDatum(mark: Element): Record<string, unknown> | null {
  const item = (mark as SVGElement & { __data__?: { datum?: unknown; text?: unknown } }).__data__;
  const datum = item?.datum;
  return datum && typeof datum === "object" ? { ...datum, chartLabel: item?.text } : null;
}

export function VegaChart({
  spec,
  ariaLabel,
  onDatumClick,
  interactiveMarkSelector,
  fitContainerWidth = false,
  highlight,
}: {
  spec: VisualizationSpec;
  ariaLabel: string;
  onDatumClick?: (datum: Record<string, unknown>) => void;
  interactiveMarkSelector?: string;
  fitContainerWidth?: boolean;
  highlight?: ChartHighlight;
}) {
  const containerRef = useRef<HTMLDivElement>(null);
  const interaction = useRef({ onDatumClick, interactiveMarkSelector, highlight });
  interaction.current = { onDatumClick, interactiveMarkSelector, highlight };
  const syncInteractions = useRef<(() => void) | null>(null);
  const pendingFocus = useRef<{ id: string; tag: string } | null>(null);

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;
    let disposed = false;
    let resizeObserver: ResizeObserver | null = null;
    let finalize: (() => void) | null = null;
    let removeSelectionClick: (() => void) | null = null;

    const initialWidth = Math.max(280, container.clientWidth - 32);
    const embeddedSpec = fitContainerWidth ? { ...spec, width: initialWidth } as VisualizationSpec : spec;
    // Label layout caches text measurements, so wait for the actual chart font.
    void Promise.all([import("vega-embed"), document.fonts.ready]).then(([{ default: vegaEmbed }]) => {
      if (disposed) return null;
      return vegaEmbed(container, embeddedSpec, {
        renderer: "svg",
        actions: {
          export: { svg: true, png: true },
          source: false,
          compiled: false,
          editor: false,
        },
        tooltip: true,
        patch: (compiled) => {
          const visit = (marks: NonNullable<typeof compiled.marks>) => {
            for (const mark of marks) {
              if (mark.name?.includes("_highlight_")) mark.interactive = false;
              if (mark.type === "group" && mark.marks) visit(mark.marks);
            }
          };
          visit(compiled.marks ?? []);
          return compiled;
        },
      });
    }).then((result) => {
      if (!result) return;
      if (disposed) {
        result.finalize();
        return;
      }
      finalize = result.finalize;
      const actionSummary = container.querySelector<HTMLElement>(".vega-embed details > summary");
      actionSummary?.setAttribute("aria-label", "Export chart");
      actionSummary?.setAttribute("title", "Export chart");
      const activate = (datum: Record<string, unknown>) => {
        const current = interaction.current;
        if (current.highlight?.selection.active) {
          const id = current.highlight.getId(datum);
          if (id !== null) current.highlight.selection.toggle(id);
        } else current.onDatumClick?.(datum);
      };
      result.view.addEventListener("click", (_event, item) => {
        if (item?.datum && typeof item.datum === "object") activate(item.datum as Record<string, unknown>);
      });
      // Header labels can be non-interactive Vega marks. Enable the same selection
      // action on these explicit DOM targets without also firing Vega's navigation.
      const selectionClick = (event: MouseEvent) => {
        const current = interaction.current.highlight;
        if (!current?.selection.active || !(event.target instanceof Element)) return;
        const mark = event.target.closest(current.markSelector);
        if (!mark || !container.contains(mark)) return;
        const datum = markDatum(mark);
        const id = datum && current.getId(datum);
        if (id === null) return;
        event.preventDefault();
        event.stopPropagation();
        current.selection.toggle(id);
      };
      container.addEventListener("click", selectionClick, true);
      removeSelectionClick = () => container.removeEventListener("click", selectionClick, true);
      const sync = () => {
        const current = interaction.current;
        const selection = current.highlight?.selection;
        container.querySelectorAll<SVGElement>(".interactive-chart-mark").forEach((mark) => {
          mark.classList.remove("interactive-chart-mark");
          for (const attribute of ["role", "tabindex", "aria-keyshortcuts", "aria-pressed"]) mark.removeAttribute(attribute);
          mark.onkeydown = null;
        });
        if (current.highlight) {
          container.querySelectorAll<SVGElement>(current.highlight.markSelector).forEach((mark) => {
            const datum = markDatum(mark);
            const id = datum && current.highlight!.getId(datum);
            if (id === null) return;
            mark.dataset.highlightId = id;
            mark.style.pointerEvents = selection!.active ? "all" : "";
            const label = (mark.getAttribute("aria-label") ?? mark.textContent ?? "").replace(/; Highlighted: (Yes|No)$/, "");
            mark.setAttribute("aria-label", `${label}; Highlighted: ${selection!.selected.has(id) ? "Yes" : "No"}`);
          });
        }
        const selector = selection?.active ? current.highlight!.markSelector : current.interactiveMarkSelector;
        if (selector) container.querySelectorAll<SVGElement>(selector).forEach((mark) => {
          const datum = markDatum(mark);
          const id = datum && current.highlight?.getId(datum);
          if (selection?.active && id == null) return;
          mark.classList.add("interactive-chart-mark");
          mark.setAttribute("role", "button");
          mark.setAttribute("tabindex", "0");
          mark.setAttribute("aria-keyshortcuts", "Enter Space");
          if (selection?.active && id != null) mark.setAttribute("aria-pressed", String(selection.selected.has(id)));
          mark.onkeydown = (event) => {
            if (event.key === "Enter" || event.key === " ") {
              event.preventDefault();
              const datum = markDatum(mark);
              if (datum) activate(datum);
            }
          };
        });
      };
      syncInteractions.current = sync;
      sync();
      if (pendingFocus.current !== null) {
        const target = [...container.querySelectorAll<SVGElement>("[data-highlight-id]")]
          .find((mark) => mark.dataset.highlightId === pendingFocus.current!.id
            && mark.tagName === pendingFocus.current!.tag && mark.hasAttribute("tabindex"));
        target?.focus({ preventScroll: true });
        pendingFocus.current = null;
      }
      container.style.minHeight = "";
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
      const focused = document.activeElement;
      if (focused instanceof SVGElement && container.contains(focused)) {
        pendingFocus.current = focused.dataset.highlightId ? { id: focused.dataset.highlightId, tag: focused.tagName } : null;
      }
      // Keep the document height stable while the replacement chart initializes.
      container.style.minHeight = `${container.offsetHeight}px`;
      syncInteractions.current = null;
      resizeObserver?.disconnect();
      removeSelectionClick?.();
      finalize?.();
      container.replaceChildren();
    };
  }, [fitContainerWidth, spec]);

  useEffect(() => { syncInteractions.current?.(); }, [highlight, interactiveMarkSelector]);

  return <div ref={containerRef} className={`chart${highlight?.selection.active ? " highlight-active" : ""}`} role={interactiveMarkSelector || highlight ? "region" : "img"} aria-label={ariaLabel} />;
}
