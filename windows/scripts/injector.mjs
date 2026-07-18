import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const windowsRoot = path.resolve(here, "..");
const repositoryRoot = path.resolve(windowsRoot, "..");
const DEFAULT_CATALOG = path.join(repositoryRoot, "themes", "catalog.json");
const SKIN_VERSION = "2.2.9";
const LOOPBACK_HOSTS = new Set(["127.0.0.1", "localhost", "[::1]"]);
const MAX_ART_BYTES = 16 * 1024 * 1024;
const WINDOW_ACTION_BINDING = "__codexDreamSkinWindowAction";

function parseArgs(argv) {
  const options = {
    port: 9335,
    mode: "watch",
    timeoutMs: 30000,
    screenshot: null,
    reload: false,
    catalog: DEFAULT_CATALOG,
    themeId: null,
    themeDir: null,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--port") options.port = Number(argv[++i]);
    else if (arg === "--once") options.mode = "once";
    else if (arg === "--watch") options.mode = "watch";
    else if (arg === "--verify") options.mode = "verify";
    else if (arg === "--remove") options.mode = "remove";
    else if (arg === "--check-payload") options.mode = "check";
    else if (arg === "--window-smoke") options.mode = "window-smoke";
    else if (arg === "--resize-self-test") options.mode = "resize-self-test";
    else if (arg === "--timeout-ms") options.timeoutMs = Number(argv[++i]);
    else if (arg === "--screenshot") options.screenshot = path.resolve(argv[++i]);
    else if (arg === "--catalog") options.catalog = path.resolve(argv[++i]);
    else if (arg === "--theme-id") options.themeId = String(argv[++i]);
    else if (arg === "--theme-dir") options.themeDir = path.resolve(argv[++i]);
    else if (arg === "--reload") options.reload = true;
    else throw new Error(`Unknown argument: ${arg}`);
  }
  if (!Number.isInteger(options.port) || options.port < 1024 || options.port > 65535) {
    throw new Error(`Invalid port: ${options.port}`);
  }
  if (!Number.isFinite(options.timeoutMs) || options.timeoutMs < 250 || options.timeoutMs > 120000) {
    throw new Error(`Invalid timeout: ${options.timeoutMs}`);
  }
  return options;
}

function validatedDebuggerUrl(target, port) {
  const url = new URL(target.webSocketDebuggerUrl);
  if (url.protocol !== "ws:" || !LOOPBACK_HOSTS.has(url.hostname) || Number(url.port) !== port) {
    throw new Error(`Rejected non-loopback CDP WebSocket URL: ${url.href}`);
  }
  return url.href;
}

class CdpSession {
  constructor(target, port) {
    this.target = target;
    this.port = port;
    this.ws = new WebSocket(validatedDebuggerUrl(target, port));
    this.nextId = 1;
    this.pending = new Map();
    this.listeners = new Map();
    this.closed = false;
  }

  async open({ enableRuntime = true, enablePage = true } = {}) {
    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error("CDP WebSocket open timed out")), 5000);
      this.ws.addEventListener("open", () => { clearTimeout(timeout); resolve(); }, { once: true });
      this.ws.addEventListener("error", () => { clearTimeout(timeout); reject(new Error("CDP WebSocket open failed")); }, { once: true });
    });
    this.ws.addEventListener("message", (event) => this.onMessage(event));
    this.ws.addEventListener("close", () => {
      this.closed = true;
      for (const waiter of this.pending.values()) {
        clearTimeout(waiter.timeout);
        waiter.reject(new Error("CDP socket closed"));
      }
      this.pending.clear();
    });
    if (enableRuntime) await this.send("Runtime.enable");
    if (enablePage) await this.send("Page.enable");
    return this;
  }

  onMessage(event) {
    const message = JSON.parse(String(event.data));
    if (message.id) {
      const waiter = this.pending.get(message.id);
      if (!waiter) return;
      clearTimeout(waiter.timeout);
      this.pending.delete(message.id);
      if (message.error) waiter.reject(new Error(`${message.error.message} (${message.error.code})`));
      else waiter.resolve(message.result);
      return;
    }
    for (const listener of this.listeners.get(message.method) ?? []) listener(message.params ?? {});
  }

  on(method, listener) {
    const listeners = this.listeners.get(method) ?? [];
    listeners.push(listener);
    this.listeners.set(method, listeners);
  }

  send(method, params = {}) {
    if (this.closed) return Promise.reject(new Error("CDP session is closed"));
    return new Promise((resolve, reject) => {
      const id = this.nextId++;
      const timeout = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`CDP command timed out: ${method}`));
      }, 10000);
      this.pending.set(id, { resolve, reject, timeout });
      this.ws.send(JSON.stringify({ id, method, params }));
    });
  }

  async evaluate(expression) {
    const result = await this.send("Runtime.evaluate", {
      expression,
      awaitPromise: true,
      returnByValue: true,
      userGesture: false,
    });
    if (result.exceptionDetails) {
      const detail = result.exceptionDetails.exception?.description ?? result.exceptionDetails.text;
      throw new Error(`Renderer evaluation failed: ${detail}`);
    }
    return result.result?.value;
  }

  close() {
    if (!this.closed) this.ws.close();
    this.closed = true;
  }
}

async function fetchJson(url, timeoutMs = 2000) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, { signal: controller.signal });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    return response.json();
  } finally {
    clearTimeout(timeout);
  }
}

async function listAppTargets(port) {
  const targets = await fetchJson(`http://127.0.0.1:${port}/json/list`);
  return targets.filter((item) => {
    if (item.type !== "page" || !item.url?.startsWith("app://") || !item.webSocketDebuggerUrl) return false;
    try { validatedDebuggerUrl(item, port); return true; } catch { return false; }
  });
}

async function connectTarget(target, port) {
  return new CdpSession(target, port).open();
}

async function connectBrowserSession(port) {
  const version = await fetchJson(`http://127.0.0.1:${port}/json/version`);
  const target = {
    id: "browser",
    title: "Codex Browser",
    url: `http://127.0.0.1:${port}/json/version`,
    webSocketDebuggerUrl: version.webSocketDebuggerUrl,
  };
  return new CdpSession(target, port).open({ enableRuntime: false, enablePage: false });
}

async function probeSession(session) {
  return session.evaluate(`(() => {
    const markers = {
      shell: Boolean(document.querySelector('main.main-surface')),
      sidebar: Boolean(document.querySelector('aside.app-shell-left-panel')),
      composer: Boolean(document.querySelector('.composer-surface-chrome')),
      main: Boolean(document.querySelector('[role="main"]')),
    };
    return { title: document.title, href: location.href, markers,
      codex: markers.shell && markers.sidebar && (markers.composer || markers.main) };
  })()`);
}

async function connectCodexTargets(port, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  let lastError;
  while (Date.now() < deadline) {
    try {
      const connected = [];
      for (const target of await listAppTargets(port)) {
        let session;
        try {
          session = await connectTarget(target, port);
          const probe = await probeSession(session);
          if (probe?.codex) connected.push({ target, session, probe });
          else session.close();
        } catch (error) {
          session?.close();
          lastError = error;
        }
      }
      if (connected.length) return connected;
      lastError = new Error("No page matched the expected Codex shell markers");
    } catch (error) { lastError = error; }
    await new Promise((resolve) => setTimeout(resolve, 350));
  }
  throw new Error(`No verified Codex renderer on 127.0.0.1:${port}: ${lastError?.message ?? "timed out"}`);
}

const text = (value, fallback, max) => typeof value === "string" && value.trim()
  ? value.trim().slice(0, max) : fallback;
const color = (value, fallback) => {
  if (typeof value !== "string") return fallback;
  const normalized = value.trim();
  return /^#[0-9a-f]{6}$/i.test(normalized) || /^rgba?\([0-9., %]+\)$/i.test(normalized)
    ? normalized : fallback;
};

function normalizeVisual(rawVisual) {
  if (!rawVisual || typeof rawVisual !== "object" || Array.isArray(rawVisual)) return null;
  const layoutVariant = ["enfp", "purple-night", "miku"].includes(rawVisual.layoutVariant)
    ? rawVisual.layoutVariant : "";
  const sidebar = rawVisual.sidebar && typeof rawVisual.sidebar === "object" && !Array.isArray(rawVisual.sidebar)
    ? {
        brand: text(rawVisual.sidebar.brand, "", 80),
        subtitle: text(rawVisual.sidebar.subtitle, "", 80),
        footerText: text(rawVisual.sidebar.footerText, "", 80),
      }
    : { brand: "", subtitle: "", footerText: "" };
  const cards = Array.isArray(rawVisual.cards) ? rawVisual.cards.slice(0, 4).map((card) => {
    const source = card && typeof card === "object" && !Array.isArray(card) ? card : {};
    const action = source.action === "plugins" ? "plugins" : "prompt";
    return {
      icon: text(source.icon, "✦", 12),
      title: text(source.title, "Codex", 48),
      detail: text(source.detail, "", 100),
      action,
      prompt: action === "prompt" ? text(source.prompt, source.title || "", 240) : "",
    };
  }) : [];
  const noteSource = rawVisual.note && typeof rawVisual.note === "object" && !Array.isArray(rawVisual.note)
    ? rawVisual.note : {};
  const note = {
    title: text(noteSource.title, "", 80),
    lines: Array.isArray(noteSource.lines)
      ? noteSource.lines.slice(0, 4).map((line) => text(line, "", 120)).filter(Boolean)
      : [],
  };
  const chromeSource = rawVisual.chrome && typeof rawVisual.chrome === "object" && !Array.isArray(rawVisual.chrome)
    ? rawVisual.chrome : {};
  return {
    layoutVariant,
    sidebar,
    cards,
    note,
    chrome: {
      sparkles: chromeSource.sparkles === true,
      ribbon: chromeSource.ribbon === true,
      polaroid: chromeSource.polaroid === true,
    },
  };
}

function normalizeTheme(raw, packTheme = {}) {
  const mergedVisual = packTheme.visual || raw.visual ? {
    ...(packTheme.visual ?? {}),
    ...(raw.visual ?? {}),
    sidebar: { ...(packTheme.visual?.sidebar ?? {}), ...(raw.visual?.sidebar ?? {}) },
    note: { ...(packTheme.visual?.note ?? {}), ...(raw.visual?.note ?? {}) },
    chrome: { ...(packTheme.visual?.chrome ?? {}), ...(raw.visual?.chrome ?? {}) },
    cards: Array.isArray(raw.visual?.cards) ? raw.visual.cards : packTheme.visual?.cards,
  } : null;
  const merged = {
    ...packTheme,
    ...raw,
    colors: { ...(packTheme.colors ?? {}), ...(raw.colors ?? {}) },
    visual: mergedVisual,
  };
  const kind = merged.kind === "original" || merged.profile === "off" ? "original" : "theme";
  const appearance = merged.appearance === "light" || merged.appearance === "dark" ? merged.appearance : "";
  const artPosition = ["center center", "center top", "center bottom", "left center", "right center", "left top", "right top"]
    .includes(merged.art?.position) ? merged.art.position : "center center";
  const artSize = merged.art?.size === "contain" ? "contain" : "cover";
  return {
    schemaVersion: 1,
    id: text(merged.id, "custom", 80),
    kind,
    profile: kind === "original" ? "off" : text(merged.profile, "inspiration-universe", 40),
    appearance,
    art: { position: artPosition, size: artSize },
    name: text(merged.name, kind === "original" ? "原皮" : "Codex Dream Skin", 80),
    brandSubtitle: text(merged.brandSubtitle, "CODEX DREAM SKIN", 80),
    tagline: text(merged.tagline, "Make something wonderful.", 160),
    projectPrefix: text(merged.projectPrefix, "选择项目 · ", 80),
    projectLabel: text(merged.projectLabel, "◉  选择项目", 80),
    statusText: text(merged.statusText, "DREAM SKIN ONLINE", 80),
    quote: text(merged.quote, "MAKE SOMETHING WONDERFUL", 120),
    visual: normalizeVisual(merged.visual),
    image: typeof merged.image === "string" && merged.image ? merged.image : null,
    preview: typeof merged.preview === "string" && merged.preview ? merged.preview : null,
    colors: {
      background: color(merged.colors?.background, "#fff4fa"),
      panel: color(merged.colors?.panel, "#fffafd"),
      panelAlt: color(merged.colors?.panelAlt, "#f5eafd"),
      accent: color(merged.colors?.accent, "#b65cff"),
      accentAlt: color(merged.colors?.accentAlt, "#ff73bd"),
      secondary: color(merged.colors?.secondary, "#8b3dce"),
      highlight: color(merged.colors?.highlight, "#f3a5cc"),
      text: color(merged.colors?.text, "#4a235f"),
      muted: color(merged.colors?.muted, "#835f91"),
      line: color(merged.colors?.line, "rgba(221, 122, 184, .42)"),
    },
  };
}

async function pathExists(file) {
  try { await fs.access(file); return true; } catch { return false; }
}

function confinedPath(base, relative, label) {
  if (typeof relative !== "string" || !relative) return null;
  const resolved = path.resolve(base, relative);
  const rel = path.relative(repositoryRoot, resolved);
  if (rel.startsWith("..") || path.isAbsolute(rel)) throw new Error(`${label} escapes the installed theme root`);
  return resolved;
}

async function loadTheme(options) {
  let entry = null;
  let packRoot = null;
  let catalogRoot = path.dirname(options.catalog);

  if (options.themeDir) {
    packRoot = options.themeDir;
    const packTheme = JSON.parse(await fs.readFile(path.join(packRoot, "theme.json"), "utf8"));
    entry = packTheme;
  } else if (await pathExists(options.catalog)) {
    const catalog = JSON.parse(await fs.readFile(options.catalog, "utf8"));
    if (catalog.schemaVersion !== 1 || !Array.isArray(catalog.themes)) throw new Error("Unsupported theme catalog schema");
    entry = catalog.themes.find((item) => item.id === options.themeId || item.aliases?.includes(options.themeId));
    if (!entry) throw new Error(`Theme not found in catalog: ${options.themeId || "missing id"}`);
    if (entry.enabled === false) throw new Error(`Theme is disabled: ${entry.id}`);
    if (Array.isArray(entry.platforms) && !entry.platforms.some((value) => ["windows", "win32", "all"].includes(String(value).toLowerCase()))) {
      throw new Error(`Theme does not support Windows: ${entry.id}`);
    }
    if (entry.windowsThemeDir) {
      packRoot = confinedPath(repositoryRoot, entry.windowsThemeDir, "Windows theme pack");
    } else {
      const windowsPack = path.join(windowsRoot, "themes", entry.id);
      const compatiblePack = entry.pack ? confinedPath(repositoryRoot, entry.pack, "Theme pack") : path.join(repositoryRoot, "macos", "themes", entry.id);
      if (await pathExists(windowsPack)) packRoot = windowsPack;
      else if (await pathExists(compatiblePack)) packRoot = compatiblePack;
    }
    if (entry.image) {
      const catalogImage = confinedPath(repositoryRoot, entry.image, "Theme image");
      if (!packRoot || path.dirname(catalogImage) !== path.resolve(packRoot)) throw new Error(`Theme image is outside its declared pack: ${entry.id}`);
      entry = { ...entry, image: path.basename(catalogImage) };
    }
  } else {
    packRoot = path.join(windowsRoot, "assets");
    entry = JSON.parse(await fs.readFile(path.join(packRoot, "theme.json"), "utf8"));
  }

  let packTheme = {};
  if (packRoot && await pathExists(path.join(packRoot, "theme.json"))) {
    packTheme = JSON.parse(await fs.readFile(path.join(packRoot, "theme.json"), "utf8"));
  }
  const theme = normalizeTheme(entry, packTheme);
  if (theme.kind === "original") return { theme, imagePath: null, imageBytes: 0 };

  let imagePath = null;
  if (theme.image) {
    if (path.basename(theme.image) !== theme.image) throw new Error("Theme image must be a filename inside its pack");
    if (!packRoot) throw new Error(`Theme ${theme.id} declares an image without a pack`);
    imagePath = path.join(packRoot, theme.image);
    const stat = await fs.stat(imagePath);
    if (!stat.isFile() || stat.size < 1 || stat.size > MAX_ART_BYTES) {
      throw new Error(`Theme image must be a non-empty file no larger than ${MAX_ART_BYTES} bytes`);
    }
    const extension = path.extname(imagePath).toLowerCase();
    if (![".png", ".jpg", ".jpeg", ".webp"].includes(extension)) throw new Error(`Unsupported theme image: ${extension}`);
    return { theme, imagePath, imageBytes: stat.size };
  }
  return { theme, imagePath: null, imageBytes: 0 };
}

async function loadPayload(options) {
  const loaded = await loadTheme(options);
  if (loaded.theme.kind === "original") return { ...loaded, payload: null };
  const stylesheetByProfile = {
    "dream-fiona": "dream-skin.css",
    "inspiration-universe": "dream-skin.css",
    "generic": "dream-skin.css",
    "qq2007": "qq2007.css",
  };
  const stylesheet = stylesheetByProfile[loaded.theme.profile];
  if (!stylesheet) throw new Error(`Unsupported trusted theme profile: ${loaded.theme.profile}`);
  const cssPath = path.join(windowsRoot, "assets", stylesheet);
  const effectiveCss = await pathExists(cssPath) ? cssPath : path.join(windowsRoot, "assets", "dream-skin.css");
  const [css, template] = await Promise.all([
    fs.readFile(effectiveCss, "utf8"),
    fs.readFile(path.join(windowsRoot, "assets", "renderer-inject.js"), "utf8"),
  ]);
  let artDataUrl = "";
  if (loaded.imagePath) {
    const art = await fs.readFile(loaded.imagePath);
    const ext = path.extname(loaded.imagePath).toLowerCase();
    const mime = ext === ".jpg" || ext === ".jpeg" ? "image/jpeg" : ext === ".webp" ? "image/webp" : "image/png";
    artDataUrl = `data:${mime};base64,${art.toString("base64")}`;
  }
  const payload = template
    .replace("__DREAM_SKIN_CSS_JSON__", JSON.stringify(css))
    .replace("__DREAM_SKIN_ART_JSON__", JSON.stringify(artDataUrl))
    .replace("__DREAM_SKIN_THEME_JSON__", JSON.stringify(loaded.theme))
    .replace("__DREAM_SKIN_VERSION_JSON__", JSON.stringify(SKIN_VERSION));
  return { ...loaded, payload };
}

async function applyToSession(session, payload) { return session.evaluate(payload); }

async function removeFromSession(session) {
  return session.evaluate(`(() => {
    window.__CODEX_DREAM_SKIN_DISABLED__ = true;
    const state = window.__CODEX_DREAM_SKIN_STATE__;
    if (state?.cleanup) return state.cleanup();
    document.documentElement?.classList.remove('codex-dream-skin');
    document.documentElement?.removeAttribute('data-dream-theme');
    document.documentElement?.removeAttribute('data-dream-theme-id');
    document.documentElement?.removeAttribute('data-dream-palette');
    document.documentElement?.style.removeProperty('--dream-art');
    for (const name of ['--dream-theme-background','--dream-theme-panel','--dream-theme-panel-alt','--dream-theme-accent','--dream-theme-accent-alt','--dream-theme-secondary','--dream-theme-highlight','--dream-theme-text','--dream-theme-muted','--dream-theme-line']) {
      document.documentElement?.style.removeProperty(name);
    }
    document.getElementById('codex-dream-skin-style')?.remove();
    document.getElementById('codex-dream-skin-chrome')?.remove();
    delete window.__CODEX_DREAM_SKIN_STATE__;
    return true;
  })()`);
}

async function verifyRemovedSession(session) {
  return session.evaluate(`(() => !document.documentElement.classList.contains('codex-dream-skin') &&
    !document.documentElement.hasAttribute('data-dream-theme') &&
    !document.documentElement.hasAttribute('data-dream-theme-id') &&
    !document.documentElement.hasAttribute('data-dream-palette') &&
    !document.documentElement.style.getPropertyValue('--dream-art') &&
    !document.documentElement.style.getPropertyValue('--dream-theme-accent') &&
    !document.getElementById('codex-dream-skin-style') &&
    !document.getElementById('codex-dream-skin-chrome') &&
    !window.__CODEX_DREAM_SKIN_STATE__)()`);
}

async function verifySession(session, expectedId = null) {
  return session.evaluate(`(() => {
    const box = (node) => { if (!node) return null; const r = node.getBoundingClientRect();
      return { x: Math.round(r.x), y: Math.round(r.y), width: Math.round(r.width), height: Math.round(r.height) }; };
    const chrome = document.getElementById('codex-dream-skin-chrome');
    const result = {
      installed: document.documentElement.classList.contains('codex-dream-skin'),
      themeId: window.__CODEX_DREAM_SKIN_STATE__?.themeId ?? null,
      profile: document.documentElement.getAttribute('data-dream-theme'),
      version: window.__CODEX_DREAM_SKIN_STATE__?.version ?? null,
      stylePresent: Boolean(document.getElementById('codex-dream-skin-style')),
      chromePresent: Boolean(chrome),
      chromePointerEvents: chrome ? getComputedStyle(chrome).pointerEvents : null,
      composer: box(document.querySelector('.composer-surface-chrome')),
      sidebar: box(document.querySelector('aside.app-shell-left-panel')),
      viewport: { width: innerWidth, height: innerHeight },
      overflowX: document.documentElement.scrollWidth > document.documentElement.clientWidth,
    };
    result.pass = result.installed && result.stylePresent && result.chromePresent &&
      Boolean(result.composer) && Boolean(result.sidebar) && !result.overflowX &&
      (!${JSON.stringify(expectedId)} || result.themeId === ${JSON.stringify(expectedId)});
    return result;
  })()`);
}

async function waitForVerifiedSession(session, timeoutMs, expectedId) {
  const deadline = Date.now() + timeoutMs;
  let last;
  while (Date.now() < deadline) {
    last = await verifySession(session, expectedId);
    if (last.pass) return last;
    await new Promise((resolve) => setTimeout(resolve, 450));
  }
  return last;
}

async function capture(session, outputPath) {
  await fs.mkdir(path.dirname(outputPath), { recursive: true });
  const result = await session.send("Page.captureScreenshot", { format: "png", fromSurface: true, captureBeyondViewport: false });
  await fs.writeFile(outputPath, Buffer.from(result.data, "base64"));
}

const MIN_WINDOW_WIDTH = 760;
const MIN_WINDOW_HEIGHT = 560;
const RESIZE_DIRECTIONS = new Set(["n", "s", "e", "w", "ne", "nw", "se", "sw"]);
const normalBounds = new Map();
const resizeStates = new Map();
const windowActionQueues = new WeakMap();

const finiteNumber = (value, fallback = 0) => Number.isFinite(Number(value)) ? Number(value) : fallback;
const clampDelta = (value) => Math.max(-10000, Math.min(10000, finiteNumber(value)));
const geometryFromBounds = (bounds) => ({
  left: Math.round(finiteNumber(bounds?.left)),
  top: Math.round(finiteNumber(bounds?.top)),
  width: Math.round(finiteNumber(bounds?.width)),
  height: Math.round(finiteNumber(bounds?.height)),
});
const validGeometry = (bounds) => bounds.width > 320 && bounds.height > 240;

function calculateResizeBounds(source, direction, deltaX, deltaY) {
  const dx = clampDelta(deltaX);
  const dy = clampDelta(deltaY);
  const right = source.left + source.width;
  const bottom = source.top + source.height;
  let left = source.left;
  let top = source.top;
  let width = source.width;
  let height = source.height;
  if (direction.includes("e")) width = Math.max(MIN_WINDOW_WIDTH, source.width + dx);
  if (direction.includes("s")) height = Math.max(MIN_WINDOW_HEIGHT, source.height + dy);
  if (direction.includes("w")) {
    width = Math.max(MIN_WINDOW_WIDTH, source.width - dx);
    left = right - width;
  }
  if (direction.includes("n")) {
    height = Math.max(MIN_WINDOW_HEIGHT, source.height - dy);
    top = bottom - height;
  }
  return { left: Math.round(left), top: Math.round(top), width: Math.round(width), height: Math.round(height) };
}

function parseWindowMessage(payload) {
  if (["minimize", "toggle-maximize", "close"].includes(payload)) return { type: "action", action: payload };
  try {
    const message = JSON.parse(payload);
    if (!message || !["resize-start", "resize-move", "resize-end"].includes(message.type)) return null;
    if (!RESIZE_DIRECTIONS.has(message.direction)) return null;
    return message;
  } catch { return null; }
}

async function setRendererWindowState(session, state) {
  if (!session || session.closed) return;
  await session.evaluate(`(() => {
    const root = document.documentElement;
    if (!root) return false;
    root.setAttribute("data-dream-window-state", ${JSON.stringify(String(state || "normal"))});
    return true;
  })()`);
}

async function releaseResizeState(session, persist = true) {
  const key = session.target.id;
  const state = resizeStates.get(key);
  if (!state) return;
  resizeStates.delete(key);
  try {
    if (persist) {
      const current = await state.browser.send("Browser.getWindowForTarget", { targetId: key });
      const bounds = geometryFromBounds(current.bounds);
      if (current.bounds?.windowState === "normal" && validGeometry(bounds)) normalBounds.set(state.windowId, bounds);
    }
  } finally { state.browser.close(); }
}

async function performResizeMessage(session, message) {
  const key = session.target.id;
  if (message.type === "resize-start") {
    await releaseResizeState(session, false);
    const browser = await connectBrowserSession(session.port);
    try {
      const current = await browser.send("Browser.getWindowForTarget", { targetId: key });
      const bounds = geometryFromBounds(current.bounds);
      if (!Number.isInteger(current.windowId) || current.bounds?.windowState !== "normal" || !validGeometry(bounds)) {
        await setRendererWindowState(session, current.bounds?.windowState || "normal");
        browser.close();
        return;
      }
      normalBounds.set(current.windowId, bounds);
      resizeStates.set(key, { browser, windowId: current.windowId, direction: message.direction, bounds });
      await setRendererWindowState(session, "normal");
      return;
    } catch (error) { browser.close(); throw error; }
  }

  const state = resizeStates.get(key);
  if (!state || state.direction !== message.direction) return;
  if (message.type === "resize-end") {
    await releaseResizeState(session, true);
    return;
  }

  const nextBounds = calculateResizeBounds(state.bounds, state.direction, message.dx, message.dy);
  await state.browser.send("Browser.setWindowBounds", {
    windowId: state.windowId,
    bounds: nextBounds,
  });
}

async function performWindowAction(session, payload) {
  const message = parseWindowMessage(payload);
  if (!message) return;
  if (message.type !== "action") return performResizeMessage(session, message);
  const action = message.action;
  if (action === "close") { await releaseResizeState(session, false); await session.send("Page.close"); return; }
  await releaseResizeState(session, true);
  const browser = await connectBrowserSession(session.port);
  try {
    const current = await browser.send("Browser.getWindowForTarget", { targetId: session.target.id });
    const windowId = current.windowId;
    const currentGeometry = geometryFromBounds(current.bounds);
    if (!Number.isInteger(windowId)) throw new Error("Codex window id is unavailable");
    if (current.bounds?.windowState === "normal" && validGeometry(currentGeometry)) normalBounds.set(windowId, currentGeometry);
    if (action === "minimize") {
      await browser.send("Browser.setWindowBounds", { windowId, bounds: { windowState: "minimized" } });
      await setRendererWindowState(session, "minimized");
    } else if (current.bounds?.windowState === "maximized") {
      await browser.send("Browser.setWindowBounds", { windowId, bounds: { windowState: "normal" } });
      const saved = normalBounds.get(windowId);
      if (saved && validGeometry(saved)) {
        await new Promise((resolve) => setTimeout(resolve, 120));
        await browser.send("Browser.setWindowBounds", { windowId, bounds: saved });
      }
      await setRendererWindowState(session, "normal");
    } else {
      await browser.send("Browser.setWindowBounds", { windowId, bounds: { windowState: "maximized" } });
      await setRendererWindowState(session, "maximized");
    }
  } finally { browser.close(); }
}

async function enableWindowActions(session) {
  await session.send("Runtime.addBinding", { name: WINDOW_ACTION_BINDING });
  session.on("Runtime.bindingCalled", ({ name, payload }) => {
    if (name !== WINDOW_ACTION_BINDING) return;
    const previous = windowActionQueues.get(session) || Promise.resolve();
    const next = previous.catch(() => {}).then(() => performWindowAction(session, payload));
    windowActionQueues.set(session, next);
    next.catch((error) => console.error(`[dream-skin] window action failed: ${error.message}`));
  });
  const browser = await connectBrowserSession(session.port);
  try {
    const current = await browser.send("Browser.getWindowForTarget", { targetId: session.target.id });
    const bounds = geometryFromBounds(current.bounds);
    if (current.bounds?.windowState === "normal" && validGeometry(bounds)) normalBounds.set(current.windowId, bounds);
    await setRendererWindowState(session, current.bounds?.windowState || "normal");
  } finally { browser.close(); }
}

async function runOneShot(options) {
  const connected = await connectCodexTargets(options.port, options.timeoutMs);
  const loaded = options.mode === "once" || options.reload ? await loadPayload(options) : null;
  const results = [];
  let captured = false;
  for (const { target, session, probe } of connected) {
    try {
      if (options.mode === "remove") await removeFromSession(session);
      else if (options.mode === "once") {
        if (!loaded?.payload) await removeFromSession(session); else await applyToSession(session, loaded.payload);
      }
      if (options.reload) {
        await session.send("Page.reload", { ignoreCache: true });
        await new Promise((resolve) => setTimeout(resolve, 1600));
        if (loaded?.payload) await applyToSession(session, loaded.payload);
      }
      const result = options.mode === "remove" || loaded?.theme.kind === "original"
        ? await verifyRemovedSession(session)
        : await waitForVerifiedSession(session, options.timeoutMs, loaded?.theme.id ?? options.themeId);
      results.push({ targetId: target.id, title: target.title, url: target.url, probe, result });
      if (options.screenshot && !captured) { await capture(session, options.screenshot); captured = true; }
    } finally { session.close(); }
  }
  console.log(JSON.stringify({ mode: options.mode, version: SKIN_VERSION, port: options.port, targets: results }, null, 2));
  if (!results.length || results.some((item) => typeof item.result === "boolean" ? !item.result : !item.result?.pass)) process.exitCode = 2;
}

async function runWatch(options) {
  const loaded = await loadPayload(options);
  if (!loaded.payload) throw new Error("Original mode does not run an injector watcher");
  const sessions = new Map();
  let stopping = false;
  process.on("SIGINT", () => { stopping = true; });
  process.on("SIGTERM", () => { stopping = true; });
  while (!stopping) {
    let targets = [];
    try { targets = await listAppTargets(options.port); }
    catch { await new Promise((resolve) => setTimeout(resolve, 1200)); continue; }
    const active = new Set(targets.map((item) => item.id));
    for (const [id, session] of sessions) if (!active.has(id) || session.closed) {
      await releaseResizeState(session, false);
      session.close();
      sessions.delete(id);
    }
    for (const target of targets) {
      if (sessions.has(target.id)) continue;
      let session;
      try {
        session = await connectTarget(target, options.port);
        const probe = await probeSession(session);
        if (!probe?.codex) { session.close(); continue; }
        await enableWindowActions(session);
        session.on("Page.loadEventFired", () => setTimeout(() => applyToSession(session, loaded.payload).catch(() => {}), 250));
        await applyToSession(session, loaded.payload);
        sessions.set(target.id, session);
        console.log(`[dream-skin] injected ${loaded.theme.id} into ${target.id}`);
      } catch (error) { session?.close(); console.error(`[dream-skin] inject failed: ${error.message}`); }
    }
    await new Promise((resolve) => setTimeout(resolve, 900));
  }
  for (const session of sessions.values()) {
    await releaseResizeState(session, false);
    session.close();
  }
}

async function runWindowSmoke(options) {
  const connected = await connectCodexTargets(options.port, options.timeoutMs);
  const browser = await connectBrowserSession(options.port);
  const results = [];
  const pause = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));
  const geometryMatches = (actual, expected, tolerance = 3) => ["left", "top", "width", "height"]
    .every((key) => Math.abs(finiteNumber(actual?.[key]) - finiteNumber(expected?.[key])) <= tolerance);
  try {
    for (const { target, session } of connected) {
      let original;
      try {
        original = await browser.send("Browser.getWindowForTarget", { targetId: target.id });
        if (original.bounds?.windowState !== "normal") {
          await browser.send("Browser.setWindowBounds", { windowId: original.windowId, bounds: { windowState: "normal" } });
          await pause(300);
        }
        let baselineResult = await browser.send("Browser.getWindowForTarget", { targetId: target.id });
        let baseline = geometryFromBounds(baselineResult.bounds);
        if (baseline.width < 840 || baseline.height < 640) {
          baseline = { ...baseline, width: Math.max(840, baseline.width), height: Math.max(640, baseline.height) };
          await browser.send("Browser.setWindowBounds", { windowId: baselineResult.windowId, bounds: baseline });
          await pause(300);
          baselineResult = await browser.send("Browser.getWindowForTarget", { targetId: target.id });
          baseline = geometryFromBounds(baselineResult.bounds);
        }
        await enableWindowActions(session);
        const handles = await session.evaluate(`(() => [...document.querySelectorAll('[data-dream-resize-direction]')].map((node) => {
          const style = getComputedStyle(node);
          return { direction: node.dataset.dreamResizeDirection, cursor: style.cursor, pointerEvents: style.pointerEvents,
            webkitAppRegion: style.webkitAppRegion, visibility: style.visibility };
        }))()`);
        const expectedCursors = { n: "ns-resize", s: "ns-resize", e: "ew-resize", w: "ew-resize",
          ne: "nesw-resize", sw: "nesw-resize", nw: "nwse-resize", se: "nwse-resize" };
        const handlesPass = handles.length === 8 && handles.every((handle) => handle.cursor === expectedCursors[handle.direction]
          && handle.pointerEvents === "auto" && handle.webkitAppRegion === "no-drag" && handle.visibility !== "hidden");

        const invokeResize = async (message) => {
          await session.evaluate(`window.${WINDOW_ACTION_BINDING}(${JSON.stringify(JSON.stringify(message))})`);
          await pause(180);
        };
        await invokeResize({ type: "resize-start", direction: "se", screenX: 0, screenY: 0 });
        await invokeResize({ type: "resize-move", direction: "se", dx: 32, dy: 24 });
        await invokeResize({ type: "resize-end", direction: "se" });
        const resizedResult = await browser.send("Browser.getWindowForTarget", { targetId: target.id });
        const expectedResized = { ...baseline, width: baseline.width + 32, height: baseline.height + 24 };
        const resizePass = geometryMatches(resizedResult.bounds, expectedResized, 4);

        await browser.send("Browser.setWindowBounds", { windowId: baselineResult.windowId, bounds: baseline });
        await pause(250);
        const click = await session.evaluate(`(() => { const b=document.querySelector('[data-dream-window-action="toggle-maximize"]'); if(b)b.click(); return Boolean(b); })()`);
        await pause(1000);
        const maximized = await browser.send("Browser.getWindowForTarget", { targetId: target.id });
        const maximizedHandles = await session.evaluate(`(() => [...document.querySelectorAll('[data-dream-resize-direction]')]
          .every((node) => getComputedStyle(node).pointerEvents === 'none' || getComputedStyle(node).visibility === 'hidden'))()`);
        await session.evaluate(`document.querySelector('[data-dream-window-action="toggle-maximize"]')?.click()`);
        await pause(1200);
        const restored = await browser.send("Browser.getWindowForTarget", { targetId: target.id });
        const restoredHandles = await session.evaluate(`(() => [...document.querySelectorAll('[data-dream-resize-direction]')]
          .every((node) => getComputedStyle(node).pointerEvents === 'auto' && getComputedStyle(node).visibility !== 'hidden'))()`);
        const restorePass = click && maximized.bounds?.windowState === "maximized" && restored.bounds?.windowState === "normal"
          && geometryMatches(restored.bounds, baseline, 3);
        const pass = handlesPass && resizePass && maximizedHandles && restoredHandles && restorePass;
        results.push({ targetId: target.id, original: original.bounds, baseline, handles, resized: resizedResult.bounds,
          maximized: maximized.bounds, restored: restored.bounds, checks: { handlesPass, resizePass, maximizedHandles, restoredHandles, restorePass }, pass });
      } finally {
        await releaseResizeState(session, false);
        if (original?.windowId) {
          const originalGeometry = geometryFromBounds(original.bounds);
          if (validGeometry(originalGeometry)) {
            await browser.send("Browser.setWindowBounds", { windowId: original.windowId, bounds: { windowState: "normal" } });
            await pause(120);
            await browser.send("Browser.setWindowBounds", { windowId: original.windowId, bounds: originalGeometry });
          }
          if (original.bounds?.windowState && original.bounds.windowState !== "normal") {
            await browser.send("Browser.setWindowBounds", { windowId: original.windowId, bounds: { windowState: original.bounds.windowState } });
          }
        }
        session.close();
      }
    }
  } finally { browser.close(); }
  console.log(JSON.stringify({ mode: "window-smoke", targets: results }, null, 2));
  if (!results.length || results.some((item) => !item.pass)) process.exitCode = 2;
}

function runResizeSelfTest() {
  const source = { left: 100, top: 80, width: 1000, height: 700 };
  const cases = [
    ["n", 0, 30, { left: 100, top: 110, width: 1000, height: 670 }],
    ["s", 0, 30, { left: 100, top: 80, width: 1000, height: 730 }],
    ["e", 40, 0, { left: 100, top: 80, width: 1040, height: 700 }],
    ["w", 40, 0, { left: 140, top: 80, width: 960, height: 700 }],
    ["ne", 40, -20, { left: 100, top: 60, width: 1040, height: 720 }],
    ["nw", -50, -20, { left: 50, top: 60, width: 1050, height: 720 }],
    ["se", 40, 30, { left: 100, top: 80, width: 1040, height: 730 }],
    ["sw", 40, 30, { left: 140, top: 80, width: 960, height: 730 }],
    ["w", 900, 0, { left: 340, top: 80, width: MIN_WINDOW_WIDTH, height: 700 }],
    ["n", 0, 500, { left: 100, top: 220, width: 1000, height: MIN_WINDOW_HEIGHT }],
  ].map(([direction, dx, dy, expected]) => {
    const actual = calculateResizeBounds(source, direction, dx, dy);
    return { direction, dx, dy, expected, actual, pass: JSON.stringify(actual) === JSON.stringify(expected) };
  });
  const pass = cases.every((item) => item.pass);
  console.log(JSON.stringify({ mode: "resize-self-test", minimum: { width: MIN_WINDOW_WIDTH, height: MIN_WINDOW_HEIGHT }, cases, pass }, null, 2));
  if (!pass) process.exitCode = 2;
}

try {
  const options = parseArgs(process.argv.slice(2));
  if (options.mode === "check") {
    const loaded = await loadPayload(options);
    console.log(JSON.stringify({ pass: true, version: SKIN_VERSION, themeId: loaded.theme.id, themeName: loaded.theme.name,
      kind: loaded.theme.kind, profile: loaded.theme.profile, appearance: loaded.theme.appearance, art: loaded.theme.art,
      visual: loaded.theme.visual, imageBytes: loaded.imageBytes,
      payloadBytes: loaded.payload ? Buffer.byteLength(loaded.payload) : 0 }, null, 2));
  } else if (options.mode === "resize-self-test") runResizeSelfTest();
  else if (options.mode === "watch") await runWatch(options);
  else if (options.mode === "window-smoke") await runWindowSmoke(options);
  else await runOneShot(options);
} catch (error) {
  console.error(`[dream-skin] ${error.stack || error.message}`);
  process.exitCode = 1;
}
