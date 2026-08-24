const millisecondFormatOptions: Intl.NumberFormatOptions = {
  maximumFractionDigits: 3,
};

const scoreFormatter = new Intl.NumberFormat(undefined, {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});

const countFormatter = new Intl.NumberFormat(undefined, {
  maximumFractionDigits: 0,
});

const usdFormatter = new Intl.NumberFormat(undefined, {
  style: "currency",
  currency: "USD",
  minimumFractionDigits: 2,
  maximumFractionDigits: 4,
});

const usdRateFormatter = new Intl.NumberFormat(undefined, {
  style: "currency",
  currency: "USD",
  minimumFractionDigits: 2,
  maximumFractionDigits: 4,
});

export function formatMilliseconds(value: number | null): string {
  if (value === null) return "—";
  return `${value.toLocaleString(undefined, millisecondFormatOptions)} ms`;
}

export function formatScore(value: number | null): string {
  return value === null ? "—" : scoreFormatter.format(value);
}

export function formatCount(value: number | null): string {
  return value === null ? "—" : countFormatter.format(value);
}

export function formatUsd(value: number | null): string {
  return value === null ? "—" : usdFormatter.format(value);
}

export function formatUsdPerMillion(value: number | null): string {
  return value === null ? "—" : `${usdRateFormatter.format(value)} / M tokens`;
}

export function shortHash(value: string): string {
  return value.slice(0, 9);
}

export function formatSnapshotTimestamp(value: string): string {
  const match = /^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2}:\d{2})(?:\.\d+)?(Z|[+-]\d{2}:\d{2})$/.exec(value);
  if (!match) return value;

  const zone = match[3] === "Z" ? "UTC" : `UTC${match[3]}`;
  return `${match[1]} ${match[2]} ${zone}`;
}
