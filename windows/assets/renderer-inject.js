((cssText, artDataUrl, theme, version) => {
  const STATE_KEY = "__CODEX_DREAM_SKIN_STATE__";
  const STYLE_ID = "codex-dream-skin-style";
  const CHROME_ID = "codex-dream-skin-chrome";
  const SIDEBAR_ID = "codex-dream-skin-sidebar-identity";
  const RESIZE_LAYER_ID = "codex-dream-window-resize-layer";
  const THEME_ATTR = "data-dream-theme";
  const THEME_ID_ATTR = "data-dream-theme-id";
  const profile = theme.profile || "inspiration-universe";
  const instanceToken = Symbol("codex-dream-skin-instance");
  const visual = theme.visual && typeof theme.visual === "object" ? theme.visual : {};
  const layoutVariant = ["enfp", "purple-night", "miku"].includes(visual.layoutVariant) ? visual.layoutVariant : "";
  const visualSidebar = visual.sidebar && typeof visual.sidebar === "object" ? visual.sidebar : {};
  const visualNote = visual.note && typeof visual.note === "object" ? visual.note : {};
  const visualChrome = visual.chrome && typeof visual.chrome === "object" ? visual.chrome : {};
  const hasThemeVisualCards = Array.isArray(visual.cards) && visual.cards.length > 0;
  const cardSets = {
    classic: [["</>","探索并理解代码","梳理代码结构与实现逻辑"],["✚","构建新功能","创建应用、组件或工具"],["☑","审查代码","发现问题并提出修改建议"],["🛠","修复问题","定位失败并完成可靠修复"]],
    fortune: [["🪙","成本优化","识别浪费并降低资源成本"],["账","技术债清账","扫描债务并逐项清理"],["▧","自动报表总结","生成进度与质量报告"],["✚","冲突合并开运","检查冲突并安全合并"]],
    future: [["</>","构建","编写代码与应用"],["◇","分析","数据分析与洞察"],["🚀","自动化","智能体与工作流"],["↓","调试","修复问题与优化"]],
    inspiration: [["💡","灵感脑暴","把脑子里的一万种可能都倒出来"],["⚡","快速原型","先跑起来，再继续打磨"],["🎮","边玩边改","改到爽为止，体验即正义"],["🧩","插件与工具","打开真实 Codex 插件入口"]],
    qq: [["📝","新建与规划","创建任务并拆解后续步骤"],["📚","调研与总结","整理资料并提炼结论"],["🕘","自动化处理","处理日常和重复性工作"],["🧩","插件与工具","打开真实 Codex 插件入口"]],
  };
  const fallbackCardSet = profile === "qq2007" ? null : cardSets[({"skin-01":"classic","skin-02":"fortune","skin-03":"future","skin-04":"classic","skin-05":"inspiration","skin-06":"classic","skin-07":"classic","skin-08":"classic"})[theme.id]];
  const cardSet = hasThemeVisualCards
    ? visual.cards
    : fallbackCardSet?.map((card, index) => ({
        icon: card[0], title: card[1], detail: card[2], action: index === 3 ? "plugins" : "native", prompt: "",
      }));
  const escapeHtml = (value) => String(value ?? "").replace(/[&<>"']/g, (character) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  })[character]);
  window.__CODEX_DREAM_SKIN_DISABLED__ = false;

  const previous = window[STATE_KEY];
  previous?.observer?.disconnect();
  if (previous?.timer) clearInterval(previous.timer);
  if (previous?.scheduler?.timeout) clearTimeout(previous.scheduler.timeout);
  if (previous?.resizeHandler) window.removeEventListener("resize", previous.resizeHandler);
  if (previous?.scrollHandler) window.removeEventListener("scroll", previous.scrollHandler, true);
  if (previous?.frameScheduler?.frame) cancelAnimationFrame(previous.frameScheduler.frame);
  if (previous?.qqSidebarObserver) previous.qqSidebarObserver.disconnect();
  if (previous?.qqSidebarResetTimer) clearTimeout(previous.qqSidebarResetTimer);
  previous?.qqSidebarInteractionController?.abort();
  previous?.layoutResizeObserver?.disconnect();
  if (previous?.layoutSyncFrame) cancelAnimationFrame(previous.layoutSyncFrame);
  if (previous?.layoutPointerHandler) document.removeEventListener("pointermove", previous.layoutPointerHandler, true);
  if (previous?.artUrl) URL.revokeObjectURL(previous.artUrl);
  if (previous?.profile && (previous.profile !== profile || previous.themeId !== theme.id)) {
    document.getElementById(CHROME_ID)?.remove();
    document.getElementById("dream-extra-card")?.remove();
  }
  document.getElementById(RESIZE_LAYER_ID)?.remove();
  window[STATE_KEY] = { instanceToken };

  const artUrl = (() => {
    if (!artDataUrl) return "";
    const comma = artDataUrl.indexOf(",");
    const binary = atob(artDataUrl.slice(comma + 1));
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index);
    const mime = artDataUrl.slice(5, artDataUrl.indexOf(";")) || "image/png";
    return URL.createObjectURL(new Blob([bytes], { type: mime }));
  })();

  const variables = {
    "--dream-theme-background": theme.colors.background,
    "--dream-theme-panel": theme.colors.panel,
    "--dream-theme-panel-alt": theme.colors.panelAlt,
    "--dream-theme-accent": theme.colors.accent,
    "--dream-theme-accent-alt": theme.colors.accentAlt,
    "--dream-theme-secondary": theme.colors.secondary,
    "--dream-theme-highlight": theme.colors.highlight,
    "--dream-theme-text": theme.colors.text,
    "--dream-theme-muted": theme.colors.muted,
    "--dream-theme-line": theme.colors.line,
    "--dream-art-position": theme.art?.position || "center center",
    "--dream-art-size": theme.art?.size || "cover",
  };
  const backgroundMatch = String(theme.colors.background || "").trim().match(/^#([0-9a-f]{6})$/i);
  const configuredAppearance = String(theme.appearance || "").toLowerCase();
  const palette = configuredAppearance === "light" || configuredAppearance === "dark" ? configuredAppearance : backgroundMatch ? (() => {
    const value = Number.parseInt(backgroundMatch[1], 16);
    const red = (value >> 16) & 255;
    const green = (value >> 8) & 255;
    const blue = value & 255;
    return (red * 0.299 + green * 0.587 + blue * 0.114) >= 150 ? "light" : "dark";
  })() : "light";
  const clamp = (value, minimum, maximum) => Math.max(minimum, Math.min(maximum, value));
  const canRestoreQQSidebar = previous?.version === version &&
    previous?.profile === "qq2007" &&
    previous?.qqSidebarInitializing !== true &&
    Number.isFinite(Number(previous?.qqSidebarRatio));
  let qqSidebarRatio = canRestoreQQSidebar
    ? clamp(Number(previous.qqSidebarRatio), 0.16, 0.42)
    : 333 / 1440;
  let qqShouldResetSidebarWidth = profile === "qq2007" && !canRestoreQQSidebar;
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

  const sendWindowMessage = (message) => {
    if (typeof window.__codexDreamSkinWindowAction !== "function") return;
    window.__codexDreamSkinWindowAction(typeof message === "string" ? message : JSON.stringify(message));
  };

  const fillComposerPrompt = (prompt) => {
    const value = String(prompt || "").trim();
    if (!value) return false;
    const editor = document.querySelector(
      '.composer-surface-chrome textarea, .composer-surface-chrome [contenteditable="true"], .composer-surface-chrome .ProseMirror',
    );
    if (!(editor instanceof HTMLElement)) return false;
    editor.focus();
    if (editor instanceof HTMLTextAreaElement || editor instanceof HTMLInputElement) {
      const descriptor = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(editor), "value");
      if (descriptor?.set) descriptor.set.call(editor, value);
      else editor.value = value;
      editor.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText", data: value }));
      editor.dispatchEvent(new Event("change", { bubbles: true }));
      return true;
    }
    const selection = window.getSelection();
    const range = document.createRange();
    range.selectNodeContents(editor);
    selection?.removeAllRanges();
    selection?.addRange(range);
    const inserted = typeof document.execCommand === "function" && document.execCommand("insertText", false, value);
    if (!inserted || !editor.textContent?.includes(value)) editor.textContent = value;
    editor.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText", data: value }));
    selection?.removeAllRanges();
    return true;
  };

  const openPlugins = () => {
    const plugin = [...document.querySelectorAll('button, a, [role="button"]')].find((node) =>
      !node.closest?.(`#${CHROME_ID}, #dream-extra-card`) &&
      /插件|plugins?|extensions?/i.test(`${node.getAttribute("aria-label") || ""} ${node.getAttribute("title") || ""} ${node.textContent || ""}`),
    );
    if (!(plugin instanceof HTMLElement)) return false;
    plugin.click();
    return true;
  };

  const ensureSidebarIdentity = () => {
    const existing = document.getElementById(SIDEBAR_ID);
    const aside = document.querySelector("aside.app-shell-left-panel");
    const hasContent = Boolean(visualSidebar.brand || visualSidebar.subtitle || visualSidebar.footerText);
    if (profile === "qq2007" || !hasContent || !(aside instanceof HTMLElement)) {
      existing?.remove();
      return;
    }
    let identity = existing;
    if (!identity || identity.parentElement !== aside) {
      identity?.remove();
      identity = document.createElement("div");
      identity.id = SIDEBAR_ID;
      identity.setAttribute("aria-hidden", "true");
      identity.innerHTML = '<div class="dream-sidebar-brand"><strong></strong><small></small></div><div class="dream-sidebar-footer"></div>';
      aside.appendChild(identity);
    }
    identity.setAttribute("data-dream-layout", layoutVariant || "generic");
    const values = [visualSidebar.brand || theme.name, visualSidebar.subtitle || theme.brandSubtitle, visualSidebar.footerText || ""];
    [identity.querySelector("strong"), identity.querySelector("small"), identity.querySelector(".dream-sidebar-footer")]
      .forEach((node, index) => { if (node.textContent !== values[index]) node.textContent = values[index]; });
  };

  const ensureResizeLayer = () => {
    if (profile !== "qq2007") {
      document.getElementById(RESIZE_LAYER_ID)?.remove();
      return null;
    }
    let layer = document.getElementById(RESIZE_LAYER_ID);
    if (layer) return layer;
    layer = document.createElement("div");
    layer.id = RESIZE_LAYER_ID;
    layer.setAttribute("aria-hidden", "true");
    layer.innerHTML = ["n", "s", "e", "w", "ne", "nw", "se", "sw"]
      .map((direction) => `<div class="dream-window-resize-handle" data-dream-resize-direction="${direction}"></div>`)
      .join("");
    document.body.appendChild(layer);

    let drag = null;
    let frame = null;
    let pendingMove = null;
    const flushMove = () => {
      frame = null;
      if (!pendingMove) return;
      sendWindowMessage(pendingMove);
      pendingMove = null;
    };
    const finish = (event) => {
      if (!drag || (event && event.pointerId !== drag.pointerId)) return;
      if (frame) cancelAnimationFrame(frame);
      frame = null;
      if (pendingMove) sendWindowMessage(pendingMove);
      pendingMove = null;
      sendWindowMessage({ type: "resize-end", direction: drag.direction });
      drag = null;
      document.documentElement.removeAttribute("data-dream-window-resizing");
    };

    layer.addEventListener("pointerdown", (event) => {
      const handle = event.target.closest?.("[data-dream-resize-direction]");
      const direction = handle?.getAttribute("data-dream-resize-direction");
      if (!direction || document.documentElement.getAttribute("data-dream-window-state") !== "normal") return;
      event.preventDefault();
      event.stopPropagation();
      drag = { pointerId: event.pointerId, direction, startX: event.screenX, startY: event.screenY };
      handle.setPointerCapture?.(event.pointerId);
      document.documentElement.setAttribute("data-dream-window-resizing", direction);
      sendWindowMessage({ type: "resize-start", direction, screenX: event.screenX, screenY: event.screenY });
    });
    layer.addEventListener("pointermove", (event) => {
      if (!drag || event.pointerId !== drag.pointerId) return;
      event.preventDefault();
      pendingMove = {
        type: "resize-move",
        direction: drag.direction,
        dx: event.screenX - drag.startX,
        dy: event.screenY - drag.startY,
      };
      if (!frame) frame = requestAnimationFrame(flushMove);
    });
    layer.addEventListener("pointerup", finish);
    layer.addEventListener("pointercancel", finish);
    layer.addEventListener("lostpointercapture", finish);
    return layer;
  };

  const ensureChrome = (shellMain, home) => {
    let chrome = document.getElementById(CHROME_ID);
    if (!chrome || chrome.parentElement !== document.body || chrome.dataset.themeId !== theme.id) {
      chrome?.remove();
      chrome = document.createElement("div");
      chrome.id = CHROME_ID;
      chrome.dataset.themeId = theme.id || "custom";
      chrome.setAttribute("data-dream-layout", layoutVariant || "generic");
      chrome.innerHTML = profile === "qq2007" ? `
        <div class="dream-window-title"><b>🐧 Codex 2007</b><span>${escapeHtml(theme.brandSubtitle)}</span></div>
        <div class="dream-window-actions">
          <button type="button" data-dream-window-action="minimize" aria-label="最小化">—</button>
          <button type="button" data-dream-window-action="toggle-maximize" aria-label="放大或还原">□</button>
          <button type="button" data-dream-window-action="close" aria-label="关闭">×</button>
        </div>
        <div class="dream-brand"><b>${escapeHtml(theme.name)}</b><small>${escapeHtml(theme.tagline)}</small></div>` : `
        <div class="dream-brand"><span class="dream-note">✦</span><span><b>${escapeHtml(visualSidebar.brand || theme.name)}</b><small>${escapeHtml(visualSidebar.subtitle || theme.brandSubtitle)}</small></span></div>
        <div class="dream-signature">${escapeHtml(theme.quote)}</div>
        ${visualNote.title || visualNote.lines?.length ? `<section class="dream-theme-note"><strong>${escapeHtml(visualNote.title)}</strong>${(visualNote.lines || []).map((line) => `<span>${escapeHtml(line)}</span>`).join("")}</section>` : ""}
        ${visualChrome.sparkles ? '<div class="dream-sparkles"><i></i><i></i><i></i><i></i><i></i><i></i></div>' : ""}
        ${visualChrome.ribbon ? '<div class="dream-ribbon"><span>♡</span>🎀<span>✦</span></div>' : ""}
        ${visualChrome.polaroid ? '<div class="dream-polaroid"></div>' : ""}`;
      document.body.appendChild(chrome);
      chrome.querySelectorAll("[data-dream-window-action]").forEach((button) => {
        button.addEventListener("click", (event) => {
          event.preventDefault();
          event.stopPropagation();
          const action = button.getAttribute("data-dream-window-action");
          sendWindowMessage(action);
        });
      });
    }
    ensureResizeLayer();
    const box = shellMain.getBoundingClientRect();
    chrome.style.left = `${Math.round(box.left)}px`;
    chrome.style.top = `${Math.round(box.top)}px`;
    chrome.style.width = `${Math.round(box.width)}px`;
    chrome.style.height = `${Math.round(box.height)}px`;
    chrome.classList.toggle("dream-home-shell", Boolean(home));
    const note = chrome.querySelector(".dream-theme-note");
    const composerSurface = home?.querySelector(".composer-surface-chrome");
    const composerFrame = composerSurface?.closest(".flex.w-full.flex-col.gap-2.relative") || composerSurface;
    const composerBox = composerFrame?.getBoundingClientRect();
    const noteRoom = composerBox ? Math.floor(box.right - composerBox.right - 18) : 0;
    const noteVisible = Boolean(note && composerBox && noteRoom >= 154 && composerBox.height >= 90);
    note?.classList.toggle("is-visible", noteVisible);
    if (noteVisible) {
      note.style.left = `${Math.round(composerBox.right - box.left + 12)}px`;
      note.style.top = `${Math.round(composerBox.top - box.top)}px`;
      note.style.width = `${Math.min(164, noteRoom)}px`;
      note.style.minHeight = `${Math.round(Math.min(152, composerBox.height))}px`;
    }
    if (cardSet && home && profile !== "qq2007") {
      [...home.querySelectorAll('[class~="group/home-suggestions"] button')].slice(0, 4).forEach((button, index) => {
        const card = cardSet[index];
        if (!card) return;
        const rect = button.getBoundingClientRect();
        if (rect.width < 40 || rect.height < 40) return;
        let visual = chrome.querySelector(`.dream-card-visual[data-card-index="${index + 1}"]`);
        if (!visual) {
          visual = document.createElement("button");
          visual.type = "button";
          visual.className = "dream-card-visual";
          visual.dataset.cardIndex = String(index + 1);
          visual.innerHTML = "<span></span><strong></strong><small></small><i>→</i>";
          visual.addEventListener("click", (event) => {
            event.preventDefault();
            event.stopPropagation();
            if (visual.__dreamAction === "plugins") openPlugins();
            else if (visual.__dreamAction === "prompt") fillComposerPrompt(visual.__dreamPrompt);
            else if (visual.__dreamTarget instanceof HTMLElement) visual.__dreamTarget.click();
          });
          chrome.appendChild(visual);
        }
        const geometry = { left: `${Math.round(rect.left - box.left)}px`, top: `${Math.round(rect.top - box.top)}px`, width: `${Math.round(rect.width)}px`, height: `${Math.round(rect.height)}px` };
        for (const [property, value] of Object.entries(geometry)) if (visual.style[property] !== value) visual.style[property] = value;
        const nativeLines = (button.innerText || "").split(/\n+/).map((line) => line.trim()).filter(Boolean);
        const visualTitle = hasThemeVisualCards ? card.title : (nativeLines[0] || card.title);
        const visualDetail = hasThemeVisualCards ? card.detail : (nativeLines.slice(1).join(" · ") || card.detail);
        const actionLabel = hasThemeVisualCards ? `${visualTitle}：${visualDetail}` :
          (button.getAttribute("aria-label") || button.getAttribute("title") || visualTitle);
        if (visual.dataset.actionLabel !== actionLabel) visual.dataset.actionLabel = actionLabel;
        visual.setAttribute("aria-label", actionLabel);
        visual.__dreamAction = card.action;
        visual.__dreamPrompt = card.prompt || card.title;
        visual.__dreamTarget = button;
        const icon = visual.querySelector("span");
        const title = visual.querySelector("strong");
        const detail = visual.querySelector("small");
        if (icon.textContent !== card.icon) icon.textContent = card.icon;
        if (title.textContent !== visualTitle) title.textContent = visualTitle;
        if (detail.textContent !== visualDetail) detail.textContent = visualDetail;
      });
      const count = Math.min(4, home.querySelectorAll('[class~="group/home-suggestions"] button').length);
      chrome.querySelectorAll(".dream-card-visual").forEach((node) => { if (Number(node.dataset.cardIndex) > count) node.remove(); });
    } else chrome.querySelectorAll(".dream-card-visual").forEach((node) => node.remove());
    return chrome;
  };

  const ensureQQSidebarObserver = (root) => {
    if (profile !== "qq2007") {
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
      const width = aside.getBoundingClientRect().width;
      if (!Number.isFinite(width) || width < 120) return;
      if (qqShouldResetSidebarWidth) {
        const referenceWidth = Math.round(window.innerWidth * qqSidebarRatio);
        if (Math.abs(width - referenceWidth) > 1.5) aside.style.width = `${referenceWidth}px`;
        return;
      }
      const currentWidth = Math.round(window.innerWidth * qqSidebarRatio);
      if (Math.abs(width - currentWidth) <= 1.5) return;
      if (!qqUserResizeActive && performance.now() > qqUserResizeGraceUntil) {
        aside.style.width = `${currentWidth}px`;
        return;
      }
      qqSidebarRatio = clamp(width / Math.max(window.innerWidth, 1), 0.16, 0.42);
      root.style.setProperty("--qq-left", `${Math.round(width)}px`);
      if (window[STATE_KEY]) window[STATE_KEY].qqSidebarRatio = qqSidebarRatio;
    };
    if (qqObservedAside !== aside) {
      if (qqShouldResetSidebarWidth) {
        const referenceWidth = Math.round(window.innerWidth * qqSidebarRatio);
        if (referenceWidth > 0) aside.style.width = `${referenceWidth}px`;
        qqSidebarResetTimer = setTimeout(() => {
          qqShouldResetSidebarWidth = false;
          qqSidebarResetTimer = null;
          aside.style.width = `${referenceWidth}px`;
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

  const ensure = () => {
    if (window.__CODEX_DREAM_SKIN_DISABLED__ || window[STATE_KEY]?.instanceToken !== instanceToken) return;
    const root = document.documentElement;
    if (!root) return;
    root.classList.add("codex-dream-skin");
    root.setAttribute(THEME_ATTR, profile);
    root.setAttribute(THEME_ID_ATTR, theme.id || "custom");
    root.setAttribute("data-dream-layout", layoutVariant || "generic");
    root.setAttribute("data-dream-palette", palette);
    for (const [name, value] of Object.entries(variables)) root.style.setProperty(name, value);
    if (artUrl) root.style.setProperty("--dream-art", `url("${artUrl}")`);
    else root.style.setProperty("--dream-art", "none");

    let style = document.getElementById(STYLE_ID);
    if (!style) {
      style = document.createElement("style");
      style.id = STYLE_ID;
      (document.head || root).appendChild(style);
    }
    if (style.textContent !== cssText || style.dataset.dreamVersion !== version || style.dataset.themeId !== theme.id) {
      style.textContent = cssText;
      style.dataset.dreamVersion = version;
      style.dataset.themeId = theme.id;
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
        if (profile !== "qq2007" && (event.buttons & 1) === 1) scheduleLayoutSync();
      };
      document.addEventListener("pointermove", layoutPointerHandler, { passive: true, capture: true });
    }
    ensureQQSidebarObserver(root);
    ensureSidebarIdentity();
    const home = document.querySelector('[role="main"]:has([data-testid="home-icon"]), [role="main"]:has([data-feature="game-source"])');
    root.setAttribute("data-dream-page", home ? "home" : "task");
    document.querySelectorAll('[role="main"].dream-home').forEach((node) => node.classList.toggle("dream-home", node === home));
    if (home) home.classList.add("dream-home");
    const nativeOverlayOpen = [...document.querySelectorAll(
      '[data-radix-popper-content-wrapper], [role="menu"], [role="dialog"], [data-state="open"][data-side], div.z-50',
    )].some((node) => {
      if (!(node instanceof HTMLElement) || node.closest(`#${CHROME_ID}`)) return false;
      const rect = node.getBoundingClientRect();
      const nodeStyle = getComputedStyle(node);
      return rect.width > 80 && rect.height > 40 && nodeStyle.display !== "none" && nodeStyle.visibility !== "hidden";
    });
    document.getElementById(CHROME_ID)?.toggleAttribute("data-native-overlay-open", nativeOverlayOpen);
    const suggestionsGrid = home?.querySelector('[class~="group/home-suggestions"] .grid');
    const nativeCardButtons = suggestionsGrid
      ? [...suggestionsGrid.querySelectorAll('button')].filter((button) => !button.closest('#dream-extra-card'))
      : [];
    const nativeCardCount = nativeCardButtons.length;
    let extraCard = document.getElementById("dream-extra-card");
    if (profile === "qq2007") {
      extraCard?.remove();
    } else if (cardSet?.length > 3 && suggestionsGrid && nativeCardCount === 3) {
      if (!extraCard || extraCard.parentElement !== suggestionsGrid) {
        extraCard?.remove();
        extraCard = document.createElement("div");
        extraCard.id = "dream-extra-card";
        extraCard.innerHTML = '<button type="button" class="dream-plugin-card" aria-label="打开 Codex 插件"></button>';
        extraCard.querySelector("button")?.addEventListener("click", () => {
          const card = cardSet[3];
          if (card?.action === "plugins") openPlugins();
          else if (card?.action === "prompt") fillComposerPrompt(card.prompt || card.title);
        });
        suggestionsGrid.appendChild(extraCard);
      }
    } else extraCard?.remove();
    if (!shellMain || !document.body) return;
    shellMain.classList.toggle("dream-home-shell", Boolean(home));
    ensureChrome(shellMain, home);
  };

  const cleanup = () => {
    window.__CODEX_DREAM_SKIN_DISABLED__ = true;
    document.documentElement?.classList.remove("codex-dream-skin");
    document.documentElement?.removeAttribute(THEME_ATTR);
    document.documentElement?.removeAttribute(THEME_ID_ATTR);
    document.documentElement?.removeAttribute("data-dream-layout");
    document.documentElement?.removeAttribute("data-dream-palette");
    document.documentElement?.removeAttribute("data-dream-page");
    document.documentElement?.removeAttribute("data-dream-window-state");
    document.documentElement?.removeAttribute("data-dream-window-resizing");
    document.documentElement?.style.removeProperty("--dream-art");
    for (const name of Object.keys(variables)) document.documentElement?.style.removeProperty(name);
    document.querySelectorAll(".dream-home").forEach((node) => node.classList.remove("dream-home"));
    document.querySelectorAll(".dream-home-shell").forEach((node) => node.classList.remove("dream-home-shell"));
    document.getElementById(STYLE_ID)?.remove();
    document.getElementById(CHROME_ID)?.remove();
    document.getElementById(RESIZE_LAYER_ID)?.remove();
    document.getElementById(SIDEBAR_ID)?.remove();
    document.getElementById("dream-extra-card")?.remove();
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
    const state = window[STATE_KEY];
    state?.observer?.disconnect();
    if (state?.timer) clearInterval(state.timer);
    if (state?.scheduler?.timeout) clearTimeout(state.scheduler.timeout);
    if (state?.resizeHandler) window.removeEventListener("resize", state.resizeHandler);
    if (state?.scrollHandler) window.removeEventListener("scroll", state.scrollHandler, true);
    if (state?.frameScheduler?.frame) cancelAnimationFrame(state.frameScheduler.frame);
    if (state?.artUrl) URL.revokeObjectURL(state.artUrl);
    delete window[STATE_KEY];
    return true;
  };

  const scheduler = { timeout: null };
  const scheduleEnsure = () => {
    if (scheduler.timeout) clearTimeout(scheduler.timeout);
    scheduler.timeout = setTimeout(() => { scheduler.timeout = null; ensure(); }, 140);
  };
  const observer = new MutationObserver((mutations) => {
    const internalOnly = mutations.every((mutation) => {
      const target = mutation.target instanceof Element ? mutation.target : mutation.target.parentElement;
      return target === document.documentElement && mutation.attributeName === "style"
        || target?.id === STYLE_ID
        || Boolean(target?.closest?.(`#${CHROME_ID}`));
    });
    if (!internalOnly) scheduleEnsure();
  });
  observer.observe(document.documentElement, { childList: true, subtree: true });
  const timer = setInterval(() => {
    if (window[STATE_KEY]?.instanceToken !== instanceToken) return;
    const style = document.getElementById(STYLE_ID);
    if (!style || style.textContent !== cssText || style.dataset.themeId !== theme.id ||
        document.documentElement.getAttribute(THEME_ID_ATTR) !== (theme.id || "custom")) ensure();
  }, 1000);
  const resizeHandler = scheduleEnsure;
  window.addEventListener("resize", resizeHandler, { passive: true });
  const frameScheduler = { frame: null };
  const scrollHandler = () => {
    if (profile === "qq2007" || frameScheduler.frame) return;
    frameScheduler.frame = requestAnimationFrame(() => {
      frameScheduler.frame = null;
      ensure();
    });
  };
  window.addEventListener("scroll", scrollHandler, { passive: true, capture: true });
  window[STATE_KEY] = { instanceToken, ensure, cleanup, observer, timer, scheduler, resizeHandler, scrollHandler, frameScheduler, layoutResizeObserver, layoutSyncFrame, layoutPointerHandler,
    qqSidebarObserver, qqSidebarResetTimer, qqSidebarInitializing: qqShouldResetSidebarWidth,
    qqSidebarInteractionController, qqSidebarRatio, artUrl, version, themeId: theme.id, themeName: theme.name, profile };
  ensure();
  return { installed: true, version, themeId: theme.id, profile };
})(__DREAM_SKIN_CSS_JSON__, __DREAM_SKIN_ART_JSON__, __DREAM_SKIN_THEME_JSON__, __DREAM_SKIN_VERSION_JSON__)
