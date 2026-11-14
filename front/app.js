import { API_URL } from "./config.js";
import { api } from "./api.js";

const $ = (selector, root = document) => root.querySelector(selector);

$("#docs-link").href = API_URL;

const dateFormat = new Intl.DateTimeFormat("fr-FR", { dateStyle: "long" });
const formatDate = (iso) => dateFormat.format(new Date(iso));

// Construit un élément sans jamais passer par innerHTML : les données de
// l'API (titres, noms) sont insérées comme du texte.
function el(tag, props = {}, ...children) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(props)) {
    if (key === "class") node.className = value;
    else if (key.startsWith("on")) node.addEventListener(key.slice(2), value);
    else node.setAttribute(key, value);
  }
  node.append(...children);
  return node;
}

function button(label, onClick, className = "") {
  return el("button", { type: "button", class: className, onclick: onClick }, label);
}

function toast(message, isError = false) {
  const node = el("p", { class: isError ? "toast error" : "toast" }, message);
  $("#toasts").append(node);
  setTimeout(() => node.remove(), 5000);
}

// Exécute une action déclenchée par un bouton et affiche l'erreur de l'API.
async function run(action) {
  try {
    await action();
  } catch (error) {
    toast(error.message, true);
  }
}

function showFormError(dialog, error) {
  const target = $(".form-error", dialog);
  target.textContent = error ? error.message : "";
  target.hidden = !error;
}

for (const cancel of document.querySelectorAll("[data-cancel]")) {
  cancel.addEventListener("click", () => cancel.closest("dialog").close());
}

// Branche un formulaire de boîte de dialogue sur un appel à l'API.
// L'erreur renvoyée par l'API reste affichée dans la boîte, qui ne se ferme
// qu'en cas de succès.
// handler = fonction qui sera appelé à l'envoi du formulaire (créer/modifier)
function bindSubmit(dialog, form, handler) {
  form.addEventListener("submit", async (event) => {
    // empêche le navigateur de recharger la page
    event.preventDefault();
    // efface les erreurs 
    showFormError(dialog, null);

    try {
      // new FormData(form) : récupère les données
      // transmission à handler
      await handler(new FormData(form));
      // si ok , femeture de la boite de dialog
      dialog.close();
      // actualisation de la liste des jeux
      await refresh();
      // sinon erreur transmise à la boite de dialogue
    } catch (error) {
      showFormError(dialog, error);
    }
  });
}

// --- Onglets ---------------------------------------------------------------

const tabs = ["games", "members"];

function currentTab() {
  const name = location.hash.slice(1);
  return tabs.includes(name) ? name : "games";
}

async function refresh() {
  const tab = currentTab();
  for (const name of tabs) {
    $(`#${name}`).hidden = name !== tab;
    $(`[data-tab="${name}"]`).toggleAttribute("aria-current", name === tab);
  }
  await run(tab === "games" ? loadGames : loadMembers);
}

window.addEventListener("hashchange", refresh);

// --- Jeux ------------------------------------------------------------------

async function loadGames() {
  // demande tous les jeux au serveur
  const games = await api.listGames();
  // vérification si games est vide == .hidden
  $("#games-empty").hidden = games.length > 0;
  // si des objets sont présent == création d'une gameCard / objet
  $("#games-list").replaceChildren(...games.map(gameCard));
}

function gameCard(game) {
  // affiche le nbr de joueurs
  const players =
    game.minPlayers === game.maxPlayers ? `${game.minPlayers}` : `${game.minPlayers} à ${game.maxPlayers}`;

    // affiche le statut du jeu
  const status = game.isAvailable
    ? el("span", { class: "badge ok" }, "Disponible")
    : el("span", { class: "badge busy" }, "Emprunté");

  // zone boutons
  // function button(label, onClick, className = "") -> ligne 24
  // () => : action lors du clik
  const actions = el("div", { class: "actions" });

  // bouton emprunter
  if (game.isAvailable) {
    actions.append(button("Emprunter", () => openBorrowDialog(game), "primary"));
  }

  // bouton modifier
  actions.append(button("Modifier", () => openEditDialog(game)));

  // bouton supprimer
  actions.append(button("Supprimer", () => openDeleteDialog(game), "danger"));

  // construction carte
  return el(
    "li",
    { class: "card" },
    el("div", { class: "card-head" }, el("h3", {}, game.title), status),
    el("p", { class: "meta" }, `${players} joueur·ses · ${game.durationMinutes} min`),
    actions,
  );
}

// fenêtre
const gameDialog = $("#game-dialog");
// formulaire
const gameForm = $("#game-form");
// mode ajout (null) OU modification (objet)
let editingGame = null;

// formulaire de modification
function openEditDialog(game) {

  // mode modification 
  editingGame = game;

  // h2
  // gameForm : id du formulaire
  $("h2", gameForm).textContent = "Modifier un jeu";

  // titre div
  gameForm.elements.title.value = game.title;

  // input minPlayer
  gameForm.elements.minPlayers.value = game.minPlayers;

  // input maxPlayer
  gameForm.elements.maxPlayers.value = game.maxPlayers;

  // input durationMinute
  gameForm.elements.durationMinutes.value = game.durationMinutes;

  // effacer les anciennes erreurs
  showFormError(gameDialog, null);

  // ouvrir le formulaire de modification
  gameDialog.showModal();
}

// modifier le formulaire d'ajout
$("#add-game").addEventListener("click", () => {

  // mode ajout
  editingGame = null;

  // vider les champs
  gameForm.reset();

  // remet le bon titre
  $("h2", gameForm).textContent = "Ajouter un jeu";

  // effacer les anciennes erreurs
  showFormError(gameDialog, null);

  // ouvrir le formulaire d'ajout
  gameDialog.showModal();
});

bindSubmit(gameDialog, gameForm, (data) => {
  const game = {
    title: data.get("title").trim(),
    minPlayers: Number(data.get("minPlayers")),
    maxPlayers: Number(data.get("maxPlayers")),
    durationMinutes: Number(data.get("durationMinutes")),
  };

  // si editingGame contient un jeu -> modification.
  if (editingGame) {
    return api.updateGame(editingGame.id, game);
  }

  // Sinon -> création
  return api.createGame(game);
});

// fenêtre de confirmation
const deleteGameDialog = $("#delete-game-dialog");

// texte de confirmation
const deleteGameMessage = $("#delete-game-message");

// bouton supprimer
const confirmDeleteButton = $("#confirm-delete-game")

// jeu en cours de supression
let deletingGame = null;

// dialog de suppression
function openDeleteDialog(game) {

  // jeu à supprimer
  deletingGame = game;

  // confirmation
  deleteGameMessage.textContent =
    `Voulez-vous vraiment supprimer le jeu « ${game.title} » ?`;

  // effacer les anciennes erreurs
  showFormError(deleteGameDialog, null);

  // Ouvrir le formulaire de supression
  deleteGameDialog.showModal();
}

// clik sur le bouton confirmer
confirmDeleteButton.addEventListener("click", async () => {

  // aucun jeu selectionné , arret
  if (!deletingGame) return;

  // desactivation du btn (1 demande)
  confirmDeleteButton.disabled = true;

  // efface les msg d'erreurs
  showFormError(deleteGameDialog, null);

  try {

    // appel API pour supprimer le jeu
    await api.deleteGame(deletingGame.id);

    // si refus de l'API
  } catch (error) {

    // affiche l'erreur sans fermer la fenêtre
    showFormError(deleteGameDialog, error);
    confirmDeleteButton.disabled = false;
    return;
  }

  // si la suppression réussi
  deleteGameDialog.close();
  deletingGame = null;
  confirmDeleteButton.disabled = false;

  // message pour l'utilisateur
  toast("Le jeu a bien été supprimé")

  // actualise la liste
  await refresh();

});

// --- Emprunts --------------------------------------------------------------

const borrowDialog = $("#borrow-dialog");
const borrowForm = $("#borrow-form");
let borrowedGame = null;

async function openBorrowDialog(game) {
  await run(async () => {
    const members = await api.listMembers();
    if (members.length === 0) {
      toast("Ajoutez d'abord un·e adhérent·e pour pouvoir emprunter.", true);
      return;
    }
    borrowedGame = game;
    $("#borrow-dialog-title").textContent = `Emprunter « ${game.title} »`;
    $("select", borrowForm).replaceChildren(
      ...members.map((member) => el("option", { value: member.id }, `${member.name} (${member.email})`)),
    );
    showFormError(borrowDialog, null);
    borrowDialog.showModal();
  });
}

bindSubmit(borrowDialog, borrowForm, async (data) => {
  const loan = await api.borrow(borrowedGame.id, data.get("memberID"));
  toast(`« ${borrowedGame.title} » emprunté, à rendre avant le ${formatDate(loan.dueAt)}.`);
});

// --- Adhérent·es -----------------------------------------------------------

// fenêtre de confirmation de suppression d'un membre
const deleteMemberDialog = $("#delete-member-dialog");
// texte
const deleteMemberMessage = $("#delete-member-message");
// bouton de confirmation
const confirmDeleteMemberButton = $("#confirm-delete-member");
// membre en cours de suppression (deletingMember.id)
let deletingMember = null;

// ouvre la fenêtre de confirmation de suppression
function openDeleteMemberDialog(member) {

  // objet pour la modification
  deletingMember = member;

  // message de confirmation
  deleteMemberMessage.textContent =
    `Voulez-vous vraiment supprimer l'adhérent·e « ${member.name} » ?`;

  // efface anciennes erreurs
  showFormError(deleteMemberDialog, null);

  // ouvre la fenêtre
  deleteMemberDialog.showModal();
}

// action lors du clic sur le bouton de confirmation
confirmDeleteMemberButton.addEventListener("click", async () => {
  // vérification : membre sélectionné sinon pas d'apel API
  if (!deletingMember) return;

  // désactive le bouton (1 seul clik)
  confirmDeleteMemberButton.disabled = true;

  // efface anciennes erreurs
  showFormError(deleteMemberDialog, null);

  try {

    // appel à l'API pour supprimer le membre
    await api.deleteMember(deletingMember.id);

    // si hitstorique d'empruns
  } catch (error) {

    // affiche l'erreur dans la fenêtre sans la fermer
    showFormError(deleteMemberDialog, error);

    // réactive le bouton pour permettre une nouvelle tentative
    confirmDeleteMemberButton.disabled = false;

    return;
  }

  // succès ? fermeture de la la fenêtre
  deleteMemberDialog.close();

  // membre éffacé
  deletingMember = null;

  // réactivation du bouton
  confirmDeleteMemberButton.disabled = false;

  // message utilisateur
  toast("L'adhérent·e a bien été supprimé·e.");

  // actualisation de la liste des membres
  await refresh();
});

async function loadMembers() {
  const members = await api.listMembers();
  $("#members-empty").hidden = members.length > 0;
  $("#members-list").replaceChildren(...members.map(memberRow));
}

// card member
function memberRow(member) {
  // div actions
  const actions = el("div", { class: "actions" });

  // bouttons
  actions.append(button("Modifier", () => openEditMemberDialog(member)));
  actions.append(button("Supprimer", () => openDeleteMemberDialog(member), "danger"));

  return el(
    "li",
    { class: "row" },
    el(
      "div",
      { class: "row-main" },
      el("p", {}, el("strong", {}, member.name)),
      el("p", { class: "meta" }, member.email),
    ),
    // div actions à l'interieur de li
    actions,
  );
}

const memberDialog = $("#member-dialog");
const memberForm = $("#member-form");
// null = ajouter
let editingMember = null;

// formulaire de modification
function openEditMemberDialog(member) {

  editingMember = member;

  // titre
  $("h2", memberForm).textContent = "Modifier un·e adhérent·e";

  // nom
  memberForm.elements.name.value = member.name;

  // email
  memberForm.elements.email.value = member.email;

  // efface anciennes erreurs
  showFormError(memberDialog, null);

  // ouvre la fenêtre
  memberDialog.showModal();
}

// adapter le bouton ajouter
$("#add-member").addEventListener("click", () => {
  // null = création
  editingMember = null;

  // vide les champs du formulaire
  memberForm.reset();

  // titre initial
  $("h2", memberForm).textContent = "Ajouter un·e adhérent·e";

  // efface anciennes erreurs
  showFormError(memberDialog, null);

  // ouvre la fenêtre
  memberDialog.showModal();
});

// bouton enregister : création ? modification ?
bindSubmit(memberDialog, memberForm, (data) => {

  // Récupération des données du formulaire
  const member = {
    name: data.get("name").trim(),
    email: data.get("email").trim(),
  };

  // Si modification
  if (editingMember) {
    return api.updateMember(editingMember.id, member);
  }

  // Sinon création 
  return api.createMember(member);
});

refresh();
