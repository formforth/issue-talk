"use strict";
let renderRevision = 0;
window.renderDiagram = async function (source, dark) {
  if (source.length > 20000 || source.includes("%%{") || /^\s*---/.test(source)) {
    throw new Error("Unsupported diagram configuration or size");
  }
  const revision = ++renderRevision;
  document.body.className = dark ? "dark" : "";
  mermaid.initialize({
    startOnLoad: false,
    securityLevel: "strict",
    theme: dark ? "dark" : "default",
    suppressErrorRendering: true,
    maxTextSize: 20000,
    maxEdges: 200,
    htmlLabels: false,
    flowchart: { htmlLabels: false },
    secure: ["secure", "securityLevel", "startOnLoad", "maxTextSize", "maxEdges", "htmlLabels"]
  });
  const result = await mermaid.render("issueTalkDiagram", source);
  if (revision === renderRevision) document.getElementById("diagram").innerHTML = result.svg;
  return true;
};
