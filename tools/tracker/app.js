// Polls /data.json and redraws the scene snapshots, roadmap and model gallery when they change.
"use strict";

const POLL_MS = 3000;
const STATUS_LABEL = { done: "Done", "in-progress": "In progress", planned: "Planned" };
let version = null;
let data = null;
let filter = "all";
let lastOk = 0;

const $ = (id) => document.getElementById(id);

function el(tag, attrs = {}, ...children) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === "class") node.className = v;
    else if (k.startsWith("on")) node.addEventListener(k.slice(2), v);
    else if (v !== undefined && v !== null) node.setAttribute(k, v);
  }
  for (const c of children.flat()) {
    if (c === null || c === undefined) continue;
    node.append(c instanceof Node ? c : document.createTextNode(String(c)));
  }
  return node;
}

function badge(status) {
  return el("span", { class: `badge ${status}` }, STATUS_LABEL[status] || status);
}

function ago(seconds) {
  if (!seconds) return "";
  const s = Math.max(0, Date.now() / 1000 - seconds);
  if (s < 60) return "just now";
  if (s < 3600) return `${Math.floor(s / 60)} min ago`;
  if (s < 86400) return `${Math.floor(s / 3600)} h ago`;
  return `${Math.floor(s / 86400)} d ago`;
}

function progress(items) {
  if (!items.length) return null;
  const done = items.filter((i) => i.status === "done").length;
  const pct = Math.round((done / items.length) * 100);
  return el("div", { class: "progress", role: "progressbar", "aria-valuenow": pct, "aria-valuemin": 0, "aria-valuemax": 100, "aria-label": `${done} of ${items.length} done` },
    el("span", { style: `width:${pct}%` }),
  );
}

function renderNow() {
  const r = data.roadmap;
  const m = (r.milestones || []).find((x) => x.id === r.now);
  const box = $("now");
  box.replaceChildren();
  if (!m) return;
  const items = m.items || [];
  const current = items.filter((i) => i.status === "in-progress");
  const done = items.filter((i) => i.status === "done").length;
  box.append(...[
    el("p", { class: "eyebrow" }, "Now working on"),
    el("h2", {}, `Milestone ${m.id}: ${m.title}`),
    el("p", { class: "summary" }, m.summary || ""),
    progress(items),
    el("p", { class: "count" }, `${done} of ${items.length} items done`),
    current.length ? el("ul", { class: "current" }, current.map((i) => el("li", {}, i.text))) : null,
  ].filter(Boolean));
}

function renderRoadmap() {
  const list = $("roadmap");
  list.replaceChildren(
    ...(data.roadmap.milestones || []).map((m) => {
      const items = m.items || [];
      const models = data.models.filter((x) => x.milestone === m.id);
      const open = m.status === "in-progress";
      return el("li", { class: `milestone ${m.status}` },
        el("details", open ? { open: "" } : {},
          el("summary", {},
            el("span", { class: "mid" }, m.id),
            el("span", { class: "mtitle" }, m.title),
            badge(m.status),
            models.length ? el("span", { class: "mcount" }, `${models.length} model${models.length === 1 ? "" : "s"}`) : null,
          ),
          el("p", { class: "summary" }, m.summary || ""),
          progress(items),
          milestoneStrip(m.id),
          items.length
            ? el("ul", { class: "items" }, items.map((i) => el("li", { class: i.status },
                el("span", { class: "tick", "aria-hidden": "true" }), el("span", {}, i.text),
                el("span", { class: "sr" }, ` (${STATUS_LABEL[i.status] || i.status})`))))
            : el("p", { class: "empty" }, "Items are decided in this milestone's Q&A."),
        ),
      );
    }),
  );
}

function modelCard(m) {
  const hero = m.renders[0];
  const figure = hero
    ? el("button", { class: "thumb", type: "button", "aria-label": `Enlarge ${m.name}`, onclick: () => openViewer(m) },
        el("img", { src: hero.url, alt: `${m.name} render`, loading: "lazy" }))
    : el("div", { class: "thumb placeholder" }, el("span", {}, m.status === "planned" ? "Not started" : "No render yet"));
  return el("article", { class: `model ${m.status}` },
    figure,
    el("div", { class: "meta" },
      el("h4", {}, m.name),
      badge(m.status),
    ),
    m.note ? el("p", { class: "note" }, m.note) : null,
    el("p", { class: "updated" }, m.updated ? `Rendered ${ago(m.updated)}` : (m.built ? "Built, not rendered" : "")),
  );
}

function renderModels() {
  const box = $("models");
  box.replaceChildren();
  const shown = data.models.filter((m) => filter === "all" || m.status === filter);
  if (data.catalog_error) box.append(el("p", { class: "error" }, data.catalog_error));
  if (!shown.length) {
    box.append(el("p", { class: "empty" }, data.models.length ? "Nothing matches this filter." : "No models yet. They appear here as the art pipeline builds them."));
    return;
  }
  for (const m of data.roadmap.milestones || []) {
    const group = shown.filter((x) => x.milestone === m.id);
    if (!group.length) continue;
    box.append(
      el("h3", { class: "group" }, `Milestone ${m.id}: ${m.title}`),
      el("div", { class: "grid" }, group.map(modelCard)),
    );
  }
}

// The viewer shows one image of a list ({url, caption}) and steps through it.
let viewerList = [];
let viewerIndex = 0;

function openViewer(m) {
  openImages(m.renders.map((r) => ({ url: r.url, caption: `${m.name} · ${STATUS_LABEL[m.status] || m.status}${m.note ? " · " + m.note : ""}` })), 0);
}

function openImages(list, index) {
  viewerList = list;
  viewerIndex = index;
  showViewerImage();
  const dlg = $("viewer");
  if (!dlg.open) dlg.showModal();
}

function showViewerImage() {
  const item = viewerList[viewerIndex];
  if (!item) return;
  $("viewer-img").src = item.url;
  $("viewer-img").alt = item.caption;
  const many = viewerList.length > 1;
  $("viewer-caption").textContent = many ? `${item.caption} (${viewerIndex + 1} of ${viewerList.length})` : item.caption;
  $("viewer-prev").hidden = !many;
  $("viewer-next").hidden = !many;
}

function stepViewer(delta) {
  if (viewerList.length < 2) return;
  viewerIndex = (viewerIndex + delta + viewerList.length) % viewerList.length;
  showViewerImage();
}

$("viewer-prev").addEventListener("click", () => stepViewer(-1));
$("viewer-next").addEventListener("click", () => stepViewer(1));
$("viewer").addEventListener("keydown", (e) => {
  if (e.key === "ArrowLeft") stepViewer(-1);
  if (e.key === "ArrowRight") stepViewer(1);
});

// --- scene snapshots ---

function milestoneTitle(id) {
  const m = (data.roadmap.milestones || []).find((x) => x.id === id);
  return m ? `Milestone ${m.id}: ${m.title}` : `Milestone ${id}`;
}

function when(iso) {
  const t = Date.parse(iso);
  if (Number.isNaN(t)) return iso;
  return new Date(t).toLocaleString(undefined, { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });
}

function snapImages(snap) {
  return snap.shots.map((s) => ({ url: s.url, caption: `${s.title} · ${milestoneTitle(snap.milestone)} · ${when(snap.time)}` }));
}

function shotButton(snap, i, cls) {
  const s = snap.shots[i];
  return el("figure", { class: cls },
    el("button", { class: "thumb", type: "button", "aria-label": `Enlarge: ${s.title}`, onclick: () => openImages(snapImages(snap), i) },
      el("img", { src: s.url, alt: s.title, loading: "lazy" })),
    el("figcaption", {}, s.title),
  );
}

function snapMeta(snap) {
  return el("p", { class: "snapmeta" },
    el("strong", {}, milestoneTitle(snap.milestone)), ` · ${when(snap.time)}`,
    snap.commit ? el("code", {}, snap.commit) : null,
    snap.note ? ` · ${snap.note}` : "",
  );
}

function renderScenes() {
  const snaps = data.scenes || [];
  const latest = $("latest");
  const timeline = $("timeline");
  latest.replaceChildren();
  timeline.replaceChildren();
  if (!snaps.length) {
    latest.append(el("p", { class: "empty" }, "No snapshots yet. Take one with tools/tracker/capture.py."));
    return;
  }
  const newest = snaps[snaps.length - 1];
  latest.append(
    snapMeta(newest),
    el("div", { class: "scene-hero" }, newest.shots.map((_, i) => shotButton(newest, i, i === 0 ? "hero" : "shot"))),
  );
  for (const snap of [...snaps].reverse()) {
    timeline.append(el("li", { class: "snap" },
      snapMeta(snap),
      el("div", { class: "strip" }, snap.shots.map((_, i) => shotButton(snap, i, "shot"))),
    ));
  }
}

// A milestone's newest snapshot, shown in its roadmap entry.
function milestoneStrip(id) {
  const snaps = (data.scenes || []).filter((s) => s.milestone === id);
  if (!snaps.length) return null;
  const snap = snaps[snaps.length - 1];
  return el("div", { class: "strip small" }, snap.shots.map((_, i) => shotButton(snap, i, "shot")));
}

function render() {
  renderNow();
  renderScenes();
  renderRoadmap();
  renderModels();
}

async function poll() {
  try {
    const res = await fetch("/data.json", { cache: "no-store" });
    if (!res.ok) throw new Error(res.statusText);
    const next = await res.json();
    lastOk = Date.now();
    if (next.version !== version) {
      version = next.version;
      data = next;
      render();
    }
    $("live").textContent = "Live · updates automatically";
    $("live").classList.remove("stale");
  } catch (e) {
    $("live").textContent = lastOk ? `Offline · last update ${ago(lastOk / 1000)}` : "Can't reach the tracker server";
    $("live").classList.add("stale");
  }
  setTimeout(poll, POLL_MS);
}

document.querySelectorAll("[data-filter]").forEach((b) =>
  b.addEventListener("click", () => {
    filter = b.dataset.filter;
    document.querySelectorAll("[data-filter]").forEach((x) => x.setAttribute("aria-pressed", String(x === b)));
    if (data) renderModels();
  }),
);

// Keep the "rendered N min ago" labels fresh between data changes.
setInterval(() => { if (data) renderModels(); }, 60000);
poll();
