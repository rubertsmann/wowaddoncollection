# GuildGames 0.11.3

**English:** The restore command from 0.11.2 (`/gg caught restore`) is no longer available: the companion it was made
for is back. If you still miss a companion after the update to 0.11, keep a copy of
`WTF/Account/<account>/SavedVariables/GuildGames.lua.bak` and contact us. Nothing else changes; arena fights still need
the same version on both sides, so please update.

**Deutsch:** Der Wiederherstellungsbefehl aus 0.11.2 (`/gg caught restore`) ist nicht mehr verfügbar: Der Begleiter,
für den er gedacht war, ist zurück. Wenn dir nach dem Update auf 0.11 noch ein Begleiter fehlt, sichere eine Kopie von
`WTF/Account/<Account>/SavedVariables/GuildGames.lua.bak` und melde dich. Sonst ändert sich nichts; Arenakämpfe
brauchen weiterhin auf beiden Seiten dieselbe Version, also bitte aktualisieren.

# GuildGames 0.11.2

**English:** Fixes lost companions after the update to 0.11: when an older GuildGames version was still in use in the
guild, updating could empty your AZEcaught companions and remove your active companion. This version keeps them.
**If you have not updated to 0.11 yet, update straight to this version.** If you already lost your companion, keep a
copy of `WTF/Account/<account>/SavedVariables/GuildGames.lua.bak` and contact us: we can build a restore code from it,
which you enter once with `/gg caught restore <code>`.

**Deutsch:** Behebt verlorene Begleiter nach dem Update auf 0.11: Wenn in der Gilde noch eine ältere GuildGames-Version
lief, konnte das Update deine AZEcaught-Begleiter leeren und deinen aktiven Begleiter entfernen. Diese Version behält
sie. **Wer noch nicht auf 0.11 aktualisiert hat, sollte direkt auf diese Version gehen.** Wenn dein Begleiter schon weg
ist, sichere eine Kopie von `WTF/Account/<Account>/SavedVariables/GuildGames.lua.bak` und melde dich: Daraus können
wir einen Wiederherstellungscode erstellen, den du einmal mit `/gg caught restore <Code>` eingibst.

# GuildGames 0.11.1

**English:** Fixes the "reserved for the Blizzard UI" error that GuildGames could cause in fights: the rope checked its
28 yard range with a function the game does not allow during combat. The rope and the traps now need the enemy to be
**fighting you** instead of a distance. Until it is, the rope icon is greyed out, and a click tells you to attack it
first. The rope icon also goes away on a dead enemy and after a failed throw (it came back after a minute before).
**Everyone should update:** arena fights only work between players on the same GuildGames version.

**Deutsch:** Behebt den Fehler "nur für die Blizzard-Oberfläche reserviert", den GuildGames in Kämpfen auslösen
konnte: Das Seil prüfte seine 28 Meter Reichweite mit einer Funktion, die das Spiel im Kampf nicht erlaubt. Seil und
Fallen brauchen jetzt statt einer Entfernung einen Gegner, der **mit dir kämpft**. Bis dahin ist das Seilsymbol
ausgegraut, und ein Klick sagt dir, dass du ihn zuerst angreifen musst. Das Seilsymbol verschwindet außerdem bei einem
toten Gegner und nach einem misslungenen Wurf (vorher kam es nach einer Minute zurück). **Alle sollten
aktualisieren:** Arenakämpfe gehen nur zwischen Spielern mit derselben GuildGames-Version.

# GuildGames 0.11.0

**English:** Every monster you catch is now its own companion in your **roster** (Collection > Caught, one row per
catch). One is active at a time: **Make companion** switches for free, and each one keeps its needs, hearts, arena
level and training. Resting companions are frozen, so they don't get hungry and can't die; a training that is running
stops when you switch. **Release** lets a companion go for good. Arena fights are now **3 against 3**: you challenge
with a team of three in fighting order, and the other player sees your team in full (flip through it with the
arrows) and picks three of their own to counter it, with their win chance shown. The winner of a round stays in with
the health it has left for the next opponent. Every companion that fought gets XP, more for every opponent it beat.
Arena buffs now work on the whole team. **Everyone must update:** fights only work between players on the same
GuildGames version, and the arena tells you when your versions differ. Open one-against-one challenges from the old
version are cancelled and your own wagers are refunded.

**Deutsch:** Jedes gefangene Monster ist jetzt ein eigener Begleiter in deinem **Kader** (Sammlung > Gefangen, eine
Zeile pro Fang). Einer ist aktiv: **Als Begleiter** wechselt kostenlos, und jeder behält seine Bedürfnisse,
Herzen, Arenastufe und sein Training. Ruhende Begleiter sind eingefroren, sie bekommen keinen Hunger und können nicht
sterben; ein laufendes Training endet beim Wechsel. **Freilassen** lässt einen Begleiter endgültig gehen.
Arenakämpfe sind jetzt **3 gegen 3**: Du forderst mit einem Team aus drei Begleitern in Kampfreihenfolge heraus, und
der andere Spieler sieht dein Team vollständig (mit den Pfeilen durchblättern) und wählt drei eigene als Konter, mit
Anzeige seiner Siegchance. Der Sieger einer Runde bleibt mit seinem restlichen Leben gegen den nächsten Gegner im
Kampf. Jeder Begleiter, der gekämpft hat, bekommt EP, mehr für jeden besiegten Gegner. Arena-Buffs wirken jetzt auf
das ganze Team. **Alle müssen aktualisieren:** Kämpfe gehen nur zwischen Spielern mit derselben GuildGames-Version,
und die Arena sagt dir, wenn eure Versionen verschieden sind. Offene Eins-gegen-eins-Herausforderungen der alten
Version werden abgebrochen, und deine eigenen Einsätze bekommst du zurück.

# GuildGames 0.10.0

**English:** Thirteen new items in the AZEcaught shop. **Charms** (bought once, worn in one charm slot, swapped for
free in the Inventory): Lucky Charm (+10% catch rewards), Steady Hand (a longer best moment), Second Chance (when the
rope slips off, you can throw once more at the same enemy) and Rare Lure (+25% for elite and rare catches). **Care:**
Feast (hunger and thirst to full), Squeaky Toy (affection to full) and Care Elixir (the needs don't drop for 4 hours).
**Arena:** War Paint (+10% attack for 3 fights), Bark Skin (+10% health for 3 fights) and Swift Tonic (+25% speed for
one fight); their icons show next to your fighter for both sides. **Games:** Dash Shield (Companion Dash survives one
hit), Head Start (the run starts at 200 m) and Survivor Bomb (clears the screen once per run, stakes up to 250g).
Runs that used an item carry a bag icon on the boards. Prices may still change. Guild members on an older version
see the same fight results; they just don't see the buff icons and bag marks.

**Deutsch:** Dreizehn neue Gegenstände im AZEcaught-Laden. **Talismane** (einmal gekauft, in einem Talisman-Platz
getragen, im Inventar kostenlos wechselbar): Glücksbringer (+10 % Fangbelohnung), Ruhige Hand (ein längerer bester
Moment), Zweite Chance (rutscht das Seil ab, darfst du noch einmal auf denselben Gegner werfen) und Seltener Köder
(+25 % für Elite- und seltene Fänge). **Pflege:** Festmahl (Hunger und Durst voll), Quietschspielzeug (Zuneigung voll)
und Pflegeelixier (die Bedürfnisse sinken 4 Stunden lang nicht). **Arena:** Kriegsbemalung (+10 % Angriff für 3 Kämpfe),
Baumrinde (+10 % Leben für 3 Kämpfe) und Flinkes Tonikum (+25 % Tempo für einen Kampf); ihre Symbole stehen für beide
Seiten neben deinem Kämpfer. **Spiele:** Sprintschild (Begleiter-Sprint übersteht einen Treffer), Vorsprung (der Lauf
beginnt bei 200 m) und Überlebensbombe (räumt einmal pro Lauf den Bildschirm, Einsatz bis 250g). Läufe mit einem
Gegenstand tragen ein Taschensymbol in den Bestenlisten. Die Preise können sich noch ändern. Gildenmitglieder mit einer
älteren Version sehen dieselben Kampfergebnisse, nur ohne Buff-Symbole und Taschen-Markierung.

# GuildGames 0.9.1

**English:** The Arena, Shop and Inventory tabs of AZEcaught now open only once you have a companion; until then
Companion and Collection are available, and your next catch becomes your companion. Small fix: a pet or monster whose
3D model is not shown yet appears as an icon instead of an empty spot. No need for everyone to update at once.

**Deutsch:** Die Reiter Arena, Laden und Inventar in AZEcaught öffnen sich erst, wenn du einen Begleiter hast; bis
dahin gibt es Begleiter und Sammlung, und dein nächster Fang wird dein Begleiter. Kleine Korrektur: Ein Begleiter oder
Monster, dessen 3D-Modell noch nicht angezeigt wird, erscheint als Symbol statt als leere Stelle. Nicht alle müssen
gleichzeitig aktualisieren.

# GuildGames 0.9.0

**English:** A new game: **Companion Dash**. Your companion runs through a scrolling landscape while the monsters you
have found or caught come at it. Click the top half of the play area to jump (hold for a higher jump) and hold the
bottom half to duck under flying monsters; Space and the arrow keys work too. The speed keeps rising and one hit ends
the run. There is no stake: every 100 m pays 1g into your gold, up to 50g a day, and the guild board shows the longest
runs of the week and of all time. You need a companion to play. In Survivor your companion now stands in the middle
and attacks the monsters, on a grass field, and shots no longer fly out of the window. Guild members without this
version simply do not see the runner board; nothing breaks for them.

**Deutsch:** Ein neues Spiel: **Begleiter-Sprint**. Dein Begleiter läuft durch eine vorbeiziehende Landschaft, und die
Monster, die du gefunden oder gefangen hast, kommen ihm entgegen. Klick in die obere Hälfte springt (halten: höher),
die untere Hälfte halten duckt unter fliegenden Monstern durch; Leertaste und Pfeiltasten gehen auch. Das Tempo
steigt, ein Treffer beendet den Lauf. Ohne Einsatz: Alle 100 m gibt es 1g, bis zu 50g am Tag, und die Gildenrangliste
zeigt die längsten Läufe der Woche und aller Zeiten. Du brauchst einen Begleiter. In Survivor steht jetzt dein Begleiter
in der Mitte und greift die Monster an, auf einer Wiese, und Geschosse fliegen nicht mehr aus dem Fenster. Wer diese
Version nicht hat, sieht die Läufer-Rangliste einfach nicht; es geht nichts kaputt.

# GuildGames 0.8.0

**English:** AZEcaught has a Shop and an Inventory now. Buy items with your gold: Delicious Meat (50g) makes every
catch succeed for 20 seconds, with a small clock showing the time left. Magic Traps catch an enemy at once, at any
health, without a fight: the Magic Trap (500g) catches normal enemies, the Elite Magic Trap (1000g) also elites, the
Rare Magic Trap (1500g) also rares; never a world boss. A refused trap is kept. While you own catch items, a small bag
sits next to your target's rope icon: click it, then click the item. If you prefer, the options can show the rope icon
and the bag next to your target frame instead of on the nameplates. The AZEcaught tabs are icons now (hover for the
name), and AZEcaught is the first button at the top left. No need for everyone to update at once: nothing changes in
what the guild sees.

**Deutsch:** AZEcaught hat jetzt einen Laden und ein Inventar. Kaufe Gegenstände mit deinem Gold: Köstliches Fleisch
(50g) lässt 20 Sekunden lang jeden Fang gelingen, eine kleine Uhr zeigt die Restzeit. Magische Fallen fangen einen
Gegner sofort, bei jeder Gesundheit, ohne Kampf: die Magische Falle (500g) fängt normale Gegner, die Elite-Magiefalle
(1000g) auch Elite, die Seltene Magiefalle (1500g) auch seltene; nie einen Weltboss. Eine abgelehnte Falle behältst
du. Solange du Fanggegenstände hast, sitzt ein kleiner Beutel neben dem Seil-Symbol deines Ziels: anklicken, dann den
Gegenstand. Wer mag, lässt Seil-Symbol und Beutel in den Optionen neben dem Zielfenster statt auf den
Namensplaketten anzeigen. Die AZEcaught-Reiter sind jetzt Symbole (Name beim Darüberfahren), und AZEcaught ist der
erste Knopf oben links. Nicht alle müssen gleichzeitig aktualisieren: Für die Gilde ändert sich nichts.

# GuildGames 0.7.0

**English:** Your companion's fighter now lives right below the pet. In the Companion view you see its arena level,
wins and losses and an XP bar under its name, and the four training icons (Attack, Defense, Speed, Vitality) with
their points, for example 10/25. Click an icon to start that training; the time left shows on the icon. Feeding,
watering, petting and sleeping are now done by clicking the need bar itself (hover it for the price). The Arena tab
now only has Guild and Fights. In the small pet window, the new button under the pet opens the four training icons;
click one to train, click anywhere else to close them. No need for everyone to update at once: nothing changes in
what the guild sees.

**Deutsch:** Der Kämpfer deines Begleiters sitzt jetzt direkt unter dem Tier. In der Begleiter-Ansicht siehst du unter
dem Namen die Arenastufe, Siege und Niederlagen und einen EP-Balken, und darunter die vier Trainings-Symbole (Angriff,
Verteidigung, Tempo, Vitalität) mit ihren Punkten, zum Beispiel 10/25. Ein Klick auf ein Symbol startet das Training;
die Restzeit steht auf dem Symbol. Füttern, Tränken, Streicheln und Schlafen machst du jetzt mit einem Klick auf den
Bedarfsbalken selbst (beim Darüberfahren steht der Preis). Der Arena-Reiter hat nur noch Gilde und Kämpfe. Im kleinen
Tierfenster öffnet der neue Knopf unter dem Tier die vier Trainings-Symbole; ein Klick auf eines trainiert, ein Klick
irgendwo anders schließt sie. Nicht alle müssen gleichzeitig aktualisieren: Für die Gilde ändert sich nichts.

# GuildGames 0.6.0

**English:** Arena fights are now a surprise: when your fight is decided, the chat tells you to watch it, and the
result, the wager and any side bets are paid only after you watched the replay (or by themselves after 24 hours).
When someone challenges you, you can now make a counter offer with a different wager; the challenger then accepts it
(the fight starts) or declines it (both get their gold back). Accept and decline are now two icons below the fight
list. Catching: the rope now says why it cannot be thrown: catching does not work in dungeons and raids, the enemy
must be your own kill (not tagged by someone else) and within 28 yards. Members on older versions still play with
you, but they do not see counter offers, so update to use them.

**Deutsch:** Arena-Kämpfe sind jetzt eine Überraschung: Wenn dein Kampf entschieden ist, sagt dir der Chat, dass du
ihn ansehen sollst, und das Ergebnis, der Einsatz und Wetten werden erst ausgezahlt, wenn du die Wiederholung gesehen
hast (oder nach 24 Stunden von selbst). Wenn dich jemand herausfordert, kannst du jetzt ein Gegenangebot mit einem
anderen Einsatz machen; der Herausforderer nimmt es an (der Kampf beginnt) oder lehnt ab (beide bekommen ihr Gold
zurück). Annehmen und Ablehnen sind jetzt zwei Symbole unter der Kampfliste. Fangen: Das Seil sagt jetzt, warum es
nicht geworfen werden kann: In Dungeons und Schlachtzügen funktioniert Fangen nicht, der Gegner muss dein eigener Kill
sein (nicht von jemand anderem markiert) und höchstens 28 Meter entfernt. Mitglieder mit älteren Versionen spielen
weiter mit dir, sehen aber keine Gegenangebote; aktualisiere, um sie zu nutzen.

# GuildGames 0.5.0

**English:** New minimal view: /gg and the minimap button now open a small window with only your AZEcaught companion
and no text. Four round buttons around it (food, water, petting, sleep) fill up like a ring with each need and turn
yellow or red when it gets low; click one to care for your pet. The heart in the top-right corner pulses when you earn
hearts. The icon in the top-left corner switches to the full window and back. In Options > AddOns > GuildGames
AZEcaught you can choose which view opens first, set the opacity and size, lock its position and hide it in combat.
Your companion now also does something on its own every few minutes: a roar, a dance, a wave or a swing. Members on
older versions keep working with you.

**Deutsch:** Neue minimale Ansicht: /gg und der Minimap-Knopf öffnen jetzt ein kleines Fenster nur mit deinem
AZEcaught-Begleiter und ohne Text. Vier runde Knöpfe darum (Futter, Wasser, Streicheln, Schlaf) füllen sich wie ein
Ring mit jedem Bedürfnis und werden gelb oder rot, wenn es knapp wird; ein Klick pflegt dein Tier. Das Herz oben rechts
pulsiert, wenn du Herzen bekommst. Das Symbol oben links wechselt zum vollen Fenster und zurück. Unter Optionen >
AddOns > GuildGames AZEcaught wählst du, welche Ansicht zuerst öffnet, stellst Deckkraft und Größe ein, sperrst die
Position und blendest sie im Kampf aus. Dein Begleiter macht jetzt außerdem alle paar Minuten etwas von selbst: ein
Brüllen, einen Tanz, ein Winken oder einen Hieb. Mitglieder mit älteren Versionen arbeiten weiter mit dir zusammen.

# GuildGames 0.4.2

**English:** GuildGames is now also listed in the addon menu at the minimap (the button that lists your addons), where your
game has one. So you can still open it when Leatrix Plus or another minimap button collector hides or gathers the
minimap buttons. Members on older versions keep working with you.

**Deutsch:** GuildGames steht jetzt auch im Addon-Menü an der Minimap (der Knopf, der deine Addons auflistet), sofern dein
Spiel eins hat. So kannst du es weiterhin öffnen, wenn Leatrix Plus oder ein anderer Minimap-Knopf-Sammler die
Minimap-Knöpfe ausblendet oder einsammelt. Mitglieder mit älteren Versionen arbeiten weiter mit dir zusammen.

# GuildGames 0.4.1

**English:** Fixes the chat message "No player named ... is currently playing" that could appear while the addon was
syncing after a guild member logged out. Nothing is sent to members who have gone offline anymore. Members on older
versions keep working with you.

**Deutsch:** Behebt die Chatmeldung "Momentan ist kein Spieler mit dem Namen ... online", die beim Abgleich erscheinen
konnte, nachdem sich ein Gildenmitglied ausgeloggt hatte. An Mitglieder, die offline gegangen sind, wird nichts mehr
geschickt. Mitglieder mit älteren Versionen arbeiten weiter mit dir zusammen.

# GuildGames 0.4.0

**English:** The minimap button is now a standard addon button, so minimap button collectors such as Leatrix Plus
("Combine addon buttons") and data bars such as Titan Panel now list GuildGames. Drag it with the left mouse button.
It starts at a new default spot once, so move it back where you like it. Members on older versions keep playing with you.

**Deutsch:** Der Minimap-Knopf ist jetzt ein Standard-Addon-Knopf, daher führen Minimap-Knopf-Sammler wie Leatrix Plus
("Addon-Knöpfe zusammenfassen") und Datenleisten wie Titan Panel GuildGames jetzt auf. Verschieben mit der linken
Maustaste. Er startet einmalig an einer neuen Standardposition; zieh ihn einfach wieder an deinen Wunschplatz.
Mitglieder mit älteren Versionen spielen weiter mit dir.

# GuildGames 0.3.1

**English:** Fixes: the minimap button now sits on the ring outside the minimap, like other addons' buttons. Guild
members whose game still shows realm names now receive your games data (leaderboards, arena fighters) again. Members
on 0.3.0 keep playing with you; everyone should update so the realm fix works both ways.

**Deutsch:** Fehlerbehebungen: Der Minimap-Knopf sitzt jetzt auf dem Ring außerhalb der Minimap, wie die Knöpfe anderer
Addons. Gildenmitglieder, deren Spiel noch Realmnamen anzeigt, erhalten deine Spieldaten (Bestenlisten,
Arena-Kämpfer) wieder. Mitglieder mit 0.3.0 spielen weiter mit dir; alle sollten aktualisieren, damit die
Realm-Korrektur in beide Richtungen wirkt.
