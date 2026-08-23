import { useEffect, useState } from "react";

import { PageIntro } from "../components/PageIntro";
import { useDataset } from "../data/context";

const PAPER_URL = "https://link.springer.com/chapter/10.1007/978-3-032-35248-4_2";
const DOI_URL = "https://doi.org/10.1007/978-3-032-35248-4_2";

export const ORIGINAL_PAPER_BIBTEX = `@inbook{Thoman_2026,
  author = {Thoman, Peter and Gschwandtner, Philipp},
  title = {Evaluating the Parallelization Capabilities of State-of-the-Art Agentic Large Language Models},
  booktitle = {Euro-Par 2026: Parallel Processing},
  series = {Lecture Notes in Computer Science},
  volume = {16781},
  publisher = {Springer Nature Switzerland},
  year = {2026},
  month = aug,
  pages = {17--31},
  doi = {10.1007/978-3-032-35248-4_2},
  url = {https://doi.org/10.1007/978-3-032-35248-4_2},
  isbn = {9783032352484},
  issn = {1611-3349}
}`;

export function CiteView() {
  const { manifest } = useDataset();
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    if (!copied) return;
    const timeout = window.setTimeout(() => setCopied(false), 1800);
    return () => window.clearTimeout(timeout);
  }, [copied]);

  async function copyBibtex(): Promise<void> {
    try {
      await navigator.clipboard.writeText(ORIGINAL_PAPER_BIBTEX);
      setCopied(true);
    } catch {
      window.prompt("Copy BibTeX", ORIGINAL_PAPER_BIBTEX);
    }
  }

  return (
    <main id="main-content" className="page-shell cite-page">
      <PageIntro
        eyebrow="Citation"
        title="Cite this work"
        description={<>The peer-reviewed Euro-Par 2026 paper is the current citation target for this explorer.</>}
      />

      <div className="cite-layout">
        <section className="cite-card cite-authors" aria-labelledby="cite-authors-heading">
          <p className="eyebrow">Authors</p>
          <h2 id="cite-authors-heading">Peter Thoman and Philipp Gschwandtner</h2>
          <ul>
            <li>
              <a href="https://dps.uibk.ac.at/~petert" target="_blank" rel="noreferrer">Peter Thoman <span aria-hidden="true">↗</span></a>
            </li>
            <li>
              <a href="https://dps.uibk.ac.at/~philipp" target="_blank" rel="noreferrer">Philipp Gschwandtner <span aria-hidden="true">↗</span></a>
            </li>
          </ul>
          <p>
            Distributed and Parallel Systems Research Group,
            University of Innsbruck.
          </p>
        </section>

        <section className="cite-card cite-publication" aria-labelledby="cite-publication-heading">
          <header>
            <p className="eyebrow">Current citation target</p>
            <span>Original paper</span>
          </header>
          <h2 id="cite-publication-heading">
            <a href={PAPER_URL} target="_blank" rel="noreferrer">
              Evaluating the Parallelization Capabilities of State-of-the-Art Agentic Large Language Models
            </a>
          </h2>
          <p>Peter Thoman and Philipp Gschwandtner</p>
          <dl>
            <div><dt>Published in</dt><dd>Euro-Par 2026: Parallel Processing</dd></div>
            <div><dt>Series</dt><dd>Lecture Notes in Computer Science, volume 16781</dd></div>
            <div><dt>Pages</dt><dd>17–31</dd></div>
            <div><dt>Publisher</dt><dd>Springer Nature Switzerland, 2026</dd></div>
            <div><dt>DOI</dt><dd><a href={DOI_URL} target="_blank" rel="noreferrer">10.1007/978-3-032-35248-4_2</a></dd></div>
          </dl>
          <aside className="citation-scope-note" aria-label="Citation scope">
            <strong>Scope note</strong>
            <p>
              This explorer contains an extended dataset and uses a slightly revised methodology.
              The citation above describes the original published study and does not document every model
              or methodological detail in the current snapshot. When reporting results obtained from this
              site, identify artifact snapshot <code>{manifest.artifactCommit.slice(0, 9)}</code> in addition
              to citing the paper.
            </p>
          </aside>
        </section>

        <section className="cite-card cite-bibtex" aria-labelledby="cite-bibtex-heading">
          <header>
            <div>
              <p className="eyebrow">Bibliography</p>
              <h2 id="cite-bibtex-heading">BibTeX</h2>
            </div>
            <button className="secondary-button" type="button" onClick={() => void copyBibtex()}>
              <span aria-hidden="true">{copied ? "✓" : "⧉"}</span>
              {copied ? "Copied" : "Copy BibTeX"}
            </button>
          </header>
          <pre><code>{ORIGINAL_PAPER_BIBTEX}</code></pre>
          <p className="copy-status" aria-live="polite">{copied ? "BibTeX copied to the clipboard." : ""}</p>
        </section>
      </div>
    </main>
  );
}
