// Zoom web client adapter (zoom.us/wc). Best effort: Zoom's web UI is driven by aria labels, which is what this reads.

TraqulaBridge.start({
  site: "zoomweb",

  micButton() {
    return document.querySelector('button[aria-label^="mute" i], button[aria-label^="unmute" i]');
  },

  inCall() {
    return this.micButton() !== null;
  },

  title() {
    const heading = document.querySelector('[class*="meeting-info"] [class*="topic"], [aria-label*="meeting topic" i]');
    return TraqulaBridge.text(heading) || document.title || null;
  },

  muted() {
    const button = this.micButton();
    if (!button) return null;
    return /^unmute/i.test(button.getAttribute("aria-label") || "");
  },

  tiles() {
    return Array.from(document.querySelectorAll('[class*="video-avatar__avatar"], [class*="gallery-video-container__video-frame"]'));
  },

  nameOf(tile) {
    const name = tile.querySelector('[class*="display-name"], [class*="video-avatar__avatar-name"]');
    return TraqulaBridge.text(name) || null;
  },

  speaker() {
    const speaking = this.tiles().find((tile) => /speaking|active/i.test(tile.className) || TraqulaBridge.isAnimating(tile));
    return speaking ? this.nameOf(speaking) : null;
  },

  participants() {
    return Array.from(new Set(this.tiles().map((tile) => this.nameOf(tile)).filter(Boolean)));
  },

  me() {
    const own = this.tiles().find((tile) => /\(me\)|\(自分\)/i.test(TraqulaBridge.text(tile)));
    return own ? this.nameOf(own).replace(/\s*\((me|自分)\)\s*$/i, "") : null;
  },
});
