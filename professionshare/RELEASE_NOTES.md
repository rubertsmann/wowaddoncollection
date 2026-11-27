# ProfessionShare 1.7.0

Orders now know when they were mailed. When you send a crafted item or the reagents through the addon's mailbox list,
the order notes it by itself: its History tab shows every mail with the items and amounts, and once the crafted item is
on its way the order shows the new status "Mailed" with a small letter icon. The requester still marks the order done
after picking up the mail. The person who receives the mail gets an order notification, like for other news on their
orders.

Pressing "Done" on a queued mail in the mailbox list counts too and is shown as "marked by hand". Mailed something
outside the addon, or handed it over in a trade? Open the order and use "Mark item as mailed / handed over" (crafter)
or "Mark reagents as mailed / handed over" (requester). The Orders tab filter has a new "Mailed" entry.

Guild members on older versions keep seeing and syncing orders as before; they just don't see the mail entries or the
"Mailed" status until they update.

# ProfessionShare 1.6.0

Every order now has its own window. Click the speech-bubble icon on an order: the Overview shows everything about it
at a glance (who asked for it and when, who is crafting it, the note, the reagents for the whole order with how many
you have, the tools the recipe needs, and who in the guild knows the recipe). The History tab lists every step of the
order with date and time: placed, claimed, withdrawn, done or cancelled.

New: talk about an order right where it is. The Chat tab of the order window lets everyone in the guild who uses the
addon read and write about that order. When someone writes on an order you placed or are crafting, you are told like
for other order news (the number on the minimap button and on the order's icon, the sound and a chat line); opening
the chat marks it read.

Settings: "Tell me about" is now a dropdown with every choice, and there is a new one, "Orders I have the profession
level for": you also hear about orders for recipes you do not know yet when your profession is high enough to learn
them.

Guild members on an older version keep seeing and syncing orders as before; they just do not see the chat. Update to
chat with them.

# ProfessionShare 1.5.0

The Orders tab is easier to use. One filter menu at the top replaces the "Show" and "Show finished" buttons, and you
can right-click any order to claim it, withdraw, mark it done, cancel it or whisper. Each order also has small icons
for the same actions. The Craft button now sits at the top and works on the order you selected.

New: send orders by mail. On an order, click the bag icon to mail the reagents to the crafter who took it, or the
letter icon to mail the finished item to the person who ordered it. The mails wait in the new Mail tab. When you open a
mailbox, a list appears next to it: click Fill and the mail is prepared for you (recipient, subject and the exact
amounts from your bags). You only press Send. Items you do not have yet stay in the list for later.

If you use Auctionator: the coin icon on an order puts its reagents on a shopping list. Collect as many orders as you
like; the next time you open the auction house, Auctionator searches for all of them at once. You can choose to buy
only what is missing from your bags and bank. Auctionator is optional; without it nothing changes.

No need for everyone to update at the same time: members on 1.4.x and 1.5.0 work together.

# ProfessionShare 1.4.3

**English:** The profession buttons at the top right now open the right window with one click. The Skinning button
opened nothing before, so your Skinning recipes were never shared; click it once after the update. All buttons used to
fire twice per click, which sometimes closed the window right away; that is fixed too. The addon now also tells the
developer which spell opens each profession window, so the buttons for the remaining professions can be made just as
reliable. No need for everyone to update at the same time: members on 1.4.x work together as before.

**Deutsch:** Die Berufsknöpfe oben rechts öffnen jetzt mit einem Klick das richtige Fenster. Der Kürschnerei-Knopf hat
vorher nichts geöffnet, deshalb wurden deine Kürschnerei-Rezepte nie geteilt; klicke ihn nach dem Update einmal an.
Alle Knöpfe haben bisher pro Klick zweimal ausgelöst und das Fenster dadurch manchmal sofort wieder geschlossen; auch
das ist behoben. Das Addon meldet dem Entwickler jetzt außerdem, welcher Zauber welches Berufsfenster öffnet, damit die
Knöpfe der übrigen Berufe genauso zuverlässig werden. Nicht alle müssen gleichzeitig updaten: Mitglieder mit 1.4.x
arbeiten wie gewohnt zusammen.

# ProfessionShare 1.4.2

**English:** Misc Items -> Keys now lists every main dungeon key, also the ones nobody in the guild holds yet (greyed
out, 0 holders), so you can see at a glance which keys are missing. The Dalaran sewer key is now listed for Dalaran.
No need for everyone to update at the same time: members on 1.4.x work together as before.

**Deutsch:** Sonstiges -> Schlüssel zeigt jetzt alle wichtigen Dungeonschlüssel, auch die, die noch niemand in der
Gilde hat (ausgegraut, 0 Besitzer). So siehst du sofort, welche Schlüssel noch fehlen. Der Kanalisationsschlüssel von
Dalaran wird jetzt für Dalaran angezeigt. Nicht alle müssen gleichzeitig updaten: Mitglieder mit 1.4.x arbeiten wie
gewohnt zusammen.

# ProfessionShare 1.4.1

**English:** New button in the settings (Interface -> AddOns -> ProfessionShare -> Recipe drops): **Announce the
recipes in my bags now** (or type `/ps drops scan`). Every tradeable recipe in your bags is announced to the guild as if
it had just dropped: members who can learn one are told, and hovering the recipe shows you who answered. Handy for
recipes you looted before updating. Members on 1.4.0 work with you as before.

**Deutsch:** Neuer Knopf in den Einstellungen (Interface -> AddOns -> ProfessionShare -> Rezeptfunde): **Rezepte in
meinen Taschen jetzt melden** (oder `/ps drops scan`). Jedes handelbare Rezept in deinen Taschen wird der Gilde gemeldet,
als wäre es gerade gefallen: Mitglieder, die eins lernen können, werden benachrichtigt, und wenn du über das Rezept
fährst, siehst du, wer geantwortet hat. Praktisch für Rezepte, die du vor dem Update gefunden hast. Mitglieder mit 1.4.0
arbeiten wie gewohnt mit dir zusammen.

# ProfessionShare 1.4.0

**English:** The Misc Items tab has two new lists. **Cooldowns** shows the crafts with a cooldown (Transmute, Mooncloth,
Salt Shaker) as a grid of icons: each one shows how long until somebody in the guild can craft it again and glows when
someone online is ready. Hover an icon to see every crafter and their time left; click it to whisper the best crafter
with the craft's link already in the chat box, or right-click to choose a crafter. **Reputation** lists the guild's
standing with the factions that matter (Argent Dawn, Timbermaw, Hydraxian Waterlords, cities and more), with a faction
filter, search, and a hint what each standing unlocks. New **recipe drop alerts**: when a tradeable recipe drops into
your bags, guild members who can learn it get a chat line or the minimap icon, and the recipe's tooltip shows you who
answered. All settings are now grouped on one page (Interface -> AddOns -> ProfessionShare, or `/ps options`), with a
switch for the minimap button. Members on older versions keep working with you, but only members on this version share
cooldowns, reputation and recipe drops.

**Deutsch:** Der Reiter Sonstiges hat zwei neue Listen. **Abklingzeiten** zeigt die Rezepte mit Abklingzeit
(Transmutieren, Mondstoff, Salzstreuer) als Symbolraster: Jedes Symbol zeigt, wie lange es dauert, bis jemand in der
Gilde es wieder herstellen kann, und leuchtet, wenn jemand online bereit ist. Fahre über ein Symbol, um alle Hersteller
mit ihrer Restzeit zu sehen; ein Klick flüstert den besten Hersteller mit dem Link des Rezepts im Chatfeld an, ein
Rechtsklick lässt dich einen Hersteller wählen. **Ruf** zeigt den Ruf der Gilde bei den wichtigen Fraktionen
(Argentumdämmerung, Holzschlundfeste, Hydraxianer, Hauptstädte und mehr), mit Fraktionsfilter, Suche und einem Hinweis,
was jede Rufstufe freischaltet. Neu sind **Rezept-Fundmeldungen**: Fällt ein handelbares Rezept in deine Taschen,
bekommen Gildenmitglieder, die es lernen können, eine Chatzeile oder das Minimap-Symbol, und der Tooltip des Rezepts
zeigt dir, wer geantwortet hat. Alle Einstellungen stehen jetzt gebündelt auf einer Seite (Interface -> AddOns ->
ProfessionShare oder `/ps options`), mit einem Schalter für den Minimap-Knopf. Mitglieder mit älteren Versionen arbeiten
weiter mit dir zusammen, aber nur Mitglieder mit dieser Version teilen Abklingzeiten, Ruf und Rezeptfunde.

# ProfessionShare 1.3.0

**English:** New **Feedback** tab: send feedback, a feature request or a bug report straight to the addon developer.
Pick the type and a short template helps you write it; bug reports can attach some technical details (addon version,
sync state, recent log lines) so the problem is easier to find. Under the text box you see your messages and how many
have already reached the developer. The tab only appears in the developer's guild. The Debug tab is now hidden; type
`/ps debug` to show it. Members on older versions keep working with you, but need this version to send feedback.

**Deutsch:** Neuer Reiter **Feedback**: Schicke Feedback, einen Funktionswunsch oder eine Fehlermeldung direkt an den
Addon-Entwickler. Wähle die Art, eine kurze Vorlage hilft beim Schreiben; Fehlermeldungen können technische Details
anhängen (Addon-Version, Sync-Zustand, letzte Protokollzeilen), damit sich das Problem leichter finden lässt. Unter dem
Textfeld siehst du deine Nachrichten und wie viele schon beim Entwickler angekommen sind. Der Reiter erscheint nur in
der Gilde des Entwicklers. Der Debug-Reiter ist jetzt ausgeblendet; mit `/ps debug` wird er angezeigt. Mitglieder mit
älteren Versionen arbeiten weiter mit dir zusammen, brauchen zum Senden von Feedback aber diese Version.

# ProfessionShare 1.2.2

**English:** ProfessionShare is now also listed in the addon menu at the minimap (the button that lists your addons), where your
game has one. So you can still open it when Leatrix Plus or another minimap button collector hides or gathers the
minimap buttons. Members on older versions keep working with you.

**Deutsch:** ProfessionShare steht jetzt auch im Addon-Menü an der Minimap (der Knopf, der deine Addons auflistet), sofern dein
Spiel eins hat. So kannst du es weiterhin öffnen, wenn Leatrix Plus oder ein anderer Minimap-Knopf-Sammler die
Minimap-Knöpfe ausblendet oder einsammelt. Mitglieder mit älteren Versionen arbeiten weiter mit dir zusammen.

# ProfessionShare 1.2.1

**English:** Fixes the chat message "No player named ... is currently playing" that could appear while the addon was
syncing, for example after a guild member logged out while you were crafting. The addon now sends fewer and fresher
updates while you level a profession and no longer sends anything to members who have gone offline. Please update;
members on older versions keep working with you.

**Deutsch:** Behebt die Chatmeldung "Momentan ist kein Spieler mit dem Namen ... online", die beim Abgleich erscheinen
konnte, zum Beispiel wenn sich ein Gildenmitglied ausloggte, während du handwerkst. Das Addon schickt beim Skillen
eines Berufs jetzt weniger und aktuellere Nachrichten und nichts mehr an Mitglieder, die offline gegangen sind. Bitte
aktualisieren; Mitglieder mit älteren Versionen arbeiten weiter mit dir zusammen.

# ProfessionShare 1.2.0

**English:** The "Available" tab is now called **Misc Items** and has a dropdown with three lists. **Recipe items**
works as before. **Keys** shows which guild members carry which dungeon key (Scarlet Key, Key to the City, Skeleton
Key, Shadowforge Key, Seal of Ascension and more), so you know whom to bring to open a door. **Attunements** shows who
can enter Molten Core, Onyxia, Blackwing Lair, Naxxramas and Upper Blackrock Spire. Every list is a sortable table:
click a column title to sort and pick the columns you want in the "Columns" menu. Keys and attunements are found
automatically. Members on older versions keep working with you, but only members on 1.2.0 appear in the Keys and
Attunements lists.

**Deutsch:** Der Reiter "Verfügbar" heißt jetzt **Sonstiges** und hat eine Auswahl mit drei Listen.
**Rezept-Gegenstände** funktioniert wie bisher. **Schlüssel** zeigt, welche Gildenmitglieder welchen Dungeonschlüssel
dabeihaben (etwa für das Scharlachrote Kloster, Stratholme, Scholomance, die Schwarzfelstiefen und Düsterbruch),
damit ihr wisst, wen ihr zum Öffnen einer Tür mitnehmt. **Zugänge** zeigt, wer den Geschmolzenen
Kern, Onyxias Hort, den Pechschwingenhort, Naxxramas und die Obere Schwarzfelsspitze betreten darf. Jede Liste ist eine
sortierbare Tabelle: Klick auf einen Spaltentitel sortiert, im Menü "Spalten" wählst du die Spalten aus. Schlüssel und
Zugänge werden automatisch erkannt. Mitglieder mit älteren Versionen arbeiten weiter mit dir zusammen, in den Listen
Schlüssel und Zugänge erscheinen aber nur Mitglieder mit 1.2.0.

# ProfessionShare 1.1.0

**English:** The minimap button is now a standard addon button, so minimap button collectors such as Leatrix Plus
("Combine addon buttons") and data bars such as Titan Panel now list ProfessionShare. Drag it with the left mouse
button. It starts at a new default spot once, so move it back where you like it. Members on older versions keep
working with you.

**Deutsch:** Der Minimap-Knopf ist jetzt ein Standard-Addon-Knopf, daher führen Minimap-Knopf-Sammler wie Leatrix Plus
("Addon-Knöpfe zusammenfassen") und Datenleisten wie Titan Panel ProfessionShare jetzt auf. Verschieben mit der linken
Maustaste. Er startet einmalig an einer neuen Standardposition; zieh ihn einfach wieder an deinen Wunschplatz.
Mitglieder mit älteren Versionen arbeiten weiter mit dir zusammen.

# ProfessionShare 1.0.2

**English:** Maintenance release: a diagnostic for the addon's maintainer that shows which version each guild member
runs, so sync problems can be found faster. Nothing changes for you; updating keeps everyone on the same version.

**Deutsch:** Wartungsversion: eine Diagnose für den Entwickler des Addons, die zeigt, welche Version jedes
Gildenmitglied nutzt, damit Probleme beim Abgleich schneller gefunden werden. Für dich ändert sich nichts; mit dem
Update bleiben alle auf demselben Stand.

# ProfessionShare 1.0.1

**English:** Fixes: guild members whose game still shows realm names can now see your recipes and recipe items again.
The minimap button now sits on the ring outside the minimap, like other addons' buttons. In a narrow window the recipe
table no longer runs under the recipe details: it scrolls sideways instead (slider below the table, or Shift + mouse
wheel). Members on 1.0.0 keep syncing with you; everyone should update so the realm fix works both ways.

**Deutsch:** Fehlerbehebungen: Gildenmitglieder, deren Spiel noch Realmnamen anzeigt, sehen deine Rezepte und
Rezeptgegenstände wieder. Der Minimap-Knopf sitzt jetzt auf dem Ring außerhalb der Minimap, wie die Knöpfe anderer
Addons. In einem schmalen Fenster läuft die Rezepttabelle nicht mehr unter die Rezeptdetails, sondern lässt sich
seitlich scrollen (Schieberegler unter der Tabelle oder Umschalt + Mausrad). Mitglieder mit 1.0.0 tauschen weiter Daten
mit dir aus; alle sollten aktualisieren, damit die Realm-Korrektur in beide Richtungen wirkt.

# ProfessionShare 1.0.0

**English:** TalentShare is now called **ProfessionShare**. Please remove the old TalentShare addon. The command is now
`/ps`. ProfessionShare starts with empty data: open each of your professions once so it reads your recipes again; your
guild members' professions come back on their own once they have updated too. Old and new versions do not see each other.

**Deutsch:** TalentShare heißt jetzt **ProfessionShare**. Bitte entferne das alte TalentShare-Addon. Der Befehl lautet
jetzt `/ps`. ProfessionShare startet ohne Daten: Öffne jeden deiner Berufe einmal, damit deine Rezepte neu eingelesen
werden; die Berufe deiner Gildenmitglieder kommen von selbst zurück, sobald sie ebenfalls aktualisiert haben. Alte und
neue Versionen sehen sich gegenseitig nicht.

# TalentShare 0.7.3

**English:** Fix: most enchantments showed their tools and reagents instead of their effect. They now show the real
effect (for example "permanently enchant a cloak to increase Agility by 3"); it appears a moment after the list opens.

**Deutsch:** Fehlerbehebung: Die meisten Verzauberungen zeigten ihre Werkzeuge und Reagenzien statt ihrer Wirkung. Jetzt
erscheint die echte Wirkung (zum Beispiel „Einen Umhang dauerhaft so verzaubern, dass er die Beweglichkeit um 3 erhöht.“),
einen Moment nachdem die Liste geöffnet wurde.

# TalentShare 0.7.2

**English:** Enchantments now show what they do. Hover the icon of an enchant in the Recipes tab, or select it, to see its
effect (for example "+1 Agility"); the search also finds enchants by their effect.

**Deutsch:** Verzauberungen zeigen jetzt, was sie bewirken. Fahre im Reiter „Rezepte“ über das Symbol einer
Verzauberung oder wähle sie aus, um ihre Wirkung zu sehen (zum Beispiel „+1 Beweglichkeit“); auch die Suche findet
Verzauberungen über ihre Wirkung.

# TalentShare 0.7.1

**English:** Fix: the TalentShare window can now be opened, closed and used during combat (before, `/ts`, the minimap
button and Escape did nothing in a fight). The profession icons and the Craft button are hidden while you are in combat
and come back right after it.

**Deutsch:** Fehlerbehebung: Das TalentShare-Fenster lässt sich jetzt auch im Kampf öffnen, schließen und benutzen
(vorher passierte bei `/ts`, dem Minimap-Knopf und Escape im Kampf nichts). Die Berufssymbole und der Knopf „Herstellen“
sind im Kampf ausgeblendet und erscheinen direkt danach wieder.

# TalentShare 0.7.0

## English

**New: the recipe list is a table, and the window can be resized.**

- **Recipe table.** The Recipes tab now shows columns with titles: Item level, Required level, Profession, Skill and
  Category. Recipe names appear in the colour of the item they make (green, blue, purple, ...).
- **Sorting.** The list starts with the highest item level on top. Click any column title to sort by it; click it
  again to reverse the order.
- **Choose your columns.** `/ts options` (or the Options button) has a new "Recipe list" section: switch each column on
  or off and pick the sort order.
- **Resizable window.** Drag the grip at the bottom right corner to make the window bigger. All lists grow with it,
  and the size is remembered.
- **Games moved out.** The coin flip and the slot machine are now their own addon, **GuildGames** (`/gg`). Install it
  if you want to keep playing; TalentShare no longer has a Games tab. Old game results are not carried over.

**After updating:** restart the game. Members still on 0.6.0 keep sharing recipes, orders and items with you as before.
Don't go back to 0.6.0 afterwards: it can no longer save changes to the updated data.

## Deutsch

**Neu: die Rezeptliste ist eine Tabelle, und das Fenster lässt sich in der Größe ändern.**

- **Rezepttabelle.** Der Reiter „Rezepte“ zeigt jetzt Spalten mit Überschriften: Gegenstandsstufe, Benötigte Stufe,
  Beruf, Fertigkeit und Kategorie. Rezeptnamen erscheinen in der Farbe des hergestellten Gegenstands (grün, blau,
  lila, ...).
- **Sortieren.** Die Liste beginnt mit der höchsten Gegenstandsstufe. Klicke auf eine Spaltenüberschrift, um danach zu
  sortieren; ein zweiter Klick dreht die Reihenfolge um.
- **Spalten auswählen.** In `/ts options` (oder über den Knopf „Optionen“) gibt es den neuen Abschnitt „Rezeptliste“:
  jede Spalte ein- oder ausschalten und die Sortierung wählen.
- **Fenstergröße.** Zieh am Griff in der rechten unteren Ecke, um das Fenster zu vergrößern. Alle Listen wachsen mit,
  und die Größe bleibt gespeichert.
- **Spiele ausgelagert.** Münzwurf und Spielautomat sind jetzt ein eigenes Addon, **GuildGames** (`/gg`). Installiere
  es, wenn du weiterspielen möchtest; TalentShare hat keinen Reiter „Spiele“ mehr. Alte Spielergebnisse werden nicht
  übernommen.

**Nach dem Update:** Spiel neu starten. Mitglieder mit 0.6.0 tauschen Rezepte, Bestellungen und Gegenstände weiter mit
dir aus wie bisher. Danach nicht mehr auf 0.6.0 zurückgehen: diese Version kann die aktualisierten Daten nicht mehr
speichern.
