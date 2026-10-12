# WorshipStudio

Gestore di brani con accordi e scalette per suonare dal vivo. È una PWA scritta in Flutter: gira nel browser su desktop e mobile, si installa come app e funziona offline. I dati restano sul dispositivo (IndexedDB).

Le funzioni ricalcano quelle di SongbookPro, analizzato in [REVERSE_ENGINEERING.md](REVERSE_ENGINEERING.md); il codice è scritto da zero.

## Avvio

```
flutter pub get
flutter run -d chrome                 # sviluppo

flutter build web --release --no-web-resources-cdn
node tool/postbuild.js                # obbligatorio: prepara la cache offline
node tool/serve.js 8080               # prova locale su http://localhost:8080
```

`tool/postbuild.js` scrive in `build/web/sw.js` l'elenco dei file della build: senza questo passo l'app non parte offline.

Per pubblicarla basta copiare `build/web` su un hosting statico **HTTPS** (richiesto per installazione e service worker). Se non è servita dalla radice del dominio, aggiungi `--base-href /percorso/` alla build.

## Cosa fa

- **Brani** in ChordPro: accordi sopra il testo, sezioni, commenti, tablature. Accetta anche testo con gli accordi sulla riga sopra e intestazioni tipo `Verse 1:` o `[Chorus]`. Nell'editor si sceglie se scrivere in ChordPro o con gli accordi sopra il testo; il brano passa da una forma all'altra.
- **Tonalità**: trasposizione, capotasto, rilevamento automatico, notazione standard, latina, tedesca o Nashville.
- **Scalette**: data, ordine a trascinamento, note, tonalità e capotasto diversi per scaletta, navigazione precedente/successivo.
- **Dal vivo**: scorrimento automatico, metronomo, zoom, schermo intero, schermo sempre acceso, tasti freccia / Pag↑↓ (pedali Bluetooth).
- **Libreria**: ricerca su titolo, artista, etichette e testo; cartelle, etichette, ordinamento.
- **Import**: `.cho .chordpro .crd .pro .txt .onsong`, backup `.wsbackup` e, in via sperimentale, archivi `.sbp` di SongbookPro.
- **Export**: brano in ChordPro, scaletta o intera libreria come `.wsbackup`.
- Interfaccia in italiano e inglese, tema chiaro/scuro.

## Struttura

| Percorso | Contenuto |
| --- | --- |
| `lib/music/` | parser ChordPro, trasposizione, notazioni, rilevamento tonalità |
| `lib/data/` | stato dell'app e persistenza (sembast), import/export, brani demo |
| `lib/ui/` | libreria, vista brano, editor, impostazioni |
| `lib/platform/` | API del browser (download, audio, schermo intero, wake lock) |
| `web/sw.js` | service worker per l'uso offline |
| `test/` | test di parser, trasposizione, import, stato e layout |
