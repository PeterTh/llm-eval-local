import { useDataset } from "../data/context";
import { formatSnapshotTimestamp, shortHash } from "../utils/format";

export function SiteFooter() {
  const { manifest } = useDataset();
  const snapshotUrl = `${manifest.artifactRepository}/tree/${manifest.artifactCommit}`;

  return (
    <footer className="site-footer">
      <a className="footer-snapshot" href={snapshotUrl} target="_blank" rel="noreferrer">
        <span>Snapshot <code>{shortHash(manifest.artifactCommit)}</code> ↗</span>
        <time dateTime={manifest.dataGeneratedAt}>{formatSnapshotTimestamp(manifest.dataGeneratedAt)}</time>
      </a>
      <div className="footer-brands" aria-label="Institutional affiliations">
        <a
          className="footer-dps-link"
          href="https://dps.uibk.ac.at/"
          target="_blank"
          rel="noreferrer"
          aria-label="Distributed and Parallel Systems Research Group"
        >
          <img className="footer-dps-logo" src={`${import.meta.env.BASE_URL}brand/dps-logo.svg`} alt="DPS" />
        </a>
        <a href="https://www.uibk.ac.at/" target="_blank" rel="noreferrer" aria-label="University of Innsbruck">
          <img className="footer-uibk-logo" src={`${import.meta.env.BASE_URL}brand/uibk-logo.svg`} alt="University of Innsbruck" />
        </a>
      </div>
    </footer>
  );
}
