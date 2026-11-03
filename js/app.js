// Shared client for student pages. Student identity is a per-session token kept in
// localStorage; it is sent with every write and checked in the database functions.
(function () {
  const cfg = window.EDTECH_CONFIG;
  const sb = window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseKey);
  const KEY = "edtech-lab";

  const store = {
    get() { try { return JSON.parse(localStorage.getItem(KEY) || "{}"); } catch { return {}; } },
    set(patch) { try { localStorage.setItem(KEY, JSON.stringify({ ...store.get(), ...patch })); } catch {} },
    clear() { try { localStorage.removeItem(KEY); } catch {} },
  };

  async function rpc(fn, args) {
    const { data, error } = await sb.rpc(fn, args);
    if (error) throw new Error(error.message);
    return data;
  }

  const PHASE_TEXT = {
    lobby: "Waiting for the instructor to start.",
    defining: "Poll 1 is open: submit your definition of education technology.",
    reading: "Read your group's two studies. You may start rating when ready.",
    rating_pre: "Submit your ratings now. They lock when the instructor closes this step.",
    locked: "Ratings are locked. Watch the screen.",
    revealed: "Sources are revealed. Open each study to see who produced it.",
    rating_post: "Rate your two studies again, now that you know the sources.",
    standards_submit: "Propose one standard for credible evidence.",
    standards_sort: "The class is sorting proposed standards.",
    standards_vote: "Vote for up to five standards.",
    final: "Here are the five standards the class agreed on.",
    closed: "This session has ended.",
  };

  const DIRECTIONS = ["positive", "negative", "mixed", "null", "inconclusive"];

  function el(tag, attrs = {}, ...children) {
    const e = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs)) {
      if (k === "class") e.className = v;
      else if (k === "html") e.innerHTML = v;
      else if (k.startsWith("on")) e.addEventListener(k.slice(2), v);
      else e.setAttribute(k, v);
    }
    for (const c of children) if (c != null) e.append(c);
    return e;
  }

  function status(node, msg, ok) {
    node.textContent = msg; node.className = "status " + (ok ? "ok" : "err");
  }

  // Poll session state; call cb on every change of phase or flags.
  function watchSession(cb) {
    let last = "";
    async function tick() {
      const s = store.get();
      if (!s.join_code) return;
      try {
        const sess = await rpc("get_session", { p_join_code: s.join_code });
        const sig = JSON.stringify(sess);
        if (sig !== last) { last = sig; cb(sess); }
      } catch (e) { /* keep polling */ }
    }
    tick();
    return setInterval(tick, cfg.pollMs);
  }

  function bars(container, counts, keys, cls) {
    const max = Math.max(1, ...keys.map(k => counts[k] || 0));
    container.replaceChildren(...keys.map(k => el("div", { class: "bar" },
      el("span", { class: "label" }, String(k)),
      el("div", { class: "fill " + (cls || ""), style: `width:${(100 * (counts[k] || 0) / max).toFixed(0)}%` }),
      el("span", { class: "n" }, String(counts[k] || 0)))));
  }

  window.Lab = { sb, rpc, store, el, status, watchSession, bars, PHASE_TEXT, DIRECTIONS };
})();
