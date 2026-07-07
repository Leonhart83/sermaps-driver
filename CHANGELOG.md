# Changelog

Le note di ogni versione. La sezione della versione taggata viene usata
automaticamente come descrizione della Release su GitHub.

## v1.1.7

- Correzione del numero di build (versionCode) generato dalla pipeline: ora è
  ricavato dalla versione ed è sempre crescente, evitando che un aggiornamento
  venga rifiutato da Android come "downgrade".

## v1.1.6

- Correzione dettatura vocale: la lingua italiana viene ora scelta tra quelle
  effettivamente disponibili sul dispositivo e gli eventuali errori del
  microfono vengono mostrati a schermo.
- La schermata iniziale (splash) mostra la versione reale dell'app.
- Aggiornamento automatico: quando è disponibile una versione più recente su
  GitHub, viene scaricata e installata all'avvio senza chiedere conferma.
- La versione di app e guida viene allineata automaticamente a ogni release.

## v1.1.5

- La schermata "Informazioni" mostra ora la versione reale dell'app.
- L'avviso di aggiornamento ha un pulsante "Scarica dal sito" e, se il download
  automatico fallisce, propone il download manuale dalla pagina release.
- Mappa in tema scuro più leggibile (strade e autostrade più contrastate).
- Migliorie interne e test automatici sulla logica di orari e ordinamento.

## v1.1.4

- Correzione: dopo aver aggiornato, l'app non richiede più di nuovo lo stesso
  aggiornamento. L'avviso ricompare solo quando esce una versione più nuova.

## v1.1.3

- Orari dei punti vendita: per ogni tappa puoi indicare apertura, chiusura ed
  eventuale pausa pranzo. L'auto-ordina ti porta a ogni negozio quando è aperto
  e rimanda le tappe a cui arriveresti a saracinesca abbassata.
- Sulla tappa un badge mostra gli orari, "Chiuso all'arrivo" (in rosso) o
  "Orari non definiti".
- Badge del tipo intervento (LIS, IGT, ...) più visibile (pieno e colorato).
- Mappa più leggibile: strade con contorni, arterie evidenziate e la tua
  posizione ora ben distinguibile (niente più zoom eccessivo).
- Spostamento manuale delle tappe più preciso con liste lunghe (scorrimento più
  lento durante il trascinamento).

## v1.1.2

- L'avviso di aggiornamento non compare più a ogni avvio: se scegli "Più tardi"
  quella versione non viene più richiesta (finché non ne esce una più nuova).
- Note di aggiornamento più leggibili nell'avviso in-app (rimosse formattazione
  markdown e righe tecniche); le descrizioni delle Release ora arrivano dal
  CHANGELOG del progetto.

## v1.1.1

- Manutenzione: prima release pubblicata automaticamente dalla pipeline
  (GitHub Actions). Nessuna modifica funzionale rispetto alla 1.1.0.

## v1.1.0

- Dettatura vocale degli indirizzi: tocca il microfono e detta l'indirizzo. I
  numeri civici detti a parole (es. "centotrentotto") vengono convertiti in
  cifre e i suggerimenti compaiono mentre parli, con indicatore "In ascolto".
- Dettagli intervento per ogni tappa: tipo (LIS, IGT, SISAL, TLC, GBO, GLOBAL),
  note e pausa pranzo. Vengono chiesti automaticamente quando aggiungi un
  indirizzo; puoi premere "Salta" e restano come "Non definito".
- Tipo intervento e nota mostrati in alto a destra sulla tappa; badge di stato
  "Non definito" / "Pausa non definita" per vedere subito cosa manca.
- Ordinamento automatico che evita di arrivare durante la pausa pranzo,
  rimandando la tappa dopo la riapertura.
- Gli avvisi in-app (es. "Tappa eliminata") ora si chiudono da soli.
- Aggiornamento in-app: l'app avvisa quando è disponibile una nuova versione e
  la installa con un tocco.
