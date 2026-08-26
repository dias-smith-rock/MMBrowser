/* Site config — set appStoreUrl before publish */
window.XBrowserSite = {
  appStoreUrl: "https://apps.apple.com/us/app/id6804914972?l=en-us",
  contactEmail: "gaowei85714@gmail.com",
  companyName: "XBrowser",
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
    el.textContent = cfg.contactEmail;
    if (el.tagName === "A") {
      el.setAttribute("href", "mailto:" + cfg.contactEmail);
    }
  });

  document.querySelectorAll("[data-company]").forEach((el) => {
    el.textContent = cfg.companyName;
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
  observeReveal(document.querySelectorAll(".step, .honest-note, .download .reveal-on-scroll"));
})();
