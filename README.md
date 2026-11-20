# GoogleCal — Delphi 13 VCL + Google Calendar API

Application Delphi 13 VCL qui se connecte à **Google Agenda** via l'API
**Google Calendar v3** : trouver un calendrier et le supprimer.
Aucune dépendance externe : uniquement les bibliothèques livrées avec Delphi
(REST, Indy).

## Structure

| Fichier | Rôle |
|---|---|
| `GoogleCal.dpr` | Projet Delphi |
| `src/GoogleAuth.pas` | OAuth 2.0 de bureau : navigateur par défaut + serveur de rebouclage local (127.0.0.1), échange et rafraîchissement des tokens, cache JSON |
| `src/GoogleCalendar.pas` | API Calendar v3 : lister, trouver, supprimer un calendrier |
| `src/Agenda.pas` / `FormAgenda.dfm` | Fiche de démonstration (connexion / liste / suppression) |

## Configuration (une seule fois)

1. Ouvrir [Google Cloud Console](https://console.cloud.google.com) et créer un projet,
   puis **API et services → Bibliothèque → Google Calendar API → Activer**.
2. **Écran de consentement OAuth** : type *Externe*, ajouter vos utilisateurs de test.
3. **Identifiants → Créer des identifiants → ID client OAuth → Application de bureau**.
4. Sur ce client OAuth, ajouter l'URI de redirection autorisée :
   **`http://localhost:8099/`**
5. Renseigner `CLIENT_ID` et `CLIENT_SECRET` dans `src/Agenda.pas`.

## Compiler et lancer

1. Ouvrir `GoogleCal.dpr` dans Delphi 13, cliquer sur **Exécuter**.
2. **Se connecter à Google** : le navigateur s'ouvre, autoriser l'accès.
   Le token est mis en cache dans `%USERPROFILE%\GoogleCal.token.json`
   (le refresh token évite de renouveler le consentement à chaque lancement).
3. **Lister les calendriers** : affiche tous les calendriers accessibles, avec
   leur état (`(principal)`, `[non supprimable]`).
4. **Supprimer** : suppression définitive si vous êtes propriétaire du
   calendrier secondaire ; sinon proposition de le retirer de votre liste.

## Règles de suppression côté Google

- Le calendrier **principal** ne peut pas être supprimé (HTTP 400).
- Un calendrier secondaire dont vous êtes **propriétaire** peut être supprimé
  définitivement (`calendars.delete`, réponse HTTP 204).
- Un calendrier **partagé** se retire seulement de votre liste
  (`calendarList.delete`) : le propriétaire le conserve.

## Dépannage

**Erreur 400 : `redirect_uri_mismatch`** (page « Accès bloqué » chez Google) :
l'URI de redirection envoyée par l'application ne correspond pas à celle
enregistrée dans la Console.

1. Console Google Cloud → **API et services → Identifiants** → votre
   **ID client OAuth** (Application de bureau) → Modifier.
2. Dans **« URI de redirection autorisés »**, ajoutez exactement :
   `http://localhost:8099/` (avec le `/` final ; `localhost`, pas `127.0.0.1`).
3. Enregistrer. La prise en compte est quasi immédiate (compter quelques
   minutes dans de rares cas).
4. Si vous avez changé le port, mettez aussi `URI_REDIRECTION` dans
   `src/Agenda.pas` en cohérence.

## Notes de sécurité

- Le fichier `GoogleCal.token.json` contient des tokens actifs : ne pas le
  distribuer, l'ajouter à `.gitignore` si le binaire est copié autre part.
- Le scope `https://www.googleapis.com/auth/calendar` est « sensible » :
  hors période de test, Google exige la vérification de l'application.
