const search = document.querySelector(".plugin-search");
const query = document.querySelector("#plugin-query");
const status = document.querySelector("#plugin-results");
const list = document.querySelector("#plugin-list");

function normalize(text) {
  return text.toLowerCase().replace(/['’]/g, "").replace(/[^\p{L}\p{N}]+/gu, " ").trim();
}

const plugins = Array.from(list.querySelectorAll("[data-plugin-id]"), (card) => ({
  card,
  text: normalize([
    card.dataset.pluginId,
    card.dataset.pluginAlias,
    card.querySelector("h2").textContent,
    card.querySelector("p").textContent,
  ].join(" ")),
}));

function filterPlugins() {
  const terms = normalize(query.value).split(" ");
  let count = 0;

  for (const plugin of plugins) {
    const matches = terms.every((term) => plugin.text.includes(term));
    plugin.card.hidden = !matches;
    if (matches) count += 1;
  }

  list.hidden = count === 0;
  status.textContent = count === 0
    ? "No matching plugins. Try another search."
    : count === 1 ? "1 plugin" : `${count} plugins`;
}

query.addEventListener("input", filterPlugins);
search.hidden = false;
filterPlugins();
