import { useEffect, useMemo, useRef, useState } from "react";

import type { EntityMetadata } from "../data/types";

export function FilterMenu({
  label,
  entities,
  selected,
  onChange,
}: {
  label: string;
  entities: EntityMetadata[];
  selected: readonly string[];
  onChange: (values: string[]) => void;
}) {
  const [query, setQuery] = useState("");
  const menuRef = useRef<HTMLDetailsElement>(null);
  const selectedSet = useMemo(() => new Set(selected), [selected]);
  const visible = entities.filter((entity) =>
    entity.label.toLocaleLowerCase().includes(query.trim().toLocaleLowerCase())
    || entity.id.toLocaleLowerCase().includes(query.trim().toLocaleLowerCase()));
  const summary = selected.length === 0
    ? `All ${label.toLocaleLowerCase()}`
    : selected.length === 1
      ? entities.find((entity) => entity.id === selected[0])?.label ?? selected[0]
      : `${selected.length} ${label.toLocaleLowerCase()}`;

  useEffect(() => {
    function closeOnOutsidePointer(event: PointerEvent) {
      const menu = menuRef.current;
      if (menu?.open && event.target instanceof Node && !menu.contains(event.target)) {
        menu.open = false;
      }
    }

    function closeOnEscape(event: KeyboardEvent) {
      const menu = menuRef.current;
      if (event.key === "Escape" && menu?.open) {
        menu.open = false;
        menu.querySelector<HTMLElement>("summary")?.focus();
      }
    }

    document.addEventListener("pointerdown", closeOnOutsidePointer);
    document.addEventListener("keydown", closeOnEscape);
    return () => {
      document.removeEventListener("pointerdown", closeOnOutsidePointer);
      document.removeEventListener("keydown", closeOnEscape);
    };
  }, []);

  return (
    <details ref={menuRef} className="filter-menu">
      <summary>
        <span>{label}</span>
        <strong>{summary}</strong>
      </summary>
      <div className="filter-popover">
        {entities.length > 8 && (
          <label className="search-field compact-search">
            <span className="sr-only">Search {label.toLocaleLowerCase()}</span>
            <input value={query} onChange={(event) => setQuery(event.target.value)} placeholder={`Find ${label.toLocaleLowerCase()}…`} />
          </label>
        )}
        <div className="filter-actions">
          <button type="button" onClick={() => onChange([])}>All</button>
          <button type="button" onClick={() => onChange(entities.map((entity) => entity.id))}>Select all</button>
        </div>
        <div className="filter-options">
          {visible.map((entity) => (
            <label key={entity.id}>
              <input
                type="checkbox"
                checked={selectedSet.has(entity.id)}
                onChange={() => {
                  const next = selectedSet.has(entity.id)
                    ? selected.filter((id) => id !== entity.id)
                    : [...selected, entity.id];
                  onChange(next);
                }}
              />
              <span>{entity.label}</span>
            </label>
          ))}
          {visible.length === 0 && <p className="empty-note">No matches</p>}
        </div>
      </div>
    </details>
  );
}
