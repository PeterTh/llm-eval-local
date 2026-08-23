import { Navigate, Route, Routes } from "react-router-dom";

import { SiteHeader } from "./components/SiteHeader";
import { CiteView } from "./views/CiteView";
import { ComplexityView } from "./views/ComplexityView";
import { MethodologyView } from "./views/MethodologyView";
import { PerformanceView } from "./views/PerformanceView";
import { RunDetailView } from "./views/RunDetailView";
import { RunsView } from "./views/RunsView";
import { ScoresView } from "./views/ScoresView";
import { TiersView } from "./views/TiersView";

export function App() {
  return (
    <div className="app-shell">
      <a className="skip-link" href="#main-content">Skip to content</a>
      <SiteHeader />
      <Routes>
        <Route path="/tiers" element={<TiersView />} />
        <Route path="/runs" element={<RunsView />} />
        <Route path="/run/:id" element={<RunDetailView />} />
        <Route path="/scores" element={<ScoresView />} />
        <Route path="/complexity" element={<ComplexityView />} />
        <Route path="/performance" element={<PerformanceView />} />
        <Route path="/methodology" element={<MethodologyView />} />
        <Route path="/cite" element={<CiteView />} />
        <Route path="*" element={<Navigate to="/tiers" replace />} />
      </Routes>
      <footer className="site-footer">
        <div className="footer-brands" aria-label="Institutional affiliations">
          <a href="https://dps.uibk.ac.at/" target="_blank" rel="noreferrer" aria-label="Distributed and Parallel Systems Research Group">
            <img className="footer-dps-logo" src={`${import.meta.env.BASE_URL}brand/dps-logo.svg`} alt="DPS" />
          </a>
          <a href="https://www.uibk.ac.at/" target="_blank" rel="noreferrer" aria-label="University of Innsbruck">
            <img className="footer-uibk-logo" src={`${import.meta.env.BASE_URL}brand/uibk-logo.svg`} alt="University of Innsbruck" />
          </a>
        </div>
      </footer>
    </div>
  );
}
