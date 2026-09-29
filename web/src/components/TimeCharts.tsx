import { useMemo } from "react";
import type { VisualizationSpec } from "vega-embed";

import { adaptiveScoreDomain } from "../analysis/cost";
import { timeDomain, type TimeAnalysis } from "../analysis/time";
import type { DatasetManifest, FilterState } from "../data/types";
import { formatCount, formatGenerationTime, formatScore } from "../utils/format";
import { stableStringHash } from "../utils/hash";
import { useMediaQuery } from "../utils/media";
import { VegaChart } from "./VegaChart";

const LIGHT_COLORS = ["#004aad", "#3c6fa8", "#655f9b", "#28786d", "#8a5b42", "#6f6d31", "#526f91"];
const DARK_COLORS = ["#8fb8f5", "#74a7dc", "#aaa0e1", "#69b9ab", "#d5a080", "#b8b36a", "#91afd0"];
const SHAPES = ["circle", "square", "triangle-up", "diamond", "triangle-down"];
const ANCHORS = ["top", "bottom", "right", "left", "top-right", "top-left", "bottom-right", "bottom-left"];

function theme(dark: boolean) {
  return {
    background: dark ? "#182126" : "#ffffff",
    font: "Roboto Condensed Variable, Roboto Condensed, Arial Narrow, sans-serif",
    axis: {
      labelColor: dark ? "#c1cbc9" : "#49535d",
      titleColor: dark ? "#c1cbc9" : "#49535d",
      domainColor: dark ? "#4a5b61" : "#bdc5c3",
      tickColor: dark ? "#4a5b61" : "#bdc5c3",
      gridColor: dark ? "#334147" : "#dfe2e1",
      gridOpacity: 0.75,
    },
  };
}

interface ChartProps {
  analysis: TimeAnalysis;
  manifest: DatasetManifest;
  scale: FilterState["scale"];
  onDatumClick: (datum: Record<string, unknown>) => void;
}

export function TimeScatterChart({ analysis, manifest, scale, onDatumClick }: ChartProps) {
  const narrow = useMediaQuery("(max-width: 600px)");
  const dark = useMediaQuery("(prefers-color-scheme: dark)");
  const spec = useMemo<VisualizationSpec>(() => {
    // Place labels for the most constrained (leftmost) points first.
    const points = [...analysis.plottedModels].sort((left, right) =>
      left.meanGenerationTimeSeconds! - right.meanGenerationTimeSeconds!
      || left.modelLabel.localeCompare(right.modelLabel, "en")).map((model) => {
      const hash = stableStringHash(model.modelId);
      const pointShape = SHAPES[hash % SHAPES.length]!;
      return {
        modelId: model.modelId,
        modelLabel: model.modelLabel,
        pointLabel: narrow && model.modelLabel.length > 19 ? `${model.modelLabel.slice(0, 11)}…${model.modelLabel.slice(-7)}` : model.modelLabel,
        minutes: model.meanGenerationTimeSeconds! / 60,
        meanScore: model.meanScore,
        pointColor: (dark ? DARK_COLORS : LIGHT_COLORS)[hash % 7],
        pointShape,
        pointSize: Math.round((narrow ? 115 : 145) * (pointShape.startsWith("triangle") ? 1.35 : pointShape === "diamond" ? 1.2 : 1)),
        description: `${model.modelLabel}; mean score ${formatScore(model.meanScore)}; mean generation time ${formatGenerationTime(model.meanGenerationTimeSeconds)}; ${model.timeRunCount} timed runs`,
        tooltip: {
          Model: model.modelLabel,
          "Mean score": formatScore(model.meanScore),
          "Mean generation time": formatGenerationTime(model.meanGenerationTimeSeconds),
          "Median generation time": formatGenerationTime(model.distribution!.median),
          Runs: `${formatCount(model.scoreRunCount)} scored · ${formatCount(model.timeRunCount)} timed`,
        },
      };
    });
    return {
      $schema: "https://vega.github.io/schema/vega/v6.json",
      description: "Mean overall score versus mean agent generation time.",
      width: 600,
      height: Math.max(narrow ? 480 : 400, points.length * (narrow ? 55 : 38)),
      // Refit on container resize through VegaChart, not on pointer-driven updates.
      autosize: { type: "fit", contains: "padding" },
      padding: { left: 8, right: 8, top: 12, bottom: 6 },
      data: [{ name: "time_values", values: points }],
      scales: [
        { name: "time_x", type: scale, domain: timeDomain(analysis.plottedModels.map((model) => model.meanGenerationTimeSeconds!), scale).map((seconds) => seconds / 60), range: "width", nice: false, zero: scale === "linear" },
        { name: "score_y", type: "linear", domain: adaptiveScoreDomain(points.map((point) => point.meanScore), manifest.scoreScale.minimum, manifest.scoreScale.maximum), range: "height", nice: false, zero: false },
      ],
      axes: [
        { orient: "bottom", scale: "time_x", title: `Mean generation time (min${scale === "log" ? ", log scale" : ""})`, grid: true, tickCount: narrow ? 4 : 7, format: ".3~g", labelFontSize: narrow ? 12 : 14, titleFontSize: narrow ? 13 : 15, titlePadding: 10 },
        { orient: "left", scale: "score_y", title: "Mean overall score", grid: true, tickCount: narrow ? 5 : 7, format: ".2~f", labelFontSize: narrow ? 12 : 14, titleFontSize: narrow ? 13 : 15, titlePadding: 10 },
      ],
      marks: [
        {
          name: "time_points", type: "symbol", from: { data: "time_values" },
          encode: { update: {
            x: { scale: "time_x", field: "minutes" }, y: { scale: "score_y", field: "meanScore" },
            shape: { field: "pointShape" }, size: { field: "pointSize" }, fill: { field: "pointColor" }, fillOpacity: { value: 0.88 },
            stroke: { value: dark ? "#182126" : "#ffffff" }, strokeWidth: { value: 1.3 }, cursor: { value: "pointer" },
            description: { field: "description" }, tooltip: { field: "tooltip" },
          } },
        },
        {
          name: "time_labels", type: "text", from: { data: "time_points" }, interactive: false,
          encode: { enter: {
            text: { field: "datum.pointLabel" }, font: { value: theme(dark).font }, fontSize: { value: narrow ? (points.length > 20 ? 11 : 12) : 14 },
            fontWeight: { value: 520 }, fill: { value: dark ? "#edf0eb" : "#303941" },
          } },
          transform: [{ type: "label", anchor: [9, 18, 30, 45, 65].flatMap(() => ANCHORS), offset: [9, 18, 30, 45, 65].flatMap((distance) => ANCHORS.map(() => distance)), padding: 0, size: { signal: "[width, height]" } }],
        },
        {
          name: "time_label_guides", type: "rule", from: { data: "time_labels" }, interactive: false, aria: false,
          encode: { update: {
            x: { field: "x" }, y: { field: "y" },
            x2: { field: "datum.x" }, y2: { field: "datum.y" },
            stroke: { value: dark ? "#91afd0" : "#526f91" }, strokeWidth: { value: 0.7 },
            opacity: { signal: "datum.opacity && hypot(datum.x - datum.datum.x, datum.y - datum.datum.y) > 35 ? 0.5 : 0" },
          } },
        },
      ],
      config: theme(dark),
    } as VisualizationSpec;
  }, [analysis, manifest, scale, narrow, dark]);
  return <VegaChart spec={spec} ariaLabel={`Time efficiency chart for ${analysis.plottedModels.length} models`} onDatumClick={onDatumClick} interactiveMarkSelector=".time_points path" fitContainerWidth />;
}

export function TimeDistributionChart({ analysis, manifest, scale, onDatumClick }: ChartProps) {
  const narrow = useMediaQuery("(max-width: 600px)");
  const dark = useMediaQuery("(prefers-color-scheme: dark)");
  const spec = useMemo<VisualizationSpec>(() => {
    const summaries = analysis.plottedModels.map((model) => {
      const stats = model.distribution!;
      return {
        modelId: model.modelId, modelLabel: model.modelLabel,
        mean: stats.mean / 60, median: stats.median / 60, q1: stats.firstQuartile / 60, q3: stats.thirdQuartile / 60,
        lower: stats.lowerWhisker / 60, upper: stats.upperWhisker / 60,
        description: `${model.modelLabel}; median generation time ${formatGenerationTime(stats.median)}; mean ${formatGenerationTime(stats.mean)}; ${model.timeRunCount} timed runs`,
        tooltip: {
          Model: model.modelLabel, "Timed runs": formatCount(model.timeRunCount), Mean: formatGenerationTime(stats.mean),
          Median: formatGenerationTime(stats.median), Q1: formatGenerationTime(stats.firstQuartile), Q3: formatGenerationTime(stats.thirdQuartile),
          "Lower whisker": formatGenerationTime(stats.lowerWhisker), "Upper whisker": formatGenerationTime(stats.upperWhisker),
          Minimum: formatGenerationTime(stats.minimum), Maximum: formatGenerationTime(stats.maximum), Outliers: formatCount(stats.outlierCount),
        },
      };
    });
    const benchmarks = new Map(manifest.benchmarks.map((entity) => [entity.id, entity.label]));
    const backends = new Map(manifest.backends.map((entity) => [entity.id, entity.label]));
    const outliers = analysis.plottedModels.flatMap((model) => model.outliers.map((run) => ({
      runId: run.id, modelId: run.modelId, minutes: run.generationTimeSeconds / 60,
      offset: (stableStringHash(run.id) / 0xffff_ffff - 0.5) * 12,
      description: `${run.id}; ${model.modelLabel}; generation time ${formatGenerationTime(run.generationTimeSeconds)}; score ${run.overallScore}; Tukey outlier`,
      tooltip: {
        Model: model.modelLabel, Benchmark: benchmarks.get(run.benchmarkId) ?? run.benchmarkId,
        Backend: backends.get(run.backendId) ?? run.backendId, Repetition: run.repetition,
        "Generation time": formatGenerationTime(run.generationTimeSeconds), Score: run.overallScore, Observation: "Tukey outlier",
      },
    })));
    const labels = Object.fromEntries(summaries.map((model) => [model.modelId, model.modelLabel]));
    const y = { scale: "model_y", field: "modelId", band: 0.5 };
    const color = dark ? "#9fc5f8" : "#0b5bbb";
    const info = { tooltip: { field: "tooltip" }, description: { field: "description" } };
    return {
      $schema: "https://vega.github.io/schema/vega/v6.json",
      description: "Generation-time distributions with quartiles, median, mean, Tukey whiskers and outliers.",
      width: 600, height: Math.max(160, summaries.length * (narrow ? 38 : 44) + 60),
      autosize: { type: "fit", contains: "padding" }, padding: { left: 4, right: 12, top: 10, bottom: 6 },
      data: [{ name: "time_summaries", values: summaries }, { name: "time_outliers", values: outliers }],
      scales: [
        { name: "time_x", type: scale, domain: timeDomain(analysis.plottedModels.flatMap((model) => [model.distribution!.minimum, model.distribution!.maximum]), scale).map((seconds) => seconds / 60), range: "width", nice: false, zero: scale === "linear" },
        { name: "model_y", type: "band", domain: summaries.map((model) => model.modelId), range: "height", padding: 0.25 },
      ],
      axes: [
        { orient: "bottom", scale: "time_x", title: `Generation time (min${scale === "log" ? ", log scale" : ""})`, grid: true, tickCount: narrow ? 4 : 8, format: ".3~g", labelFontSize: narrow ? 11 : 13, titleFontSize: narrow ? 12 : 14, titlePadding: 10 },
        { orient: "left", scale: "model_y", ticks: false, domain: false, encode: { labels: { update: { text: { signal: `${JSON.stringify(labels)}[datum.value]` }, tooltip: { signal: `${JSON.stringify(labels)}[datum.value]` } } } }, labelLimit: narrow ? 120 : 220, labelPadding: 10, labelFontSize: narrow ? 11 : 14 },
      ],
      marks: [
        {
          type: "rule", from: { data: "time_summaries" },
          encode: { update: {
            x: { scale: "time_x", field: "lower" }, x2: { scale: "time_x", field: "upper" },
            y, stroke: { value: color }, ...info,
          } },
        },
        ...["lower", "upper"].map((field) => ({
          type: "rule", from: { data: "time_summaries" },
          encode: { update: {
            x: { scale: "time_x", field },
            y: { ...y, offset: -6 }, y2: { ...y, offset: 6 },
            stroke: { value: color }, ...info,
          } },
        })),
        {
          name: "time_boxes", type: "rect", from: { data: "time_summaries" },
          encode: { update: {
            x: { scale: "time_x", field: "q1" }, x2: { scale: "time_x", field: "q3" },
            y: { ...y, offset: -9 }, y2: { ...y, offset: 9 },
            fill: { value: dark ? "#416a98" : "#b9d3f5" }, stroke: { value: color }, ...info,
          } },
        },
        {
          type: "rule", from: { data: "time_summaries" },
          encode: { update: {
            x: { scale: "time_x", field: "median" },
            y: { ...y, offset: -9 }, y2: { ...y, offset: 9 },
            stroke: { value: dark ? "#ffffff" : "#102b49" }, strokeWidth: { value: 2 }, ...info,
          } },
        },
        {
          name: "time_means", type: "symbol", from: { data: "time_summaries" },
          encode: { update: {
            x: { scale: "time_x", field: "mean" }, y,
            shape: { value: "diamond" }, size: { value: narrow ? 55 : 75 },
            fill: { value: dark ? "#f4f8ff" : "#0b3d79" },
            stroke: { value: dark ? "#182126" : "#ffffff" }, ...info,
          } },
        },
        {
          name: "time_outlier_points", type: "symbol", from: { data: "time_outliers" },
          encode: { update: {
            x: { scale: "time_x", field: "minutes" }, y: { ...y, offset: { field: "offset" } },
            size: { value: narrow ? 32 : 42 }, fill: { value: color }, fillOpacity: { value: 0.65 },
            stroke: { value: dark ? "#182126" : "#ffffff" }, strokeWidth: { value: 0.7 },
            cursor: { value: "pointer" }, ...info,
          } },
        },
      ],
      config: theme(dark),
    } as VisualizationSpec;
  }, [analysis, manifest, scale, narrow, dark]);
  return <VegaChart spec={spec} ariaLabel={`Time distribution chart for ${analysis.plottedModels.length} models`} onDatumClick={onDatumClick} interactiveMarkSelector=".time_outlier_points path" fitContainerWidth />;
}
