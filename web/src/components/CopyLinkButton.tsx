import { useEffect, useState } from "react";

export function CopyLinkButton() {
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    if (!copied) return;
    const timeout = window.setTimeout(() => setCopied(false), 1800);
    return () => window.clearTimeout(timeout);
  }, [copied]);

  async function copy(): Promise<void> {
    try {
      await navigator.clipboard.writeText(window.location.href);
      setCopied(true);
    } catch {
      window.prompt("Copy this link", window.location.href);
    }
  }

  return (
    <button className="quiet-button share-button" type="button" onClick={() => void copy()}>
      <span aria-hidden="true">{copied ? "✓" : "↗"}</span>
      {copied ? "Copied" : "Share view"}
    </button>
  );
}
