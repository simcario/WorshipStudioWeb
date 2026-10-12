# Analisi di SongbookPro 26.0.2 (Windows)

Analisi statica del pacchetto installato `765JonathanSalmon.SongbookPro_26.0.2.0_x64`, usata per decidere le funzioni di WorshipStudio. L'app non è stata eseguita: tutto ciò che segue viene dai file distribuiti. Nessun codice o risorsa dell'originale è stato copiato.

## Metodo e limiti

- **REA** `analyze_javascript_application` sulla web-app incorporata (`data/flutter_assets/assets/web`): 4 file JS analizzati, 373 risultati. Copertura parziale: l'analisi semantica di `vendor.js` e del worker ha esaurito la memoria.
- **Stringhe dello snapshot Dart** (`data/app.so`, 19,5 MB): lo snapshot non è offuscato, quindi nomi di librerie, classi, SQL e chiavi di traduzione sono leggibili.
- **Non fatto**: decompilazione del codice nativo (Ghidra non è configurato in REA e richiede JDK 21) e osservazione dell'app in esecuzione. Il comportamento a runtime è quindi dedotto, non osservato.

## Architettura osservata

- App **Flutter** (Dart AOT) con plugin nativi: SQLite, pdfium, audio (SoLoud, just_audio), Bluetooth LE, MIDI, WebView2, Sentry.
- Sorgenti in `package:songbookpro/`: 358 librerie, organizzate in `DAL/` (database), `models/` (importer, exporter, renderer, sync, stampa), `controllers/`, `views/`, `modules/` (strumenti, media, MIDI).
- Stato con GetX; archivio locale SQLite più Hive; client GraphQL per il servizio a pagamento "Groups".
- **SongbookPro Manager**: web-app Quasar/Vue servita dall'app sulla rete locale, con rotte `/edit`, `/arrange`, `/organise` e API `/api/editor/songs`, `/api/arrange/sets`, `/api/arrange/setItem`, `/api/arrange/templates`, `/api/organise/upload`, `/api/settings`.

## Modello dati (SQL nello snapshot)

| Tabella | Campi principali |
| --- | --- |
| `Songs` | name, author, subTitle, content, key, KeyShift, Capo, TempoInt, timeSig, Duration, _tags, _folders, Copyright, Url, NotesText, NotesDraw, SectionOrder, SongNumber, Zoom, type, ParentId, locked, Deleted, SyncId |
| `Sets` | name, date, pinned, Deleted, SyncId |
| `SetItems` | SetId, SongId, Order, keyOfset, Capo, NotesText, SectionOrder, ItemType, Content |
| `Folders` | Name, Order |
| `LyricFormat2` | stile per sezione: colori chiaro/scuro, grassetto, corsivo, rientro |
| `Templates`, `Pedals`, `PdfCache` | modelli di nota, azioni dei pedali, cache PDF |
| `groups_*` | copia locale delle librerie condivise |

La tonalità è un intero: 0 = A … 11 = Ab per le maggiori, 12 = F#m … 15 = Am … 23 = Fm per le minori (dal selettore del Manager). `type = 1` indica un brano ChordPro.

## Funzioni individuate

- **Formati**: file associati `.cho .crd .chordpro .chopro .chord .pro .txt .onsong .docx .pdf .jpg .png .sbp .sbpbackup .onsongarchive`; export in ChordPro, PDF, SBP e riepilogo scaletta.
- **ChordPro**: direttive standard di sezione, commento e metadati, più le estensioni `x_sbp_hide`, `x_sbp_show`, `x_sbp_tag(s)`; conversione tra "accordi sopra il testo" e ChordPro.
- **Visualizzazione**: trasposizione, capotasto, notazione standard/latina/tedesca/Nashville, dimensione e colore accordi, modalità scorrimento/pagine/adatta alla pagina, ordine delle sezioni (`V1 C1 V2 C1 B1 C1`).
- **Dal vivo**: scorrimento automatico con ritardo, metronomo, zoom, note testuali e a mano libera, basi audio, accordatore, diagrammi accordi (chitarra, ukulele, banjo, mandolino, piano).
- **Pedali**: avanti/indietro pagina e brano, scorrimento, trasposizione, metronomo, schermo intero; anche via MIDI.
- **Scalette**: fissaggio, duplicazione, mescolamento, note, timer, modelli, stampa.
- **Rete**: sincronizzazione Dropbox, Google Drive, OneDrive, WebDAV; ricerca brani su Ultimate Guitar, WorshipTogether, E-Chords; librerie condivise "Groups".
- **Lingue**: en, da, de, es, fr, hu, it, pt-BR.

## Cosa copre WorshipStudio

| Area | Stato |
| --- | --- |
| Brani ChordPro, sezioni, ordine sezioni, `x_sbp_hide/show` | fatto |
| Trasposizione, capotasto, notazioni, rilevamento tonalità | fatto |
| Scalette con tonalità per elemento, note, fissaggio, duplicazione | fatto |
| Scorrimento automatico, metronomo, zoom, schermo intero, tasti/pedali | fatto |
| Cartelle, etichette, ricerca, ordinamento | fatto |
| Import ChordPro / testo / OnSong, backup | fatto |
| Import `.sbp` | sperimentale: la struttura del file è dedotta dallo schema, non verificata su un archivio reale |
| PDF e immagini, stampa, note a mano libera, diagrammi accordi, accordatore | non incluso |
| Basi audio, MIDI, sincronizzazione cloud, ricerca online, Groups | non incluso |
| Semantica esatta di `x_sbp_hide/show` e stili per sezione | dedotta dai nomi, non osservata |
