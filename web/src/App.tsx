import { Navigate, Route, Routes } from "react-router-dom";

import { SiteFooter } from "./components/SiteFooter";
import { SiteHeader } from "./components/SiteHeader";
import { CiteView } from "./views/CiteView";
import { ComplexityView } from "./views/ComplexityView";
import { CostView } from "./views/CostView";
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
        <Route path="/cost" element={<CostView />} />
        <Route path="/methodology" element={<MethodologyView />} />
        <Route path="/cite" element={<CiteView />} />
        <Route path="*" element={<Navigate to="/tiers" replace />} />
      </Routes>
      <SiteFooter />
    </div>
  );
}
