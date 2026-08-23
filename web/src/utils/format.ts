const millisecondFormatOptions: Intl.NumberFormatOptions = {
  maximumFractionDigits: 3,
};

export function formatMilliseconds(value: number | null): string {
  if (value === null) return "—";
  return `${value.toLocaleString(undefined, millisecondFormatOptions)} ms`;
}
