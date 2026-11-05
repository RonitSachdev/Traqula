// Microsoft Teams web adapter. Best effort: reads Teams' aria labels and data-tid hooks.

TraqulaBridge.start({
  site: "teams",

  micButton() {
    return document.querySelector('[data-tid="toggle-mute"], button[aria-label*="mute" i]');
  },

  inCall() {
    return this.micButton() !== null;
  },

  title() {
    const heading = document.querySelector('[data-tid="call-title"], [data-tid*="meeting-title" i]');
    return TraqulaBridge.text(heading) || document.title || null;
  },

  muted() {
    const button = this.micButton();
    if (!button) return null;
    const pressed = button.getAttribute("aria-pressed");
    if (pressed !== null) return pressed === "true";
    return /^unmute/i.test(button.getAttribute("aria-label") || "");
  },

  tiles() {
    return Array.from(document.querySelectorAll('[data-tid*="participant-tile" i], [data-tid*="video-tile" i], [data-cid*="calling-participant" i]'));
  },

  nameOf(tile) {
    const name = tile.querySelector('[data-tid*="name" i], [class*="displayName" i]');
    return TraqulaBridge.text(name) || (tile.getAttribute("aria-label") || "").split(",")[0].trim() || null;
  },

  speaker() {
    const speaking = this.tiles().find((tile) => /speaking/i.test(tile.getAttribute("aria-label") || "") || TraqulaBridge.isAnimating(tile));
    return speaking ? this.nameOf(speaking) : null;
  },

  participants() {
    return Array.from(new Set(this.tiles().map((tile) => this.nameOf(tile)).filter(Boolean)));
  },

  me() {
    const own = this.tiles().find((tile) => /\(you\)|\(自分\)/i.test(TraqulaBridge.text(tile)));
    return own ? this.nameOf(own).replace(/\s*\((you|自分)\)\s*$/i, "") : null;
  },
});
