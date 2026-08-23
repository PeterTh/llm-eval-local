import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { HashRouter } from "react-router-dom";

import "@fontsource-variable/roboto-condensed/wght.css";
import { App } from "./App";
import { DatasetProvider } from "./data/context";
import "./styles.css";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <HashRouter>
      <DatasetProvider>
        <App />
      </DatasetProvider>
    </HashRouter>
  </StrictMode>,
);
