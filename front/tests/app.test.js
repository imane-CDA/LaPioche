import { assertEqual, assertIncludes, assertTrue, test, waitFor } from "./runner.js";
import { mountApp } from "./helpers.js";

const catan = { id: "g1", title: "Catan", minPlayers: 3, maxPlayers: 4, durationMinutes: 90, isAvailable: true };
const dixit = { id: "g2", title: "Dixit", minPlayers: 3, maxPlayers: 6, durationMinutes: 30, isAvailable: false, activeLoanID: "l2" };
const camille = { id: "m1", name: "Camille", email: "camille@example.com" };

const cardOf = (app, title) => app.$$("#games-list .card").find((card) => card.querySelector("h3").textContent === title);

// --- Jeux

test("games list shows one card per game with its availability", async () => {
  const app = await mountApp({ "GET /games": [catan, dixit] });
  await waitFor(() => app.$$("#games-list .card").length === 2, "deux cartes de jeu");
  assertIncludes(cardOf(app, "Catan").textContent, "Disponible");
  assertIncludes(cardOf(app, "Dixit").textContent, "Emprunté");
  assertIncludes(cardOf(app, "Catan").textContent, "3 à 4 joueur·ses · 90 min");
});

test("available games offer Borrow and borrowed games offer Return", async () => {
  const app = await mountApp({ "GET /games": [catan, dixit] });

  await waitFor(() => app.$$("#games-list .card").length === 2);

  const labels = (title) =>
    [...cardOf(app, title).querySelectorAll("button")].map((button) =>
      button.textContent.trim()
    );

  assertTrue(
    labels("Catan").includes("Emprunter"),
    "Catan devrait proposer Emprunter"
  );

  assertTrue(
    labels("Dixit").includes("Rendre"),
    "Dixit devrait proposer Rendre"
  );

  assertTrue(
    !labels("Dixit").includes("Emprunter"),
    "Dixit ne devrait pas proposer Emprunter"
  );
});

test("returning a borrowed game calls the API and makes it available again", async () => {
  let returned = false;

  const app = await mountApp({
    "GET /games": () =>
      returned
        ? [{ ...dixit, isAvailable: true, activeLoanID: null }]
        : [dixit],

    "POST /loans/l2/return": () => {
      returned = true;
      return [
        200,
        {
          id: "l2",
          gameID: "g2",
          memberID: "m1",
          borrowedAt: new Date().toISOString(),
          dueAt: new Date().toISOString(),
          returnedAt: new Date().toISOString(),
        },
      ];
    },
  });

  await waitFor(
    () => app.$$("#games-list .card").length === 1,
    "la carte de Dixit"
  );

  app.click("Rendre", cardOf(app, "Dixit"));

  await waitFor(
    () => app.calls.some(
      (call) => call.method === "POST" && call.path === "/loans/l2/return"
    ),
    "l'appel POST de retour"
  );

  await waitFor(
    () => app.$("#toasts").textContent.includes("bien été rendu"),
    "le message de confirmation"
  );

  await waitFor(
    () => cardOf(app, "Dixit").textContent.includes("Disponible"),
    "le jeu redevenu disponible"
  );

  assertTrue(
    [...cardOf(app, "Dixit").querySelectorAll("button")]
      .some((button) => button.textContent.trim() === "Emprunter"),
    "Dixit devrait proposer Emprunter après son retour"
  );
});

test("returning an already returned loan displays a French error", async () => {
  const app = await mountApp({
    "GET /games": [dixit],
    "POST /loans/l2/return": [
      409,
      {
        error: true,
        reason: "Loan has already been returned",
      },
    ],
  });

  await waitFor(() => app.$$("#games-list .card").length === 1);
  app.click("Rendre", cardOf(app, "Dixit"));

  await waitFor(
    () => app.$("#toasts").textContent.includes("Cet emprunt a déjà été rendu."),
    "le message d'erreur en français"
  );
});

test("with no game, a message invites to add one", async () => {
  const app = await mountApp({ "GET /games": [] });
  await waitFor(() => !app.$("#games-empty").hidden);
  assertIncludes(app.$("#games-empty").textContent, "ne contient aucun jeu");
  assertIncludes(app.$("#games-empty").textContent, "Ajouter un jeu");
});

test("adding a game posts the form then reloads the list", async () => {
  const app = await mountApp({ "GET /games": [catan], "POST /games": [201, { ...catan, id: "g3", title: "Dixit" }] });
  await waitFor(() => app.$$("#games-list .card").length === 1);
  app.click("Ajouter un jeu");
  const form = app.$("#game-form");
  form.elements.title.value = "  Dixit ";
  form.elements.minPlayers.value = "3";
  form.elements.maxPlayers.value = "6";
  form.elements.durationMinutes.value = "30";
  form.requestSubmit();
  await waitFor(() => app.calls.some((call) => call.method === "POST" && call.path === "/games"), "l'appel POST /games");
  assertEqual(app.calls.find((call) => call.method === "POST").body, {
    title: "Dixit",
    minPlayers: 3,
    maxPlayers: 6,
    durationMinutes: 30,
  });
  await waitFor(() => !app.$("#game-dialog").open, "la boîte se ferme");
});

// modification d'un jeu
test("editing a game sends a PUT request and reloads the list", async () => {
  let games = [catan];
  const updatedGame = {
    ...catan,
    title: "Catan modifié",
  };
  const app = await mountApp({
    "GET /games": () => games,
    "PUT /games/g1": () => {
      games = [updatedGame];
      return [200, updatedGame];
    },
  });
  await waitFor(() => app.$$("#games-list .card").length === 1);
  app.click("Modifier", cardOf(app, "Catan"));
  const form = app.$("#game-form");
  assertEqual(form.elements.title.value, "Catan");
  form.elements.title.value = "Catan modifié";
  form.requestSubmit();
  await waitFor(
    () => app.calls.some(
      (call) => call.method === "PUT" && call.path === "/games/g1"
    ),
    "l'appel PUT /games/g1"
  );
  await waitFor(() => !app.$("#game-dialog").open);
  await waitFor(
    () => cardOf(app, "Catan modifié") !== undefined,
    "le jeu modifié dans la liste"
  );
});

// suppression réussie
test("deleting a game confirms the action and reloads the list", async () => {
  let games = [catan];
  const app = await mountApp({
    "GET /games": () => games,
    "DELETE /games/g1": () => {
      games = [];
      return [204];
    },
  });
  await waitFor(
    () => app.$$("#games-list .card").length === 1,
    "affichage de la carte du jeu",
  );
  const card = cardOf(app, "Catan");
  assertTrue(card !== undefined, "la carte Catan existe");
  const deleteButton = [...card.querySelectorAll("button")].find(
  button => button.textContent.trim() === "Supprimer"
);
assertTrue(
  deleteButton !== undefined,
  "le bouton Supprimer existe dans la carte Catan",
);
deleteButton.click();
await waitFor(
  () => app.$("#delete-game-dialog").open,
  "ouverture de la fenêtre de confirmation",
);
  assertIncludes(
    app.$("#delete-game-message").textContent,
    "Catan",
  );
  app.click("Supprimer", app.$("#delete-game-dialog"));
  await waitFor(
    () => app.calls.some(
      call => call.method === "DELETE" && call.path === "/games/g1"
    ),
    "envoi de la requête DELETE",
  );
  await waitFor(
    () => !app.$("#delete-game-dialog").open,
    "fermeture de la fenêtre de confirmation",
  );
  await waitFor(
    () => app.$("#games-empty").hidden === false,
    "affichage du message indiquant qu'il n'y a plus de jeux",
  );
});

test("a validation error is shown in French and the dialog stays open", async () => {
  const app = await mountApp({
    "GET /games": [],
    "POST /games": [400, { error: true, reason: "title is empty, durationMinutes is less than minimum of 1" }],
  });
  await waitFor(() => !app.$("#games-empty").hidden, "la page est chargée");
  app.click("Ajouter un jeu");
  app.$("#game-form").requestSubmit();
  await waitFor(() => !app.$("#game-dialog .form-error").hidden, "le message d'erreur");
  assertEqual(app.$("#game-dialog .form-error").textContent, "Le titre est obligatoire. La durée doit être d'au moins 1.");
  assertTrue(app.$("#game-dialog").open, "la boîte devrait rester ouverte");
});

// refus de suppression
test("a deletion error is shown in French and the dialog stays open", async () => {
  const app = await mountApp({
    "GET /games": [dixit],

    "DELETE /games/g2": [
      409,
      {
        error: true,
        reason: "A game with loans cannot be deleted",
      },
    ],
  });
  await waitFor(() => app.$$("#games-list .card").length === 1);
  app.click("Supprimer", cardOf(app, "Dixit"));
  await waitFor(() => app.$("#delete-game-dialog").open);
  app.click("Supprimer", app.$("#delete-game-dialog"));
  await waitFor(
    () => !app.$("#delete-game-dialog .form-error").hidden,
    "le message d'erreur"
  );
  assertIncludes(
    app.$("#delete-game-dialog .form-error").textContent,
    "historique d'emprunts"
  );
  assertTrue(
    app.$("#delete-game-dialog").open,
    "la boîte de confirmation devrait rester ouverte"
  );
});

// --- Emprunts

test("borrowing a game sends the game and the chosen member", async () => {
  const app = await mountApp({
    "GET /games": [catan],
    "GET /members": [camille],
    "POST /loans": [201, { id: "l1", gameID: "g1", memberID: "m1", borrowedAt: new Date().toISOString(), dueAt: new Date().toISOString() }],
  });
  await waitFor(() => app.$$("#games-list .card").length === 1);
  app.click("Emprunter", cardOf(app, "Catan"));
  await waitFor(() => app.$("#borrow-dialog").open, "la boîte d'emprunt");
  app.$("#borrow-form").requestSubmit();
  await waitFor(() => app.calls.some((call) => call.method === "POST" && call.path === "/loans"), "l'appel POST /loans");
  assertEqual(app.calls.find((call) => call.path === "/loans").body, { gameID: "g1", memberID: "m1" });
  await waitFor(() => app.$("#toasts").textContent.includes("emprunté"), "le message de confirmation");
});

test("borrowing without any member explains that one must be added first", async () => {
  const app = await mountApp({ "GET /games": [catan], "GET /members": [] });
  await waitFor(() => app.$$("#games-list .card").length === 1);
  app.click("Emprunter", cardOf(app, "Catan"));
  await waitFor(() => app.$("#toasts").textContent.includes("Ajoutez d'abord"), "le message d'aide");
  assertTrue(!app.$("#borrow-dialog").open, "la boîte d'emprunt ne doit pas s'ouvrir");
});

// --- Adhérent·es

test("members tab lists the members", async () => {
  const app = await mountApp({ "GET /members": [camille] }, { hash: "#members" });
  await waitFor(() => app.$$("#members-list .row").length === 1);
  assertIncludes(app.$("#members-list .row").textContent, "Camille");
  assertIncludes(app.$("#members-list .row").textContent, "camille@example.com");
});

test("member loan history displays returned, active and overdue loans", async () => {
  const loans = [
    {
      id: "l1",
      gameTitle: "Catan",
      borrowedAt: "2026-01-01T10:00:00.000Z",
      dueAt: "2026-01-15T10:00:00.000Z",
      returnedAt: "2026-01-10T10:00:00.000Z",
    },
    {
      id: "l2",
      gameTitle: "Dixit",
      borrowedAt: "2026-11-01T10:00:00.000Z",
      dueAt: "2026-11-30T10:00:00.000Z",
      returnedAt: null,
    },
    {
      id: "l3",
      gameTitle: "Azul",
      borrowedAt: "2026-01-01T10:00:00.000Z",
      dueAt: "2026-01-15T10:00:00.000Z",
      returnedAt: null,
    },
  ];

  const app = await mountApp({
    "GET /members": [camille],
    "GET /members/m1/loans": loans,
  }, { hash: "#members" });

  await waitFor(() => app.$$("#members-list .row").length === 1);

  const historyButton = [...app.$$("#members-list button")]
    .find((button) => button.textContent === "Historique");

  assertTrue(historyButton, "The history button should exist");

  historyButton.click();

  await waitFor(() => app.$("#member-loans-dialog").open);

  await waitFor(() => app.$$("#member-loans-list .row").length === 3);

  const history = app.$("#member-loans-list").textContent;

  assertIncludes(history, "Catan");
  assertIncludes(history, "Dixit");
  assertIncludes(history, "Azul");
  assertIncludes(history, "Rendu");
  assertIncludes(history, "En cours");
  assertIncludes(history, "En retard");
});

test("member loan history displays an empty state when there are no loans", async () => {
  const app = await mountApp({
    "GET /members": [camille],
    "GET /members/m1/loans": [],
  }, { hash: "#members" });

  await waitFor(() => app.$$("#members-list .row").length === 1);

  const historyButton = [...app.$$("#members-list button")]
    .find((button) => button.textContent === "Historique");

  assertTrue(historyButton, "The history button should exist");

  historyButton.click();

  await waitFor(() => !app.$("#member-loans-dialog").open);
  await waitFor(() => app.$("#member-loans-empty").hidden);

  assertIncludes(
    app.$("#member-loans-empty").textContent,
    "aucun emprunt"
  );

  assertEqual(app.$$("#member-loans-list .row").length, 0);
});

test("a member loan history error is shown in French", async () => {
  const app = await mountApp(
    {
      "GET /members": [camille],
      "GET /members/m1/loans": [
        404,
        {
          error: true,
          reason: "Member not found",
        },
      ],
    },
    { hash: "#members" },
  );

  await waitFor(() => app.$$("#members-list .row").length === 1);

  const historyButton = [...app.$$("#members-list button")]
    .find((button) => button.textContent === "Historique");

  assertTrue(historyButton, "The history button should exist");

  historyButton.click();

  await waitFor(
    () => app.$$("#toasts > *").length > 0,
    "le message d'erreur",
  );

  assertIncludes(
    app.$("#toasts").textContent,
    "adhérent",
  );

  assertTrue(
    !app.$("#member-loans-dialog").open,
    "the history dialog should stay closed after an error",
  );
});

test("with no member, a message invites to add one", async () => {
  const app = await mountApp({ "GET /members": [] }, { hash: "#members" });
  await waitFor(() => !app.$("#members-empty").hidden);
  assertIncludes(app.$("#members-empty").textContent, "Ajouter un·e adhérent·e");
});

test("adding a member posts the form", async () => {
  const app = await mountApp({ "GET /members": [], "POST /members": [201, camille] }, { hash: "#members" });
  await waitFor(() => !app.$("#members-empty").hidden);
  app.click("Ajouter un·e adhérent·e");
  const form = app.$("#member-form");
  form.elements.name.value = " Camille ";
  form.elements.email.value = "camille@example.com";
  form.requestSubmit();
  await waitFor(() => app.calls.some((call) => call.method === "POST" && call.path === "/members"), "l'appel POST /members");
  assertEqual(app.calls.find((call) => call.method === "POST").body, { name: "Camille", email: "camille@example.com" });
});

test("an email already in use is shown in French", async () => {
  const app = await mountApp(
    { "GET /members": [], "POST /members": [409, { error: true, reason: "A member with this email already exists" }] },
    { hash: "#members" },
  );
  await waitFor(() => !app.$("#members-empty").hidden);
  app.click("Ajouter un·e adhérent·e");
  app.$("#member-form").requestSubmit();
  await waitFor(() => !app.$("#member-dialog .form-error").hidden, "le message d'erreur");
  assertIncludes(app.$("#member-dialog .form-error").textContent, "utilise déjà cette adresse e-mail");
});

// modification d'un membre
test("editing a member sends a PUT request and reloads the list", async () => {
  let members = [camille];
  const updatedMember = {
    ...camille,
    name: "Camille modifiée",
  };
  const app = await mountApp(
    {
      "GET /members": () => members,
      "PUT /members/m1": () => {
        members = [updatedMember];
        return [200, updatedMember];
      },
    },
    { hash: "#members" },
  );
  await waitFor(() => app.$$("#members-list .row").length === 1);
  app.click("Modifier", app.$("#members-list .row"));
  const form = app.$("#member-form");
  assertEqual(form.elements.name.value, "Camille");
  assertEqual(form.elements.email.value, "camille@example.com");
  form.elements.name.value = "Camille modifiée";
  form.requestSubmit();
  await waitFor(
    () => app.calls.some(
      (call) => call.method === "PUT" && call.path === "/members/m1"
    ),
    "l'appel PUT /members/m1",
  );
  await waitFor(() => !app.$("#member-dialog").open);
  await waitFor(
    () => app.$("#members-list").textContent.includes("Camille modifiée"),
    "le membre modifié dans la liste",
  );
});

// refus de modification
test("a member update error is shown in French and the form stays open", async () => {
  const app = await mountApp(
    {
      "GET /members": [camille],
      "PUT /members/m1": [
        409,
        {
          error: true,
          reason: "A member with this email already exists",
        },
      ],
    },
    { hash: "#members" },
  );
  await waitFor(() => app.$$("#members-list .row").length === 1);
  app.click("Modifier", app.$("#members-list .row"));
  const form = app.$("#member-form");
  form.elements.email.value = "autre@example.com";
  form.requestSubmit();
  await waitFor(
    () => !app.$("#member-dialog .form-error").hidden,
    "le message d'erreur",
  );
  assertIncludes(
    app.$("#member-dialog .form-error").textContent,
    "utilise déjà cette adresse e-mail",
  );
  assertTrue(
    app.$("#member-dialog").open,
    "le formulaire devrait rester ouvert",
  );
});

// supression réussie d'un membre
test("deleting a member confirms the action and reloads the list", async () => {
  let members = [camille];
  const app = await mountApp(
    {
      "GET /members": () => members,
      "DELETE /members/m1": () => {
        members = [];
        return [204];
      },
    },
    { hash: "#members" },
  );
  await waitFor(
    () => app.$$("#members-list .row").length === 1,
    "affichage du membre",
  );
  app.click("Supprimer", app.$("#members-list .row"));
  await waitFor(
    () => app.$("#delete-member-dialog").open,
    "ouverture de la fenêtre de confirmation",
  );
  assertIncludes(
    app.$("#delete-member-message").textContent,
    "Camille",
  );
  app.click("Supprimer", app.$("#delete-member-dialog"));
  await waitFor(
    () => app.calls.some(
      (call) => call.method === "DELETE" && call.path === "/members/m1"
    ),
    "l'appel DELETE /members/m1",
  );
  await waitFor(
    () => !app.$("#delete-member-dialog").open,
    "fermeture de la fenêtre de confirmation",
  );
  await waitFor(
    () => !app.$("#members-empty").hidden,
    "affichage du message indiquant qu'il n'y a plus de membres",
  );
});

// refus de suppression d'un membre
test("a member deletion error is shown in French and the dialog stays open", async () => {
  const app = await mountApp(
    {
      "GET /members": [camille],

      "DELETE /members/m1": [
        409,
        {
          error: true,
          reason: "A member with loans cannot be deleted",
        },
      ],
    },
    { hash: "#members" },
  );
  await waitFor(
    () => app.$$("#members-list .row").length === 1,
  );
  app.click("Supprimer", app.$("#members-list .row"));
  await waitFor(
    () => app.$("#delete-member-dialog").open,
  );
  app.click("Supprimer", app.$("#delete-member-dialog"));
  await waitFor(
    () => !app.$("#delete-member-dialog .form-error").hidden,
    "le message d'erreur",
  );
  assertIncludes(
    app.$("#delete-member-dialog .form-error").textContent,
    "historique d'emprunts",
  );
  assertTrue(
    app.$("#delete-member-dialog").open,
    "la fenêtre de confirmation devrait rester ouverte",
  );
});

// Emprunts en retard

test("overdue loans tab displays loans and overdue count", async () => {
  const loans = [
    {
      id: "l1",
      gameTitle: "Catan",
      memberName: "Camille",
      borrowedAt: "2026-10-20T10:00:00.000Z",
      dueAt: "2026-11-13T10:00:00.000Z",
    },
  ];

  const app = await mountApp(
    {
      "GET /loans/overdue": loans,
    },
    { hash: "#overdue" },
  );

  await waitFor(
    () => app.$$("#overdue-list .row").length === 1,
    "affichage de l'emprunt en retard",
  );

  const row = app.$("#overdue-list .row");

  assertIncludes(row.textContent, "Catan");
  assertIncludes(row.textContent, "Camille");
  assertIncludes(row.textContent, "À rendre depuis le");
  assertIncludes(row.textContent, "En retard de");

  assertEqual(
    app.$("#overdue-count").textContent,
    "1 emprunt en retard",
  );
});

test("overdue loans tab displays an empty state when there are no overdue loans", async () => {
  const app = await mountApp(
    {
      "GET /loans/overdue": [],
    },
    { hash: "#overdue" },
  );

  await waitFor(
    () => !app.$("#overdue-empty").hidden,
    "le message indiquant qu'il n'y a aucun retard",
  );

  assertIncludes(
    app.$("#overdue-empty").textContent,
    "Aucun emprunt en retard",
  );

  assertEqual(app.$$("#overdue-list .row").length, 0);
  assertEqual(app.$("#overdue-count").textContent, "0 emprunt en retard");
});

test("overdue loans API error is shown in French", async () => {
  const app = await mountApp(
    {
      "GET /loans/overdue": [
        500,
        { error: true, reason: "Internal Server Error" },
      ],
    },
    { hash: "#overdue" },
  );

  await waitFor(
    () =>
      app.$("#toasts").textContent.includes(
        "Le serveur a rencontré une erreur",
      ),
    "le message d'erreur en français",
  );

  assertEqual(app.$$("#overdue-list .row").length, 0);
});
