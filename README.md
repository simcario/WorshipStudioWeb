# WorshipStudio

Gestore di brani con accordi e scalette per suonare dal vivo. È una PWA scritta in Flutter: gira nel browser su desktop e mobile, si installa come app e funziona offline. I dati sono sul dispositivo (IndexedDB); accedendo con Google vengono anche sincronizzati con Firebase e condivisi con i gruppi.

Le funzioni ricalcano quelle di SongbookPro, analizzato in [REVERSE_ENGINEERING.md](REVERSE_ENGINEERING.md); il codice è scritto da zero.

## Avvio

```
flutter pub get
flutter run -d chrome                 # sviluppo

flutter build web --release --no-web-resources-cdn
node tool/postbuild.js                # obbligatorio: prepara la cache offline e copia la build in server/public
node tool/serve.js 8080               # prova locale senza backend su http://localhost:8080
```

`tool/postbuild.js` scrive in `build/web/sw.js` l'elenco dei file della build (senza questo passo l'app non parte offline) e copia la build in `server/public`, da dove la serve il backend.

## Cloud: Firebase

Progetto Firebase `worshipstudioweb` (configurazione web in `lib/firebase_options.dart`).

- **Accesso** con Google (Firebase Authentication).
- **Sincronizzazione**: la libreria resta sul dispositivo; le modifiche vengono messe in coda e scambiate con Firestore all'apertura dell'app, periodicamente o in entrambi i casi. La scelta vale per tutti gli utenti e si fa in *Account e gruppi → Amministrazione*; il primo utente che la apre diventa amministratore dell'app. Vince la modifica più recente; le eliminazioni restano in Firestore come documenti `deleted: true`.
- **Gruppi**: ogni gruppo ha una sua libreria di brani e scalette. Gli amministratori invitano via email, nominano altri amministratori, rimuovono membri e decidono se anche i membri possono modificare. L'invitato accede con l'account Google di quell'indirizzo e accetta l'invito. Dal menu di un brano o di una scaletta, *Copia in…* lo porta da una libreria all'altra.
- **Backend** (`server/`, Node + Express su Firebase App Hosting): serve la PWA ed espone `/api` per gruppi, inviti e invio delle email. I gruppi si modificano solo da lì; brani e scalette sono letti e scritti dall'app direttamente su Firestore, secondo `firestore.rules`.

| Firestore | Contenuto |
| --- | --- |
| `users/{uid}/songs`, `sets`, `folders` | libreria personale |
| `groups/{id}` | nome, membri, ruoli, inviti in attesa |
| `groups/{id}/songs`, `sets` | libreria del gruppo |
| `invites/{id}` | inviti (solo backend) |
| `config/app` | ricorrenza della sincronizzazione e amministratori dell'app |

### Prima configurazione (una volta)

1. Console Firebase: passa il progetto al piano **Blaze** (richiesto da App Hosting), crea il database **Firestore**, abilita il provider **Google** in Authentication.
2. `firebase deploy --only firestore` pubblica regole e indici.
3. `firebase apphosting:backends:create --backend worshipstudio --root-dir server` crea il backend (senza collegare GitHub: il codice si carica dal PC).
4. In Authentication → Impostazioni → Domini autorizzati aggiungi il dominio del backend (`…hosted.app`).
5. Facoltativo, per l'invio automatico degli inviti: configura un account SMTP in `server/apphosting.yaml`. Senza, l'app mostra all'amministratore il testo dell'invito da spedire a mano.

### Pubblicazione

```
flutter build web --release --no-web-resources-cdn
node tool/postbuild.js
firebase deploy --only apphosting
```

### Prova locale con il backend

```
gcloud auth application-default login   # una volta: credenziali per Firestore
cd server && npm install && node index.js
```

Poi apri http://localhost:8080 (`localhost` è già tra i domini autorizzati di Firebase Authentication).

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
| `lib/data/` | stato dell'app e persistenza (sembast), sincronizzazione cloud, import/export, brani demo |
| `lib/ui/` | libreria, vista brano, editor, impostazioni, account e gruppi |
| `lib/platform/` | API del browser (download, audio, schermo intero, wake lock) |
| `web/sw.js` | service worker per l'uso offline |
| `server/` | backend per Firebase App Hosting |
| `firestore.rules` | chi può leggere e scrivere cosa su Firestore |
| `test/` | test di parser, trasposizione, import, stato e layout |
