export interface DistributionStatistics {
  count: number;
  mean: number;
  lowerWhisker: number;
  firstQuartile: number;
  median: number;
  thirdQuartile: number;
  upperWhisker: number;
  outlierCount: number;
}

function quantileSorted(values: readonly number[], probability: number): number {
  if (values.length === 1) return values[0]!;
  const index = (values.length - 1) * probability;
  const lowerIndex = Math.floor(index);
  const upperIndex = Math.ceil(index);
  const lower = values[lowerIndex]!;
  const upper = values[upperIndex]!;
  return lower + (upper - lower) * (index - lowerIndex);
}

export function summarizeDistribution(values: readonly number[]): DistributionStatistics {
  if (values.length === 0) throw new Error("Cannot summarize an empty distribution");
  const sorted = [...values].sort((left, right) => left - right);
  const firstQuartile = quantileSorted(sorted, 0.25);
  const median = quantileSorted(sorted, 0.5);
  const thirdQuartile = quantileSorted(sorted, 0.75);
  const interquartileRange = thirdQuartile - firstQuartile;
  const lowerFence = firstQuartile - 1.5 * interquartileRange;
  const upperFence = thirdQuartile + 1.5 * interquartileRange;
  const lowerWhisker = sorted.find((score) => score >= lowerFence) ?? sorted[0]!;
  const upperWhisker = [...sorted].reverse().find((score) => score <= upperFence) ?? sorted.at(-1)!;
  return {
    count: sorted.length,
    mean: sorted.reduce((total, score) => total + score, 0) / sorted.length,
    lowerWhisker,
    firstQuartile,
    median,
    thirdQuartile,
    upperWhisker,
    outlierCount: sorted.filter((score) => score < lowerWhisker || score > upperWhisker).length,
  };
}
