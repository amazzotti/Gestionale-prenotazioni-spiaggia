# Prenotazioni-spiaggia

[![CI](https://github.com/amazzotti/Gestionale-prenotazioni-spiaggia/actions/workflows/ci.yml/badge.svg)](https://github.com/amazzotti/Gestionale-prenotazioni-spiaggia/actions/workflows/ci.yml)

Gestionale per le prenotazioni di ombrelloni e tende dello stabilimento Bagni Carla 98 (Riccione).
Lo usa il personale dello stabilimento da telefono Android.

App Flutter (`applicazione_gestionale/`) con Firebase Authentication e Cloud Firestore.

## Anteprime

| Home | Mappa di oggi | Mappa di un periodo |
|---|---|---|
| ![Home](screenshots/01_home.png) | ![Mappa di oggi](screenshots/02_mappa_oggi.png) | ![Mappa periodo](screenshots/03_mappa_periodo.png) |

| Scheda prenotazione | Prenotazioni di un ombrellone | Annulla eliminazione |
|---|---|---|
| ![Scheda](screenshots/04_scheda_prenotazione.png) | ![Elenco](screenshots/05_elenco_ombrellone.png) | ![Annulla](screenshots/06_annulla_eliminazione.png) |

| Arrivi e partenze | Incassi e statistiche | Telefono nuovo |
|---|---|---|
| ![Arrivi](screenshots/07_arrivi.png) | ![Statistiche](screenshots/08_statistiche.png) | ![Telefono in attesa](screenshots/09_attesa_approvazione.png) |

| Telefoni (approvazione) | Planner | Planner: sposta |
|---|---|---|
| ![Telefoni](screenshots/10_telefoni.png) | ![Planner](screenshots/11_planner.png) | ![Planner sposta](screenshots/12_planner_sposta.png) |

Le anteprime (dati di esempio, formato telefono) si rigenerano con:
`cd applicazione_gestionale` e poi `flutter test screenshots_test --update-goldens`.

## Funzioni

- **Mappa della spiaggia** per settori (Mare, Tende, Dietro), con passerelle e zoom.
  - Si apre sul giorno di oggi. Le frecce ◀ ▶ cambiano giorno, **OGGI** torna a oggi, toccando la data si sceglie un periodo.
  - Legenda sempre visibile: verde = libero, rosso = occupato nel periodo.
    Sul quadrato compaiono il periodo della prenotazione, **€** se c'è da incassare e **✓** se il cliente è arrivato.
  - **Pressione lunga** su un ombrellone: chi c'era **prima**, chi c'è **nel periodo** e chi arriva **dopo**,
    con i giorni liberi in mezzo, più tutta la stagione.
- **Planner** (dalla home o dall'icona calendario nella mappa): una riga per ombrellone, una colonna per giorno.
  Le prenotazioni sono barre con il nome: rosse quelle del periodo scelto, grigie quelle prima e dopo.
  Tocco su una barra per modificarla, su uno spazio vuoto per prenotare. Per **spostare** si tocca la barra,
  "Sposta" e poi la riga di destinazione: le righe libere per quelle date diventano verdi.
- **Scheda prenotazione**: nome con completamento automatico dai clienti già visti, telefono con tasti **Chiama** e
  **WhatsApp** (con il riepilogo della prenotazione già scritto), date, prezzo, acconto, saldato, note.
  Il riquadro **Prima / Dopo** mostra chi c'è su quell'ombrellone prima e dopo le date scelte.
  Si può spostare su un altro ombrellone o allungare altrove. Mostra chi ha fatto l'ultima modifica.
- **Controllo doppie prenotazioni**: prima di ogni salvataggio l'app ricontrolla sul server che l'ombrellone sia libero,
  così due telefoni non possono prenotare lo stesso posto negli stessi giorni.
- **Eliminazione con conferma** e tasto **ANNULLA** per qualche secondo.
- **Arrivi e partenze** del giorno, con spunta di arrivo, importo da incassare e contatti.
- **Incassi e statistiche**: occupazione per settore, incassato, da incassare ed elenco di chi deve ancora pagare.
- **Ricerca** per nome, telefono o numero di ombrellone.
- **Editor mappa** e **Reset stagione**: solo per gli admin. L'editor non permette di togliere un ombrellone
  che ha prenotazioni.

## Sicurezza (senza login)

- **Nessuna schermata di login e nessuna password.** Ogni telefono entra in Firebase da solo, in modo
  invisibile (accesso anonimo), e riceve un codice univoco.
- Un telefono nuovo mostra "in attesa di approvazione". Un telefono admin lo approva da **Telefoni**
  e da quel momento l'app si apre direttamente. Si può togliere l'accesso in qualsiasi momento.
- Le [regole Firestore](firestore.rules) fanno vedere i dati **solo ai telefoni approvati** (collezione
  `dispositivi`) e controllano anche i dati: campi ammessi, tipi, lunghezze, importi non negativi,
  fine dopo l'inizio. Un estraneo che si procura l'app non vede niente.
- "Ultima modifica" mostra il nome del telefono (es. "Telefono di mamma").
- L'app scarica solo le prenotazioni della stagione in corso, con un solo collegamento condiviso, per restare
  lontano dai limiti del piano gratuito di Firebase. Lo spazio (1 GB gratis) non è un problema.

## Configurazione Firebase (una volta sola)

1. **Authentication → Sign-in method**: attiva **Anonimo** (Anonymous).
2. Installa la nuova versione dell'app sul **tuo** telefono e aprila: scrivi un nome (es. "Telefono di Ale")
   e premi **Chiedi l'accesso**.
3. **Firestore Database → Dati**: apri la collezione `richieste`, trova il documento con il nome del tuo telefono
   e **copia il suo ID** (la lunga sequenza di lettere e numeri).
4. Crea la collezione `dispositivi` con un documento che ha **come ID quello copiato** e i campi:
   - `nome` (stringa) = il nome del telefono
   - `ruolo` (stringa) = `admin`
5. L'app sul tuo telefono si sblocca da sola. Al primo avvio converte anche le prenotazioni salvate in formati
   vecchi (una volta sola).
6. Sugli altri telefoni installa l'app e premi **Chiedi l'accesso**; tu li approvi dalla schermata **Telefoni**.
7. Quando tutti i telefoni sono approvati: **Firestore Database → Regole**, incolla il contenuto di
   [`firestore.rules`](firestore.rules) e premi *Pubblica*.

Se un telefono reinstalla l'app o cancella i dati dell'app, riceve un codice nuovo e va approvato di nuovo.

## Ruoli

| Ruolo | Prenotazioni, arrivi, incassi | Editor mappa, reset, telefoni |
|---|---|---|
| `staff` (Solo prenotazioni) | ✅ | — |
| `admin` (Famiglia: tutto) | ✅ | ✅ |

## Versioni e rilasci

La versione compare in fondo alla schermata principale (es. **V1.0.0**). Per un rilascio ufficiale,
dal branch `main` e con tutto salvato, fai doppio clic su **`rilascia.bat`** (oppure lancialo dal terminale):

| Comando | Effetto |
|---|---|
| `rilascia.bat` | V1.0.0 → V1.0.1 (correzioni) |
| `rilascia.bat minor` | V1.0.0 → V1.1.0 (nuove funzioni) |
| `rilascia.bat major` | V1.0.0 → V2.0.0 (cambiamenti grossi) |
| `rilascia.bat prova` | mostra solo la prossima versione |

Lo script aumenta la versione, esegue i test, crea l'APK in `rilasci/`, fa commit, tag `vX.Y.Z` e push.

## Struttura del codice

| File | Cosa contiene |
|---|---|
| `lib/models.dart` | Prenotazione, ombrellone, settore |
| `lib/availability.dart` | Logica pura: disponibilità, conflitti, arrivi, ricerca, statistiche, telefono |
| `lib/booking_repository.dart` | Lettura delle prenotazioni (un solo listener) e migrazione dati |
| `lib/booking_service.dart` | Scritture: validazione, controllo conflitti sul server, chi ha modificato |
| `lib/device_service.dart`, `lib/auth_gate.dart`, `lib/devices_screen.dart` | Accesso senza login: approvazione dei telefoni |
| `lib/*_screen.dart`, `lib/booking_form.dart`, `lib/umbrella_timeline_view.dart` | Schermate (mappa, planner, scheda, arrivi, statistiche...) |

## Sviluppo e test

```bash
cd applicazione_gestionale
flutter pub get
flutter analyze
flutter test
```

I test coprono la logica, il modello, repository e service (con un Firestore finto) e le schermate principali.

Test delle regole Firestore (servono Node.js e Java 21), dalla cartella principale:

```bash
npm install --prefix firestore-tests
npx firebase-tools emulators:exec --only firestore --project demo-spiaggia "npm --prefix firestore-tests test"
```

A ogni push GitHub Actions esegue analisi, test Flutter e test delle regole.
