# TalentShare 0.4.2

## English

**Recipes and recipe items now sync between guild members on different realms.** 0.4.1 still showed empty Recipes and
Available tabs for many guilds.

**What was wrong:** a guild on WoW Forever spans several realms (for example "EU4 Realm 1", "EU4 Realm 3", "EU4 Realm 5").
The game shows names without the realm, so TalentShare added your own realm to every name. A member on another realm was
therefore called differently on each computer, and requests for recipes were ignored. The realm is now ignored in player
names, so every member has the same name everywhere. Saved data is converted automatically.

- Members who are still on 0.4.0 or 0.4.1 also receive your recipes from 0.4.2, but everyone should update.
- Debug tab -> **Name check** has a new row "Realm in player names" (should say "ignored").
- After switching to another version, the window could show mixed or broken data until `/ts clean confirm`. Now the
  guild data is fetched again automatically once after every update; your own recipes, items and orders are kept.

**After updating:** restart the game, open each profession once (icons at the top right of the Recipes tab) and wait about
two minutes.

## Deutsch

**Rezepte und Rezept-Gegenstände werden jetzt auch zwischen Gildenmitgliedern auf verschiedenen Realms geteilt.** Mit
0.4.1 blieben der Rezepte-Tab und der Verfügbar-Tab in vielen Gilden weiter leer.

**Was falsch war:** Eine Gilde auf WoW Forever erstreckt sich über mehrere Realms (zum Beispiel „EU4 Realm 1“, „EU4
Realm 3“, „EU4 Realm 5“). Das Spiel zeigt Namen ohne Realm, deshalb hat TalentShare an jeden Namen deinen eigenen Realm
angehängt. Ein Mitglied auf einem anderen Realm hieß dadurch auf jedem Rechner anders, und Anfragen nach Rezepten wurden
ignoriert. Der Realm wird in Spielernamen jetzt ignoriert, jedes Mitglied hat überall denselben Namen. Gespeicherte Daten
werden automatisch umgestellt.

- Mitglieder, die noch 0.4.0 oder 0.4.1 nutzen, bekommen deine Rezepte von 0.4.2 ebenfalls, aktualisieren sollten trotzdem alle.
- Debug-Tab -> **Namen prüfen** hat eine neue Zeile „Realm in Spielernamen“ (sollte „ignoriert“ zeigen).
- Nach einem Versionswechsel konnte das Fenster gemischte oder kaputte Daten zeigen, bis `/ts clean confirm` half. Jetzt
  werden die Gildendaten nach jedem Update einmal automatisch neu abgerufen; deine eigenen Rezepte, Gegenstände und
  Bestellungen bleiben erhalten.

**Nach dem Update:** Spiel neu starten, jeden Beruf einmal öffnen (Symbole oben rechts im Rezepte-Tab) und etwa zwei
Minuten warten.
