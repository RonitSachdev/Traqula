// Shared by every site adapter: polls the adapter twice a second and reports the meeting state when it changes.
//
// An adapter is an object with:
//   site:         "meet" | "zoomweb" | "teams"
//   inCall():     true while the page shows a joined meeting
//   title():      meeting name or code, or null
//   muted():      true / false, or null when the microphone button cannot be found
//   speaker():    display name of the participant currently highlighted as speaking, or null
//   participants(): display names visible in the call
//   me():         the user's own display name, or null

const TraqulaBridge = {
  start(adapter) {
    let last = "";
    const tick = () => {
      let snapshot;
      try {
        const inCall = adapter.inCall();
        snapshot = {
          type: "snapshot",
          site: adapter.site,
          inCall,
          title: inCall ? adapter.title() : null,
          muted: inCall ? adapter.muted() : null,
          speaker: inCall ? adapter.speaker() : null,
          participants: inCall ? adapter.participants() : [],
          me: inCall ? adapter.me() : null,
        };
      } catch (error) {
        return;
      }
      const encoded = JSON.stringify(snapshot);
      if (encoded === last) return;
      last = encoded;
      chrome.runtime.sendMessage({ type: "snapshot", snapshot }).catch(() => {});
    };
    setInterval(tick, 500);
    tick();
  },

  // Helpers shared by adapters.
  text(element) {
    return element ? element.textContent.replace(/\s+/g, " ").trim() : "";
  },
  // True when the element takes up space and is not hidden by CSS.
  isVisible(element) {
    if (!element || element.offsetWidth === 0 || element.offsetHeight === 0) return false;
    const style = getComputedStyle(element);
    return style.visibility !== "hidden" && style.opacity !== "0";
  },
  // True when something inside the element is animating, which is how speaking indicators tend to be drawn.
  isAnimating(element) {
    return element.getAnimations({ subtree: true }).some((a) => a.playState === "running");
  },
};
