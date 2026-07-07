# SerMaps Driver

App Flutter (Android/iOS) per gestire più tappe di consegna/viaggio: incolla
indirizzi, ordinali per percorso ottimale / distanza / provincia, visualizzali
sulla mappa Google e avvia la navigazione con Google Maps.

## Funzionalità

- Mappa Google integrata con marcatori numerati per ogni tappa.
- Inserimento indirizzi in due modi:
  - **Aggiungi** singolo indirizzo con autocompletamento (Google Places).
  - **Incolla lista**: più indirizzi, uno per riga.
- Ordinamento delle tappe:
  - **Ottimizza percorso** (nearest-neighbor dalla tua posizione GPS).
  - **Distanza** dalla posizione attuale.
  - **Provincia / Città** (alfabetico).
- Riordino manuale con trascinamento (drag handle).
- Eliminazione tappa con swipe verso sinistra, oppure "Elimina tutte".
- Le tappe vengono **salvate** e mantenute alla riapertura dell'app.
- **Avvia**: apre Google Maps con tutte le tappe nell'ordine impostato.

## Configurazione della chiave Google Maps

Serve una chiave dalla [Google Cloud Console](https://console.cloud.google.com/)
con queste API abilitate:

- **Maps SDK for Android** (mappa nativa Android)
- **Maps SDK for iOS** (solo se compili per iPhone)
- **Geocoding API** (indirizzo → coordinate)
- **Places API** (autocompletamento)
- **Directions API** (ordinamento ottimale + distanze/tempi reali su strada)

### Android

1. Apri `android/local.properties`.
2. Sostituisci il valore di `MAPS_API_KEY`:

   ```
   MAPS_API_KEY=LA_TUA_CHIAVE
   ```

### Chiave per le chiamate HTTP (Geocoding/Places)

La stessa chiave serve anche al codice Dart. Passala all'avvio:

```bash
flutter run --dart-define=MAPS_API_KEY=LA_TUA_CHIAVE
```

oppure, per generare l'APK:

```bash
flutter build apk --release --dart-define=MAPS_API_KEY=LA_TUA_CHIAVE
```

In alternativa puoi incollarla nel valore di default in `lib/config.dart`.

### iOS (opzionale)

Apri `ios/Runner/Info.plist` e imposta `GMSApiKey` con la tua chiave.

## Avvio

```bash
flutter pub get
flutter run --dart-define=MAPS_API_KEY=LA_TUA_CHIAVE
```

## Generare l'APK (installazione senza cavo)

```bash
flutter build apk --release --dart-define=MAPS_API_KEY=LA_TUA_CHIAVE
```

L'APK viene generato in `build/app/outputs/flutter-apk/app-release.apk`.
Copialo sul telefono e installalo (abilita "Origini sconosciute").

### Firma con un keystore tuo (per distribuzione)

Senza configurazione, la release è firmata con la chiave di debug: va bene per
installarla sul tuo telefono, ma per distribuirla è meglio un keystore tuo.

1. Crea il keystore (ti verranno chieste delle password, digitale nel terminale):

   ```bash
   keytool -genkey -v -keystore sermaps-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias sermaps
   ```

2. Crea il file `android/key.properties` (non versionato):

   ```
   storePassword=LA_PASSWORD_DELLO_STORE
   keyPassword=LA_PASSWORD_DELLA_CHIAVE
   keyAlias=sermaps
   storeFile=../sermaps-release.jks
   ```

3. Ricompila: `flutter build apk --release --dart-define=MAPS_API_KEY=LA_TUA_CHIAVE`.

> Se usi un keystore tuo, aggiungi l'impronta **SHA-1** di quel certificato alle
> restrizioni della chiave Google (Maps SDK for Android), altrimenti la mappa
> resterà grigia. La ottieni con:
> `keytool -list -v -keystore sermaps-release.jks -alias sermaps`

## Note

- Google Maps supporta al massimo **10 tappe** per percorso (1 destinazione + 9
  intermedie). Oltre tale numero le tappe in eccesso vengono ignorate
  dall'avvio navigazione.
- Con "Ordina automaticamente" attivo, l'ordine delle tappe viene ottimizzato da
  Google (Directions API) per il percorso più breve dalla tua posizione; se la
  rete non è disponibile, si usa una stima locale in linea d'aria.
- Per i suggerimenti l'autocompletamento è limitato all'Italia
  (`components=country:it`); modificabile in `lib/services/places_service.dart`.
