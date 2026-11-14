import { api, ApiError, translateError } from "../api.js";
import { assertEqual, assertIncludes, assertTrue, test } from "./runner.js";
import { fakeApi, withFakeFetch } from "./helpers.js";

// --- translateError : les messages de l'API deviennent des phrases en français

test("translateError translates a known message", () => {
  assertEqual(translateError(409, "Game is already on loan"), "Ce jeu est déjà emprunté : il faut d'abord le rendre.");
});

test("translateError translates each validation error separately", () => {
  const message = translateError(400, "title is empty, minPlayers is less than minimum of 1");
  assertEqual(message, "Le titre est obligatoire. Le nombre minimum de joueur·ses doit être d'au moins 1.");
});

test("translateError translates a missing field and an invalid email", () => {
  assertEqual(translateError(400, "name is required"), "Le nom est obligatoire.");
  assertIncludes(translateError(400, "email is not a valid email address"), "adresse e-mail n'est pas valide");
});

test("translateError never lets unknown English through", () => {
  assertEqual(translateError(409, "Something unexpected"), "Cette action est impossible dans l'état actuel des données.");
  assertEqual(translateError(500, "boom"), "Le serveur a rencontré une erreur. Réessayez dans un instant.");
  assertEqual(translateError(418, "teapot"), "Une erreur est survenue. Réessayez.");
});

// erreur Int et Bool
test("translateError translates invalid Int and Bool values", () => {
  assertEqual(
    translateError(400, "minPlayers is not an Int"),
    "Le nombre minimum de joueur·ses doit être un nombre entier."
  );
  assertEqual(
    translateError(400, "available is not a Bool"),
    "Le filtre de disponibilité doit valoir « oui » ou « non »."
  );
});

// --- requêtes envoyées à l'API

test("listGames calls GET /games", async () => {
  const { fetch, calls } = fakeApi({ "GET /games": [] });
  await withFakeFetch(fetch, () => api.listGames());
  assertEqual(`${calls[0].method} ${calls[0].path}`, "GET /games");
});

test("createGame sends a JSON POST", async () => {
  const { fetch, calls } = fakeApi({ "POST /games": [201, { id: "1" }] });
  const game = { title: "Catan", minPlayers: 3, maxPlayers: 4, durationMinutes: 90 };
  const created = await withFakeFetch(fetch, () => api.createGame(game));
  assertEqual(calls[0].method, "POST");
  assertEqual(calls[0].body, game);
  assertEqual(created.id, "1");
});

// test de modification
test("updateGame sends a JSON PUT", async () => {
  const { fetch, calls } = fakeApi({
    "PUT /games/g1": [200, { id: "g1", title: "Catan modifié" }],
  });

  const game = {
    title: "Catan modifié",
    minPlayers: 3,
    maxPlayers: 4,
    durationMinutes: 90,
  };

  const updated = await withFakeFetch(fetch, () =>
    api.updateGame("g1", game)
  );

  assertEqual(calls[0].method, "PUT");
  assertEqual(calls[0].path, "/games/g1");
  assertEqual(calls[0].body, game);
  assertEqual(updated.title, "Catan modifié");
});

// test de modification d'un membre
test("updateMember sends a JSON PUT", async () => {
  const { fetch, calls } = fakeApi({
    "PUT /members/m1": [200, {
      id: "m1",
      name: "Camille modifiée",
      email: "camille@example.com",
    }],
  });

  const member = {
    name: "Camille modifiée",
    email: "camille@example.com",
  };

  const updated = await withFakeFetch(fetch, () =>
    api.updateMember("m1", member)
  );

  assertEqual(calls[0].method, "PUT");
  assertEqual(calls[0].path, "/members/m1");
  assertEqual(calls[0].body, member);
  assertEqual(updated.name, "Camille modifiée");
});

// test de suppression d'un membre
test("deleteMember sends a DELETE request", async () => {
  const { fetch, calls } = fakeApi({
    "DELETE /members/m1": [204],
  });

  await withFakeFetch(fetch, () => api.deleteMember("m1"));

  assertEqual(calls[0].method, "DELETE");
  assertEqual(calls[0].path, "/members/m1");
});

// Tester l'erreur d'e-mail en doublon
test("updating a member with an existing email gives a French error", async () => {
  const { fetch } = fakeApi({
    "PUT /members/m1": [
      409,
      {
        error: true,
        reason: "A member with this email already exists",
      },
    ],
  });

  const member = {
    name: "Camille",
    email: "autre@example.com",
  };

  const error = await expectError(
    withFakeFetch(fetch, () => api.updateMember("m1", member))
  );

  assertTrue(error instanceof ApiError);
  assertEqual(error.status, 409);
  assertEqual(
    error.message,
    "Un·e autre adhérent·e utilise déjà cette adresse e-mail."
  );
});

// Tester la suppression interdite
test("deleting a member with loans gives a French error", async () => {
  const { fetch } = fakeApi({
    "DELETE /members/m1": [
      409,
      {
        error: true,
        reason: "A member with loans cannot be deleted",
      },
    ],
  });

  const error = await expectError(
    withFakeFetch(fetch, () => api.deleteMember("m1"))
  );

  assertTrue(error instanceof ApiError);
  assertEqual(error.status, 409);
  assertIncludes(error.message, "historique d'emprunts");
});

// test de suppression
test("deleteGame sends a DELETE request", async () => {
  const { fetch, calls } = fakeApi({
    "DELETE /games/g1": [204],
  });

  await withFakeFetch(fetch, () => api.deleteGame("g1"));

  assertEqual(calls[0].method, "DELETE");
  assertEqual(calls[0].path, "/games/g1");
});

test("borrow sends the game and the member", async () => {
  const { fetch, calls } = fakeApi({ "POST /loans": [201, { id: "l1" }] });
  await withFakeFetch(fetch, () => api.borrow("g1", "m1"));
  assertEqual(calls[0].body, { gameID: "g1", memberID: "m1" });
});

// --- erreurs

// Attend qu'une promesse échoue et renvoie l'erreur (échoue si elle réussit).
async function expectError(promise) {
  try {
    await promise;
  } catch (error) {
    return error;
  }
  throw new Error("une erreur était attendue");
}

test("an unreachable server gives a clear message", async () => {
  const unreachable = async () => {
    throw new TypeError("Failed to fetch");
  };
  const error = await expectError(withFakeFetch(unreachable, () => api.listGames()));
  assertEqual(error.status, 0);
  assertIncludes(error.message, "Impossible de joindre le serveur");
});

test("a game already on loan (409) gives a French message", async () => {
  const { fetch } = fakeApi({ "POST /loans": [409, { error: true, reason: "Game is already on loan" }] });
  const error = await expectError(withFakeFetch(fetch, () => api.borrow("g1", "m1")));
  assertTrue(error instanceof ApiError, "l'erreur devrait être une ApiError");
  assertEqual(error.status, 409);
  assertEqual(error.message, "Ce jeu est déjà emprunté : il faut d'abord le rendre.");
});

// test de refus de la supression par l'API
test("deleting a game with loans gives a French error", async () => {
  const { fetch } = fakeApi({
    "DELETE /games/g1": [
      409,
      { error: true, reason: "A game with loans cannot be deleted" },
    ],
  });

  const error = await expectError(
    withFakeFetch(fetch, () => api.deleteGame("g1"))
  );

  assertTrue(error instanceof ApiError);
  assertEqual(error.status, 409);
  assertIncludes(error.message, "historique d'emprunts");
});

// test erreur jeu introuvable
test("updating a missing game gives a French error", async () => {
  const { fetch } = fakeApi({
    "PUT /games/unknown": [
      404,
      { error: true, reason: "Game not found" },
    ],
  });

  const game = {
    title: "Catan",
    minPlayers: 3,
    maxPlayers: 4,
    durationMinutes: 90,
  };

  const error = await expectError(
    withFakeFetch(fetch, () => api.updateGame("unknown", game))
  );

  assertTrue(error instanceof ApiError);
  assertEqual(error.status, 404);
  assertIncludes(error.message, "n'existe pas");
});

