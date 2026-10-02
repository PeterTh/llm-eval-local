import { describe, expect, it } from "vitest";
import { copyHighlights, readHighlights, toggleHighlight } from "./highlights";

describe("shareable highlights", () => {
  it("round-trips opaque IDs and deduplicates independently of filters", () => {
    const params = new URLSearchParams();
    for (const id of ["model/a?x&+= ü", "model/a?x&+= ü", "unknown", ""]) params.append("highlight-model", id);
    params.append("highlight-benchmark", "same/id");
    params.append("highlight-run", "same/id");
    params.append("model", "filtered-out");
    expect(readHighlights(new URLSearchParams(params.toString()))).toEqual({
      modelIds: ["model/a?x&+= ü", "unknown"], benchmarkIds: ["same/id"], runIds: ["same/id"],
    });
  });

  it("adds multiple highlights and removes only the activated entity", () => {
    const initial = new URLSearchParams("model=visible&benchmark=one&highlight-model=hidden&highlight-run=run&scale=linear&page=2");
    const added = toggleHighlight(initial, "modelIds", "new/id");
    expect(readHighlights(added).modelIds).toEqual(["hidden", "new/id"]);
    const removed = toggleHighlight(added, "modelIds", "hidden");
    expect(readHighlights(removed)).toEqual({ modelIds: ["new/id"], benchmarkIds: [], runIds: ["run"] });
    for (const key of ["model", "benchmark", "scale", "page"]) expect(removed.getAll(key)).toEqual(initial.getAll(key));
    expect(initial.getAll("highlight-model")).toEqual(["hidden"]);
  });

  it("omits empty selections and preserves unrelated highlight types", () => {
    const params = new URLSearchParams("highlight-run=run&highlight-run=run&highlight-benchmark=bench");
    const next = toggleHighlight(params, "runIds", "run");
    expect(next.has("highlight-run")).toBe(false);
    expect(next.get("highlight-benchmark")).toBe("bench");
  });

  it("preserves highlights through a filter reset without keeping analysis controls", () => {
    const params = new URLSearchParams("model=x&sort=strongest&focus=x&highlight-model=hidden&highlight-benchmark=b&highlight-run=r");
    expect(copyHighlights(params).toString()).toBe("highlight-model=hidden&highlight-benchmark=b&highlight-run=r");
    const target = new URLSearchParams("benchmark=destination&highlight-model=stale");
    expect(copyHighlights(params, target).get("benchmark")).toBe("destination");
    expect(target.getAll("highlight-model")).toEqual(["hidden"]);
  });
});
