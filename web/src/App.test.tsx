import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router-dom";
import { describe, expect, it, vi } from "vitest";

import { App } from "./App";
import { DatasetProvider } from "./data/context";

const fixtures = vi.hoisted(() => ({
  dataset: null as null | { manifest: unknown; scoreCube: unknown },
  runs: null as null | unknown[],
  runError: null as Error | null,
}));

vi.mock("./data/client", async () => {
  const actual = await vi.importActual<typeof import("./data/client")>("./data/client");
  return {
    ...actual,
    loadDataset: vi.fn(async () => fixtures.dataset),
    loadRuns: vi.fn(async () => {
      if (fixtures.runError) throw fixtures.runError;
      return fixtures.runs;
    }),
    loadRunById: vi.fn(async (_manifest, id: string) => fixtures.runs?.find((run: any) => run.id === id) ?? null),
  };
});

vi.mock("./components/VegaChart", () => ({
  VegaChart: ({ ariaLabel, onDatumClick }: { ariaLabel: string; onDatumClick?: (datum: Record<string, unknown>) => void }) => {
    const scores = ariaLabel.startsWith("Score distribution chart");
    const benchmarkComplexity = ariaLabel.startsWith("Benchmark complexity violin chart");
    const targetComplexity = ariaLabel.startsWith("Target complexity violin chart");
    const label = scores
      ? "Synthetic score point"
      : benchmarkComplexity
        ? "Synthetic benchmark violin"
        : targetComplexity
          ? "Synthetic target violin"
          : "Synthetic chart segment";
    return (
      <button
        type="button"
        onClick={() => onDatumClick?.(
          scores
            ? { runId: "bench&one_model/a?x_gpu+x_r1" }
            : benchmarkComplexity
              ? { categoryType: "benchmark", categoryId: "bench&one" }
              : targetComplexity
                ? { categoryType: "backend", categoryId: "gpu+x" }
                : { modelId: "model/a?x", bandId: "invalid" },
        )}
      >
        {label}
      </button>
    );
  },
}));

async function renderApp(initial = "/tiers", options: { runError?: Error } = {}) {
  const { manifestFixture, scoreCubeFixture, runsFixture } = await import("./test/fixtures");
  fixtures.dataset = { manifest: manifestFixture, scoreCube: scoreCubeFixture };
  fixtures.runs = runsFixture;
  fixtures.runError = options.runError ?? null;
  const rendered = render(<MemoryRouter initialEntries={[initial]}><DatasetProvider><App /></DatasetProvider></MemoryRouter>);
  await screen.findByRole("link", { name: "LLM Autoparallelization Benchmark home" });
  return rendered;
}

describe("explorer routing", () => {
  it("drills from a tier segment to filtered runs and preserves context in detail", async () => {
    await renderApp("/tiers?benchmark=bench%26one&backend=gpu%2Bx");
    await userEvent.click(screen.getByRole("button", { name: "Synthetic chart segment" }));
    expect(await screen.findByRole("heading", { name: "Runs" })).toBeInTheDocument();
    await waitFor(() => expect(screen.getByText("1 matching runs")).toBeInTheDocument());
    await userEvent.click(screen.getByRole("link", { name: "bench&one_model/a?x_gpu+x_r1" }));
    expect(await screen.findByRole("heading", { name: "bench&one_model/a?x_gpu+x_r1" })).toBeInTheDocument();
    expect(screen.getByRole("link", { name: /Generated source directory/ })).toHaveAttribute("target", "_blank");
    expect(screen.getByRole("link", { name: /Back to matching runs/ })).toHaveAttribute("href", expect.stringContaining("benchmark=bench%26one"));
  });

  it("restores repeated special-character filters from the URL and can reset them", async () => {
    const { container } = await renderApp("/tiers?model=model%2Fa%3Fx&benchmark=bench%26one&backend=gpu%2Bx&sort=strongest");
    const summaries = container.querySelectorAll(".filter-menu > summary > strong");
    expect(summaries[0]).toHaveTextContent("Model A");
    expect(summaries[1]).toHaveTextContent("Bench & One");
    expect(summaries[2]).toHaveTextContent("GPU + X");
    expect(screen.getByRole("combobox", { name: "Order" })).toHaveValue("strongest");
    fireEvent.click(screen.getByRole("button", { name: /Reset/ }));
    expect(container.querySelector(".filter-menu > summary > strong")).toHaveTextContent("Default");
  });

  it("starts with the named default model set and keeps all-selection modes distinct", async () => {
    const { container } = await renderApp();
    const modelMenu = container.querySelector<HTMLDetailsElement>(".filter-menu")!;
    const modelSummary = within(modelMenu).getByText("Default", { selector: "summary strong" });
    expect(screen.getByLabelText("Current selection summary")).toHaveTextContent(/1 model\s*1 run/);

    await userEvent.click(modelMenu.querySelector("summary")!);
    expect(within(modelMenu).getByRole("checkbox", { name: "Model A" })).not.toBeChecked();
    expect(within(modelMenu).getByRole("checkbox", { name: "unknown-model" })).toBeChecked();
    expect(within(modelMenu).getByRole("button", { name: "Default", pressed: true })).toBeInTheDocument();

    await userEvent.click(within(modelMenu).getByRole("button", { name: /^All$/ }));
    expect(modelSummary).toHaveTextContent("All models");
    expect(screen.getByRole("link", { name: "Model scores" })).toHaveAttribute("href", "/scores?model-set=all");

    await userEvent.click(within(modelMenu).getByRole("button", { name: "Select all" }));
    expect(modelSummary).toHaveTextContent("2 models");
    const explicitSelection = new URL(screen.getByRole("link", { name: "Model scores" }).getAttribute("href")!, "https://example.test");
    expect(explicitSelection.searchParams.getAll("model")).toEqual(["model/a?x", "unknown-model"]);
    expect(explicitSelection.searchParams.has("model-set")).toBe(false);

    await userEvent.click(within(modelMenu).getByRole("button", { name: "Default" }));
    expect(modelSummary).toHaveTextContent("Default");
    expect(screen.getByRole("link", { name: "Model scores" })).toHaveAttribute("href", "/scores");
  });

  it("loads filtered model-score distributions and returns from a selected run with context", async () => {
    await renderApp("/scores?model=model%2Fa%3Fx&benchmark=bench%26one&backend=gpu%2Bx&sort=strongest");
    expect(await screen.findByRole("heading", { name: "Model scores" })).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Model scores" })).toHaveClass("active");
    expect(screen.getByRole("combobox", { name: "Order" })).toHaveValue("strongest");
    await waitFor(() => expect(screen.getByLabelText("Current score selection summary")).toHaveTextContent(/1 model\s*2 runs\s*6\.00 mean score/));
    expect(screen.getByText("Synthetic score point")).toBeInTheDocument();

    await userEvent.click(screen.getByRole("button", { name: "Synthetic score point" }));
    expect(await screen.findByRole("heading", { name: "bench&one_model/a?x_gpu+x_r1" })).toBeInTheDocument();
    const back = screen.getByRole("link", { name: /Back to model scores/ });
    expect(back).toHaveAttribute("href", expect.stringContaining("/scores?model=model%2Fa%3Fx"));
    expect(back).toHaveAttribute("href", expect.stringContaining("benchmark=bench%26one"));
    expect(back).toHaveAttribute("href", expect.stringContaining("backend=gpu%2Bx"));
    expect(back).toHaveAttribute("href", expect.stringContaining("sort=strongest"));
  });

  it("preserves wildcard model selection through score details and complexity drill-down", async () => {
    const scoreView = await renderApp("/scores?model-set=all");
    await userEvent.click(await screen.findByRole("button", { name: "Synthetic score point" }));
    expect(await screen.findByRole("link", { name: /Back to model scores/ })).toHaveAttribute(
      "href", expect.stringContaining("model-set=all"),
    );
    scoreView.unmount();

    await renderApp("/complexity?model-set=all");
    await userEvent.click(screen.getByRole("button", { name: "Synthetic benchmark violin" }));
    expect(await screen.findByRole("heading", { name: "Runs" })).toBeInTheDocument();
    await waitFor(() => expect(screen.getByText("3 matching runs")).toBeInTheDocument());
    expect(screen.getByRole("link", { name: "Model scores" })).toHaveAttribute("href", expect.stringContaining("model-set=all"));
  });

  it("shows explicit empty and error states for model-score observations", async () => {
    const empty = await renderApp("/scores?benchmark=missing-cell");
    expect(await screen.findByRole("heading", { name: "This filter combination has no scored runs." })).toBeInTheDocument();
    empty.unmount();

    await renderApp("/scores", { runError: new Error("synthetic shard failure") });
    expect(await screen.findByRole("heading", { name: "The score observations could not be loaded." })).toBeInTheDocument();
    expect(screen.getByText("synthetic shard failure")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Try again" })).toBeInTheDocument();
  });

  it("recomputes complexity distributions and drills from benchmarks or targets to runs", async () => {
    const benchmarkView = await renderApp("/complexity?model=model%2Fa%3Fx");
    expect(await screen.findByRole("heading", { name: "Benchmark / Target complexity" })).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Complexity" })).toHaveClass("active");
    expect(screen.getByLabelText("Current complexity selection summary")).toHaveTextContent(/1 model\s*2 runs\s*6\.00 grand mean/);
    expect(screen.getByText("Synthetic benchmark violin")).toBeInTheDocument();
    expect(screen.getByText("Synthetic target violin")).toBeInTheDocument();

    await userEvent.click(screen.getByRole("button", { name: "Synthetic benchmark violin" }));
    expect(await screen.findByRole("heading", { name: "Runs" })).toBeInTheDocument();
    expect(screen.getByText("Bench & One", { selector: ".filter-menu summary strong" })).toBeInTheDocument();
    benchmarkView.unmount();

    await renderApp("/complexity?model=model%2Fa%3Fx");
    await userEvent.click(screen.getByRole("button", { name: "Synthetic target violin" }));
    expect(await screen.findByRole("heading", { name: "Runs" })).toBeInTheDocument();
    expect(screen.getByText("GPU + X", { selector: ".filter-menu summary strong" })).toBeInTheDocument();
  });

  it("shows an explicit empty state for complexity filters without observations", async () => {
    await renderApp("/complexity?benchmark=missing-cell");
    expect(await screen.findByRole("heading", { name: "This filter combination has no scored runs." })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Clear filters" })).toBeInTheDocument();
  });

  it("dismisses an open filter menu on outside pointer input or Escape", async () => {
    const { container } = await renderApp();
    const menu = container.querySelector<HTMLDetailsElement>(".filter-menu")!;
    const summary = menu.querySelector<HTMLElement>("summary")!;

    fireEvent.click(summary);
    expect(menu.open).toBe(true);
    fireEvent.pointerDown(container.querySelector(".view-summary")!);
    expect(menu.open).toBe(false);

    fireEvent.click(summary);
    expect(menu.open).toBe(true);
    fireEvent.keyDown(document, { key: "Escape" });
    expect(menu.open).toBe(false);
    expect(summary).toHaveFocus();
  });

  it("dismisses the About menu on outside pointer input or Escape", async () => {
    const { container } = await renderApp();
    const menu = container.querySelector<HTMLDetailsElement>(".about-menu")!;
    const summary = menu.querySelector<HTMLElement>("summary")!;

    fireEvent.click(summary);
    expect(menu.open).toBe(true);
    fireEvent.pointerDown(container.querySelector(".view-summary")!);
    expect(menu.open).toBe(false);

    fireEvent.click(summary);
    expect(menu.open).toBe(true);
    fireEvent.keyDown(document, { key: "Escape" });
    expect(menu.open).toBe(false);
    expect(summary).toHaveFocus();
  });

  it("presents institutional context and the methodology at navigation level", async () => {
    const { container } = await renderApp();
    const view = within(container);
    expect(view.queryByText("Next", { exact: true })).not.toBeInTheDocument();
    expect(container.querySelector(".nav-performance")).not.toHaveAttribute("title");
    await userEvent.click(view.getByText("About", { selector: "summary" }));
    const aboutPanel = within(container.querySelector(".about-panel")!);
    const groupLink = aboutPanel.getByRole("link", { name: "Distributed and Parallel Systems Research Group" });
    expect(groupLink).toHaveAttribute("href", "https://dps.uibk.ac.at/");
    expect(aboutPanel.getByRole("link", { name: "University of Innsbruck" })).toHaveAttribute("href", "https://www.uibk.ac.at/");
    expect(aboutPanel.getByRole("link", { name: "Citation information" })).toHaveAttribute("href", "/cite");
    expect(aboutPanel.queryByText("Dataset snapshot")).not.toBeInTheDocument();
    expect(aboutPanel.queryByText(/current publication target/)).not.toBeInTheDocument();
    expect(aboutPanel.getByText(/lists the authors and copyable BibTeX/)).toBeInTheDocument();
    await userEvent.click(aboutPanel.getByRole("link", { name: "Methodology" }));
    expect(await view.findByRole("heading", { name: "Methodology" })).toBeInTheDocument();
    expect(view.getByRole("heading", { name: "Agent harnesses" })).toBeInTheDocument();
    expect(view.getByRole("heading", { name: "Five sequential stages" })).toBeInTheDocument();
    expect(view.getByRole("heading", { name: "Recorded local execution system" })).toBeInTheDocument();
    expect(view.getByText(/five independent agent invocations were performed/)).toBeInTheDocument();
    expect(view.queryByRole("heading", { name: "Current dataset" })).not.toBeInTheDocument();
    expect(view.queryByText(/derived from the data rather than fixed by the website/)).not.toBeInTheDocument();
    expect(view.getByText("GitHub Copilot CLI", { selector: "h3" })).toBeInTheDocument();
    expect(view.getAllByText("one test GPU", { exact: true })).toHaveLength(2);
    expect(view.getByRole("link", { name: /Experiment harness configuration/ })).toHaveAttribute(
      "href",
      "https://github.com/example/experiment/blob/dddddddddddddddddddddddddddddddddddddddd/experiment.rb",
    );
    expect(view.getByRole("link", { name: /Threshold review/ })).toHaveAttribute("target", "_blank");
    const footer = within(container.querySelector(".site-footer")!);
    expect(footer.queryByText(/Client-only/)).not.toBeInTheDocument();
    expect(footer.getByRole("link", { name: "Distributed and Parallel Systems Research Group" })).toHaveAttribute("href", "https://dps.uibk.ac.at/");
    expect(footer.getByRole("link", { name: "University of Innsbruck" })).toHaveAttribute("href", "https://www.uibk.ac.at/");
  });

  it("provides the published citation, author links, scope note, and copyable BibTeX", async () => {
    const writeText = vi.fn().mockResolvedValue(undefined);
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: { writeText },
    });

    await renderApp("/cite");
    expect(screen.getByRole("heading", { name: "Citation" })).toHaveClass("sr-only");
    expect(screen.queryByRole("heading", { name: "Cite this work" })).not.toBeInTheDocument();
    expect(screen.getByText("Please Cite the following paper if you use this work")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Cite" })).toHaveClass("active");
    expect(screen.getByRole("link", { name: "Peter Thoman" })).toHaveAttribute("href", "https://dps.uibk.ac.at/~petert");
    expect(screen.getByRole("link", { name: "Philipp Gschwandtner" })).toHaveAttribute("href", "https://dps.uibk.ac.at/~philipp");

    const paper = screen.getByRole("link", {
      name: "Evaluating the Parallelization Capabilities of State-of-the-Art Agentic Large Language Models",
    });
    expect(paper).toHaveAttribute("href", "https://link.springer.com/chapter/10.1007/978-3-032-35248-4_2");
    expect(paper).toHaveAttribute("target", "_blank");
    expect(screen.getByLabelText("Citation scope")).toHaveTextContent("extended dataset");
    expect(screen.getByLabelText("Citation scope")).toHaveTextContent("slightly revised methodology");

    await userEvent.click(screen.getByRole("button", { name: /Copy BibTeX/ }));
    expect(writeText).toHaveBeenCalledWith(expect.stringContaining("doi = {10.1007/978-3-032-35248-4_2}"));
    expect(screen.getByRole("button", { name: /Copied/ })).toBeInTheDocument();
    expect(screen.getByText("BibTeX copied to the clipboard.")).toBeInTheDocument();
  });
});
