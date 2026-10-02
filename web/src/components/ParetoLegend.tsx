export function ParetoLegend({ metric }: { metric: "mean cost" | "mean generation time" }) {
  return (
    <p className="chart-footnote pareto-legend">
      <span className="pareto-legend-label"><span className="pareto-legend-key" aria-hidden="true" />Pareto front · current selection</span>
      <span>No other visible model has at least as high a mean score and at most as much {metric}, with one strict improvement.</span>
    </p>
  );
}
