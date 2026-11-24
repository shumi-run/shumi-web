const filters = [
  { id: "all", label: "All hosts" },
  { id: "local", label: "Local", kind: "host" },
  { id: "web", label: "shumi-web", kind: "project" },
  { id: "build", label: "Build server", kind: "host", remote: true },
  { id: "release", label: "release-tools", kind: "project" },
];

const sessions = [
  {
    id: "search", title: "Fix search tests", provider: "Codex", status: "Working", tone: "working",
    host: "local", project: "web", branch: "main",
    prompt: "Add a regression test for search when a project has no sessions.",
    reply: "I reproduced the empty-project case. I’m adding a regression test for the empty result view.",
  },
  {
    id: "review", title: "Review release", provider: "Codex", status: "Needs input", tone: "input",
    host: "build", project: "release", branch: "release-notes",
    prompt: "Check the release notes against the changes in the archive.",
    reply: "The archive matches the notes. Should the installation section include a separate example for macOS?",
  },
  {
    id: "docs", title: "Update install docs", provider: "Claude Code", status: "Unread", tone: "unread",
    host: "local", project: "web", branch: "docs/install",
    prompt: "Clarify where the plugins directory belongs after extraction.",
    reply: "I updated the install guide to show the executable and plugins directory side by side.",
  },
  {
    id: "archive", title: "Check archive contents", provider: "Claude Code", status: "Ready", tone: "ready",
    host: "build", project: "release", branch: "main",
    prompt: "List the files we expect in the release archive.",
    reply: "The archive should include the shumi-tui executable, license notices, and the bundled plugins directory.",
  },
];

const demo = document.querySelector("#demo");
const hosts = document.querySelector("#host-list");
const sessionList = document.querySelector("#session-list");
const count = document.querySelector("#session-count");
const conversation = document.querySelector("#conversation");
const inbox = document.querySelector("#inbox-dialog");
const inboxList = document.querySelector("#inbox-list");
const help = document.querySelector("#help-dialog");

let activeSession = sessions[0].id;

function element(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function row(id, className) {
  const button = element("button", `list-row ${className}`);
  button.type = "button";
  button.dataset.id = id;
  return button;
}

function statusLabel(session) {
  return element("span", `status status-${session.tone}`, session.status);
}

function sessionRow(session) {
  const button = row(session.id, "session-row");
  const meta = element("span", "session-meta");
  meta.append(statusLabel(session), element("span", "provider", session.provider));
  button.append(element("span", "row-title", session.title), meta);
  return button;
}

function filterRow(filter) {
  const button = row(filter.id, `filter-row filter-${filter.kind || "all"}`);
  const icon = element("span", "filter-icon", filter.kind === "project" ? "└" : "▦");
  icon.setAttribute("aria-hidden", "true");
  button.append(icon, element("span", "", filter.label));
  if (filter.remote) button.append(element("span", "ssh-tag", "SSH"));
  return button;
}

function setSelection(list, activeId) {
  for (const button of list.querySelectorAll("button[data-id]")) {
    const selected = button.dataset.id === activeId;
    button.setAttribute("aria-pressed", String(selected));
    button.tabIndex = selected ? 0 : -1;
  }
}

function label(id) {
  return filters.find(filter => filter.id === id).label;
}

function message(author, text) {
  const block = element("div", "message");
  block.append(element("p", "message-author", author), element("p", "", text));
  return block;
}

function selectSession(id) {
  activeSession = id;
  setSelection(sessionList, id);

  const session = sessions.find(item => item.id === id);
  const header = element("div", "conversation-header");
  const meta = element("div", "conversation-meta");
  meta.append(statusLabel(session), element("span", "provider", session.provider));
  header.append(
    element("h4", "", session.title),
    element("p", "", `${label(session.host)} / ${label(session.project)} · ${session.branch}`),
    meta,
  );

  const messages = element("div", "messages");
  messages.append(message("You", session.prompt), message(session.provider, session.reply));
  conversation.replaceChildren(header, messages);
}

function selectFilter(id, preferredSession = activeSession) {
  setSelection(hosts, id);

  const visible = sessions.filter(session => id === "all" || session.host === id || session.project === id);
  sessionList.replaceChildren(...visible.map(sessionRow));
  count.textContent = visible.length;
  selectSession(visible.find(session => session.id === preferredSession)?.id ?? visible[0].id);
}

function wireList(list, select, activateOnMove = true) {
  function getRow(event) {
    const button = event.target.closest("button[data-id]");
    return button?.parentElement === list ? button : null;
  }

  list.addEventListener("click", event => {
    const button = getRow(event);
    if (button) select(button.dataset.id);
  });

  list.addEventListener("keydown", event => {
    const directions = { ArrowDown: 1, ArrowUp: -1, j: 1, k: -1 };
    const direction = directions[event.key];
    const button = getRow(event);
    if (!button || !direction || event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return;

    event.preventDefault();
    const rows = [...list.querySelectorAll("button[data-id]")];
    const index = Math.max(0, Math.min(rows.length - 1, rows.indexOf(button) + direction));
    const next = rows[index];
    if (next === button) return;
    if (activateOnMove) select(next.dataset.id);
    next.focus();
  });
}

hosts.replaceChildren(...filters.map(filterRow));
selectFilter("all");
wireList(hosts, selectFilter);
wireList(sessionList, selectSession);

inboxList.replaceChildren(...sessions.filter(session => ["input", "unread"].includes(session.tone)).map(sessionRow));
wireList(inboxList, id => {
  inbox.close();
  selectFilter("all", id);
  sessionList.querySelector('[aria-pressed="true"]').focus();
}, false);

const openInbox = document.querySelector("#open-inbox");
const openHelp = document.querySelector("#open-help");
openInbox.addEventListener("click", () => inbox.showModal());
openHelp.addEventListener("click", () => help.showModal());

demo.addEventListener("keydown", event => {
  if (event.altKey || event.ctrlKey || event.metaKey || event.repeat) return;
  if (event.key === "?") {
    event.preventDefault();
    help.showModal();
  }
  if (event.key.toLowerCase() === "i") {
    event.preventDefault();
    inbox.showModal();
  }
});

document.querySelector("#demo-actions").hidden = false;
document.querySelector("#keyboard-hints").hidden = false;

const copy = document.querySelector("#copy-command");
const command = document.querySelector("#install-command");
const feedback = document.querySelector("#copy-feedback");
copy.hidden = false;

copy.addEventListener("click", async () => {
  feedback.textContent = "";
  feedback.classList.add("sr-only");
  try {
    await navigator.clipboard.writeText(command.textContent);
    copy.textContent = "Copied";
    feedback.textContent = "Install command copied.";
  } catch {
    const range = document.createRange();
    range.selectNodeContents(command);
    const selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
    copy.textContent = "Selected";
    feedback.classList.remove("sr-only");
    feedback.textContent = "Command selected. Use your usual copy shortcut.";
  }
});
