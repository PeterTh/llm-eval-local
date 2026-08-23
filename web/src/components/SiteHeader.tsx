import { useEffect, useRef } from "react";
import { Link, NavLink, useLocation } from "react-router-dom";

import { useDataset } from "../data/context";
import { CopyLinkButton } from "./CopyLinkButton";

const navigation = [
  { to: "/tiers", label: "Tiered Success", enabled: true, className: "nav-tiers" },
  { to: "/scores", label: "Model scores", enabled: true, className: "nav-scores" },
  { to: "/complexity", label: "Complexity", enabled: true, className: "nav-complexity" },
  { to: "/performance", label: "Performance", enabled: false, className: "nav-performance" },
  { to: "/runs", label: "Runs", enabled: true, className: "nav-runs" },
] as const;

function shortHash(value: string): string {
  return value.slice(0, 9);
}

export function SiteHeader() {
  const { manifest } = useDataset();
  const location = useLocation();
  const aboutMenu = useRef<HTMLDetailsElement>(null);
  const snapshotUrl = `${manifest.artifactRepository}/tree/${manifest.artifactCommit}`;
  const persistentParams = new URLSearchParams();
  const currentParams = new URLSearchParams(location.search);
  for (const key of ["model", "model-set", "benchmark", "backend"]) {
    currentParams.getAll(key).forEach((value) => persistentParams.append(key, value));
  }
  const persistentSearch = persistentParams.toString();

  useEffect(() => {
    function closeOnOutsidePointer(event: PointerEvent) {
      const menu = aboutMenu.current;
      if (menu?.open && event.target instanceof Node && !menu.contains(event.target)) {
        menu.open = false;
      }
    }

    function closeOnEscape(event: KeyboardEvent) {
      const menu = aboutMenu.current;
      if (event.key === "Escape" && menu?.open) {
        menu.open = false;
        menu.querySelector<HTMLElement>("summary")?.focus();
      }
    }

    document.addEventListener("pointerdown", closeOnOutsidePointer);
    document.addEventListener("keydown", closeOnEscape);
    return () => {
      document.removeEventListener("pointerdown", closeOnOutsidePointer);
      document.removeEventListener("keydown", closeOnEscape);
    };
  }, []);

  return (
    <>
      <header className="site-header">
        <div className="brand-lockup">
          <NavLink className="brand-mark" to={{ pathname: "/tiers", search: persistentSearch }} aria-label="LLM Autoparallelization Benchmark home">
            <i /><i /><i /><i />
          </NavLink>
          <div>
            <p className="brand-name">LLM Autoparallelization Benchmark</p>
          </div>
        </div>
        <div className="header-actions">
          <CopyLinkButton />
          <details ref={aboutMenu} className="about-menu">
            <summary className="quiet-button">About</summary>
            <div className="about-panel">
              <h2>About this evaluation</h2>
              <p>
                This page presents data from an ongoing evaluation of LLM parallelization capabilities
                carried out by the <a href="https://dps.uibk.ac.at/" target="_blank" rel="noreferrer">Distributed
                and Parallel Systems Research Group</a> at the <a href="https://www.uibk.ac.at/" target="_blank" rel="noreferrer">University of Innsbruck</a>.
              </p>
              <p><Link to={{ pathname: "/methodology", search: persistentSearch }} onClick={() => { if (aboutMenu.current) aboutMenu.current.open = false; }}>Methodology</Link> summarizes the experimental design, validation pipeline, performance measurements, and scoring procedure.</p>
              <p><Link to={{ pathname: "/cite", search: persistentSearch }} onClick={() => { if (aboutMenu.current) aboutMenu.current.open = false; }}>Citation information</Link> lists the authors and copyable BibTeX.</p>
              <dl className="provenance-list compact">
                <div><dt>Artifact</dt><dd><a href={snapshotUrl} target="_blank" rel="noreferrer">{shortHash(manifest.artifactCommit)}</a></dd></div>
                <div><dt>Scoring digest</dt><dd><code>{shortHash(manifest.scoringDigest)}</code></dd></div>
                <div><dt>Generated source</dt><dd><a href={`${manifest.generatedSourceRepository}/tree/${manifest.generatedSourceCommit}`} target="_blank" rel="noreferrer">{shortHash(manifest.generatedSourceCommit)}</a></dd></div>
                <div><dt>Site build</dt><dd><code>{__SITE_BUILD_COMMIT__.slice(0, 9)}</code></dd></div>
              </dl>
            </div>
          </details>
        </div>
      </header>
      <nav className="primary-nav" aria-label="Analysis views">
        <div className="nav-scroll">
          {navigation.map((item) => item.enabled ? (
            <NavLink
              key={item.to}
              to={{ pathname: item.to, search: persistentSearch }}
              className={({ isActive }) => `${item.className}${isActive ? " active" : ""}`}
            >
              {item.label}
            </NavLink>
          ) : (
            <span key={item.to} className={`nav-pending ${item.className}`} aria-disabled="true">
              {item.label}
            </span>
          ))}
          <span className="nav-separator" aria-hidden="true">|</span>
          <NavLink
            to={{ pathname: "/methodology", search: persistentSearch }}
            className={({ isActive }) => `nav-methodology${isActive ? " active" : ""}`}
          >
            Methodology
          </NavLink>
          <NavLink
            to={{ pathname: "/cite", search: persistentSearch }}
            className={({ isActive }) => `nav-cite${isActive ? " active" : ""}`}
          >
            Cite
          </NavLink>
        </div>
        <a className="snapshot-link" href={snapshotUrl} target="_blank" rel="noreferrer">
          Snapshot <code>{shortHash(manifest.artifactCommit)}</code> ↗
        </a>
      </nav>
    </>
  );
}
