/* Site config — set appStoreUrl before publish */
window.XBrowserSite = {
  appStoreUrl: "https://apps.apple.com/us/app/id6804914972?l=en-us",
  /** Public-facing support address (domain identity for trust / EEAT). */
  contactEmailDisplay: "support@xxxxxbrowser.cc",
  /** Actual mailbox that receives mail (until domain inbox is fully cut over). */
  contactEmailMailto: "gaowei85714@gmail.com",
};

(function () {
  const cfg = window.XBrowserSite;

  document.querySelectorAll("[data-app-store]").forEach((el) => {
    if (cfg.appStoreUrl && cfg.appStoreUrl !== "#") {
      el.setAttribute("href", cfg.appStoreUrl);
      el.removeAttribute("aria-disabled");
      const coming = el.querySelector("[data-coming-soon]");
      if (coming) coming.hidden = true;
    } else {
      el.setAttribute("href", "#download");
      el.addEventListener("click", (e) => {
        e.preventDefault();
        const target = document.getElementById("download");
        if (target) target.scrollIntoView({ behavior: "smooth" });
      });
    }
  });

  document.querySelectorAll("[data-contact-email]").forEach((el) => {
    el.textContent = cfg.contactEmailDisplay;
    if (el.tagName === "A") {
      el.setAttribute("href", "mailto:" + cfg.contactEmailMailto);
    }
  });

  const hero = document.querySelector(".hero__content");
  if (hero) {
    requestAnimationFrame(() => hero.classList.add("is-ready"));
  }

  const observeReveal = (nodes) => {
    if (!nodes.length) return;
    if (!("IntersectionObserver" in window)) {
      nodes.forEach((n) => n.classList.add("is-visible"));
      return;
    }
    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add("is-visible");
            io.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.22 }
    );
    nodes.forEach((n) => io.observe(n));
  };

  observeReveal(document.querySelectorAll(".feature"));
  observeReveal(
    document.querySelectorAll(
      ".step, .how-demo, .honest-note, .download .reveal-on-scroll, .quote, .blog-item, .price-card"
    )
  );

  /* Space chip demo: one <img>, swap src only (never stack two images). */
  const startSpaceDemos = () => {
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduce) return;
    document.querySelectorAll(".space-demo-img[data-space-frames]").forEach((img) => {
      const frames = img
        .getAttribute("data-space-frames")
        .split(",")
        .map((s) => s.trim())
        .filter(Boolean);
      if (frames.length < 2) return;
      const chipNames = (img.getAttribute("data-space-chips") || "")
        .split(",")
        .map((s) => s.trim())
        .filter(Boolean);
      const chipRoot = img.closest(".how-demo");
      let i = Math.max(0, frames.indexOf(img.getAttribute("src")));
      if (i < 0) i = 0;
      img.src = frames[i];
      window.setInterval(() => {
        i = (i + 1) % frames.length;
        img.src = frames[i];
        if (chipRoot && chipNames.length) {
          chipRoot.querySelectorAll(".how-demo__chip").forEach((chip) => {
            chip.classList.toggle(
              "is-active",
              chip.getAttribute("data-chip") === chipNames[i]
            );
          });
        }
      }, 1600);
    });
  };
  startSpaceDemos();
})();
