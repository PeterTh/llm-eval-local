const ANCHORS = ["top", "bottom", "right", "left", "top-right", "top-left", "bottom-right", "bottom-left"];
// Try the usual short guides first. Dense mobile clusters also need intermediate
// positions: a coarse distance grid can miss a free slot between nearby labels.
const OFFSETS = [...new Set([9, 18, 30, 45, 65, 90, 120, 160, 210, 270,
  ...Array.from({ length: 54 }, (_, index) => (index + 1) * 10)])];

/** Reserve the font's full line box for collision detection without enlarging visible text. */
export function scatterLabels({ name, points, font, fontSize, color, guideColor, padding, priorityField }: {
  name: string;
  points: string;
  font: string;
  fontSize: number;
  color: string;
  guideColor: string;
  padding: number;
  priorityField?: string;
}) {
  const layout = `${name}_layout`;
  return [
    {
      name: layout, type: "text", from: { data: points }, interactive: false, aria: false,
      encode: { enter: {
        text: { field: "datum.pointLabel" }, font: { value: font }, fontWeight: { value: 520 },
        // Vega's label transform uses fontSize as height, but the rendered line box is taller.
        fontSize: { value: fontSize + 4 }, fillOpacity: { value: 0 },
      } },
      transform: [{
        type: "label", anchor: OFFSETS.flatMap(() => ANCHORS),
        offset: OFFSETS.flatMap((distance) => ANCHORS.map(() => distance)),
        // Sort label placement only; point order stays stable for keyboard use.
        ...(priorityField ? { sort: { field: `datum.datum.${priorityField}`, order: "descending" } } : {}),
        padding, size: { signal: "[width, height]" },
      }],
    },
    {
      name: `${name}_guides`, type: "rule", from: { data: layout }, interactive: false, aria: false,
      encode: { update: {
        x: { field: "x" }, y: { field: "y" }, x2: { field: "datum.x" }, y2: { field: "datum.y" },
        stroke: { value: guideColor }, strokeWidth: { value: 0.7 },
        opacity: { signal: "datum.opacity && hypot(datum.x - datum.datum.x, datum.y - datum.datum.y) > 35 ? 0.5 : 0" },
      } },
    },
    {
      name, type: "text", from: { data: layout }, interactive: false,
      encode: { update: {
        x: { field: "x" }, align: { field: "align" }, baseline: { value: "middle" },
        // Keep the smaller visible glyphs centered in the reserved collision box.
        y: { signal: "datum.y + (datum.baseline === 'top' ? datum.fontSize / 2 : datum.baseline === 'bottom' ? -datum.fontSize / 2 : 0)" },
        dy: { value: 1 },
        opacity: { field: "opacity" }, text: { field: "text" }, font: { value: font },
        fontWeight: { value: 520 }, fontSize: { value: fontSize }, fill: { value: color },
      } },
    },
  ];
}
