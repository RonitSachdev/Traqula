// Google Meet adapter. Selectors live only here; when Meet changes its page, this is the file to fix.
//
// Calibrated against the live page on 2026-11-05 (Meet build 20261030):
// - The pre-join screen already carries data-in-call="true" and the microphone button, so "in the
//   call" means participant tiles exist.
// - Tiles are [data-participant-id]; the display name is the tile's span.notranslate (icons are <i>).
// - The self tile is the only one with the "Backgrounds and effects" control, recognised by its
//   locale-independent icon glyph "visual_effects". There is no data-self-name.
// - Each tile has [jsname="QgSmzd"] level indicators: the three-bar one (three child divs) is hidden
//   while silent and shown while that participant speaks; the small one gains class sxlEM meanwhile.
// - The microphone and camera buttons both carry data-is-muted; the mic one shows the "mic"/"mic_off" glyph.
// - Meeting paths may have a prefix segment (/meet/xxx-xxxx-xxx); the tab title is "Meet - <name or code>".

TraqulaBridge.start({
  site: "meet",

  inCall() {
    return this.tiles().length > 0 && this.micButton() !== null;
  },

  title() {
    const fromTab = document.title.replace(/^Meet\s*[-–—]\s*/, "").trim();
    const code = (location.pathname.match(/[a-z]{3}-[a-z]{4}-[a-z]{3}/) || [])[0] || null;
    return fromTab && fromTab !== "Meet" ? fromTab : code;
  },

  micButton() {
    return (
      Array.from(document.querySelectorAll("button[data-is-muted]")).find((button) =>
        /^mic(_off)?$/.test(TraqulaBridge.text(button))
      ) || null
    );
  },

  muted() {
    const button = this.micButton();
    return button ? button.getAttribute("data-is-muted") === "true" : null;
  },

  tiles() {
    return Array.from(document.querySelectorAll("[data-participant-id]"));
  },

  nameOf(tile) {
    const name = tile.querySelector("span.notranslate");
    return name ? TraqulaBridge.text(name) || null : null;
  },

  isSelf(tile) {
    return Array.from(tile.querySelectorAll("i")).some((icon) => TraqulaBridge.text(icon) === "visual_effects");
  },

  isSpeaking(tile) {
    return Array.from(tile.querySelectorAll('[jsname="QgSmzd"]')).some(
      (indicator) =>
        (indicator.children.length > 0 && TraqulaBridge.isVisible(indicator)) || indicator.classList.contains("sxlEM")
    );
  },

  speaker() {
    const speaking = this.tiles().find((tile) => !this.isSelf(tile) && this.isSpeaking(tile));
    return speaking ? this.nameOf(speaking) : null;
  },

  participants() {
    return Array.from(new Set(this.tiles().map((tile) => this.nameOf(tile)).filter(Boolean)));
  },

  me() {
    const self = this.tiles().find((tile) => this.isSelf(tile));
    return self ? this.nameOf(self) : null;
  },
});
