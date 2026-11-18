(() => {
  const TOPIC_LABELS = {
    ai: "AI News",
    gov: "Gov News",
    police: "Police",
    "tech-law": "Tech Law",
  };

  const state = {
    topic: "all",
    range: "3",
    urgency: "all",
    query: "",
    items: [],
    meta: null,
  };

  const els = {
    syncStamp: document.getElementById("syncStamp"),
    totalCount: document.getElementById("totalCount"),
    overviewStrip: document.getElementById("overviewStrip"),
    cardGrid: document.getElementById("cardGrid"),
    emptyMsg: document.getElementById("emptyMsg"),
    resultCount: document.getElementById("resultCount"),
    rangeSelect: document.getElementById("rangeSelect"),
    urgencySelect: document.getElementById("urgencySelect"),
    searchInput: document.getElementById("searchInput"),
    detailDialog: document.getElementById("detailDialog"),
    detailTopic: document.getElementById("detailTopic"),
    detailTitle: document.getElementById("detailTitle"),
    detailMeta: document.getElementById("detailMeta"),
    detailBody: document.getElementById("detailBody"),
    detailLink: document.getElementById("detailLink"),
    policeTools: document.getElementById("policeTools"),
  };

  function escapeHtml(value) {
    return String(value ?? "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function parseDate(value) {
    if (!value) return null;
    const d = new Date(value);
    return Number.isNaN(d.getTime()) ? null : d;
  }

  function formatDate(value) {
    const d = parseDate(value);
    if (!d) return "—";
    return d.toLocaleDateString("th-TH", {
      year: "numeric",
      month: "short",
      day: "numeric",
    });
  }

  function excerpt(text, max = 180) {
    const clean = String(text || "")
      .replace(/<[^>]+>/g, " ")
      .replace(/\s+/g, " ")
      .trim();
    if (clean.length <= max) return clean;
    return `${clean.slice(0, max - 1)}…`;
  }

  function inRange(itemDate, range) {
    if (range === "all") return true;
    const d = parseDate(itemDate);
    if (!d) return true;
    const days = Number(range);
    const start = new Date();
    start.setHours(0, 0, 0, 0);
    start.setDate(start.getDate() - (days - 1));
    return d >= start;
  }

  async function loadFeed() {
    const res = await fetch(`data/feed.json?ts=${Date.now()}`, { cache: "no-store" });
    if (!res.ok) throw new Error(`feed.json HTTP ${res.status}`);
    return res.json();
  }

  function filteredItems() {
    const q = state.query.trim().toLowerCase();
    return state.items.filter((item) => {
      if (state.topic !== "all" && item.topic !== state.topic) return false;
      if (!inRange(item.date || item.published_at, state.range)) return false;
      if (state.urgency !== "all" && (item.urgency || "medium") !== state.urgency) return false;
      if (!q) return true;
      const hay = [
        item.title,
        item.summary,
        item.content,
        item.agency,
        item.source,
        ...(item.tags || []),
      ]
        .join(" ")
        .toLowerCase();
      return hay.includes(q);
    });
  }

  function renderOverview(items) {
    if (state.topic !== "all") {
      els.overviewStrip.hidden = true;
      els.overviewStrip.innerHTML = "";
      return;
    }
    const counts = { ai: 0, gov: 0, police: 0, "tech-law": 0 };
    for (const item of items) {
      if (counts[item.topic] != null) counts[item.topic] += 1;
    }
    els.overviewStrip.hidden = false;
    els.overviewStrip.innerHTML = Object.keys(TOPIC_LABELS)
      .map(
        (key) => `
        <button type="button" class="overview-card" data-topic="${key}">
          <strong>${counts[key]}</strong>
          <span>${TOPIC_LABELS[key]}</span>
        </button>`
      )
      .join("");
  }

  function renderCards(items) {
    els.resultCount.textContent = `${items.length} รายการ`;
    els.emptyMsg.hidden = items.length > 0;
    els.cardGrid.innerHTML = items
      .slice(0, 240)
      .map((item, index) => {
        const urgency = item.urgency || "medium";
        return `
        <button type="button" class="card" data-index="${index}" style="animation-delay:${Math.min(index, 12) * 30}ms">
          <div class="card-top">
            <span class="topic-chip" data-topic="${escapeHtml(item.topic)}">${escapeHtml(TOPIC_LABELS[item.topic] || item.topic)}</span>
            <span class="urgency" data-u="${escapeHtml(urgency)}">${escapeHtml(urgency.toUpperCase())}</span>
          </div>
          <h3>${escapeHtml(item.title)}</h3>
          <p>${escapeHtml(excerpt(item.summary || item.content))}</p>
          <div class="card-foot">
            <span>${escapeHtml(item.agency || item.source || "—")}</span>
            <span>${escapeHtml(formatDate(item.date || item.published_at))}</span>
          </div>
        </button>`;
      })
      .join("");
  }

  function openDetail(item) {
    els.detailTopic.textContent = TOPIC_LABELS[item.topic] || item.topic;
    els.detailTitle.textContent = item.title || "";
    els.detailMeta.textContent = [
      item.agency || item.source || null,
      formatDate(item.date || item.published_at),
      item.urgency ? `urgency: ${item.urgency}` : null,
    ]
      .filter(Boolean)
      .join(" · ");

    const body = item.content_html || item.content || item.summary || "";
    if (item.content_html) {
      els.detailBody.innerHTML = body;
    } else {
      els.detailBody.textContent = body;
    }

    if (item.source_url) {
      els.detailLink.innerHTML = `<a href="${escapeHtml(item.source_url)}" target="_blank" rel="noopener">เปิดแหล่งข่าว</a>`;
    } else {
      els.detailLink.innerHTML = "";
    }
    els.detailDialog.showModal();
  }

  function paint() {
    const items = filteredItems();
    if (els.policeTools) els.policeTools.hidden = state.topic !== "police";
    renderOverview(items);
    renderCards(items);
  }

  function bind() {
    document.querySelectorAll(".topic-tab").forEach((btn) => {
      btn.addEventListener("click", () => {
        document.querySelectorAll(".topic-tab").forEach((b) => b.classList.toggle("is-active", b === btn));
        state.topic = btn.dataset.topic;
        paint();
      });
    });

    els.overviewStrip.addEventListener("click", (event) => {
      const card = event.target.closest(".overview-card");
      if (!card) return;
      state.topic = card.dataset.topic;
      document.querySelectorAll(".topic-tab").forEach((b) => {
        b.classList.toggle("is-active", b.dataset.topic === state.topic);
      });
      paint();
    });

    els.rangeSelect.addEventListener("change", () => {
      state.range = els.rangeSelect.value;
      paint();
    });
    els.urgencySelect.addEventListener("change", () => {
      state.urgency = els.urgencySelect.value;
      paint();
    });
    els.searchInput.addEventListener("input", () => {
      state.query = els.searchInput.value;
      paint();
    });

    els.cardGrid.addEventListener("click", (event) => {
      const card = event.target.closest(".card");
      if (!card) return;
      const items = filteredItems();
      const item = items[Number(card.dataset.index)];
      if (item) openDetail(item);
    });
  }

  async function boot() {
    bind();
    try {
      const feed = await loadFeed();
      state.meta = feed.meta || {};
      state.items = Array.isArray(feed.items) ? feed.items : [];
      els.syncStamp.textContent = state.meta.synced_at
        ? `ซิงก์ ${formatDate(state.meta.synced_at)}`
        : "พร้อมใช้งาน";
      els.totalCount.textContent = `${state.items.length} ข่าว`;
      paint();
    } catch (err) {
      els.syncStamp.textContent = "โหลดไม่สำเร็จ";
      els.emptyMsg.hidden = false;
      els.emptyMsg.textContent = `โหลด feed ไม่ได้: ${err.message}`;
    }
  }

  boot();
})();
