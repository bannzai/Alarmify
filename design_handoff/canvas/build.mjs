// Signalarm のデザインカンバス (Claude Code の /design) に流し込むアートボード (.dc.html) と canvas.json を生成する。
// 画面ごとの構成はここが正で、ダーク / ライトは同じ構成にテーマのトークン (tokens.md と同じ値) を当てて出力する。
// 生成物は同じディレクトリに置き、再生成は冪等 (同じ入力から同じファイルを上書きする)。
//
// 実行: node design_handoff/canvas/build.mjs
import { writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const outDir = dirname(fileURLToPath(import.meta.url));

// ---- デザイントークン (design_handoff/tokens.md が正。ここは同じ値の転記) ----
const themes = {
  dark: {
    id: "Dark",
    bg: "#0A0A0B",
    bg2: "#0F1012",
    panel: "#15161A",
    fg: "#F2F2F0",
    fg2: "rgba(242,242,240,0.76)",
    fg3: "rgba(242,242,240,0.56)",
    fg4: "rgba(242,242,240,0.35)",
    hair: "rgba(242,242,240,0.10)",
    hair2: "rgba(242,242,240,0.16)",
    accent: "#F97316",
    accentText: "#F97316",
    accentSoft: "rgba(249,115,22,0.14)",
    accentLine: "rgba(249,115,22,0.40)",
    onAccent: "#0A0A0B",
    destructive: "#FF453A",
    scheme: "dark",
  },
  light: {
    id: "Light",
    bg: "#F5F5F3",
    bg2: "#ECECE9",
    panel: "#FFFFFF",
    fg: "#111113",
    fg2: "rgba(17,17,19,0.72)",
    fg3: "rgba(17,17,19,0.52)",
    fg4: "rgba(17,17,19,0.36)",
    hair: "rgba(17,17,19,0.10)",
    hair2: "rgba(17,17,19,0.16)",
    accent: "#F97316",
    accentText: "#C2410C",
    accentSoft: "rgba(249,115,22,0.12)",
    accentLine: "rgba(249,115,22,0.45)",
    onAccent: "#FFFFFF",
    destructive: "#FF3B30",
    scheme: "light",
  },
};

// style="..." 属性の中に置くため、フォント名の引用符はシングルクォートにする (二重引用符だと属性が途中で閉じる)
const sans = `-apple-system, 'SF Pro Text', 'Helvetica Neue', system-ui, sans-serif`;
const mono = `ui-monospace, 'SF Mono', Menlo, Consolas, monospace`;

// ---- アイコン (stroke ベースの inline SVG。24px グリッド) ----
const icon = (name, size = 20, color = "currentColor") => {
  const paths = {
    bell: `<path d="M6 16V11a6 6 0 0 1 12 0v5l2 2H4l2-2Z"/><path d="M10 20a2 2 0 0 0 4 0"/>`,
    bellRing: `<path d="M6 16V11a6 6 0 0 1 12 0v5l2 2H4l2-2Z"/><path d="M10 20a2 2 0 0 0 4 0"/><path d="M2.5 9a8 8 0 0 1 2-4.5"/><path d="M21.5 9a8 8 0 0 0-2-4.5"/>`,
    gear: `<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1Z"/>`,
    chevron: `<path d="m9 6 6 6-6 6"/>`,
    back: `<path d="m15 6-6 6 6 6"/>`,
    copy: `<rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V5a2 2 0 0 1 2-2h10"/>`,
    key: `<circle cx="8" cy="15" r="4"/><path d="m11 12 9-9"/><path d="m17 6 3 3"/><path d="m14 9 2 2"/>`,
    plug: `<path d="M9 2v6"/><path d="M15 2v6"/><path d="M6 8h12v3a6 6 0 0 1-12 0V8Z"/><path d="M12 17v5"/>`,
    check: `<path d="m5 12 5 5 9-10"/>`,
    arrow: `<path d="M4 12h16"/><path d="m14 6 6 6-6 6"/>`,
    clock: `<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>`,
    terminal: `<path d="m5 7 5 5-5 5"/><path d="M12 17h7"/>`,
    server: `<rect x="3" y="4" width="18" height="7" rx="2"/><rect x="3" y="13" width="18" height="7" rx="2"/><path d="M7 7.5h.01"/><path d="M7 16.5h.01"/>`,
    phone: `<rect x="6" y="2" width="12" height="20" rx="3"/><path d="M10 18h4"/>`,
    history: `<path d="M3 12a9 9 0 1 0 3-6.7"/><path d="M3 4v5h5"/><path d="M12 7v5l3 2"/>`,
    devices: `<rect x="3" y="5" width="12" height="14" rx="2"/><rect x="17" y="9" width="4" height="10" rx="1.5"/>`,
    infinity: `<path d="M7 8a4 4 0 0 0 0 8c3 0 4-4 5-4s2-4 5-4a4 4 0 0 1 0 8c-3 0-4-4-5-4s-2 4-5 4"/>`,
    close: `<path d="m6 6 12 12"/><path d="m18 6-12 12"/>`,
    external: `<path d="M14 4h6v6"/><path d="M20 4 10 14"/><path d="M18 13v6H5V6h6"/>`,
    book: `<path d="M4 4h6a3 3 0 0 1 3 3v13a2 2 0 0 0-2-2H4V4Z"/><path d="M20 4h-6a3 3 0 0 0-3 3v13a2 2 0 0 1 2-2h7V4Z"/>`,
    lock: `<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>`,
    moon: `<path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5Z"/>`,
    pause: `<path d="M9 5v14"/><path d="M15 5v14"/>`,
    waves: `<path d="M6 16V11a6 6 0 0 1 12 0v5l2 2H4l2-2Z"/><path d="M10 20a2 2 0 0 0 4 0"/><path d="M1.5 10a10 10 0 0 1 2.5-6"/><path d="M22.5 10a10 10 0 0 0-2.5-6"/>`,
    mail: `<rect x="3" y="5" width="18" height="14" rx="2"/><path d="m3 7 9 6 9-6"/>`,
  };
  return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="${color}" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${paths[name]}</svg>`;
};

// ---- 共通の部品 ----
const s = (obj) =>
  Object.entries(obj)
    .filter(([, v]) => v !== undefined && v !== null && v !== false)
    .map(([k, v]) => `${k.replace(/[A-Z]/g, (m) => "-" + m.toLowerCase())}: ${v}`)
    .join("; ");

const phone = (t, body, { title, sub } = {}) => `<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
  <style>
    body { margin: 0; background: ${t.bg}; color: ${t.fg}; font-family: ${sans}; -webkit-font-smoothing: antialiased; color-scheme: ${t.scheme}; }
    a { color: ${t.accentText}; text-decoration: none; } a:hover { color: ${t.accent}; }
    * { box-sizing: border-box; }
  </style>
</helmet>
<div style="${s({ width: "390px", height: "844px", background: t.bg, color: t.fg, overflow: "hidden", display: "flex", flexDirection: "column", position: "relative", fontFamily: sans })}">
${body}
</div>
</x-dc>
</body>
</html>
`;

// ナビゲーションバー。iOS の status bar 領域 (上 59px) は空けておく (偽のステータスバーは描かない)
const navBar = (t, { title, large = false, leading = "", trailing = "" }) => `
  <div style="${s({ height: "59px", flexShrink: 0 })}"></div>
  <div style="${s({ display: "flex", alignItems: "center", justifyContent: "space-between", height: "44px", padding: "0 16px", flexShrink: 0 })}">
    <div style="${s({ display: "flex", alignItems: "center", gap: "4px", minWidth: "60px", color: t.accentText })}">${leading}</div>
    ${large ? `<div></div>` : `<div style="${s({ fontSize: "17px", fontWeight: 600, letterSpacing: "-0.01em" })}">${title}</div>`}
    <div style="${s({ display: "flex", alignItems: "center", justifyContent: "flex-end", gap: "12px", minWidth: "60px", color: t.accentText })}">${trailing}</div>
  </div>
  ${large ? `<div style="${s({ padding: "4px 20px 12px", fontSize: "34px", lineHeight: "41px", fontWeight: 700, letterSpacing: "-0.02em", flexShrink: 0 })}">${title}</div>` : ""}
`;

const backButton = (t, label) => `<span style="${s({ display: "inline-flex", alignItems: "center", gap: "2px", fontSize: "17px", color: t.accentText })}">${icon("back", 22, t.accentText)}<span>${label}</span></span>`;

const homeIndicator = (t) => `
  <div style="${s({ height: "34px", flexShrink: 0, display: "flex", alignItems: "flex-end", justifyContent: "center", paddingBottom: "8px" })}">
    <div style="${s({ width: "134px", height: "5px", borderRadius: "3px", background: t.fg4 })}"></div>
  </div>`;

const buttonPrimary = (t, label, { iconName } = {}) => `
  <div style="${s({ display: "flex", alignItems: "center", justifyContent: "center", gap: "8px", height: "52px", borderRadius: "12px", background: t.accent, color: t.onAccent, fontSize: "17px", fontWeight: 600 })}">${iconName ? icon(iconName, 20, t.onAccent) : ""}<span>${label}</span></div>`;

const buttonSecondary = (t, label) => `
  <div style="${s({ display: "flex", alignItems: "center", justifyContent: "center", height: "48px", borderRadius: "12px", border: `1px solid ${t.hair2}`, color: t.fg2, fontSize: "17px", fontWeight: 500 })}">${label}</div>`;

const buttonText = (t, label) => `
  <div style="${s({ display: "flex", alignItems: "center", justifyContent: "center", height: "44px", color: t.fg3, fontSize: "15px", fontWeight: 500 })}">${label}</div>`;

const eyebrow = (t, text, color = t.accentText) => `
  <div style="${s({ fontFamily: mono, fontSize: "11px", letterSpacing: "0.2em", textTransform: "uppercase", color })}">${text}</div>`;

const sectionHeader = (t, text, trailing = "", { tight = false } = {}) => `
  <div style="${s({ display: "flex", alignItems: "baseline", justifyContent: "space-between", padding: tight ? "14px 20px 6px" : "20px 20px 8px", flexShrink: 0 })}">
    <div style="${s({ fontSize: "13px", fontWeight: 600, letterSpacing: "0.04em", textTransform: "uppercase", color: t.fg3 })}">${text}</div>
    ${trailing ? `<div style="${s({ fontSize: "15px", color: t.accentText, fontWeight: 500 })}">${trailing}</div>` : ""}
  </div>`;

const card = (t, inner, extra = {}) => `
  <div style="${s({ margin: "0 16px", background: t.panel, border: `1px solid ${t.hair}`, borderRadius: "14px", overflow: "hidden", flexShrink: 0, ...extra })}">${inner}</div>`;

// 行の区切りは hairline 1px (HairlineDivider と同じ)
const row = (t, inner, { last = false, padding = "13px 16px" } = {}) => `
  <div style="${s({ display: "flex", alignItems: "center", gap: "12px", padding, borderBottom: last ? undefined : `1px solid ${t.hair}`, minHeight: "48px" })}">${inner}</div>`;

const navRow = (t, label, { value = "", iconName, last = false, destructive = false } = {}) =>
  row(
    t,
    `${iconName ? `<span style="${s({ color: t.fg3, display: "flex" })}">${icon(iconName, 20, t.fg3)}</span>` : ""}
     <span style="${s({ flexGrow: 1, fontSize: "17px", color: destructive ? t.destructive : t.fg })}">${label}</span>
     ${value ? `<span style="${s({ fontSize: "17px", color: t.fg3 })}">${value}</span>` : ""}
     ${icon("chevron", 18, t.fg4)}`,
    { last },
  );

const valueRow = (t, label, value, { last = false, monoValue = false } = {}) =>
  row(
    t,
    `<span style="${s({ flexGrow: 1, fontSize: "17px" })}">${label}</span>
     <span style="${s({ fontSize: monoValue ? "13px" : "17px", fontFamily: monoValue ? mono : undefined, color: t.fg3, textAlign: "right" })}">${value}</span>`,
    { last },
  );

const code = (t, text, { wrap = true, copy = true, small = false } = {}) => `
  <div style="${s({ background: t.bg2, border: `1px solid ${t.hair}`, borderRadius: "10px", overflow: "hidden" })}">
    <div style="${s({ padding: "12px 14px", fontFamily: mono, fontSize: small ? "11px" : "12px", lineHeight: small ? "16px" : "18px", color: t.fg2, whiteSpace: wrap ? "pre-wrap" : "pre", wordBreak: wrap ? "break-all" : undefined, overflowX: wrap ? undefined : "auto" })}">${text}</div>
    ${copy ? `<div style="${s({ display: "flex", alignItems: "center", justifyContent: "flex-end", gap: "6px", padding: "8px 12px", borderTop: `1px solid ${t.hair}`, fontSize: "13px", fontWeight: 600, color: t.accentText })}">${icon("copy", 16, t.accentText)}<span>Copy</span></div>` : ""}
  </div>`;

const chip = (t, label, { accent = false } = {}) => `
  <span style="${s({ display: "inline-flex", alignItems: "center", height: "26px", padding: "0 10px", borderRadius: "13px", fontFamily: mono, fontSize: "11px", letterSpacing: "0.02em", color: accent ? t.accentText : t.fg3, background: accent ? t.accentSoft : "transparent", border: `1px solid ${accent ? t.accentLine : t.hair2}` })}">${label}</span>`;

const progress = (t, step, total = 5) => `
  <div style="${s({ display: "flex", gap: "6px", padding: "0 20px" })}">
    ${Array.from({ length: total }, (_, i) => `<div style="${s({ flexGrow: 1, height: "3px", borderRadius: "2px", background: i < step ? t.accent : t.hair2 })}"></div>`).join("")}
  </div>`;

const tokenPreview = (t) => `alm_9f2c4e1b7a03d8f6c2b19e5a4d7f0c3e8b6a2d`;
const curlLine = (t) => `curl -X POST https://api.alarmify.app/v1/alarms -H 'Authorization: Bearer alm_9f2c…' -H 'Content-Type: application/json' -d '{"fire_in":60,"title":"Deploy finished"}'`;

// ---- オンボーディング (5 画面) ----
const onboardingShell = (t, step, { eyebrowText, title, lead, visual, primary, secondary }) => `
  <div style="${s({ height: "59px", flexShrink: 0 })}"></div>
  <div style="${s({ height: "44px", display: "flex", alignItems: "center", flexShrink: 0 })}">${progress(t, step)}</div>
  <div style="${s({ padding: "28px 24px 0", display: "flex", flexDirection: "column", gap: "12px", flexShrink: 0 })}">
    ${eyebrow(t, eyebrowText)}
    <div style="${s({ fontSize: "34px", lineHeight: "40px", fontWeight: 700, letterSpacing: "-0.02em", textWrap: "balance" })}">${title}</div>
    <div style="${s({ fontSize: "17px", lineHeight: "24px", color: t.fg2, textWrap: "pretty" })}">${lead}</div>
  </div>
  <div style="${s({ flexGrow: 1, display: "flex", flexDirection: "column", justifyContent: "center", padding: "24px" })}">${visual}</div>
  <div style="${s({ padding: "0 20px 8px", display: "flex", flexDirection: "column", gap: "8px", flexShrink: 0 })}">
    ${primary}
    ${secondary ?? ""}
  </div>
  ${homeIndicator(t)}`;

const flowNode = (t, iconName, label, sub, { accent = false } = {}) => `
  <div style="${s({ display: "flex", alignItems: "center", gap: "14px", padding: "16px 18px", background: t.panel, border: `1px solid ${accent ? t.accentLine : t.hair}`, borderRadius: "14px" })}">
    <span style="${s({ display: "flex", color: accent ? t.accentText : t.fg3 })}">${icon(iconName, 24, accent ? t.accentText : t.fg3)}</span>
    <div style="${s({ display: "flex", flexDirection: "column", gap: "2px" })}">
      <div style="${s({ fontSize: "17px", fontWeight: 600 })}">${label}</div>
      <div style="${s({ fontSize: "13px", color: t.fg3, fontFamily: sub.startsWith("POST") ? mono : undefined })}">${sub}</div>
    </div>
  </div>`;

const flowArrow = (t) => `
  <div style="${s({ display: "flex", justifyContent: "center", height: "28px", alignItems: "center" })}">
    <div style="${s({ width: "1px", height: "100%", background: t.accentLine })}"></div>
  </div>`;

const onboarding1 = (t) =>
  onboardingShell(t, 1, {
    eyebrowText: "Signalarm",
    title: "Turn any webhook into a real alarm",
    lead: "Send one HTTP request from your service and this iPhone rings. Not a notification but an alarm that cuts through Silent mode and Focus even when the app is closed.",
    visual: `
      <div style="${s({ display: "flex", flexDirection: "column" })}">
        ${flowNode(t, "server", "Your service", "GitHub Actions · Home Assistant · cron")}
        ${flowArrow(t)}
        ${flowNode(t, "terminal", "Signalarm API", "POST /v1/alarms")}
        ${flowArrow(t)}
        ${flowNode(t, "bellRing", "This iPhone rings", "AlarmKit alarm on the Lock Screen", { accent: true })}
      </div>`,
    primary: buttonPrimary(t, "Get started"),
  });

const permissionCard = (t, iconName, heading, lines) => `
  <div style="${s({ background: t.panel, border: `1px solid ${t.hair}`, borderRadius: "16px", padding: "20px" })}">
    <div style="${s({ display: "flex", alignItems: "center", gap: "12px", marginBottom: "14px" })}">
      <span style="${s({ display: "flex", width: "40px", height: "40px", alignItems: "center", justifyContent: "center", borderRadius: "10px", background: t.accentSoft, color: t.accentText })}">${icon(iconName, 22, t.accentText)}</span>
      <div style="${s({ fontSize: "17px", fontWeight: 600 })}">${heading}</div>
    </div>
    <div style="${s({ display: "flex", flexDirection: "column", gap: "10px" })}">
      ${lines.map((l) => `<div style="${s({ display: "flex", gap: "10px", alignItems: "flex-start", fontSize: "15px", lineHeight: "21px", color: t.fg2 })}"><span style="${s({ display: "flex", marginTop: "2px", color: t.accentText })}">${icon("check", 16, t.accentText)}</span><span>${l}</span></div>`).join("")}
    </div>
  </div>`;

const onboarding2 = (t) =>
  onboardingShell(t, 2, {
    eyebrowText: "Step 1 of 4",
    title: "Allow alarms",
    lead: "Signalarm rings through AlarmKit, the same system as the built-in Clock. Nothing can ring without this permission.",
    visual: permissionCard(t, "bell", "What alarms can do", [
      "Ring in Silent mode and every Focus",
      "Show full screen on the Lock Screen",
      "Keep ringing until you stop them",
    ]),
    primary: buttonPrimary(t, "Allow alarms"),
    secondary: buttonText(t, "Not now"),
  });

const onboarding3 = (t) =>
  onboardingShell(t, 3, {
    eyebrowText: "Step 2 of 4",
    title: "Allow notifications",
    lead: "Your services reach this iPhone through push. That is how an alarm request arrives while the app is closed.",
    visual: permissionCard(t, "phone", "What push is used for", [
      "Deliver alarm requests from your services",
      "Schedule the alarm in the background",
      "No marketing and no unrelated banners",
    ]),
    primary: buttonPrimary(t, "Allow notifications"),
    secondary: buttonText(t, "Not now"),
  });

const onboarding4 = (t) =>
  onboardingShell(t, 4, {
    eyebrowText: "Step 3 of 4",
    title: "Your first API token",
    lead: "Paste it into the service that should wake you. It is shown only once.",
    visual: `
      <div style="${s({ display: "flex", flexDirection: "column", gap: "12px" })}">
        <div style="${s({ background: t.panel, border: `1px solid ${t.accentLine}`, borderRadius: "14px", padding: "16px" })}">
          ${eyebrow(t, "Token", t.fg3)}
          <div style="${s({ marginTop: "8px", fontFamily: mono, fontSize: "15px", lineHeight: "22px", wordBreak: "break-all", color: t.fg })}">${tokenPreview(t)}</div>
          <div style="${s({ display: "flex", alignItems: "center", justifyContent: "space-between", marginTop: "14px" })}">
            <div style="${s({ fontSize: "13px", color: t.fg3 })}">Shown only once</div>
            <div style="${s({ display: "flex", alignItems: "center", gap: "6px", height: "34px", padding: "0 12px", borderRadius: "9px", background: t.accentSoft, color: t.accentText, fontSize: "14px", fontWeight: 600 })}">${icon("copy", 16, t.accentText)}<span>Copy</span></div>
          </div>
        </div>
        ${code(t, curlLine(t), { copy: true })}
      </div>`,
    primary: buttonPrimary(t, "Continue"),
    secondary: buttonText(t, "Issue a token later"),
  });

const onboarding5 = (t) =>
  onboardingShell(t, 5, {
    eyebrowText: "Step 4 of 4",
    title: "Hear it ring",
    lead: "Schedule a test alarm one minute from now. Lock the iPhone and wait. Real requests from your services work the same way.",
    visual: `
      <div style="${s({ background: t.panel, border: `1px solid ${t.hair}`, borderRadius: "16px", padding: "22px 20px", display: "flex", flexDirection: "column", alignItems: "center", gap: "8px" })}">
        ${eyebrow(t, "Test alarm", t.fg3)}
        <div style="${s({ fontFamily: mono, fontSize: "56px", lineHeight: "60px", fontWeight: 500, letterSpacing: "-0.02em", color: t.accentText, fontVariantNumeric: "tabular-nums" })}">01:00</div>
        <div style="${s({ fontSize: "15px", color: t.fg3 })}">rings after you lock the iPhone</div>
      </div>`,
    primary: buttonPrimary(t, "Ring a test alarm in 1 minute", { iconName: "bellRing" }),
    secondary: buttonText(t, "Skip"),
  });

// ---- ホーム ----
const historyRow = (t, { title, source, when, status, ok = true, last = false }) =>
  row(
    t,
    `<div style="${s({ display: "flex", flexDirection: "column", gap: "3px", flexGrow: 1, minWidth: 0 })}">
       <div style="${s({ fontSize: "17px", fontWeight: 600, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" })}">${title}</div>
       <div style="${s({ display: "flex", alignItems: "center", gap: "8px", fontSize: "13px", color: t.fg3 })}"><span>${when}</span><span style="${s({ fontFamily: mono, fontSize: "11px" })}">${source}</span></div>
     </div>
     <div style="${s({ fontSize: "13px", fontWeight: 500, color: ok ? t.fg3 : t.fg4, whiteSpace: "nowrap" })}">${status}</div>`,
    { last, padding: "12px 16px" },
  );

const home = (t) => `
  ${navBar(t, { title: "Signalarm", large: true, trailing: icon("gear", 22, t.accentText) })}
  <div style="${s({ flexGrow: 1, overflow: "hidden", display: "flex", flexDirection: "column" })}">
    ${card(
      t,
      `<div style="${s({ padding: "18px 18px 16px", display: "flex", flexDirection: "column", gap: "6px" })}">
         <div style="${s({ display: "flex", justifyContent: "space-between", alignItems: "center" })}">
           ${eyebrow(t, "Next alarm")}
           <span style="${s({ fontSize: "13px", color: t.fg3 })}">Rings in 9h 12m</span>
         </div>
         <div style="${s({ display: "flex", alignItems: "baseline", gap: "10px", marginTop: "4px" })}">
           <span style="${s({ fontFamily: mono, fontSize: "56px", lineHeight: "60px", fontWeight: 500, letterSpacing: "-0.02em", fontVariantNumeric: "tabular-nums" })}">07:30</span>
           <span style="${s({ fontSize: "17px", color: t.fg2 })}">Tomorrow</span>
         </div>
         <div style="${s({ fontSize: "20px", fontWeight: 600, marginTop: "2px" })}">Deploy finished</div>
         <div style="${s({ display: "flex", alignItems: "center", gap: "8px", marginTop: "6px" })}">${chip(t, "alm_9f2c", { accent: true })}<span style="${s({ fontSize: "13px", color: t.fg3 })}">GitHub Actions</span></div>
       </div>`,
      { borderColor: t.accentLine },
    )}
    ${sectionHeader(t, "Recent alarms", "Ring a test")}
    ${card(
      t,
      historyRow(t, { title: "Deploy finished", source: "alm_9f2c", when: "Today 18:42", status: "Rang" }) +
        historyRow(t, { title: "Front door opened", source: "alm_c31a", when: "Today 07:15", status: "Rang" }) +
        historyRow(t, { title: "Release window opens in 1 hour", source: "alm_9f2c", when: "Yesterday 22:00", status: "Canceled", ok: false }) +
        row(
          t,
          `<span style="${s({ flexGrow: 1, fontSize: "15px", color: t.fg3 })}">Older alarms are kept in Pro</span>${icon("chevron", 18, t.fg4)}`,
          { last: true },
        ),
    )}
    ${sectionHeader(t, "Connect")}
    ${card(t, navRow(t, "API tokens", { value: "1", iconName: "key" }) + navRow(t, "Integration recipes", { iconName: "plug", last: true }))}
  </div>
  ${homeIndicator(t)}`;

// ---- API トークン ----
const tokens = (t) => `
  ${navBar(t, { title: "API tokens", leading: backButton(t, "Signalarm") })}
  <div style="${s({ flexGrow: 1, overflow: "hidden", display: "flex", flexDirection: "column", paddingTop: "8px" })}">
    ${card(
      t,
      `<div style="${s({ padding: "16px", display: "flex", flexDirection: "column", gap: "10px" })}">
         <div style="${s({ display: "flex", justifyContent: "space-between", alignItems: "center" })}">${eyebrow(t, "New token")}<span style="${s({ fontSize: "13px", color: t.fg3 })}">Shown only once</span></div>
         <div style="${s({ fontFamily: mono, fontSize: "15px", lineHeight: "22px", wordBreak: "break-all" })}">${tokenPreview(t)}</div>
         <div style="${s({ display: "flex", gap: "8px" })}">
           <div style="${s({ display: "flex", alignItems: "center", justifyContent: "center", gap: "6px", flexGrow: 1, height: "40px", borderRadius: "10px", background: t.accent, color: t.onAccent, fontSize: "15px", fontWeight: 600 })}">${icon("copy", 16, t.onAccent)}<span>Copy token</span></div>
           <div style="${s({ display: "flex", alignItems: "center", justifyContent: "center", height: "40px", padding: "0 14px", borderRadius: "10px", border: `1px solid ${t.hair2}`, color: t.fg2, fontSize: "15px", fontWeight: 500 })}">Done</div>
         </div>
       </div>`,
      { borderColor: t.accentLine },
    )}
    ${sectionHeader(t, "Tokens")}
    ${card(
      t,
      `<div style="${s({ padding: "14px 16px 12px", display: "flex", flexDirection: "column", gap: "10px" })}">
         <div style="${s({ display: "flex", alignItems: "center", justifyContent: "space-between" })}">
           <div style="${s({ display: "flex", flexDirection: "column", gap: "3px" })}">
             <span style="${s({ fontFamily: mono, fontSize: "17px" })}">alm_9f2c…</span>
             <span style="${s({ fontSize: "13px", color: t.fg3 })}">Created Sep 12 · 3 alarms this month</span>
           </div>
           <span style="${s({ fontSize: "15px", color: t.fg3 })}">Revoke</span>
         </div>
         ${code(t, curlLine(t), { copy: true })}
         <div style="${s({ display: "flex", gap: "8px", flexWrap: "wrap", alignItems: "center" })}">
           <span style="${s({ fontSize: "13px", color: t.fg3 })}">Recipes</span>${chip(t, "GitHub Actions")}${chip(t, "Home Assistant")}${chip(t, "Shortcuts")}
         </div>
       </div>`,
    )}
    <div style="${s({ padding: "16px 16px 0" })}">
      ${buttonSecondary(t, "Issue a token")}
      <div style="${s({ marginTop: "10px", fontSize: "13px", lineHeight: "18px", color: t.fg3, textAlign: "center" })}">The free plan includes one token and 20 alarms a month</div>
    </div>
  </div>
  ${homeIndicator(t)}`;

// ---- 連携レシピ ----
const recipes = (t) => `
  ${navBar(t, { title: "Integration recipes", leading: backButton(t, "Signalarm") })}
  <div style="${s({ flexGrow: 1, overflow: "hidden", display: "flex", flexDirection: "column", paddingTop: "8px" })}">
    <div style="${s({ padding: "8px 20px 16px", fontSize: "15px", lineHeight: "21px", color: t.fg2 })}">Every recipe ends with one request to <span style="${s({ fontFamily: mono, fontSize: "13px" })}">POST /v1/alarms</span>. Snippets already carry your token.</div>
    ${card(
      t,
      [
        ["cron / shell", "One curl line for scripts, crontab and CI jobs"],
        ["GitHub Actions", "Ring when a workflow finishes or fails"],
        ["Home Assistant", "A rest_command you can call from any automation"],
        ["Shortcuts", "The Get Contents of URL action for automations"],
        ["Grafana", "A webhook contact point that rings when an alert fires"],
        ["Uptime Kuma", "A webhook notification that rings when a monitor goes down"],
      ]
        .map(
          ([name, sub], i, arr) =>
            row(
              t,
              `<div style="${s({ display: "flex", flexDirection: "column", gap: "3px", flexGrow: 1 })}">
                 <div style="${s({ fontSize: "17px", fontWeight: 600 })}">${name}</div>
                 <div style="${s({ fontSize: "13px", lineHeight: "18px", color: t.fg3 })}">${sub}</div>
               </div>${icon("chevron", 18, t.fg4)}`,
              { last: i === arr.length - 1 },
            ),
        )
        .join(""),
    )}
    ${sectionHeader(t, "Reference")}
    ${card(t, navRow(t, "API reference", { iconName: "book", last: true }))}
  </div>
  ${homeIndicator(t)}`;

const recipeDetail = (t) => `
  ${navBar(t, { title: "GitHub Actions", leading: backButton(t, "Recipes"), trailing: icon("external", 20, t.accentText) })}
  <div style="${s({ flexGrow: 1, overflow: "hidden", display: "flex", flexDirection: "column", paddingTop: "8px" })}">
    ${sectionHeader(t, "Steps")}
    ${card(
      t,
      [
        `Store the token as the repository secret <span style="${s({ fontFamily: mono, fontSize: "13px" })}">ALARMIFY_TOKEN</span>. The gh CLI prompts for the value so it stays out of your shell history`,
        `Add the step at the end of the job. <span style="${s({ fontFamily: mono, fontSize: "13px" })}">if: always()</span> also rings after a failure`,
      ]
        .map(
          (text, i, arr) =>
            row(
              t,
              `<span style="${s({ fontFamily: mono, fontSize: "13px", color: t.accentText, width: "16px", flexShrink: 0, marginTop: "2px" })}">${i + 1}</span><span style="${s({ fontSize: "15px", lineHeight: "21px", color: t.fg2 })}">${text}</span>`,
              { last: i === arr.length - 1, padding: "12px 16px" },
            ),
        )
        .join(""),
    )}
    ${sectionHeader(t, "Workflow step")}
    <div style="${s({ padding: "0 16px", flexShrink: 0 })}">
      ${code(
        t,
        `- name: Ring my iPhone
  if: always()
  env:
    ALARMIFY_TOKEN: \${{ secrets.ALARMIFY_TOKEN }}
    WORKFLOW: \${{ github.workflow }}
    STATUS: \${{ job.status }}
  run: |
    curl -sS --fail-with-body -X POST \\
      https://api.alarmify.app/v1/alarms \\
      -H "Authorization: Bearer $ALARMIFY_TOKEN" \\
      -H "Content-Type: application/json" \\
      -d "$(jq -cn --arg title \\
        "$WORKFLOW: $STATUS" \\
        '{fire_in: 0, title: $title}')"`,
        { wrap: false, copy: true, small: true },
      )}
    </div>
    ${sectionHeader(t, "Secret")}
    <div style="${s({ padding: "0 16px", flexShrink: 0 })}">${code(t, `gh secret set ALARMIFY_TOKEN`, { copy: true })}</div>
  </div>
  ${homeIndicator(t)}`;

// ---- 設定 ----
const settings = (t) => `
  ${navBar(t, { title: "Settings", leading: backButton(t, "Signalarm") })}
  <div style="${s({ flexGrow: 1, overflow: "hidden", display: "flex", flexDirection: "column" })}">
    ${sectionHeader(t, "Plan", "", { tight: true })}
    ${card(t, valueRow(t, "Plan", "Free") + navRow(t, "Signalarm Pro", { last: true }))}
    ${sectionHeader(t, "Permissions", "", { tight: true })}
    ${card(t, valueRow(t, "Alarms", "Allowed") + valueRow(t, "Notifications", "Allowed", { last: true }))}
    ${sectionHeader(t, "Account", "", { tight: true })}
    ${card(t, valueRow(t, "Account ID", "uid_7Fk2…qL9", { monoValue: true }) + navRow(t, "Support", { value: "Email", last: true }))}
    ${sectionHeader(t, "Legal", "", { tight: true })}
    ${card(t, navRow(t, "Terms of Use") + navRow(t, "Privacy Policy") + navRow(t, "Legal Notice") + navRow(t, "Open Source Licenses", { last: true }))}
    <div style="${s({ padding: "14px 16px 0", flexShrink: 0 })}">
      ${card(t, row(t, `<span style="${s({ flexGrow: 1, fontSize: "17px", color: t.destructive })}">Delete Account</span>`, { last: true }), { margin: 0 })}
    </div>
  </div>
  ${homeIndicator(t)}`;

// ---- ペイウォール (sheet) ----
const planCard = (t, { name, price, per, note, selected, badge }) => `
  <div style="${s({ display: "flex", alignItems: "center", gap: "12px", padding: "14px 16px", borderRadius: "14px", background: t.panel, border: `1.5px solid ${selected ? t.accent : t.hair2}` })}">
    <span style="${s({ display: "flex", width: "22px", height: "22px", borderRadius: "11px", border: `1.5px solid ${selected ? t.accent : t.hair2}`, background: selected ? t.accent : "transparent", alignItems: "center", justifyContent: "center", flexShrink: 0 })}">${selected ? icon("check", 14, t.onAccent) : ""}</span>
    <div style="${s({ display: "flex", flexDirection: "column", gap: "2px", flexGrow: 1 })}">
      <div style="${s({ display: "flex", alignItems: "center", gap: "8px" })}"><span style="${s({ fontSize: "17px", fontWeight: 600 })}">${name}</span>${badge ? chip(t, badge, { accent: true }) : ""}</div>
      <div style="${s({ fontSize: "13px", color: t.fg3 })}">${note}</div>
    </div>
    <div style="${s({ display: "flex", flexDirection: "column", alignItems: "flex-end" })}">
      <span style="${s({ fontSize: "17px", fontWeight: 600, fontVariantNumeric: "tabular-nums" })}">${price}</span>
      <span style="${s({ fontSize: "13px", color: t.fg3 })}">${per}</span>
    </div>
  </div>`;

const paywall = (t) => `
  <div style="${s({ height: "59px", flexShrink: 0 })}"></div>
  <div style="${s({ display: "flex", justifyContent: "flex-end", padding: "0 16px", height: "44px", alignItems: "center", flexShrink: 0 })}">
    <span style="${s({ display: "flex", width: "30px", height: "30px", borderRadius: "15px", background: t.hair, alignItems: "center", justifyContent: "center", color: t.fg2 })}">${icon("close", 16, t.fg2)}</span>
  </div>
  <div style="${s({ padding: "8px 24px 0", display: "flex", flexDirection: "column", gap: "10px", flexShrink: 0 })}">
    ${eyebrow(t, "Signalarm Pro")}
    <div style="${s({ fontSize: "30px", lineHeight: "36px", fontWeight: 700, letterSpacing: "-0.02em", textWrap: "balance" })}">More services and every alarm kept</div>
    <div style="${s({ fontSize: "15px", lineHeight: "21px", color: t.fg2 })}">The free plan includes one token and 20 alarms a month. Pro removes both limits.</div>
  </div>
  <div style="${s({ padding: "22px 24px 0", display: "flex", flexDirection: "column", gap: "14px", flexShrink: 0 })}">
    ${[
      ["key", "A token for every service"],
      ["infinity", "Unlimited alarms"],
      ["history", "Full alarm history"],
      ["devices", "Rings on all your iPhones"],
    ]
      .map(
        ([ic, label]) =>
          `<div style="${s({ display: "flex", alignItems: "center", gap: "12px", fontSize: "17px" })}"><span style="${s({ display: "flex", color: t.accentText })}">${icon(ic, 20, t.accentText)}</span><span>${label}</span></div>`,
      )
      .join("")}
  </div>
  <div style="${s({ flexGrow: 1 })}"></div>
  <div style="${s({ padding: "0 16px", display: "flex", flexDirection: "column", gap: "8px", flexShrink: 0 })}">
    ${planCard(t, { name: "Yearly", price: "$14.99", per: "per year", note: "$1.25 a month billed yearly", selected: true, badge: "Best value" })}
    ${planCard(t, { name: "Monthly", price: "$1.99", per: "per month", note: "Cancel anytime", selected: false })}
  </div>
  <div style="${s({ padding: "16px 20px 6px", display: "flex", flexDirection: "column", gap: "10px", flexShrink: 0 })}">
    ${buttonPrimary(t, "Continue with Yearly")}
    <div style="${s({ fontSize: "11px", lineHeight: "15px", color: t.fg4, textAlign: "center" })}">Renews automatically until canceled in Settings. Prices shown in your local currency.</div>
    <div style="${s({ display: "flex", justifyContent: "center", gap: "18px", fontSize: "13px", color: t.fg3 })}"><span>Restore</span><span>Terms</span><span>Privacy</span><span>Legal notice</span></div>
  </div>
  ${homeIndicator(t)}`;

// ---- ロック画面 / Dynamic Island (ダークのみ。Live Activity は常に暗い地に描かれる) ----
const lockScreen = (t) => {
  const live = `
    <div style="${s({ display: "flex", alignItems: "center", gap: "12px", padding: "16px", borderRadius: "22px", background: "rgba(0,0,0,0.85)", border: "1px solid rgba(255,255,255,0.08)" })}">
      ${icon("bell", 26, t.accent)}
      <div style="${s({ display: "flex", flexDirection: "column", gap: "4px", flexGrow: 1 })}">
        <span style="${s({ fontFamily: sans, fontSize: "11px", fontWeight: 600, letterSpacing: "0.18em", color: "rgba(242,242,240,0.56)" })}">SIGNALARM</span>
        <span style="${s({ fontSize: "17px", fontWeight: 600, color: "#F2F2F0" })}">Deploy finished</span>
      </div>
      <span style="${s({ fontSize: "22px", fontWeight: 500, fontVariantNumeric: "tabular-nums", color: t.accent })}">0:58</span>
    </div>`;
  const island = (inner, w) => `
    <div style="${s({ width: w, background: "#000", borderRadius: "28px", padding: "14px 18px", display: "flex", alignItems: "center", gap: "12px", border: "1px solid rgba(255,255,255,0.06)" })}">${inner}</div>`;
  return `
    <div style="${s({ padding: "24px 20px", display: "flex", flexDirection: "column", gap: "20px", flexGrow: 1 })}">
      ${eyebrow(t, "Lock Screen · Live Activity")}
      ${live}
      <div style="${s({ fontSize: "13px", lineHeight: "18px", color: t.fg3 })}">Countdown to the alarm. When it rings the system draws the stop UI. That screen cannot be customized.</div>
      ${eyebrow(t, "Dynamic Island · expanded")}
      <div style="${s({ display: "flex", justifyContent: "center" })}">${island(
        `${icon("bell", 22, t.accent)}<span style="${s({ flexGrow: 1, fontSize: "17px", fontWeight: 600, color: "#F2F2F0" })}">Deploy finished</span><span style="${s({ fontSize: "20px", fontWeight: 500, fontVariantNumeric: "tabular-nums", color: t.accent })}">0:58</span>`,
        "350px",
      )}</div>
      ${eyebrow(t, "Dynamic Island · compact")}
      <div style="${s({ display: "flex", justifyContent: "center" })}">${island(
        `${icon("bell", 18, t.accent)}<span style="${s({ width: "70px" })}"></span><span style="${s({ fontSize: "15px", fontWeight: 500, fontVariantNumeric: "tabular-nums", color: t.accent })}">0:58</span>`,
        "auto",
      )}</div>
      ${eyebrow(t, "Dynamic Island · minimal")}
      <div style="${s({ display: "flex", justifyContent: "center" })}">${island(icon("bell", 16, t.accent), "auto")}</div>
      ${eyebrow(t, "While ringing")}
      <div style="${s({ display: "flex", justifyContent: "center" })}">${island(
        `${icon("waves", 22, t.accent)}<span style="${s({ flexGrow: 1, fontSize: "17px", fontWeight: 600, color: "#F2F2F0" })}">Deploy finished</span><span style="${s({ fontSize: "15px", color: "rgba(242,242,240,0.56)" })}">07:30</span>`,
        "350px",
      )}</div>
    </div>`;
};

// ---- 出力 ----
const screens = [
  ["OnboardingConcept", onboarding1, "Onboarding 1 · Concept"],
  ["OnboardingAlarms", onboarding2, "Onboarding 2 · Allow alarms"],
  ["OnboardingPush", onboarding3, "Onboarding 3 · Allow notifications"],
  ["OnboardingToken", onboarding4, "Onboarding 4 · First token"],
  ["OnboardingTest", onboarding5, "Onboarding 5 · Test alarm"],
  ["Home", home, "Home"],
  ["Tokens", tokens, "API tokens"],
  ["Recipes", recipes, "Integration recipes"],
  ["RecipeDetail", recipeDetail, "Recipe · GitHub Actions"],
  ["Settings", settings, "Settings"],
  ["Paywall", paywall, "Paywall"],
];

const W = 390;
const H = 844;
const GAP_X = 80;
const GAP_Y = 140;

const artboards = [];
const pages = [
  { id: "dark", name: "Dark" },
  { id: "light", name: "Light" },
];
const files = [];

for (const theme of [themes.dark, themes.light]) {
  screens.forEach(([stem, render, title], i) => {
    // ダークの先頭 (オンボーディングのコンセプト) を Main にする (カンバスの入口)
    const file = theme.id === "Dark" && i === 0 ? "Main.dc.html" : `${stem}${theme.id}.dc.html`;
    const html = phone(theme, render(theme));
    writeFileSync(join(outDir, file), html);
    files.push(file);
    const rowIndex = i < 5 ? 0 : 1;
    const col = i < 5 ? i : i - 5;
    artboards.push({
      file,
      title: `${title} (${theme.id})`,
      x: col * (W + GAP_X),
      y: rowIndex * (H + GAP_Y),
      w: W,
      h: H,
      page: theme.id.toLowerCase(),
    });
  });
}

{
  const file = "LockScreen.dc.html";
  writeFileSync(join(outDir, file), phone(themes.dark, lockScreen(themes.dark)));
  files.push(file);
  artboards.push({ file, title: "Lock Screen / Dynamic Island", x: 6 * (W + GAP_X), y: H + GAP_Y, w: W, h: H, page: "dark" });
}

const canvas = {
  pages,
  artboards,
  annotations: [
    {
      id: "note-tone",
      x: 0,
      y: -260,
      w: 560,
      page: "dark",
      text:
        "Signalarm design canvas\nTone: a trustworthy instrument for developers. Dark first, high contrast, one accent (signal orange #F97316), typography and spacing over decoration. Monospace only for tokens, curl and code.\nCopy is English (the app's base language). Japanese copy lives in design_handoff/screens/*.md.",
    },
    {
      id: "note-paywall-prices",
      x: 5 * (W + GAP_X),
      y: H + GAP_Y - 120,
      w: 390,
      page: "dark",
      text: "Prices on the paywall are SAMPLE values from documents/PROJECT.md. The app renders price, period and savings only from the RevenueCat offering and shows no fallback.",
    },
    {
      id: "note-light",
      x: 0,
      y: -200,
      w: 560,
      page: "light",
      text: "Light theme is new: the repo only defines dark tokens (Alarmify/Shared/DesignTokens.swift, docs/index.html). Values are in design_handoff/tokens.md. Small orange text uses #C2410C on light for contrast; fills and large numerals keep #F97316.",
    },
  ],
  launch: { view: "canvas", page: "dark" },
};
writeFileSync(join(outDir, "canvas.json"), JSON.stringify(canvas, null, 2) + "\n");
writeFileSync(join(outDir, "files.txt"), files.join("\n") + "\n");
console.log(`wrote ${files.length} artboards + canvas.json to ${outDir}`);
