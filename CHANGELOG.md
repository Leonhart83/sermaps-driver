# Changelog

Le note di ogni versione. La sezione della versione taggata viene usata
automaticamente come descrizione della Release su GitHub.

## v1.1.12

- Il pannello delle tappe si apre di più (la mappa occupa meno spazio), così
  l'elenco delle tappe è più leggibile.

## v1.1.11

- Dettatura vocale degli indirizzi corretta: la lingua italiana viene scelta tra
  quelle disponibili sul dispositivo e gli eventuali errori del microfono
  vengono mostrati a schermo.
- La schermata iniziale (splash) mostra la versione reale dell'app.
- Aggiornamento automatico da GitHub: all'avvio l'app scarica e installa da sola
  la versione più recente, senza loop. Se necessario chiede una volta il permesso
  "Installa app sconosciute"; una volta concesso gli aggiornamenti sono
  completamente automatici.
- Nel foglio "Dettagli intervento" i pulsanti "Salta" e "Conferma" non finiscono
  più dietro la barra di navigazione di sistema e sono più alti, quindi più
  visibili e facili da toccare.

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
