import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router-dom";
import { describe, expect, it, vi } from "vitest";

import { App } from "./App";
import { DatasetProvider } from "./data/context";

const fixtures = vi.hoisted(() => ({
  dataset: null as null | { manifest: unknown; scoreCube: unknown },
  runs: null as null | unknown[],
}));

vi.mock("./data/client", async () => {
  const actual = await vi.importActual<typeof import("./data/client")>("./data/client");
  return {
    ...actual,
    loadDataset: vi.fn(async () => fixtures.dataset),
    loadRuns: vi.fn(async () => fixtures.runs),
    loadRunById: vi.fn(async (_manifest, id: string) => fixtures.runs?.find((run: any) => run.id === id) ?? null),
  };
});

vi.mock("./components/VegaChart", () => ({
  VegaChart: ({ onDatumClick }: { onDatumClick?: (datum: Record<string, unknown>) => void }) => (
    <button type="button" onClick={() => onDatumClick?.({ modelId: "model/a?x", bandId: "invalid" })}>Synthetic chart segment</button>
  ),
}));

async function renderApp(initial = "/tiers") {
  const { manifestFixture, scoreCubeFixture, runsFixture } = await import("./test/fixtures");
  fixtures.dataset = { manifest: manifestFixture, scoreCube: scoreCubeFixture };
  fixtures.runs = runsFixture;
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
    expect(screen.getByText("All models")).toBeInTheDocument();
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
    await userEvent.click(view.getByText("About", { selector: "summary" }));
    const aboutPanel = within(container.querySelector(".about-panel")!);
    const groupLink = aboutPanel.getByRole("link", { name: "Distributed and Parallel Systems Research Group" });
    expect(groupLink).toHaveAttribute("href", "https://dps.uibk.ac.at/");
    expect(aboutPanel.getByRole("link", { name: "University of Innsbruck" })).toHaveAttribute("href", "https://www.uibk.ac.at/");
    expect(aboutPanel.getByRole("link", { name: "Citation information" })).toHaveAttribute("href", "/cite");
    await userEvent.click(aboutPanel.getByRole("link", { name: "Methodology" }));
    expect(await view.findByRole("heading", { name: "Methodology" })).toBeInTheDocument();
    expect(view.getByRole("heading", { name: "Agent harnesses" })).toBeInTheDocument();
    expect(view.getByRole("heading", { name: "Five sequential stages" })).toBeInTheDocument();
    expect(view.getByRole("heading", { name: "Recorded local execution system" })).toBeInTheDocument();
    expect(view.getByText("GitHub Copilot CLI", { selector: "h3" })).toBeInTheDocument();
    expect(view.getAllByText("one test GPU", { exact: true })).toHaveLength(2);
    expect(view.getByRole("link", { name: /Experiment harness configuration/ })).toHaveAttribute(
      "href",
      "https://github.com/example/experiment/blob/dddddddddddddddddddddddddddddddddddddddd/experiment.rb",
    );
    expect(view.getByRole("link", { name: /Threshold review/ })).toHaveAttribute("target", "_blank");
    const footer = within(container.querySelector(".site-footer")!);
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
    expect(screen.getByRole("heading", { name: "Cite this work" })).toBeInTheDocument();
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
