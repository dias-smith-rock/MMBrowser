/* Site config — replace before publish */
window.XBrowserSite = {
  appStoreUrl: "#",
  contactEmail: "support@goodcraft.app",
  companyName: "GoodCraft",
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

  const features = document.querySelectorAll(".feature");
  if (features.length && "IntersectionObserver" in window) {
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
    features.forEach((f) => io.observe(f));
  } else {
    features.forEach((f) => f.classList.add("is-visible"));
  }
})();
