/**
 * Boot Police GraphRAG + chat + connect on news-to-business-site.
 * Single graph view only (no separate cyber graph tab).
 */
(() => {
  const els = {
    tabs: Array.from(document.querySelectorAll("[data-police-tab]")),
    viewBrain: document.getElementById("view-brain"),
    viewConnect: document.getElementById("view-connect"),
    status: document.getElementById("police-status"),
    title: document.querySelector("#view-brain h1"),
    kicker: document.querySelector("#view-brain .brain-kicker"),
    connectBase: document.getElementById("connect-public-base"),
    connectLlm: document.getElementById("connect-llm-url"),
    connectMcp: document.getElementById("connect-mcp-url"),
    connectStatus: document.getElementById("connect-status"),
    connectReply: document.getElementById("connect-llm-reply"),
  };

  function setStatus(text) {
    if (els.status) els.status.textContent = text;
  }

  function setTab(tab) {
    const isBrain = tab === "brain";
    const isConnect = tab === "connect";
    els.tabs.forEach((btn) => {
      btn.classList.toggle("is-active", btn.dataset.policeTab === tab);
    });
    if (els.viewBrain) els.viewBrain.hidden = !isBrain;
    if (els.viewConnect) els.viewConnect.hidden = !isConnect;
    document.body.classList.toggle("is-brain", isBrain);
    const main = document.getElementById("main");
    if (main) main.classList.toggle("main-brain", isBrain);
    if (isBrain) {
      if (els.title) els.title.textContent = "ข้อมูลกราฟ";
      if (els.kicker) els.kicker.textContent = "Obsidian → knowledge graph";
    }
  }

  async function showBrain() {
    setTab("brain");
    setStatus("กำลังโหลดข้อมูลกราฟ…");
    try {
      if (window.BrainGraph) {
        await window.BrainGraph.show({ crimeType: "", mode: "all" });
      }
      if (window.GraphRag) {
        window.GraphRag.setMode?.("all");
        window.GraphRag.setPosts?.([]);
      }
      setStatus("ข้อมูลกราฟ · GraphRAG พร้อมถาม");
    } catch (err) {
      setStatus(`โหลดกราฟไม่สำเร็จ: ${err.message || err}`);
    }
  }

  async function refreshConnectPanel() {
    if (!window.NewsConnect) return;
    const saved = window.NewsConnect.load();
    if (els.connectBase) els.connectBase.value = saved.publicBase || "";
    const ep = await window.NewsConnect.resolve();
    if (els.connectLlm) els.connectLlm.textContent = ep.llm || "—";
    if (els.connectMcp) els.connectMcp.textContent = ep.mcp || "—";
    if (els.connectStatus) {
      els.connectStatus.textContent = ep.ok
        ? `พร้อมใช้ · แหล่ง=${ep.source} · model=${ep.model || window.NewsConnect.model}`
        : ep.reason || "ยังไม่พร้อม";
    }
  }

  function bindConnect() {
    document.getElementById("connect-save")?.addEventListener("click", async () => {
      window.NewsConnect?.save({ publicBase: els.connectBase?.value || "" });
      await refreshConnectPanel();
      if (els.connectStatus) els.connectStatus.textContent += " · บันทึกแล้ว";
    });
    document.getElementById("connect-test")?.addEventListener("click", async () => {
      if (!window.NewsConnect) return;
      if (els.connectStatus) els.connectStatus.textContent = "กำลังทดสอบ MCP…";
      const result = await window.NewsConnect.testMcp();
      if (els.connectStatus) {
        els.connectStatus.textContent = result.ok
          ? `MCP ผ่าน · ${result.message || "ok"}`
          : `MCP ไม่ผ่าน · ${result.message || result.reason || "fail"}`;
      }
    });
    document.getElementById("connect-test-llm")?.addEventListener("click", async () => {
      if (!window.NewsConnect) return;
      if (els.connectStatus) els.connectStatus.textContent = "กำลังทดสอบ LLM…";
      if (els.connectReply) {
        els.connectReply.hidden = true;
        els.connectReply.textContent = "";
      }
      const result = await window.NewsConnect.testLlm();
      if (els.connectStatus) {
        els.connectStatus.textContent = result.ok
          ? `LLM ผ่าน · ${result.message || "ok"}`
          : `LLM ไม่ผ่าน · ${result.message || result.reason || "fail"}`;
      }
      if (result.ok && result.text && els.connectReply) {
        els.connectReply.hidden = false;
        els.connectReply.textContent = result.text;
      }
    });
  }

  function bindTabs() {
    els.tabs.forEach((btn) => {
      btn.addEventListener("click", async () => {
        const tab = btn.dataset.policeTab;
        if (tab === "connect") {
          setTab("connect");
          await refreshConnectPanel();
          setStatus("หน้าเชื่อมต่อ LLM / MCP");
          return;
        }
        await showBrain();
      });
    });
  }

  function tabFromHash() {
    const raw = (location.hash || "").replace(/^#\/?/, "").toLowerCase();
    if (raw.startsWith("connect")) return "connect";
    return "brain";
  }

  async function boot() {
    document.body.classList.add("is-brain");
    bindTabs();
    bindConnect();
    window.GraphRag?.bindAsk?.();
    const tab = tabFromHash();
    if (tab === "connect") {
      setTab("connect");
      await refreshConnectPanel();
      setStatus("หน้าเชื่อมต่อ LLM / MCP");
    } else {
      await showBrain();
      await refreshConnectPanel();
    }
    window.addEventListener("hashchange", () => {
      if (tabFromHash() === "connect") {
        setTab("connect");
        void refreshConnectPanel();
      } else {
        void showBrain();
      }
    });
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", () => void boot());
  else void boot();
})();
