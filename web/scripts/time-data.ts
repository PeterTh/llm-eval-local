export function parseGenerationTime(value: string | undefined, runId: string): number | null {
  if (value === undefined || value.trim() === "") return null;
  const seconds = Number(value);
  if (!/^[+]?(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]?\d+)?$/i.test(value.trim())
    || !Number.isFinite(seconds) || seconds <= 0) {
    throw new Error(`${runId}.total_time must be a positive finite duration in seconds`);
  }
  return seconds;
}
