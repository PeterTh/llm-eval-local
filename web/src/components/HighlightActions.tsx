import type { ReactNode } from "react";
import type { HighlightSelection } from "../state/highlights";

export function highlightColor(dark: boolean): string {
  return dark ? "#f2b861" : "#a85d00";
}

/** Keep selection controls alongside the existing export action in the panel heading. */
export function HighlightActions({ selection, children }: { selection: HighlightSelection; children: ReactNode }) {
  return (
    <div className="chart-actions">
      <button type="button" className="secondary-button highlight-mode" aria-label="Highlight mode"
        aria-pressed={selection.active} onClick={() => selection.setActive(!selection.active)}
        title={selection.active ? "Select points or rows to toggle highlights. Escape returns to normal navigation." : "Highlight mode: select points or rows instead of opening records."}>
        <span className="highlight-key" aria-hidden="true" />Highlight
      </button>
      {children}
      {selection.ids.length > 0 && <span className="highlight-summary">
        <span role="status">{selection.ids.length} highlighted{selection.hiddenCount > 0 && ` · ${selection.hiddenCount} not shown`}</span>
        <button type="button" className="highlight-clear" aria-label="Clear highlights" title="Clear highlights in this view" onClick={selection.clear}>×</button>
      </span>}
    </div>
  );
}

export function HighlightCheckbox({ selection, id, label }: { selection: HighlightSelection; id: string; label: string }) {
  return <input type="checkbox" className="highlight-checkbox" aria-label={`Highlight ${label}`}
    checked={selection.selected.has(id)} onChange={() => selection.toggle(id)} />;
}
