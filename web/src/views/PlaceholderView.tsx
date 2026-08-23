import { Link } from "react-router-dom";

export function PlaceholderView() {
  return (
    <main id="main-content" className="page-shell">
      <div className="empty-state staged-state">
        <p className="eyebrow">Next review step</p>
        <h1>This analysis view is intentionally staged.</h1>
        <p>The first reviewable build covers the tier overview and its complete evidence drill-down. This route will be implemented after that build is reviewed.</p>
        <Link className="secondary-button" to="/tiers">Return to Tiered success</Link>
      </div>
    </main>
  );
}
