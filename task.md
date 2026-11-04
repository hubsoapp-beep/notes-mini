# Notes Mini — backlog

Przegląd z 2026-10-19. Stan: `main` = `5597391`, publiczne w `hubsoapp-beep/notes-mini`,
192 checki zielone, build bez ostrzeżeń, bundle 1,2 MB.

Priorytety: **P0** = ryzyko utraty danych albo aplikacja wyglądająca na zepsutą.
**P1** = funkcje, których brak zauważa się w pierwszych minutach.
**P2** = pozycjonowanie i higiena publicznego repo.

---

## P0 — ryzyko i ciche awarie

### 1. Edycja zewnętrzna nadpisuje zmiany w notatce

- [x] Zrobione: `NoteStore.refresh` / `keepConflictCopy`, checki w `testStoreIntegrity`.
- `storeDidChange()` w `Sources/NotesMini/AppDelegate.swift` odświeża tylko menu bar; otwarta
      notatka nie jest porównywana z plikiem na dysku.
- **Skutek:** notatka zmieniona w Obsidianie / innym edytorze przy otwartym panelu zostaje
      nadpisana przy następnym zapisie. Dla notatnika trzymającego dane w plikach to najgorszy
      możliwy błąd.
- **Do zrobienia:** przy zdarzeniu z watchera porównać `mtime` i treść otwartej notatki z jej
      buforem.
  - bufor czysty → przeładować i odświeżyć edytor,
  - bufor brudny → nie nadpisywać: zapisać kopię konfliktu (`nazwa (konflikt <data>).md`) i
    pokazać to w nagłówku,
  - własne zapisy już są filtrowane (`suppressUntil`, `lastSelfWriteTimestamps` w `NoteStore`) —
    mechanizm istnieje, brakuje reakcji na *cudzą* zmianę.
- **Kryterium:** check w `NotesMiniChecks`, który zapisuje plik z zewnątrz i sprawdza oba warianty.
- **Koszt:** ~1 h.

### 2. Bezpiecznik zapisu przy ciągłym pisaniu

- [x] Zrobione: `scheduleSave` liczy budżet od pierwszej edycji (`maxSaveDelay`).
- `NoteStore.saveDelay = .milliseconds(450)` i `scheduleSave` **przesuwa** zapis każdym
      znakiem.
- **Skutek:** 5 minut pisania bez pauzy dłuższej niż pół sekundy = do pliku nie poszło nic
      (do `resignKey` / ukrycia panelu / zamknięcia).
- **Do zrobienia:** maksymalny wiek brudnego bufora. `hasPendingSaves` już istnieje — wystarczy
      timer sprawdzający „brudne dłużej niż 4 s → `flushAll()`".
- **Kryterium:** check, który symuluje zapisy co 100 ms przez 5 s i sprawdza, że plik ma treść.
- **Koszt:** ~20 min.

### 3. Nieudana rejestracja skrótu globalnego jest cicha

- [ ] `registerHotkey()` w `AppDelegate` przy `register() == false` robi tylko `NSLog`.
- **Skutek:** ⌥N bywa zajęte przez inną aplikację. Wtedy Notes Mini nie ma Docka, nie ma okna
      i nie reaguje na skrót — wygląda na martwą.
- **Do zrobienia:** pozycja w menu „Pokaż notatnik (skrót zajęty)" + przy pierwszym niepowodzeniu
      otworzyć Ustawienia z podświetlonym polem skrótu; pozwolić wpisać inny.
- **Kryterium:** rejestracja skrótu, który jest już zajęty, kończy się komunikatem w UI.
- **Koszt:** ~30 min.

---

## P1 — brakujące funkcje

### 4. Drag & drop: zarejestrowany, ale nieobsłużony

- [ ] `MarkdownEditor` woła `registerForDraggedTypes([.fileURL, .string])`, ale w całym projekcie
      nie ma `draggingEntered` ani `performDragOperation`.
- **Skutek:** upuszczenie pliku na panel nic nie robi, mimo że kod sugeruje inaczej.
- **Do zrobienia:** upuszczenie `.md` → otwórz notatkę; upuszczenie obrazu → patrz punkt 7;
      upuszczenie innego pliku → wstaw link. Albo usunąć rejestrację i nie udawać funkcji.
- **Koszt:** ~1–2 h.

### 5. Kosz bez powrotu

- [ ] Jest `.trash/` i `store.trash(note)`, nie ma żadnego UI przywracania.
- **Skutek:** notatka znika i wraca tylko przez Findera.
- **Do zrobienia:** sekcja „Kosz" w nakładce ⌘P (lista + „Przywróć" + „Usuń trwale").
- **Koszt:** ~1 h.

### 6. ⌘F — wyszukiwanie w notatce

- [ ] `MarkdownEditor`: `usesFindPanel = false`, więc wyszukiwania w treści nie ma wcale.
- **Uwaga:** edytor pracuje na *display stringu* z mapowaniem do surowego Markdownu, więc
      wyszukiwanie musi iść przez to mapowanie, inaczej trafi w niewidoczne znaczniki.
- **Do zrobienia:** pasek szukania nad edytorem albo własny panel na `displayToRaw`.
- **Koszt:** ~2 h (głównie mapowanie).

### 7. Obrazki

- [ ] `importsGraphics = false`; wklejenie zrzutu ekranu wstawia nic.
- **Do zrobienia:** `attachments/` obok notatki, zapis PNG/JPG, wstawienie `![](attachments/…)`,
      blok obrazu w `BlockRenderer`.
- **Koszt:** ~4 h.

### 8. Tabele

- [ ] `MarkdownParser` i `BlockRenderer` nie znają tabel.
- **Koszt:** ~4 h.

### 9. Angielski interfejs

- [ ] Wszystkie stringi są po polsku na sztywno (menu, nakładki, ustawienia).
- **Do zrobienia:** `NSLocalizedString` + `pl.lproj` / `en.lproj`, język z systemu.
- **Koszt:** ~3 h, ale podwaja publikę publicznego repo.

### 10. Wydanie, które przejdzie Gatekeepera

- [ ] `Scripts/build.sh` podpisuje ad-hoc (`--sign -`) — na innym Macu system zablokuje aplikację.
- **Do zrobienia:** workflow na GitHuba (macOS runner): build → zip → Release na tagu, plus
      instrukcja „prawy klik → Otwórz" dla wersji bez notaryzacji.
- **Koszt:** ~1–2 h.

---

## P2 — pozycjonowanie i higiena repo

### 11. Liczby „ultra lekki" do README

- [ ] Zmierzyć i wpisać: pamięć w spoczynku, czas renderu 78 KB (`45,87 ms` — już mierzone
      w checkach), rozmiar bundla (`1,2 MB`), czas startu.
- **Dlaczego:** to jedyny wyróżnik projektu i jednocześnie regresja — pojawienie się zależności
      natychmiast psuje liczby.
- **Koszt:** ~1 h.

### 12. Higiena metadanych

- [ ] `VERSION="1.0"` zahardkodowane w `build.sh` → brać z taga (`git describe`).
- [ ] Bundle id `pl.milosz.notesmini` jest prywatny → `app.hubso.notesmini`.
      **Uwaga:** zmiana zeruje preferencje (pozycja panelu, czcionka, skrót, LaunchAgent);
      folder notatek zostaje, więc treść jest bezpieczna.
- [ ] `CHANGELOG.md` prowadzony ręcznie z historii commitów.
- **Koszt:** ~30 min.

### 13. CI z checkami

- [ ] `.github/workflows/checks.yml`: `macos-14`, `swift build -c release`,
      `swift run -c release NotesMiniChecks` przy pushu i PR.
- **Koszt:** ~20 min.

### 14. Dostępność

- [ ] `OverlayRowView` i komórki emoji to własne widoki bez roli AX — VoiceOver ich nie widzi
      (klawiatura działa: strzałki + ↩).
- **Do zrobienia:** `setAccessibilityRole(.button)`, label = tytuł + podtytuł, `isAccessibilityElement`.
- **Koszt:** ~1 h.

### 15. Domyślny folder poza `~/Documents`

- [ ] `Prefs.defaultFolder` = `~/Documents/Notes` → przy pierwszym uruchomieniu macOS pyta o dostęp
      do Dokumentów (TCC).
- **Do zrobienia:** `~/Notes` jako domyślny albo wybór folderu przy pierwszym starcie.
- **Koszt:** ~30 min.

---

## Poza zakresem (świadomie)

- iCloud sync — pliki `.md` i tak się synchronizują tym, czego już używasz.
- Baza danych, pluginy, taby, tryb rich-text, własny format plików.
- Każda z tych rzeczy zamienia 1,2 MB w kilkadziesiąt i odbiera jedyną przewagę projektu.

---

## Znana luka: brak testów UI

`NotesMiniChecks` nie widzi kodu aplikacji (osobny target), a CommandLineTools nie ma XCTest.
Dlatego zachowania UI (`hitTest` nagłówka, ramki, pełny ekran) weryfikuję jednorazowymi sondami
wstrzykiwanymi do działającej aplikacji i usuwam je przed commitem — działają, ale nie zostają
w repo.

**Realne rozwiązanie:** podział na bibliotekę `NotesMiniUI` + cienki executable i
`@testable import` w checkach. Koszt: `public` w kilku typach. Wtedy testy UI byłyby trwałe.

---

## Ostatnio zrobione

- tekst kasujący się sam: `NoteStore` działa tylko na głównym wątku i trzyma jeden obiekt `Note` na
  plik (wcześniej reload budował kopie, a `storeDidChange` z kolejki w tle podmieniał tekst edytora
  nieaktualną kopią albo wywracał aplikację),
- blokada rozmiaru okna: długi tytuł w `⌘P` rozpychał panel (580 → 1242) i trzymał go na stałe,
- `show()` na widocznym panelu nie rusza już ramki, karetki ani historii cofania,
- domyślny skrót `⌃⌥N`: `⌥N` zabierało `ń` w całym systemie,
- `Scripts/check-e2e.sh`: testy działającej aplikacji (klawiatura, przeciąganie okna); to częściowo
  domyka lukę opisaną wyżej w „brak testów UI",
- przeciąganie panelu za nagłówek (`hitTest` + `performDrag`),
- nakładki z własnym tłem (`⌘P`, `⌘K`),
- prawdziwa belka: światła, zmiana rozmiaru z krawędzi, automatyczna wysokość wyłączana ręcznym
  przeciągnięciem,
- pełny ekran z chowaniem świateł (zielony przycisk, Esc wychodzi),
- efekt szkła (rim, cień, obwódka, promień 17),
- naprawa podwójnego błędu nakładki: niejednoznaczny separator (pionowa linia) + okno zwężane
  przez Auto Layout (430 → 188),
- README + licencja MIT + publikacja repo.
