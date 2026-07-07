# Changelog

Le note di ogni versione. La sezione della versione taggata viene usata
automaticamente come descrizione della Release su GitHub.

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
