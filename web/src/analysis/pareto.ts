interface ParetoPoint {
  modelId: string;
  value: number;
  score: number;
}

/** Minimize resource use and maximize score, comparing unrounded plotted values. */
export function getParetoModelIds(points: readonly ParetoPoint[]): string[] {
  return points.filter((point) => !points.some((other) =>
    other.value <= point.value && other.score >= point.score
    && (other.value < point.value || other.score > point.score)))
    .map((point) => point.modelId);
}
