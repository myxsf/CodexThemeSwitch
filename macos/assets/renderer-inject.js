((cssText, artDataUrl, themeConfig) => {
  const STATE_KEY = "__CODEX_DREAM_SKIN_STATE__";
  const DISABLED_KEY = "__CODEX_DREAM_SKIN_DISABLED__";
  const STYLE_ID = "codex-dream-skin-style";
  const CHROME_ID = "codex-dream-skin-chrome";
  const SHELL_ATTR = "data-dream-shell";
  const THEME_ATTR = "data-dream-theme";
  const THEME_ID_ATTR = "data-dream-theme-id";
  const VERSION = __DREAM_SKIN_VERSION_JSON__;
  const INSTANCE_TOKEN = Symbol("codex-dream-skin-instance");
  const THEME = themeConfig && typeof themeConfig === "object" ? themeConfig : {};
  const VISUAL = THEME.visual && typeof THEME.visual === "object" ? THEME.visual : {};
  const THEME_PROFILE = THEME.profile || (THEME.id === "qq2007" ? "qq2007" : "inspiration-universe");
  const CARD_SETS = {
    classic: [
      ["</>", "探索并理解代码", "梳理代码结构与实现逻辑"],
      ["✚", "构建新功能", "创建应用、组件或工具"],
      ["☑", "审查代码", "发现问题并提出修改建议"],
      ["🛠", "修复问题", "定位失败并完成可靠修复"],
    ],
    fortune: [
      ["🪙", "成本优化", "识别浪费并降低资源成本"],
      ["账", "技术债清账", "扫描债务并逐项清理"],
      ["▧", "自动报表总结", "生成进度与质量报告"],
      ["✚", "冲突合并开运", "检查冲突并安全合并"],
    ],
    future: [
      ["</>", "构建", "编写代码与应用"],
      ["◇", "分析", "数据分析与洞察"],
      ["🚀", "自动化", "智能体与工作流"],
      ["↓", "调试", "修复问题与优化"],
    ],
    inspiration: [
      ["💡", "灵感脑暴", "把脑子里的一万种可能都倒出来"],
      ["⚡", "快速原型", "先跑起来，再继续打磨"],
      ["🎮", "边玩边改", "改到爽为止，体验即正义"],
      ["🧩", "插件与工具", "打开真实 Codex 插件入口"],
    ],
  };
  const CARD_SET_BY_THEME = {
    "skin-01": "classic", "skin-02": "fortune", "skin-03": "future", "skin-04": "classic",
    "skin-05": "inspiration", "skin-06": "classic", "skin-07": "classic", "skin-08": "classic",
  };
  const THEME_VARIABLES = [
    "--ds-bg", "--ds-panel", "--ds-panel-2", "--ds-green", "--ds-lime",
    "--ds-cyan", "--ds-purple", "--ds-text", "--ds-muted", "--ds-line",
    "--dream-skin-name", "--dream-skin-tagline", "--dream-skin-project-prefix",
    "--dream-skin-project-label", "--dream-skin-art-position", "--dream-skin-art-size",
    "--dream-skin-sidebar-brand", "--dream-skin-sidebar-subtitle", "--dream-skin-footer-text",
    "--qq-canvas-left", "--qq-canvas-width",
    "--qq-canvas-height", "--qq-title-h", "--qq-toolbar-h", "--qq-top",
    "--qq-bottom", "--qq-left", "--qq-right", "--qq-gutter",
    "--qq-panel-header-h", "--qq-nav-row-h", "--qq-composer-h",
    "--qq-composer-toolbar-h", "--qq-font-sm", "--qq-font-md",
    "--qq-font-lg", "--qq-window-buttons-w", "--qq-window-buttons-h",
  ];
  window[DISABLED_KEY] = false;

  const previous = window[STATE_KEY];
  if (previous?.observer) previous.observer.disconnect();
  if (previous?.timer) clearInterval(previous.timer);
  if (previous?.scheduler?.timeout) clearTimeout(previous.scheduler.timeout);
  if (previous?.resizeHandler) window.removeEventListener("resize", previous.resizeHandler);
  if (previous?.scrollHandler) window.removeEventListener("scroll", previous.scrollHandler, true);
  if (previous?.frameScheduler?.frame) cancelAnimationFrame(previous.frameScheduler.frame);
  previous?.layoutResizeObserver?.disconnect();
  if (previous?.layoutSyncFrame) cancelAnimationFrame(previous.layoutSyncFrame);
  if (previous?.layoutPointerHandler) document.removeEventListener("pointermove", previous.layoutPointerHandler, true);
  if (previous?.qqSidebarObserver) previous.qqSidebarObserver.disconnect();
  if (previous?.qqSidebarResetTimer) clearTimeout(previous.qqSidebarResetTimer);
  previous?.qqSidebarInteractionController?.abort();
  previous?.cardActionController?.abort();
  if (previous?.mediaHandler && previous?.mediaQuery) {
    try { previous.mediaQuery.removeEventListener("change", previous.mediaHandler); } catch {}
  }
  if (previous?.artUrl) URL.revokeObjectURL(previous.artUrl);
  window[STATE_KEY] = { instanceToken: INSTANCE_TOKEN };
  if (previous?.profile && previous.profile !== THEME_PROFILE) {
    document.getElementById(CHROME_ID)?.remove();
    document.getElementById("dream-skin-extra-card")?.remove();
    document.documentElement?.removeAttribute(THEME_ATTR);
    document.documentElement?.removeAttribute(THEME_ID_ATTR);
  }

  const artUrl = artDataUrl ? (() => {
    const comma = artDataUrl.indexOf(",");
    const mime = /^data:([^;,]+)/.exec(artDataUrl)?.[1] || "image/png";
    const binary = atob(artDataUrl.slice(comma + 1));
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index);
    return URL.createObjectURL(new Blob([bytes], { type: mime }));
  })() : "";

  const cssString = (value) => JSON.stringify(String(value ?? ""));
  const setAttributeIfChanged = (element, name, value) => {
    if (element.getAttribute(name) !== value) element.setAttribute(name, value);
  };
  const setStyleIfChanged = (element, name, value) => {
    if (element.style.getPropertyValue(name) !== value) element.style.setProperty(name, value);
  };
  const setTextIfChanged = (element, value) => {
    if (element && element.textContent !== value) element.textContent = value;
  };
  const toggleClassIfChanged = (element, name, enabled) => {
    if (element && element.classList.contains(name) !== enabled) element.classList.toggle(name, enabled);
  };
  const clamp = (value, minimum, maximum) => Math.max(minimum, Math.min(maximum, value));
  const canRestoreQQSidebar = previous?.version === VERSION &&
    previous?.profile === "qq2007" &&
    previous?.qqSidebarInitializing !== true &&
    Number.isFinite(Number(previous?.qqSidebarRatio));
  let qqSidebarRatio = canRestoreQQSidebar
    ? clamp(Number(previous.qqSidebarRatio), 0.16, 0.42)
    : 333 / 1440;
  let qqShouldResetSidebarWidth = THEME_PROFILE === "qq2007" && !canRestoreQQSidebar;
  let qqCanvasWidth = 0;
  let qqExpectedSidebarWidth = 0;
  let qqSidebarObserver = null;
  let qqObservedAside = null;
  let qqSidebarResetTimer = null;
  let qqSidebarInteractionController = null;
  let qqUserResizeActive = false;
  let qqUserResizeGraceUntil = 0;
  let layoutResizeObserver = null;
  let layoutObservedMain = null;
  let layoutSyncFrame = null;
  let layoutPointerHandler = null;
  const cardActionController = new AbortController();

  const openPlugins = (source) => {
    const candidates = [...document.querySelectorAll('button, a, [role="button"]')];
    const plugin = candidates.find((node) => node !== source && !node.closest('#dream-skin-extra-card') &&
      /插件|plugins?|extensions?/i.test(
        `${node.getAttribute("aria-label") || ""} ${node.getAttribute("title") || ""} ${node.textContent || ""}`
      ));
    if (plugin instanceof HTMLElement) plugin.click();
  };

  const fillComposerPrompt = (prompt) => {
    if (!prompt) return;
    const composer = document.querySelector('.composer-surface-chrome');
    const editor = composer?.querySelector('[contenteditable="true"]');
    const textControl = composer?.querySelector('textarea, input[type="text"]');
    if (editor instanceof HTMLElement) {
      editor.focus();
      editor.textContent = prompt;
      editor.dispatchEvent(new InputEvent("input", {
        bubbles: true,
        composed: true,
        inputType: "insertText",
        data: prompt,
      }));
      return;
    }
    if (textControl instanceof HTMLTextAreaElement || textControl instanceof HTMLInputElement) {
      const prototype = textControl instanceof HTMLTextAreaElement
        ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
      Object.getOwnPropertyDescriptor(prototype, "value")?.set?.call(textControl, prompt);
      textControl.dispatchEvent(new Event("input", { bubbles: true, composed: true }));
      textControl.focus();
    }
  };

  const bindCardAction = (button, card, index) => {
    if (!(button instanceof HTMLElement) || !card) return;
    button.dataset.dreamCardIndex = String(index + 1);
    button.dataset.dreamCardAction = card.action === "plugins" ? "plugins" : "prompt";
    button.dataset.dreamCardPrompt = card.prompt || "";
    button.setAttribute("aria-label", card.title || `主题功能 ${index + 1}`);
  };

  document.addEventListener("click", (event) => {
    const target = event.target instanceof Element
      ? event.target.closest("[data-dream-card-index]") : null;
    if (!(target instanceof HTMLElement)) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    if (target.dataset.dreamCardAction === "plugins") openPlugins(target);
    else fillComposerPrompt(target.dataset.dreamCardPrompt || "");
  }, { capture: true, signal: cardActionController.signal });

  /** Detect Codex app light/dark shell for CSS branching. */
  const detectShellMode = () => {
    const root = document.documentElement;
    const body = document.body;
    const cls = `${root.className || ""} ${body?.className || ""}`.toLowerCase();

    if (/\b(dark|theme-dark|appearance-dark)\b/.test(cls)) return "dark";
    if (/\b(light|theme-light|appearance-light)\b/.test(cls)) return "light";

    const dataTheme = (
      root.getAttribute("data-theme") ||
      root.getAttribute("data-appearance") ||
      root.getAttribute("data-color-mode") ||
      body?.getAttribute("data-theme") ||
      body?.getAttribute("data-appearance") ||
      ""
    ).toLowerCase();
    if (dataTheme.includes("dark")) return "dark";
    if (dataTheme.includes("light")) return "light";

    // Radios in profile menu (if present in DOM)
    const checked = document.querySelector('input[name="appearance-theme"]:checked');
    if (checked) {
      const label = (checked.getAttribute("aria-label") || checked.value || "").toLowerCase();
      if (label.includes("暗") || label.includes("dark")) return "dark";
      if (label.includes("浅") || label.includes("light")) return "light";
      if (label.includes("系统") || label.includes("system")) {
        return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
      }
    }

    // Never infer the official appearance from computed colors after the skin
    // is installed: those colors are ours and caused light/dark self-flips.
    const stableShell = root.getAttribute(SHELL_ATTR);
    if (stableShell === "light" || stableShell === "dark") return stableShell;

    try {
      if (window.matchMedia("(prefers-color-scheme: dark)").matches) return "dark";
    } catch {}
    return "light";
  };

  const applyTheme = (root, shell) => {
    const colors = THEME.colors || {};
    const accent = colors.accent || (shell === "light" ? "#e25563" : "#7cff46");
    const accentAlt = colors.accentAlt || accent;
    const secondary = colors.secondary || (shell === "light" ? "#f3a8af" : "#36d7e8");
    const highlight = colors.highlight || (shell === "light" ? "#c93d4c" : "#642a8c");
    const backgroundHex = typeof colors.background === "string" ? colors.background.trim() : "";
    const backgroundMatch = backgroundHex.match(/^#([0-9a-f]{6})$/i);
    const configuredAppearance = String(THEME.appearance || "").toLowerCase();
    const palette = configuredAppearance === "light" || configuredAppearance === "dark"
      ? configuredAppearance
      : backgroundMatch
      ? (() => {
          const value = Number.parseInt(backgroundMatch[1], 16);
          const red = (value >> 16) & 255;
          const green = (value >> 8) & 255;
          const blue = value & 255;
          return (red * 0.299 + green * 0.587 + blue * 0.114) >= 150 ? "light" : "dark";
        })()
      : shell;
    setAttributeIfChanged(root, "data-dream-palette", palette);

    let variables;
    if (shell === "light") {
      // Catalog themes may be light or dark even when Codex itself is in light
      // mode. Keep the trusted structure, but let the validated palette drive
      // every surface token so additional themes are visibly distinct.
      variables = {
        "--ds-bg": colors.background || "#f6f2f3",
        "--ds-panel": colors.panel || "#ffffff",
        "--ds-panel-2": colors.panelAlt || "#fff7f8",
        "--ds-green": accent,
        "--ds-lime": accentAlt,
        "--ds-cyan": secondary,
        "--ds-purple": highlight,
        "--ds-text": colors.text || "#1f1a1b",
        "--ds-muted": colors.muted || "#6b5f62",
        "--ds-line": colors.line || "rgba(196, 120, 128, .22)",
      };
    } else {
      variables = {
        "--ds-bg": colors.background || "#071116",
        "--ds-panel": colors.panel || "#0b1a20",
        "--ds-panel-2": colors.panelAlt || "#10272c",
        "--ds-green": accent,
        "--ds-lime": accentAlt,
        "--ds-cyan": secondary,
        "--ds-purple": highlight,
        "--ds-text": colors.text || "#e9fff1",
        "--ds-muted": colors.muted || "#9ebdb3",
        "--ds-line": colors.line || "rgba(124, 255, 70, .28)",
      };
    }

    for (const [name, value] of Object.entries(variables)) {
      if (typeof value === "string" && value) setStyleIfChanged(root, name, value);
    }
    setStyleIfChanged(root, "--dream-skin-name", cssString(THEME.name || "Codex Dream Skin"));
    setStyleIfChanged(root, "--dream-skin-tagline", cssString(THEME.tagline || "Make something wonderful."));
    setStyleIfChanged(root, "--dream-skin-project-prefix", cssString(THEME.projectPrefix || "选择项目 · "));
    setStyleIfChanged(root, "--dream-skin-project-label", cssString(THEME.projectLabel || "◉  选择项目"));
    setStyleIfChanged(root, "--dream-skin-art-position", THEME.art?.position || "center center");
    setStyleIfChanged(root, "--dream-skin-art-size", THEME.art?.size || "cover");
  };

  const applyQQGeometry = (root) => {
    const referenceWidth = 1440;
    const referenceHeight = 1080;
    const scale = Math.max(0.45, Math.min(window.innerWidth / referenceWidth, window.innerHeight / referenceHeight));
    const canvasWidth = Math.round(referenceWidth * scale);
    const canvasHeight = Math.round(referenceHeight * scale);
    const canvasLeft = Math.max(0, Math.round((window.innerWidth - canvasWidth) / 2));
    const geometryFactor = scale / 0.75;
    const uiFactor = Math.max(0.85, Math.min(1.35, geometryFactor));
    qqCanvasWidth = canvasWidth;
    qqExpectedSidebarWidth = Math.round(canvasWidth * qqSidebarRatio);
    const values = {
      "--qq-canvas-left": `${canvasLeft}px`,
      "--qq-canvas-width": `${canvasWidth}px`,
      "--qq-canvas-height": `${canvasHeight}px`,
      "--qq-title-h": `${45 * scale}px`,
      "--qq-toolbar-h": `${67 * scale}px`,
      "--qq-top": `${112 * scale}px`,
      "--qq-bottom": `${40 * scale}px`,
      "--qq-left": `${qqExpectedSidebarWidth}px`,
      "--qq-right": `${280 * scale}px`,
      "--qq-gutter": `${8 * scale}px`,
      "--qq-panel-header-h": `${45 * scale}px`,
      "--qq-nav-row-h": `${30 * uiFactor}px`,
      "--qq-composer-h": `${112 * uiFactor}px`,
      "--qq-composer-toolbar-h": `${30 * uiFactor}px`,
      "--qq-font-sm": `${12 * uiFactor}px`,
      "--qq-font-md": `${13 * uiFactor}px`,
      "--qq-font-lg": `${15 * uiFactor}px`,
      "--qq-window-buttons-w": `${91 * geometryFactor}px`,
      "--qq-window-buttons-h": `${27 * geometryFactor}px`,
    };
    for (const [name, value] of Object.entries(values)) setStyleIfChanged(root, name, value);
    return { left: canvasLeft, width: canvasWidth, height: canvasHeight, scale };
  };

  const ensureQQSidebarObserver = (root) => {
    if (THEME_PROFILE !== "qq2007") {
      qqSidebarObserver?.disconnect();
      qqSidebarObserver = null;
      qqObservedAside = null;
      qqSidebarInteractionController?.abort();
      qqSidebarInteractionController = null;
      return;
    }
    const aside = document.querySelector("aside.app-shell-left-panel");
    if (!(aside instanceof HTMLElement)) return;
    if (!qqSidebarInteractionController) {
      qqSidebarInteractionController = new AbortController();
      const options = { capture: true, signal: qqSidebarInteractionController.signal };
      const isSeparator = (target) => target instanceof Element && Boolean(target.closest(
        'aside.app-shell-left-panel > [role="separator"][aria-orientation="vertical"]',
      ));
      document.addEventListener("pointerdown", (event) => {
        if (!isSeparator(event.target)) return;
        qqUserResizeActive = true;
        qqUserResizeGraceUntil = Number.POSITIVE_INFINITY;
      }, options);
      const finishUserResize = () => {
        if (!qqUserResizeActive) return;
        qqUserResizeActive = false;
        qqUserResizeGraceUntil = performance.now() + 650;
      };
      document.addEventListener("pointerup", finishUserResize, options);
      document.addEventListener("pointercancel", finishUserResize, options);
      document.addEventListener("keydown", (event) => {
        if (!isSeparator(event.target) || !["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) return;
        qqUserResizeGraceUntil = performance.now() + 800;
      }, options);
      if (window[STATE_KEY]) window[STATE_KEY].qqSidebarInteractionController = qqSidebarInteractionController;
    }
    const sync = () => {
      if (!qqCanvasWidth) return;
      const width = aside.getBoundingClientRect().width;
      if (!Number.isFinite(width) || width < 120) return;
      if (qqShouldResetSidebarWidth) {
        if (Math.abs(width - qqExpectedSidebarWidth) > 1.5) {
          aside.style.width = `${qqExpectedSidebarWidth}px`;
        }
        return;
      }
      if (Math.abs(width - qqExpectedSidebarWidth) <= 1.5) return;
      if (!qqUserResizeActive && performance.now() > qqUserResizeGraceUntil) {
        aside.style.width = `${qqExpectedSidebarWidth}px`;
        return;
      }
      qqSidebarRatio = clamp(width / qqCanvasWidth, 0.16, 0.42);
      qqExpectedSidebarWidth = Math.round(width);
      setStyleIfChanged(root, "--qq-left", `${qqExpectedSidebarWidth}px`);
      if (window[STATE_KEY]) window[STATE_KEY].qqSidebarRatio = qqSidebarRatio;
    };
    if (qqObservedAside !== aside) {
      if (qqShouldResetSidebarWidth && qqExpectedSidebarWidth > 0) {
        // Codex remembers the native splitter width across launches. A fresh
        // QQ session must start from the reference composition once, while
        // subsequent native drags remain free to update the same inline width.
        aside.style.width = `${qqExpectedSidebarWidth}px`;
        qqSidebarResetTimer = setTimeout(() => {
          qqShouldResetSidebarWidth = false;
          qqSidebarResetTimer = null;
          aside.style.width = `${qqExpectedSidebarWidth}px`;
          if (window[STATE_KEY]) {
            window[STATE_KEY].qqSidebarResetTimer = null;
            window[STATE_KEY].qqSidebarInitializing = false;
          }
          sync();
        }, 2400);
        if (window[STATE_KEY]) {
          window[STATE_KEY].qqSidebarResetTimer = qqSidebarResetTimer;
          window[STATE_KEY].qqSidebarInitializing = true;
        }
      }
      qqSidebarObserver?.disconnect();
      qqSidebarObserver = new ResizeObserver(sync);
      qqSidebarObserver.observe(aside);
      qqObservedAside = aside;
      if (window[STATE_KEY]) window[STATE_KEY].qqSidebarObserver = qqSidebarObserver;
    }
    sync();
  };

  const existingStyle = document.getElementById(STYLE_ID);
  if (existingStyle) {
    existingStyle.textContent = cssText;
    existingStyle.dataset.dreamSkinVersion = VERSION;
    existingStyle.dataset.dreamSkinThemeId = THEME.id || "custom";
    existingStyle.dataset.dreamSkinProfile = THEME_PROFILE;
  }

  const ensure = () => {
    if (window[DISABLED_KEY] || window[STATE_KEY]?.instanceToken !== INSTANCE_TOKEN) return;
    const root = document.documentElement;
    if (!root) return;
    const shell = detectShellMode();
    if (!root.classList.contains("codex-dream-skin")) root.classList.add("codex-dream-skin");
    setAttributeIfChanged(root, SHELL_ATTR, shell);
    setAttributeIfChanged(root, THEME_ATTR, THEME_PROFILE);
    setAttributeIfChanged(root, THEME_ID_ATTR, THEME.id || "custom");
    if (VISUAL.layoutVariant) setAttributeIfChanged(root, "data-dream-layout", VISUAL.layoutVariant);
    else root.removeAttribute("data-dream-layout");
    setStyleIfChanged(root, "--dream-skin-art", artUrl ? `url("${artUrl}")` : "none");
    setStyleIfChanged(root, "--dream-skin-sidebar-brand", cssString(VISUAL.sidebar?.brand || THEME.name || "Codex"));
    setStyleIfChanged(root, "--dream-skin-sidebar-subtitle", cssString(VISUAL.sidebar?.subtitle || THEME.brandSubtitle || ""));
    setStyleIfChanged(root, "--dream-skin-footer-text", cssString(VISUAL.sidebar?.footerText || "翔仔正在工作ing"));
    applyTheme(root, shell);
    const qqGeometry = THEME_PROFILE === "qq2007" ? applyQQGeometry(root) : null;

    let style = document.getElementById(STYLE_ID);
    if (!style) {
      style = document.createElement("style");
      style.id = STYLE_ID;
      (document.head || root).appendChild(style);
    }
    if (style.textContent !== cssText ||
        style.dataset.dreamSkinVersion !== VERSION ||
        style.dataset.dreamSkinThemeId !== (THEME.id || "custom") ||
        style.dataset.dreamSkinProfile !== THEME_PROFILE) {
      style.textContent = cssText;
      style.dataset.dreamSkinVersion = VERSION;
      style.dataset.dreamSkinThemeId = THEME.id || "custom";
      style.dataset.dreamSkinProfile = THEME_PROFILE;
    }

    const shellMain = document.querySelector("main.main-surface") || document.querySelector("main");
    const scheduleLayoutSync = () => {
      if (layoutSyncFrame) return;
      layoutSyncFrame = requestAnimationFrame(() => {
        layoutSyncFrame = null;
        ensure();
      });
    };
    if (shellMain && layoutObservedMain !== shellMain) {
      layoutResizeObserver?.disconnect();
      layoutResizeObserver = new ResizeObserver(scheduleLayoutSync);
      layoutResizeObserver.observe(shellMain);
      const layoutAside = document.querySelector("aside.app-shell-left-panel");
      if (layoutAside) layoutResizeObserver.observe(layoutAside);
      layoutObservedMain = shellMain;
      if (window[STATE_KEY]) window[STATE_KEY].layoutResizeObserver = layoutResizeObserver;
    }
    if (!layoutPointerHandler) {
      layoutPointerHandler = (event) => {
        if (THEME_PROFILE !== "qq2007" && (event.buttons & 1) === 1) scheduleLayoutSync();
      };
      document.addEventListener("pointermove", layoutPointerHandler, { passive: true, capture: true });
    }
    ensureQQSidebarObserver(root);
    const homeIndicator = document.querySelector('[data-testid="home-icon"]');
    const home = homeIndicator?.closest('[role="main"]') ||
      [...document.querySelectorAll('[role="main"]')].find((candidate) =>
        candidate.querySelector('[data-feature="game-source"]')) || null;
    for (const candidate of document.querySelectorAll('[role="main"].dream-skin-home')) {
      if (candidate !== home) candidate.classList.remove("dream-skin-home");
    }
    if (home && !home.classList.contains("dream-skin-home")) home.classList.add("dream-skin-home");

    const suggestions = home?.querySelector('[class~="group/home-suggestions"]') ?? null;
    const suggestionsGrid = suggestions?.querySelector('.grid') ?? null;
    const nativeCardButtons = suggestionsGrid
      ? [...suggestionsGrid.querySelectorAll('button')].filter((button) => !button.closest('#dream-skin-extra-card'))
      : [];
    const nativeCardCount = nativeCardButtons.length;
    let extraCard = document.getElementById('dream-skin-extra-card');
    const fallbackCardSet = CARD_SETS[CARD_SET_BY_THEME[THEME.id]];
    const configuredCards = Array.isArray(VISUAL.cards) && VISUAL.cards.length === 4 ? VISUAL.cards : null;
    const cardSet = THEME_PROFILE === "qq2007" ? null : configuredCards || fallbackCardSet?.map((card) => ({
      icon: card[0], title: card[1], detail: card[2], action: "prompt", prompt: card[1],
    }));
    if (THEME_PROFILE !== "qq2007" && cardSet && suggestionsGrid && nativeCardCount === 3) {
      if (!extraCard || extraCard.parentElement !== suggestionsGrid) {
        extraCard?.remove();
        extraCard = document.createElement('div');
        extraCard.id = 'dream-skin-extra-card';
        extraCard.className = 'dream-skin-extra-card h-full min-w-0';
        extraCard.innerHTML = `<button type="button" class="dream-skin-plugin-card"></button>`;
        suggestionsGrid.appendChild(extraCard);
      }
    } else {
      // QQ uses only native home controls. This may remove our own stale node
      // from an older profile, but never adds or rewrites homepage children.
      extraCard?.remove();
    }

    if (!shellMain || !document.body) return;
    setAttributeIfChanged(root, "data-dream-page", home ? "home" : "task");
    toggleClassIfChanged(shellMain, "dream-skin-home-shell", Boolean(home));
    let chrome = document.getElementById(CHROME_ID);
    if (!chrome || chrome.parentElement !== document.body || chrome.dataset.dreamTheme !== THEME_PROFILE ||
        chrome.dataset.dreamChromeSchema !== "3" || chrome.querySelector('[data-dream-window-action]')) {
      chrome?.remove();
      chrome = document.createElement("div");
      chrome.id = CHROME_ID;
      chrome.setAttribute("aria-hidden", "true");
      chrome.dataset.dreamTheme = THEME_PROFILE;
      chrome.dataset.dreamChromeSchema = "3";
      if (THEME_PROFILE === "qq2007") {
        chrome.innerHTML = `
          <div class="qq2007-titlebar">
            <span class="qq2007-penguin">🐧</span>
            <b>Codex 2007 - <span class="qq2007-title-context">优化 KV 读写成本</span></b>
            <span class="qq2007-window-buttons" aria-hidden="true">
              <i></i><i></i><i></i>
            </span>
          </div>
          <div class="qq2007-toolbar">
            <span><i>📝</i>新建任务</span><span><i>📋</i>已安排</span><em></em>
            <span><i>🧩</i>插件</span><span><i>🖥️</i>站点</span>
            <span><i>🎵</i>拉取请求</span><span><i>💬</i>聊天</span>
          </div>
          <section class="qq2007-buddy-panel">
            <header><b>ⓧ&nbsp; Codex 好友</b><span>↗⌄</span></header>
            <div class="qq2007-mascot-card">
              <svg viewBox="0 0 180 150" aria-hidden="true">
                <defs><linearGradient id="qqBotBody" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#89aaff"/><stop offset="1" stop-color="#3059d5"/></linearGradient></defs>
                <path d="M52 37c5-22 21-32 39-27 13-7 30 0 35 13 20 0 30 16 25 32 12 14 6 33-11 40H46C29 88 23 69 35 55c-5-9 2-16 17-18Z" fill="url(#qqBotBody)" stroke="#10216f" stroke-width="3"/>
                <rect x="50" y="48" width="88" height="49" rx="14" fill="#14255e" stroke="#06143f" stroke-width="3"/>
                <path d="m76 61 12 12-12 12" fill="none" stroke="#7ff6ff" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"/>
                <path d="M107 80h16" stroke="#7ff6ff" stroke-width="5" stroke-linecap="round"/>
                <path d="M54 97 41 114v22h17l7-18 8 20h16v-25h15v25h17l8-20 7 18h17v-22l-13-17Z" fill="url(#qqBotBody)" stroke="#10216f" stroke-width="3"/>
              </svg>
            </div>
            <div class="qq2007-buddy-name"><span>✅</span><b>Codex 小蓝</b><mark>LV 07</mark></div>
            <div class="qq2007-buddy-copy">代码有问题？找我！<br>我是你的智能伙伴 Codex<br>陪你写代码，改 Bug，<br>查文档，超可靠哒！</div>
            <div class="qq2007-buddy-icons"><span>📱</span><span>⭐</span><span>✉️</span><span>🌼</span><span>🔒</span></div>
            <div class="qq2007-friends-title"><b>⌄&nbsp; 我的好友 (2/8)</b><span>⌃</span></div>
            <div class="qq2007-avatar-card">
              <div class="qq2007-stars">✦　✧　　　✦</div>
              <svg viewBox="0 0 170 210" aria-hidden="true">
                <defs><linearGradient id="qqAvatarSky" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#b8d5ff"/><stop offset="1" stop-color="#f8fbff"/></linearGradient></defs>
                <rect width="170" height="210" fill="url(#qqAvatarSky)"/>
                <circle cx="85" cy="59" r="31" fill="#ffd5b8" stroke="#7b4a35" stroke-width="2"/>
                <path d="M54 60c2-35 57-44 65-5-11-17-19-25-34-24-13 1-25 10-31 29Z" fill="#b35a1e"/>
                <path d="M68 59h9m17 0h9" stroke="#4b2d28" stroke-width="2" stroke-linecap="round"/>
                <path d="M80 71c4 3 8 3 12 0" fill="none" stroke="#c66a68" stroke-width="2" stroke-linecap="round"/>
                <path d="M61 93c15-10 33-10 48 0l13 76H48Z" fill="#fff" stroke="#788599" stroke-width="2"/>
                <path d="M48 169h74l-8 41H56Z" fill="#7f8fa9"/>
                <path d="M66 119h38" stroke="#d0d6df" stroke-width="2"/><path d="M57 169 47 205m66-36 10 36" stroke="#725440" stroke-width="6" stroke-linecap="round"/>
              </svg>
            </div>
            <div class="qq2007-friend-search">查找好友... <b>⌕</b></div>
          </section>
          <div class="qq2007-bottom-bar">
            <span>🐧</span><span>⭐</span><span>✉️</span><span>📁</span><span>🐧</span><span>🌼</span><span>▦</span>
            <b>🛡 安全　▥　📶　☕　<span class="qq2007-clock">22:48</span></b>
          </div>`;
      } else {
        chrome.innerHTML = `
          <div class="dream-skin-brand">
            <span class="dream-skin-portal-mark">◉</span>
            <span><b></b><small></small></span>
          </div>
          <div class="dream-skin-status"><i></i><span></span></div>
          <div class="dream-skin-quote"></div>
          <div class="dream-skin-particles"><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i></div>
          <div class="dream-skin-orbit"></div>
          <aside class="dream-skin-note"><strong></strong><span></span></aside>`;
      }
      document.body.appendChild(chrome);
      if (THEME_PROFILE === "qq2007") chrome.removeAttribute("aria-hidden");
    }
    const shellBox = shellMain.getBoundingClientRect();
    if (THEME_PROFILE === "qq2007") {
      const headerText = document.querySelector("main.main-surface > header.app-header-tint")?.innerText?.trim();
      const context = headerText || (home ? "Codex 工作台" : "Codex 任务");
      setTextIfChanged(chrome.querySelector(".qq2007-title-context"), context);
      setStyleIfChanged(root, "--qq-page-title", cssString(context));
      const geometry = {
        left: `${qqGeometry?.left || 0}px`,
        top: "0px",
        width: `${qqGeometry?.width || window.innerWidth}px`,
        height: `${qqGeometry?.height || window.innerHeight}px`,
      };
      for (const [name, value] of Object.entries(geometry)) {
        if (chrome.style[name] !== value) chrome.style[name] = value;
      }
    } else {
      setTextIfChanged(chrome.querySelector(".dream-skin-brand b"), THEME.name || "Codex Dream Skin");
      setTextIfChanged(chrome.querySelector(".dream-skin-brand small"), THEME.brandSubtitle || "CODEX DREAM SKIN");
      setTextIfChanged(chrome.querySelector(".dream-skin-status span"), THEME.statusText || "DREAM SKIN ONLINE");
      setTextIfChanged(chrome.querySelector(".dream-skin-quote"), THEME.quote || "MAKE SOMETHING WONDERFUL");
      const note = chrome.querySelector(".dream-skin-note");
      const noteLines = Array.isArray(VISUAL.note?.lines) ? VISUAL.note.lines.filter(Boolean) : [];
      const noteRequested = Boolean(VISUAL.note?.title && noteLines.length);
      setTextIfChanged(note?.querySelector("strong"), VISUAL.note?.title || "");
      setTextIfChanged(note?.querySelector("span"), noteLines.join("\n"));
      const geometry = {
        left: `${Math.round(shellBox.left)}px`,
        top: `${Math.round(shellBox.top)}px`,
        width: `${Math.round(shellBox.width)}px`,
        height: `${Math.round(shellBox.height)}px`,
      };
      for (const [name, value] of Object.entries(geometry)) {
        if (chrome.style[name] !== value) chrome.style[name] = value;
      }
      const composerSurface = home?.querySelector('.composer-surface-chrome');
      const composerFrame = composerSurface?.closest('.flex.w-full.flex-col.gap-2.relative') || composerSurface;
      const composerBox = composerFrame?.getBoundingClientRect();
      const noteRoom = composerBox ? Math.floor(shellBox.right - composerBox.right - 18) : 0;
      const noteVisible = noteRequested && noteRoom >= 132 && composerBox?.height >= 90;
      toggleClassIfChanged(note, "is-visible", Boolean(noteVisible));
      if (noteVisible) {
        setStyleIfChanged(note, "left", `${Math.round(composerBox.right - shellBox.left + 12)}px`);
        setStyleIfChanged(note, "top", `${Math.round(composerBox.top - shellBox.top)}px`);
        setStyleIfChanged(note, "width", `${Math.min(164, noteRoom)}px`);
        setStyleIfChanged(note, "min-height", `${Math.round(Math.min(152, composerBox.height))}px`);
      }
    }
    toggleClassIfChanged(chrome, "dream-skin-home-shell", Boolean(home));
    toggleClassIfChanged(chrome, "qq2007-shell", THEME_PROFILE === "qq2007");
    if (chrome.dataset.dreamShell !== shell) chrome.dataset.dreamShell = shell;
    const nativeOverlayOpen = [...document.querySelectorAll(
      '[data-radix-popper-content-wrapper], [role="menu"], [role="dialog"], [data-state="open"][data-side], div.z-50',
    )].some((node) => {
      if (!(node instanceof HTMLElement) || node.closest(`#${CHROME_ID}`)) return false;
      const rect = node.getBoundingClientRect();
      const nodeStyle = getComputedStyle(node);
      return rect.width > 80 && rect.height > 40 && nodeStyle.display !== "none" && nodeStyle.visibility !== "hidden";
    });
    chrome.toggleAttribute("data-native-overlay-open", nativeOverlayOpen);

    // Some Codex builds paint the suggestion-button layer behind an opaque
    // home surface. Mirror the real button rectangles visually in the
    // pointer-events:none chrome so clicks still land on the native controls.
    if (cardSet && home && THEME_PROFILE !== "qq2007") {
      const cardButtons = [...home.querySelectorAll('[class~="group/home-suggestions"] button')].slice(0, 4);
      cardButtons.forEach((button, index) => {
        const label = cardSet[index];
        if (!label) return;
        bindCardAction(button, label, index);
        const rect = button.getBoundingClientRect();
        if (rect.width < 40 || rect.height < 40) return;
        let visual = chrome.querySelector(`.dream-skin-card-visual[data-card-index="${index + 1}"]`);
        if (!visual) {
          visual = document.createElement("div");
          visual.className = "dream-skin-card-visual";
          visual.dataset.cardIndex = String(index + 1);
          visual.innerHTML = '<span class="dream-skin-card-visual-icon"></span><strong></strong><small></small><i>→</i>';
          chrome.appendChild(visual);
        }
        const geometry = {
          left: `${Math.round(rect.left - shellBox.left)}px`,
          top: `${Math.round(rect.top - shellBox.top)}px`,
          width: `${Math.round(rect.width)}px`,
          height: `${Math.round(rect.height)}px`,
        };
        for (const [property, value] of Object.entries(geometry)) {
          if (visual.style[property] !== value) visual.style[property] = value;
        }
        const visualTitle = label.title;
        const visualDetail = label.detail;
        const actionLabel = button.getAttribute("aria-label") || button.getAttribute("title") || visualTitle;
        if (visual.dataset.actionLabel !== actionLabel) visual.dataset.actionLabel = actionLabel;
        const icon = visual.querySelector(".dream-skin-card-visual-icon");
        const title = visual.querySelector("strong");
        const detail = visual.querySelector("small");
        if (icon.textContent !== label.icon) icon.textContent = label.icon;
        if (title.textContent !== visualTitle) title.textContent = visualTitle;
        if (detail.textContent !== visualDetail) detail.textContent = visualDetail;
      });
      chrome.querySelectorAll(".dream-skin-card-visual").forEach((node) => {
        if (Number(node.dataset.cardIndex) > cardButtons.length) node.remove();
      });
    } else {
      chrome.querySelectorAll(".dream-skin-card-visual").forEach((node) => node.remove());
    }
  };

  const cleanup = () => {
    window[DISABLED_KEY] = true;
    document.documentElement?.classList.remove("codex-dream-skin");
    document.documentElement?.removeAttribute(SHELL_ATTR);
    document.documentElement?.removeAttribute(THEME_ATTR);
    document.documentElement?.removeAttribute(THEME_ID_ATTR);
    document.documentElement?.removeAttribute("data-dream-layout");
    document.documentElement?.removeAttribute("data-dream-palette");
    document.documentElement?.removeAttribute("data-dream-page");
    document.documentElement?.style.removeProperty("--dream-skin-art");
    for (const name of THEME_VARIABLES) document.documentElement?.style.removeProperty(name);
    document.documentElement?.style.removeProperty("--qq-page-title");
    document.querySelectorAll(".dream-skin-home").forEach((node) => node.classList.remove("dream-skin-home"));
    document.querySelectorAll(".dream-skin-home-shell").forEach((node) => node.classList.remove("dream-skin-home-shell"));
    document.getElementById(STYLE_ID)?.remove();
    document.getElementById(CHROME_ID)?.remove();
    document.getElementById('dream-skin-extra-card')?.remove();
    qqSidebarObserver?.disconnect();
    qqSidebarObserver = null;
    qqObservedAside = null;
    if (qqSidebarResetTimer) clearTimeout(qqSidebarResetTimer);
    qqSidebarResetTimer = null;
    qqSidebarInteractionController?.abort();
    qqSidebarInteractionController = null;
    layoutResizeObserver?.disconnect();
    layoutResizeObserver = null;
    layoutObservedMain = null;
    if (layoutSyncFrame) cancelAnimationFrame(layoutSyncFrame);
    layoutSyncFrame = null;
    if (layoutPointerHandler) document.removeEventListener("pointermove", layoutPointerHandler, true);
    layoutPointerHandler = null;
    cardActionController.abort();
    const state = window[STATE_KEY];
    state?.observer?.disconnect();
    if (state?.timer) clearInterval(state.timer);
    if (state?.scheduler?.timeout) clearTimeout(state.scheduler.timeout);
    if (state?.resizeHandler) window.removeEventListener("resize", state.resizeHandler);
    if (state?.scrollHandler) window.removeEventListener("scroll", state.scrollHandler, true);
    if (state?.frameScheduler?.frame) cancelAnimationFrame(state.frameScheduler.frame);
    if (state?.mediaHandler && state?.mediaQuery) {
      try { state.mediaQuery.removeEventListener("change", state.mediaHandler); } catch {}
    }
    if (state?.artUrl) URL.revokeObjectURL(state.artUrl);
    delete window[STATE_KEY];
    return true;
  };

  const qqClockFormatter = THEME_PROFILE === "qq2007"
    ? new Intl.DateTimeFormat("zh-CN", { hour: "2-digit", minute: "2-digit", hour12: false })
    : null;
  const updateQQClock = () => {
    if (window[DISABLED_KEY] || !qqClockFormatter) return;
    const clock = document.getElementById(CHROME_ID)?.querySelector(".qq2007-clock");
    setTextIfChanged(clock, qqClockFormatter.format(new Date()));
  };

  const scheduler = { timeout: null };
  const scheduleEnsure = () => {
    if (scheduler.timeout) clearTimeout(scheduler.timeout);
    scheduler.timeout = setTimeout(() => {
      scheduler.timeout = null;
      ensure();
    }, 180);
  };
  const isInternalNode = (node) => {
    if (!(node instanceof Element)) return false;
    return node.id === STYLE_ID || node.id === CHROME_ID || Boolean(node.closest?.(`#${CHROME_ID}`));
  };
  const observer = new MutationObserver((mutations) => {
    const touchesNativeDom = mutations.some((mutation) => {
      const target = mutation.target instanceof Element ? mutation.target : mutation.target.parentElement;
      if (isInternalNode(target)) return false;
      const changedNodes = [...mutation.addedNodes, ...mutation.removedNodes].filter((node) => node instanceof Element);
      return changedNodes.length === 0 || changedNodes.some((node) => !isInternalNode(node));
    });
    if (touchesNativeDom) scheduleEnsure();
  });
  observer.observe(document.documentElement, {
    childList: true,
    subtree: true,
  });
  const timer = setInterval(() => {
    if (window[STATE_KEY]?.instanceToken !== INSTANCE_TOKEN) return;
    updateQQClock();
    const style = document.getElementById(STYLE_ID);
    if (!style || style.textContent !== cssText ||
        style.dataset.dreamSkinThemeId !== (THEME.id || "custom") ||
        document.documentElement.getAttribute(THEME_ID_ATTR) !== (THEME.id || "custom")) {
      ensure();
    }
  }, 1000);
  const resizeHandler = scheduleEnsure;
  window.addEventListener("resize", resizeHandler, { passive: true });
  const frameScheduler = { frame: null };
  const scrollHandler = () => {
    if (THEME_PROFILE === "qq2007" || frameScheduler.frame) return;
    frameScheduler.frame = requestAnimationFrame(() => {
      frameScheduler.frame = null;
      ensure();
    });
  };
  window.addEventListener("scroll", scrollHandler, { passive: true, capture: true });

  let mediaQuery = null;
  let mediaHandler = null;
  try {
    mediaQuery = window.matchMedia("(prefers-color-scheme: dark)");
    mediaHandler = () => scheduleEnsure();
    mediaQuery.addEventListener("change", mediaHandler);
  } catch {}

  window[STATE_KEY] = {
    instanceToken: INSTANCE_TOKEN,
    ensure,
    cleanup,
    observer,
    timer,
    scheduler,
    resizeHandler,
    scrollHandler,
    frameScheduler,
    layoutResizeObserver,
    layoutSyncFrame,
    layoutPointerHandler,
    mediaQuery,
    mediaHandler,
    qqSidebarObserver,
    qqSidebarResetTimer,
    qqSidebarInitializing: qqShouldResetSidebarWidth,
    qqSidebarInteractionController,
    cardActionController,
    qqSidebarRatio,
    artUrl,
    version: VERSION,
    themeId: THEME.id || "custom",
    profile: THEME_PROFILE,
    detectShellMode,
  };
  ensure();
  updateQQClock();
  return { installed: true, version: VERSION, themeId: THEME.id || "custom", profile: THEME_PROFILE, shell: detectShellMode() };
})(__DREAM_SKIN_CSS_JSON__, __DREAM_SKIN_ART_JSON__, __DREAM_SKIN_THEME_JSON__)
