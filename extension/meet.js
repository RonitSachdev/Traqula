// Google Meet adapter. Selectors live only here; when Meet changes its page, this is the file to fix.

TraqulaBridge.start({
  site: "meet",

  inCall() {
    return /^\/[a-z]{3}-[a-z]{4}-[a-z]{3}/.test(location.pathname) && this.micButton() !== null;
  },

  title() {
    const code = location.pathname.slice(1).split("/")[0];
    const named = document.querySelector('[data-meeting-title]');
    return (named && named.getAttribute("data-meeting-title")) || code;
  },

  micButton() {
    return (
      document.querySelector('button[data-is-muted]') ||
      document.querySelector('[role="button"][aria-label*="microphone" i]') ||
      document.querySelector('[role="button"][aria-label*="マイク"]')
    );
  },

  muted() {
    const button = this.micButton();
    if (!button) return null;
    const flag = button.getAttribute("data-is-muted");
    if (flag !== null) return flag === "true";
    const label = (button.getAttribute("aria-label") || "").toLowerCase();
    return /turn on|unmute|オン/.test(label);
  },

  tiles() {
    return Array.from(document.querySelectorAll("[data-participant-id]"));
  },

  nameOf(tile) {
    const self = tile.querySelector("[data-self-name]");
    if (self) return self.getAttribute("data-self-name") || TraqulaBridge.text(self);
    const label = tile.getAttribute("aria-label");
    if (label) return label.replace(/\s*\(.*\)\s*$/, "").trim();
    return TraqulaBridge.text(tile).split("\n")[0] || null;
  },

  speaker() {
    const speaking = this.tiles().find((tile) => TraqulaBridge.isAnimating(tile));
    return speaking ? this.nameOf(speaking) : null;
  },

  participants() {
    return Array.from(new Set(this.tiles().map((tile) => this.nameOf(tile)).filter(Boolean)));
  },

  me() {
    const self = document.querySelector("[data-self-name]");
    return self ? self.getAttribute("data-self-name") || TraqulaBridge.text(self) : null;
  },
});
