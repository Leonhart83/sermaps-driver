import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, HapticFeedback;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../main.dart'
    show
        kBrandCopper,
        kBrandDark,
        themeModeNotifier,
        setThemeMode,
        accentColorNotifier,
        setAccentColor,
        kAccentColors;
import '../models/stop.dart';
import '../services/directions_service.dart';
import '../services/geocode_cache.dart';
import '../services/geocoding_service.dart';
import '../services/location_service.dart';
import '../services/maps_launcher.dart';
import '../services/route_optimizer.dart';
import '../services/storage_service.dart';
import '../services/update_service.dart';
import '../utils/marker_helper.dart';
import '../widgets/add_address_sheet.dart';
import '../widgets/stop_details_sheet.dart';
import 'guide_screen.dart';
import 'onboarding_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<Stop> _stops = [];
  GoogleMapController? _mapController;
  Position? _position;
  bool _busy = false;
  String? _statusMessage;

  /// Versione dell'app (es. "1.1.5"), caricata all'avvio per la schermata
  /// "Informazioni".
  String _appVersion = '';

  /// Timer che forza la chiusura della SnackBar corrente, anche quando sul
  /// dispositivo e attivo uno screen reader (in quel caso Flutter le terrebbe
  /// aperte a tempo indeterminato).
  Timer? _snackDismissTimer;

  /// Ordina automaticamente le tappe in base alla mia posizione.
  bool _autoOptimize = true;

  /// Riduce la mappa per dare piu spazio alla lista delle tappe.
  bool _mapCollapsed = false;

  /// Stili mappa (caricati da asset) per tema chiaro/scuro.
  String? _mapStyleLight;
  String? _mapStyleDark;

  /// Id della tappa selezionata (evidenziata sulla mappa).
  String? _selectedStopId;

  /// Risultato del calcolo percorso reale (distanza/tempo/tracciato).
  RouteResult? _route;
  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};
  final Map<String, BitmapDescriptor> _markerCache = {};

  /// Cache del percorso per evitare chiamate Directions ripetute identiche.
  final Map<String, RouteResult> _routeCache = {};

  /// Numero di chiamate Directions effettuate (per tenere d'occhio i costi).
  int _directionsCalls = 0;

  /// Metri percorsi e inizio del giro corrente (per il riepilogo finale).
  double _sessionMeters = 0;
  DateTime? _sessionStart;

  /// Tappe ancora da consegnare (in attesa).
  List<Stop> get _pendingStops =>
      _stops.where((s) => s.isPending).toList();

  /// Tappe completate (consegnate o fallite).
  List<Stop> get _completedStops =>
      _stops.where((s) => s.isCompleted).toList();

  /// Tappe attive e geolocalizzate (usate per percorso/mappa/navigazione).
  List<Stop> get _activeGeocoded =>
      _stops.where((s) => s.isPending && s.isGeocoded).toList();

  static const _initialCamera = CameraPosition(
    target: LatLng(41.9028, 12.4964),
    zoom: 5.5,
  );

  @override
  void initState() {
    super.initState();
    accentColorNotifier.addListener(_onAccentChanged);
    _init();
  }

  /// Quando cambia il colore accento, rigenera i marcatori colorati.
  void _onAccentChanged() {
    _markerCache.clear();
    _rebuildMapData();
  }

  Future<void> _init() async {
    final pkg = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _appVersion = pkg.version);
    _mapStyleLight = await rootBundle.loadString('assets/map/light.json');
    _mapStyleDark = await rootBundle.loadString('assets/map/dark.json');
    final saved = await StorageService.loadStops();
    final session = await StorageService.loadSession();
    if (mounted && saved.isNotEmpty) {
      setState(() {
        _stops.addAll(saved);
        _sessionMeters = session.$1;
        _sessionStart = session.$2;
      });
    }
    await _refreshLocation(silent: true);
    await _rebuildMapData();
    if (_activeGeocoded.isNotEmpty) {
      await _recomputeRoute();
    } else {
      _fitCamera();
    }
    // Controlla in background se c'è un aggiornamento su GitHub.
    _checkForUpdate();
  }

  /// Verifica gli aggiornamenti su GitHub e, se è disponibile una versione più
  /// recente, la scarica e installa automaticamente all'avvio, senza chiedere
  /// conferma. (Il prompt finale di installazione è quello di sistema Android
  /// e non può essere evitato.)
  ///
  /// L'aggiornamento automatico viene tentato UNA sola volta per versione: se
  /// l'installazione non viene completata (prompt di sistema annullato, permesso
  /// "installa app sconosciute" non concesso, ecc.) l'app non riprova a ogni
  /// avvio, evitando il loop. Resta comunque il download manuale dal sito.
  Future<void> _checkForUpdate() async {
    final info = await UpdateService.checkForUpdate();
    if (!mounted || info == null) return;
    // Evita il loop: non ritentare la stessa versione già gestita in automatico.
    final handled = await StorageService.getSkippedUpdateVersion();
    if (!mounted || handled == info.version) return;
    // Segna la versione come già tentata PRIMA del download/installazione.
    await StorageService.setSkippedUpdateVersion(info.version);
    if (!mounted) return;
    _showSnack('Aggiornamento ${info.version}: download in corso…');
    await _downloadAndInstall(info);
  }

  /// Apre la pagina delle release su GitHub (fallback allo scaricamento manuale).
  Future<void> _openReleasesPage() async {
    if (!AppConfig.hasGithubRepo) return;
    final uri = Uri.parse(
      'https://github.com/${AppConfig.githubRepo}/releases/latest',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Scarica l'APK della nuova versione mostrando l'avanzamento e avvia
  /// l'installazione al termine.
  Future<void> _downloadAndInstall(UpdateInfo info) async {
    final progress = ValueNotifier<int>(0);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Download in corso'),
        content: ValueListenableBuilder<int>(
          valueListenable: progress,
          builder: (_, value, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: value <= 0 ? null : value / 100),
              const SizedBox(height: 12),
              Text(value <= 0 ? 'Avvio…' : '$value%'),
            ],
          ),
        ),
      ),
    );
    try {
      OtaUpdate()
          .execute(info.apkUrl, destinationFilename: 'sermaps-update.apk')
          .listen(
        (event) {
          if (event.status == OtaStatus.DOWNLOADING) {
            progress.value = int.tryParse(event.value ?? '0') ?? 0;
          } else if (event.status == OtaStatus.INSTALLING) {
            if (mounted) Navigator.of(context, rootNavigator: true).pop();
          } else if (event.status != OtaStatus.DOWNLOADING) {
            if (mounted) {
              Navigator.of(context, rootNavigator: true).pop();
              _showUpdateFailed();
            }
          }
        },
        onError: (_) {
          if (mounted) {
            Navigator.of(context, rootNavigator: true).pop();
            _showUpdateFailed();
          }
        },
      );
    } catch (_) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        _showUpdateFailed();
      }
    }
  }

  /// Notifica di aggiornamento fallito con azione per scaricare dal sito.
  void _showUpdateFailed() {
    if (!mounted) return;
    _presentSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
        content: const Text('Aggiornamento non riuscito.'),
        action: SnackBarAction(
          label: 'SCARICA DAL SITO',
          onPressed: _openReleasesPage,
        ),
      ),
    );
  }

  // --------------------------------------------------------------- Posizione

  Future<void> _refreshLocation({bool silent = false}) async {
    try {
      final pos = await LocationService.getCurrentPosition();
      if (!mounted) return;
      setState(() => _position = pos);
      await _rebuildMapData();
    } catch (e) {
      if (!silent) _showSnack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  // ------------------------------------------------------------------ Tappe

  Future<void> _addAddresses(List<String> addresses) async {
    final cleaned =
        addresses.map((a) => a.trim()).where((a) => a.isNotEmpty).toList();
    if (cleaned.isEmpty) return;

    if (!AppConfig.hasApiKey) {
      _showSnack('Configura prima la chiave Google Maps.');
      return;
    }

    setState(() {
      _busy = true;
      _statusMessage = 'Ricerca indirizzi...';
    });

    int ok = 0;
    int failed = 0;
    final added = <Stop>[]; // tappe aggiunte, per chiedere poi i dettagli
    final remaining = <String>[]; // indirizzi non elaborati per un errore rete
    Object? networkError;
    for (var i = 0; i < cleaned.length; i++) {
      final addr = cleaned[i];
      final stop = Stop(address: addr);
      try {
        // 1) Prova dalla cache locale (funziona anche offline).
        var found = await GeocodeCache.fill(stop);
        // 2) Altrimenti interroga la Geocoding API e memorizza il risultato.
        if (!found) {
          found = await GeocodingService.geocode(stop);
          if (found) await GeocodeCache.store(addr, stop);
        }
        if (found) {
          _stops.add(stop);
          added.add(stop);
          ok++;
        } else {
          failed++;
        }
      } catch (e) {
        // Errore di rete/API: interrompi e proponi un nuovo tentativo.
        networkError = e;
        remaining.addAll(cleaned.sublist(i));
        break;
      }
    }

    await StorageService.saveStops(_stops);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _statusMessage = null;
    });

    if (_stops.where((s) => s.isGeocoded).isNotEmpty) {
      await _recomputeRoute(reorder: _autoOptimize);
    } else {
      await _rebuildMapData();
      _fitCamera();
    }

    if (networkError != null) {
      _showRetry(networkError, remaining);
    } else if (failed > 0) {
      _showSnack('$ok aggiunti, $failed non trovati.');
    } else if (ok > 0) {
      _showSnack('$ok ${ok == 1 ? 'tappa aggiunta' : 'tappe aggiunte'}.');
    }

    // Chiede tipo intervento e pausa pranzo per ogni tappa appena aggiunta.
    for (final s in added) {
      if (!mounted) break;
      await _editDetails(s, isNew: true);
    }
  }

  /// Mostra un avviso d'errore con azione "RIPROVA" per gli indirizzi rimasti.
  void _showRetry(Object error, List<String> remaining) {
    final msg = error.toString().replaceFirst('Exception: ', '');
    _presentSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
        content: Text(
          remaining.isEmpty
              ? msg
              : '$msg\n${remaining.length} indirizzi non elaborati.',
        ),
        action: remaining.isEmpty
            ? null
            : SnackBarAction(
                label: 'RIPROVA',
                onPressed: () => _addAddresses(remaining),
              ),
      ),
    );
  }

  Future<void> _removeStop(String id) async {
    final idx = _stops.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    final removed = _stops[idx];
    setState(() => _stops.removeAt(idx));
    await StorageService.saveStops(_stops);
    if (_stops.where((s) => s.isGeocoded).isNotEmpty) {
      await _recomputeRoute(reorder: _autoOptimize);
    } else {
      setState(() {
        _route = null;
        _polylines = {};
      });
      await _rebuildMapData();
      _fitCamera();
    }
    if (!mounted) return;
    _presentSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: const Text('Tappa eliminata.'),
        action: SnackBarAction(
          label: 'ANNULLA',
          onPressed: () => _restoreStopAt(idx, removed),
        ),
      ),
    );
  }

  /// Reinserisce una tappa eliminata nella sua posizione (azione "ANNULLA").
  Future<void> _restoreStopAt(int index, Stop stop) async {
    setState(() {
      final i = index.clamp(0, _stops.length);
      _stops.insert(i, stop);
    });
    await StorageService.saveStops(_stops);
    if (_activeGeocoded.isNotEmpty) {
      await _recomputeRoute(reorder: false, silentFail: true);
    } else {
      await _rebuildMapData();
      _fitCamera();
    }
  }

  Future<void> _clearAll() async {
    if (_stops.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminare tutte le tappe?'),
        content: const Text('Potrai annullare subito dopo, se è un errore.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    // Backup per l'eventuale annullamento.
    final backup = _stops.map((s) => Stop.fromJson(s.toJson())).toList();
    final backupMeters = _sessionMeters;
    final backupStart = _sessionStart;
    final count = backup.length;
    setState(() {
      _stops.clear();
      _route = null;
      _polylines = {};
      _markers = {};
      _sessionMeters = 0;
      _sessionStart = null;
    });
    await StorageService.saveStops(_stops);
    await StorageService.saveSession(0, null);

    if (!mounted) return;
    _presentSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        content: Text('$count ${count == 1 ? 'tappa eliminata' : 'tappe eliminate'}.'),
        action: SnackBarAction(
          label: 'ANNULLA',
          onPressed: () => _restoreAll(backup, backupMeters, backupStart),
        ),
      ),
    );
  }

  /// Ripristina le tappe dopo un'eliminazione (azione "ANNULLA").
  Future<void> _restoreAll(
    List<Stop> backup,
    double meters,
    DateTime? start,
  ) async {
    setState(() {
      _stops
        ..clear()
        ..addAll(backup);
      _sessionMeters = meters;
      _sessionStart = start;
    });
    await StorageService.saveStops(_stops);
    await StorageService.saveSession(meters, start);
    if (_activeGeocoded.isNotEmpty) {
      await _recomputeRoute(reorder: false, silentFail: true);
    } else {
      await _rebuildMapData();
      _fitCamera();
    }
  }

  Future<void> _reorderPending(int oldIndex, int newIndex) async {
    final wasAuto = _autoOptimize;
    final pending = _pendingStops;
    if (newIndex > oldIndex) newIndex--;
    final item = pending.removeAt(oldIndex);
    pending.insert(newIndex, item);
    final completed = _completedStops;
    setState(() {
      _stops
        ..clear()
        ..addAll([...pending, ...completed]);
      // Lo spostamento manuale ha la priorita: disattiva il riordino automatico.
      _autoOptimize = false;
    });
    await StorageService.saveStops(_stops);
    await _recomputeRoute(reorder: false, silentFail: true);
    if (wasAuto) {
      _showSnack('Ordine manuale: ordinamento automatico disattivato.');
    }
  }

  /// Sposta una tappa attiva dalla posizione [from] alla [to] (indici nella
  /// lista delle tappe da fare). Disattiva l'ordinamento automatico.
  Future<void> _movePending(int from, int to) async {
    final pending = _pendingStops;
    if (from < 0 || from >= pending.length) return;
    to = to.clamp(0, pending.length - 1);
    if (from == to) return;
    final wasAuto = _autoOptimize;
    final item = pending.removeAt(from);
    pending.insert(to, item);
    final completed = _completedStops;
    setState(() {
      _stops
        ..clear()
        ..addAll([...pending, ...completed]);
      _autoOptimize = false;
    });
    await StorageService.saveStops(_stops);
    await _recomputeRoute(reorder: false, silentFail: true);
    if (wasAuto) {
      _showSnack('Ordine manuale: ordinamento automatico disattivato.');
    }
  }

  // ----------------------------------------------------------- Calcolo rotta

  Future<void> _recomputeRoute({
    bool reorder = true,
    bool silentFail = false,
  }) async {
    // Azzera i dettagli di tratta precedenti per evitare valori obsoleti.
    for (final s in _stops) {
      s.legDistanceMeters = null;
      s.legDurationSeconds = null;
      s.etaMinutes = null;
    }
    if (_activeGeocoded.isEmpty) {
      setState(() {
        _route = null;
        _polylines = {};
      });
      await _rebuildMapData();
      _fitCamera();
      return;
    }

    if (_position == null) {
      await _refreshLocation();
      if (_position == null) {
        if (!silentFail) {
          _showSnack('Posizione non disponibile per il calcolo del percorso.');
        }
        await _rebuildMapData();
        _fitCamera();
        return;
      }
    }

    // Ordina "più vicina a me prima" solo tra le tappe ancora da consegnare.
    if (reorder) {
      final now = TimeOfDay.now();
      final sortedPending = RouteOptimizer.sort(
        _stops.where((s) => s.isPending && s.isGeocoded).toList(),
        mode: SortMode.optimizeRoute,
        startLat: _position!.latitude,
        startLng: _position!.longitude,
        nowMinutes: now.hour * 60 + now.minute,
      );
      final pendingNoGeo =
          _stops.where((s) => s.isPending && !s.isGeocoded).toList();
      final completed = _stops.where((s) => s.isCompleted).toList();
      _stops
        ..clear()
        ..addAll([...sortedPending, ...pendingNoGeo, ...completed]);
      await StorageService.saveStops(_stops);
    }

    final ordered = _activeGeocoded;

    // Cache: se l'ordine/coordinate non sono cambiati, riusa il risultato
    // senza richiamare (a pagamento) la Directions API.
    final sig = _routeSignature(ordered);
    final cached = _routeCache[sig];
    if (cached != null) {
      _applyRouteResult(cached, ordered);
      await _rebuildMapData();
      _fitCamera();
      return;
    }

    setState(() {
      _busy = true;
      _statusMessage = 'Calcolo distanze...';
    });

    try {
      _directionsCalls++;
      final result = await DirectionsService.optimizedRoute(
        startLat: _position!.latitude,
        startLng: _position!.longitude,
        stops: ordered,
        optimize: false,
      );
      _routeCache[sig] = result;
      _applyRouteResult(result, ordered);
    } catch (e) {
      // Fallback offline: distanze in linea d'aria (mantiene l'ordine).
      _applyStraightLineLegs(ordered);
      setState(() {
        _route = null;
        _polylines = {};
      });
      if (!silentFail) {
        _showSnack('Distanze su strada non disponibili: stima in linea d\'aria.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _statusMessage = null;
        });
      }
    }

    await _rebuildMapData();
    _fitCamera();
  }

  /// Firma del percorso (origine + coordinate ordinate) per la cache.
  String _routeSignature(List<Stop> ordered) {
    final o = _position == null
        ? 'na'
        : '${_position!.latitude.toStringAsFixed(3)},'
            '${_position!.longitude.toStringAsFixed(3)}';
    final pts = ordered
        .map((s) => '${s.lat!.toStringAsFixed(5)},${s.lng!.toStringAsFixed(5)}')
        .join('|');
    return '$o>$pts';
  }

  /// Applica un [result] (anche dalla cache) all'ordine [ordered] corrente.
  void _applyRouteResult(RouteResult result, List<Stop> ordered) {
    for (var i = 0; i < ordered.length; i++) {
      ordered[i].legDistanceMeters =
          i < result.legDistances.length ? result.legDistances[i] : null;
      ordered[i].legDurationSeconds =
          i < result.legDurations.length ? result.legDurations[i] : null;
    }
    _computeEtas(ordered);
    setState(() {
      _route = result;
      _polylines = {
        Polyline(
          polylineId: const PolylineId('route'),
          points: result.polyline,
          color: kBrandCopper,
          width: 6,
        ),
      };
    });
  }

  /// Calcola l'orario di arrivo stimato (ETA) per ogni tappa, partendo da
  /// adesso e sommando i tempi di percorrenza reali.
  void _computeEtas(List<Stop> ordered) {
    final now = TimeOfDay.now();
    final base = now.hour * 60 + now.minute;
    int accSec = 0;
    for (final s in ordered) {
      if (s.legDurationSeconds == null) {
        s.etaMinutes = null;
        continue;
      }
      accSec += s.legDurationSeconds!;
      s.etaMinutes = base + (accSec / 60).round();
    }
  }

  /// Calcola distanze approssimate (in linea d'aria) per ogni tratta,
  /// partendo dalla posizione attuale. Usato come fallback offline.
  void _applyStraightLineLegs(List<Stop> ordered) {
    if (_position == null) return;
    double prevLat = _position!.latitude;
    double prevLng = _position!.longitude;
    for (final s in ordered) {
      final m = LocationService.distanceMeters(
          prevLat, prevLng, s.lat!, s.lng!);
      s.legDistanceMeters = m.round();
      s.legDurationSeconds = null; // tempo non stimabile senza strade
      prevLat = s.lat!;
      prevLng = s.lng!;
    }
  }

  Future<void> _applySort(SortMode mode) async {
    if (_stops.isEmpty) return;
    if (mode == SortMode.optimizeRoute) {
      await _recomputeRoute(reorder: true);
      return;
    }
    if (mode == SortMode.byDistance && _position == null) {
      await _refreshLocation();
    }
    setState(() {
      final sorted = RouteOptimizer.sort(
        _stops,
        mode: mode,
        startLat: _position?.latitude,
        startLng: _position?.longitude,
      );
      _stops
        ..clear()
        ..addAll(sorted);
      _route = null;
      _polylines = {};
      for (final s in _stops) {
        s.legDistanceMeters = null;
        s.legDurationSeconds = null;
      }
    });
    await StorageService.saveStops(_stops);
    await _rebuildMapData();
    _showSnack('Ordinato: ${mode.label}');
  }

  // ------------------------------------------------------------- Navigazione

  static const int _batchSize = MapsLauncher.maxWaypoints + 1; // 10 tappe

  Future<void> _startNavigation() async {
    final active = _activeGeocoded;
    if (active.isEmpty) {
      _showSnack('Nessuna tappa da fare.');
      return;
    }
    // Google Maps gestisce max 10 tappe: naviga il primo "giro".
    final batch = active.take(_batchSize).toList();
    final ok = await MapsLauncher.startNavigation(batch);
    if (!ok) {
      _showSnack('Impossibile aprire Google Maps.');
    } else if (active.length > _batchSize) {
      _showSnack(
        'Giro di ${batch.length} tappe avviato. '
        'Restano ${active.length - _batchSize} tappe per i prossimi giri.',
      );
    }
  }

  /// Apre Google Maps verso la prossima tappa da fare.
  Future<void> _navigateNext() async {
    final active = _activeGeocoded;
    if (active.isEmpty) {
      _showSnack('Nessuna tappa da fare.');
      return;
    }
    final ok = await MapsLauncher.openSingle(active.first);
    if (!ok) _showSnack('Impossibile aprire Google Maps.');
  }

  // ---------------------------------------------------------- Stato consegna

  Future<void> _setStatus(Stop s, StopStatus status) async {
    final previous = s.status;
    if (status == StopStatus.delivered) {
      HapticFeedback.mediumImpact();
    } else if (status == StopStatus.failed) {
      HapticFeedback.lightImpact();
    }
    // Accumula i dati di sessione quando si completa una tappa in attesa.
    if (previous == StopStatus.pending && status != StopStatus.pending) {
      _sessionStart ??= DateTime.now();
      if (s.legDistanceMeters != null) {
        _sessionMeters += s.legDistanceMeters!.toDouble();
      }
      await StorageService.saveSession(_sessionMeters, _sessionStart);
    }
    setState(() => s.status = status);
    await StorageService.saveStops(_stops);
    // Ricalcola il giro sulle tappe rimaste (rispetta auto/manuale).
    await _recomputeRoute(reorder: _autoOptimize, silentFail: true);
    if (!mounted) return;

    if (status == StopStatus.delivered || status == StopStatus.failed) {
      _presentSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            status == StopStatus.delivered
                ? 'Segnata come completata.'
                : 'Segnata come non riuscita.',
          ),
          action: SnackBarAction(
            label: 'ANNULLA',
            onPressed: () => _undoStatus(s, previous, status),
          ),
        ),
      );
    }
  }

  /// Ripristina lo stato precedente di una tappa (azione "ANNULLA").
  Future<void> _undoStatus(Stop s, StopStatus previous, StopStatus applied) async {
    // Annulla anche l'eventuale conteggio aggiunto al riepilogo.
    if (previous == StopStatus.pending && applied != StopStatus.pending) {
      if (s.legDistanceMeters != null) {
        _sessionMeters -= s.legDistanceMeters!.toDouble();
        if (_sessionMeters < 0) _sessionMeters = 0;
      }
      await StorageService.saveSession(_sessionMeters, _sessionStart);
    }
    setState(() => s.status = previous);
    await StorageService.saveStops(_stops);
    await _recomputeRoute(reorder: _autoOptimize, silentFail: true);
  }

  Future<void> _restoreStop(Stop s) async {
    setState(() => s.status = StopStatus.pending);
    await StorageService.saveStops(_stops);
    await _recomputeRoute(reorder: _autoOptimize, silentFail: true);
  }

  /// Blocca/sblocca una tappa come prima o ultima del giro.
  Future<void> _setPin(Stop s, StopPin pin) async {
    setState(() => s.pin = pin);
    await StorageService.saveStops(_stops);
    // I pin sono un vincolo d'ordine: riapplica l'ordinamento rispettandoli.
    await _recomputeRoute(reorder: true, silentFail: true);
    _showSnack(
      pin == StopPin.first
          ? 'Bloccata come prima tappa.'
          : pin == StopPin.last
              ? 'Bloccata come ultima tappa.'
              : 'Vincolo rimosso.',
    );
  }

  /// Imposta o modifica l'orario limite ("entro le") di una tappa.
  Future<void> _setDeadline(Stop s) async {
    final initial = s.deadlineMinutes != null
        ? TimeOfDay(
            hour: s.deadlineMinutes! ~/ 60, minute: s.deadlineMinutes! % 60)
        : TimeOfDay.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: 'Completare entro le',
    );
    if (picked == null) return;
    setState(() => s.deadlineMinutes = picked.hour * 60 + picked.minute);
    await StorageService.saveStops(_stops);
  }

  /// Rimuove l'orario limite da una tappa.
  Future<void> _clearDeadline(Stop s) async {
    setState(() => s.deadlineMinutes = null);
    await StorageService.saveStops(_stops);
  }

  /// Apre il foglio "Dettagli tappa" per impostare tipo, note e orari.
  Future<void> _editDetails(Stop s, {bool isNew = false}) async {
    final result = await showModalBottomSheet<StopDetailsResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StopDetailsSheet(stop: s, isNew: isNew),
    );
    if (result == null) return;
    setState(() {
      s.serviceType = result.serviceType;
      s.note = result.note;
      s.continuousHours = result.continuousHours;
      s.lunchStartMinutes = result.lunchStartMinutes;
      s.lunchEndMinutes = result.lunchEndMinutes;
      s.openStartMinutes = result.openStartMinutes;
      s.openEndMinutes = result.openEndMinutes;
    });
    await StorageService.saveStops(_stops);
    // Se ora ci sono orari del punto vendita e l'auto-ordina è attivo, riordina
    // il giro per arrivare quando l'attività è aperta.
    if (_autoOptimize && (s.hasHours || s.hasLunchBreak) && s.isPending) {
      await _recomputeRoute(reorder: true, silentFail: true);
    }
  }

  /// Inverte l'ordine delle tappe da fare.
  Future<void> _reversePending() async {
    if (_pendingStops.length < 2) return;
    final reversed = _pendingStops.reversed.toList();
    final completed = _completedStops;
    setState(() {
      _stops
        ..clear()
        ..addAll([...reversed, ...completed]);
      _autoOptimize = false;
    });
    await StorageService.saveStops(_stops);
    await _recomputeRoute(reorder: false, silentFail: true);
    _showSnack('Percorso invertito (ordine manuale).');
  }

  /// Condivide/esporta il giro come testo.
  Future<void> _shareRoute() async {
    final active = _activeGeocoded;
    if (active.isEmpty) {
      _showSnack('Nessuna tappa da condividere.');
      return;
    }
    final b = StringBuffer('Giro SerMaps Driver\n\n');
    for (var i = 0; i < active.length; i++) {
      b.writeln('${i + 1}. ${active[i].address}');
    }
    if (_route != null) {
      b.writeln('\nTotale: ${_route!.distanceLabel} · ${_route!.durationLabel}');
    }
    await Share.share(b.toString(), subject: 'Giro SerMaps');
  }

  /// Apre la schermata Guida in-app.
  void _openGuide() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const GuideScreen()),
    );
  }

  /// Riapre l'introduzione (onboarding) dal menu.
  void _openOnboarding() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const OnboardingScreen(fromMenu: true)),
    );
  }

  /// Dialogo "Informazioni" con logo, versione e autore.
  Future<void> _openAbout() async {
    final cs = Theme.of(context).colorScheme;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset(
                'img/serworks-app-icon-512.png',
                width: 72,
                height: 72,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'SerMaps Driver',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text('Versione ${_appVersion.isEmpty ? '—' : _appVersion}',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
            const SizedBox(height: 16),
            Text('Creata da',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            const SizedBox(height: 2),
            const Text(
              'Roberto Rolle',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Text(
              'Gestione tappe, ottimizzazione percorso e navigazione per consegne.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _openGuide();
            },
            child: const Text('Apri la guida'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Chiudi'),
          ),
        ],
      ),
    );
  }

  /// Voce di menu con icona a sinistra per maggiore chiarezza.
  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }

  /// Blocco in alto a destra della tappa: tipo intervento + nota (post-it).
  Widget _buildCornerInfo(Stop s) {
    final cs = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (s.serviceType != ServiceType.none)
            _serviceBadge(
              Icons.build_circle,
              s.serviceType.label,
              cs.primary,
            )
          else
            _serviceBadge(
              Icons.help_outline,
              'Non definito',
              Colors.grey.shade500,
            ),
          if (s.note != null && s.note!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.6)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sticky_note_2,
                      size: 13, color: Colors.amber.shade800),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      s.note!,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                        color: Colors.brown.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Badge pieno e ben visibile per il tipo di intervento (LIS, IGT, ...).
  Widget _serviceBadge(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(9),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  /// Piccola etichetta colorata con icona (tipo intervento, orari...).
  Widget _infoChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// Icona associata a ciascuna modalità di ordinamento.
  IconData _sortIcon(SortMode m) {
    switch (m) {
      case SortMode.optimizeRoute:
        return Icons.route;
      case SortMode.byDistance:
        return Icons.straighten;
      case SortMode.byProvinceCity:
        return Icons.location_city;
      case SortMode.byDeadline:
        return Icons.schedule;
    }
  }

  /// Dialogo di scelta del tema (Sistema / Chiaro / Scuro).
  Future<void> _openThemeDialog() async {
    Widget option(ThemeMode m, String label, IconData icon) {
      return ValueListenableBuilder<ThemeMode>(
        valueListenable: themeModeNotifier,
        builder: (context, current, _) => ListTile(
          leading: Icon(icon),
          title: Text(label),
          trailing: current == m
              ? const Icon(Icons.check, color: kBrandCopper)
              : null,
          onTap: () => setThemeMode(m),
        ),
      );
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tema'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            option(ThemeMode.system, 'Sistema (automatico)',
                Icons.brightness_auto),
            option(ThemeMode.light, 'Chiaro', Icons.light_mode),
            option(ThemeMode.dark, 'Scuro', Icons.dark_mode),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Chiudi'),
          ),
        ],
      ),
    );
  }

  /// Dialogo di scelta del colore accento dell'app.
  Future<void> _openColorDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Colore app'),
        content: ValueListenableBuilder<Color>(
          valueListenable: accentColorNotifier,
          builder: (context, current, _) => Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (final c in kAccentColors)
                GestureDetector(
                  onTap: () => setAccentColor(c.color),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: c.color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: current.toARGB32() == c.color.toARGB32()
                                ? Colors.white
                                : Colors.transparent,
                            width: 3,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: c.color.withValues(
                                alpha: current.toARGB32() == c.color.toARGB32()
                                    ? 0.5
                                    : 0.0,
                              ),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: current.toARGB32() == c.color.toARGB32()
                            ? const Icon(Icons.check,
                                color: Colors.white, size: 22)
                            : null,
                      ),
                      const SizedBox(height: 4),
                      Text(c.label, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Chiudi'),
          ),
        ],
      ),
    );
  }

  void _showCompletedSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) {
        final completed = _completedStops;
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Tappe completate',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            if (completed.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('Nessuna tappa completata.')),
              ),
            ...completed.map(
              (s) => ListTile(
                leading: Icon(
                  s.status == StopStatus.delivered
                      ? Icons.check_circle
                      : Icons.cancel,
                  color: s.status == StopStatus.delivered
                      ? Colors.green
                      : Colors.red,
                ),
                title: Text(
                  s.address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: s.subtitle.isNotEmpty ? Text(s.subtitle) : null,
                trailing: TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _restoreStop(s);
                  },
                  child: const Text('Ripristina'),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // --------------------------------------------------------------- Dialoghi

  Future<void> _openAddSingle() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const AddAddressSheet(),
    );
    if (result != null && result.trim().isNotEmpty) {
      await _addSingleAddress(result.trim());
    }
  }

  /// Aggiunge un singolo indirizzo gestendo i casi ambigui (più risultati):
  /// se Google trova più corrispondenze, l'utente sceglie quella giusta.
  Future<void> _addSingleAddress(String address) async {
    if (!AppConfig.hasApiKey) {
      _showSnack('Configura prima la chiave Google Maps.');
      return;
    }
    // Se l'indirizzo è già in cache, usalo (funziona anche offline).
    final cached = Stop(address: address);
    if (await GeocodeCache.fill(cached)) {
      _stops.add(cached);
      await StorageService.saveStops(_stops);
      if (_activeGeocoded.isNotEmpty) {
        await _recomputeRoute(reorder: _autoOptimize);
      } else {
        await _rebuildMapData();
        _fitCamera();
      }
      _showSnack('Tappa aggiunta.');
      if (mounted) await _editDetails(cached, isNew: true);
      return;
    }
    setState(() {
      _busy = true;
      _statusMessage = 'Ricerca indirizzo...';
    });
    List<Stop> candidates;
    try {
      candidates = await GeocodingService.geocodeCandidates(address);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _statusMessage = null;
        });
        _showRetry(e, [address]);
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _statusMessage = null;
    });

    if (candidates.isEmpty) {
      _showSnack('Indirizzo non trovato.');
      return;
    }

    Stop chosen;
    if (candidates.length == 1) {
      chosen = candidates.first;
    } else {
      final picked = await _chooseCandidate(candidates);
      if (picked == null) return; // annullato
      chosen = picked;
    }

    await GeocodeCache.store(address, chosen);
    _stops.add(chosen);
    await StorageService.saveStops(_stops);
    if (_activeGeocoded.isNotEmpty) {
      await _recomputeRoute(reorder: _autoOptimize);
    } else {
      await _rebuildMapData();
      _fitCamera();
    }
    _showSnack('Tappa aggiunta.');
    if (mounted) await _editDetails(chosen, isNew: true);
  }

  /// Mostra una scelta tra più candidati per un indirizzo ambiguo.
  Future<Stop?> _chooseCandidate(List<Stop> candidates) {
    return showModalBottomSheet<Stop>(
      context: context,
      showDragHandle: true,
      builder: (_) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Più risultati trovati: scegli quello giusto',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
          ...candidates.map(
            (c) => ListTile(
              leading: const Icon(Icons.location_on_outlined,
                  color: kBrandCopper),
              title: Text(c.address),
              subtitle: c.subtitle.isNotEmpty ? Text(c.subtitle) : null,
              onTap: () => Navigator.pop(context, c),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openPasteList() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Incolla lista indirizzi'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 8,
            decoration: const InputDecoration(
              hintText: 'Un indirizzo per riga...\n\n'
                  'Via Roma 1, Torino\n'
                  'Piazza Duomo, Milano\n'
                  'Corso Italia 5, Napoli',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Aggiungi'),
          ),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      await _addAddresses(result.split('\n'));
    }
  }

  // ------------------------------------------------------------------ Mappa

  Future<void> _rebuildMapData() async {
    final markers = <Marker>{};
    // Tappe attive: pin numerati nell'ordine di visita.
    final active = _activeGeocoded;
    for (var i = 0; i < active.length; i++) {
      final s = active[i];
      final selected = s.id == _selectedStopId;
      final icon = await _numberIcon(i + 1, selected: selected);
      markers.add(
        Marker(
          markerId: MarkerId(s.id),
          position: LatLng(s.lat!, s.lng!),
          icon: icon,
          anchor: const Offset(0.5, 1.0),
          zIndexInt: selected ? 3 : 1,
          infoWindow: InfoWindow(
            title: '${i + 1}. ${s.city ?? s.address}',
            snippet: s.address,
          ),
        ),
      );
    }
    // Tappe completate: pin custom verde (consegnata) o rosso (fallita).
    for (final s in _completedStops.where((e) => e.isGeocoded)) {
      final icon = await _statusIcon(s.status == StopStatus.delivered);
      markers.add(
        Marker(
          markerId: MarkerId(s.id),
          position: LatLng(s.lat!, s.lng!),
          icon: icon,
          anchor: const Offset(0.5, 1.0),
          alpha: 0.85,
          infoWindow: InfoWindow(
            title: s.status == StopStatus.delivered
                ? '✓ ${s.city ?? s.address}'
                : '✗ ${s.city ?? s.address}',
            snippet: s.address,
          ),
        ),
      );
    }
    // Marcatore ben visibile della posizione attuale.
    if (_position != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('_me'),
          position: LatLng(_position!.latitude, _position!.longitude),
          icon: await _positionIcon(),
          anchor: const Offset(0.5, 0.5),
          zIndexInt: 6,
          infoWindow: const InfoWindow(title: 'La tua posizione'),
        ),
      );
    }
    if (mounted) setState(() => _markers = markers);
  }

  Future<BitmapDescriptor> _positionIcon() async {
    final accent = accentColorNotifier.value;
    final key = 'me-${accent.toARGB32()}';
    if (_markerCache.containsKey(key)) return _markerCache[key]!;
    try {
      final icon = await MarkerHelper.positionMarker(color: accent);
      _markerCache[key] = icon;
      return icon;
    } catch (_) {
      return MarkerHelper.fallback();
    }
  }

  Future<BitmapDescriptor> _numberIcon(int number,
      {bool selected = false}) async {
    final accent = accentColorNotifier.value;
    final key = 'n$number${selected ? '-s' : ''}-${accent.toARGB32()}';
    if (_markerCache.containsKey(key)) return _markerCache[key]!;
    try {
      final icon = await MarkerHelper.numberedMarker(
        number,
        color: accent,
        scale: selected ? 1.35 : 1.0,
      );
      _markerCache[key] = icon;
      return icon;
    } catch (_) {
      return MarkerHelper.fallback();
    }
  }

  Future<BitmapDescriptor> _statusIcon(bool delivered) async {
    final key = delivered ? 'ok' : 'no';
    if (_markerCache.containsKey(key)) return _markerCache[key]!;
    try {
      final icon = await MarkerHelper.statusMarker(delivered: delivered);
      _markerCache[key] = icon;
      return icon;
    } catch (_) {
      return MarkerHelper.fallback();
    }
  }

  void _fitCamera() {
    final controller = _mapController;
    if (controller == null) return;

    final points = <LatLng>[
      for (final s in _stops)
        if (s.isGeocoded) LatLng(s.lat!, s.lng!),
      if (_position != null) LatLng(_position!.latitude, _position!.longitude),
    ];
    if (points.isEmpty) return;

    if (points.length == 1) {
      controller.animateCamera(CameraUpdate.newLatLngZoom(points.first, 15));
      return;
    }

    double minLat = points.first.latitude, maxLat = points.first.latitude;
    double minLng = points.first.longitude, maxLng = points.first.longitude;
    for (final p in points) {
      minLat = p.latitude < minLat ? p.latitude : minLat;
      maxLat = p.latitude > maxLat ? p.latitude : maxLat;
      minLng = p.longitude < minLng ? p.longitude : minLng;
      maxLng = p.longitude > maxLng ? p.longitude : maxLng;
    }
    // Se i punti sono molto vicini tra loro, evita lo zoom eccessivo (che fa
    // sembrare enorme il cerchio di precisione GPS): centra con zoom fisso.
    final latSpan = maxLat - minLat;
    final lngSpan = maxLng - minLng;
    if (latSpan < 0.004 && lngSpan < 0.004) {
      controller.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2),
          15.5,
        ),
      );
      return;
    }
    controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        70,
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    _presentSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Mostra una SnackBar e ne pianifica la chiusura automatica con un [Timer].
  ///
  /// Serve perche, quando sul dispositivo e attivo uno screen reader
  /// (accessibleNavigation), Flutter ignora la durata e lascia la SnackBar
  /// aperta finche non viene chiusa manualmente: il timer la rimuove comunque.
  void _presentSnackBar(SnackBar snackBar) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    _snackDismissTimer?.cancel();
    messenger.clearSnackBars();
    messenger.showSnackBar(snackBar);
    _snackDismissTimer = Timer(snackBar.duration, () {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
    });
  }

  /// Barra di avanzamento del giro nell'AppBar ("consegnate / totale").
  PreferredSizeWidget? _progressBar() {
    final all = _stops.where((s) => s.isGeocoded).length;
    if (all == 0) return null;
    final done = _stops
        .where((s) => s.isGeocoded && s.status == StopStatus.delivered)
        .length;
    final ratio = all == 0 ? 0.0 : done / all;
    return PreferredSize(
      preferredSize: const Size.fromHeight(26),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 6,
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  color: kBrandCopper,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '$done/$all completate',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  /// Centra e zooma la mappa su una singola tappa (tap dalla lista).
  void _centerOnStop(Stop s) {
    if (!s.isGeocoded) return;
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(s.lat!, s.lng!), 15),
    );
  }

  /// Seleziona una tappa: la evidenzia in lista, ingrandisce il pin e centra.
  Future<void> _selectStop(Stop s) async {
    setState(() => _selectedStopId = s.id);
    _centerOnStop(s);
    await _rebuildMapData();
  }

  // ------------------------------------------------------------------ Build

  @override
  Widget build(BuildContext context) {
    final hasStops = _activeGeocoded.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'img/serworks-app-icon-512.png',
                width: 32,
                height: 32,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'SerMaps Driver',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<SortMode>(
            icon: const Icon(Icons.sort),
            tooltip: 'Ordina tappe',
            onSelected: _applySort,
            itemBuilder: (_) => SortMode.values
                .map((m) => PopupMenuItem(
                      value: m,
                      child: Row(
                        children: [
                          Icon(_sortIcon(m), size: 20),
                          const SizedBox(width: 12),
                          Expanded(child: Text(m.label)),
                        ],
                      ),
                    ))
                .toList(),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'clear') _clearAll();
              if (v == 'location') {
                _refreshLocation().then((_) => _fitCamera());
              }
              if (v == 'reverse') _reversePending();
              if (v == 'share') _shareRoute();
              if (v == 'theme') _openThemeDialog();
              if (v == 'color') _openColorDialog();
              if (v == 'guide') _openGuide();
              if (v == 'intro') _openOnboarding();
              if (v == 'about') _openAbout();
              if (v == 'cache') {
                setState(() => _routeCache.clear());
                _showSnack('Cache percorso svuotata.');
              }
            },
            itemBuilder: (_) => [
              _menuItem('location', Icons.my_location, 'Aggiorna posizione'),
              _menuItem('reverse', Icons.swap_vert, 'Inverti percorso'),
              _menuItem('share', Icons.ios_share, 'Condividi / esporta giro'),
              const PopupMenuDivider(),
              _menuItem('theme', Icons.brightness_6, 'Tema (chiaro/scuro)'),
              _menuItem('color', Icons.palette, 'Colore app'),
              const PopupMenuDivider(),
              PopupMenuItem(
                enabled: false,
                child: Row(
                  children: [
                    Icon(Icons.insights,
                        size: 20,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 12),
                    Expanded(child: Text('Chiamate Directions: $_directionsCalls')),
                  ],
                ),
              ),
              _menuItem('cache', Icons.cached, 'Svuota cache percorso'),
              _menuItem('clear', Icons.delete_outline, 'Elimina tutte'),
              const PopupMenuDivider(),
              _menuItem('guide', Icons.menu_book, 'Guida'),
              _menuItem('intro', Icons.slideshow, 'Rivedi introduzione'),
              _menuItem('about', Icons.info_outline, 'Informazioni'),
            ],
          ),
        ],
        bottom: _progressBar(),
      ),
      body: Column(
        children: [
          if (!AppConfig.hasApiKey) _apiKeyBanner(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final mapH = _mapCollapsed
                    ? 130.0
                    : constraints.maxHeight * 0.44;
                return Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeInOutCubic,
                      height: mapH,
                      child: _mapArea(),
                    ),
                    Expanded(child: _buildStopsPanel()),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: hasStops ? _bottomBar() : null,
    );
  }

  Widget _mapArea() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: _initialCamera,
          markers: _markers,
          polylines: _polylines,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          minMaxZoomPreference: const MinMaxZoomPreference(3, 17),
          style: isDark ? _mapStyleDark : _mapStyleLight,
          onMapCreated: (c) {
            _mapController = c;
            _fitCamera();
          },
        ),
        Positioned(
          right: 12,
          bottom: 12,
          child: FloatingActionButton.small(
            heroTag: 'loc',
            tooltip: 'Centra sulla mia posizione',
            backgroundColor: Colors.white,
            foregroundColor: kBrandDark,
            onPressed: () async {
              await _refreshLocation();
              _fitCamera();
            },
            child: const Icon(Icons.my_location),
          ),
        ),
        if (_busy)
          Positioned.fill(
            child: Container(
              color: Colors.black26,
              child: Center(
                child: Card(
                  color: Theme.of(context).colorScheme.surface,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                        const SizedBox(width: 16),
                        Text(_statusMessage ?? 'Attendere...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Barra fissa in basso con il pulsante di navigazione (non copre la lista).
  Widget _bottomBar() {
    final count = _activeGeocoded.length;
    final cs = Theme.of(context).colorScheme;
    final rounds = count > _batchSize ? (count / _batchSize).ceil() : 1;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(top: BorderSide(color: cs.outlineVariant)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (rounds > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 15, color: cs.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Giro 1 di $rounds · Google Maps gestisce '
                        '$_batchSize tappe per volta.',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _startNavigation,
                    icon: const Icon(Icons.navigation),
                    label: Text(
                      count > _batchSize
                          ? 'Avvia giro ($_batchSize di $count)'
                          : 'Avvia navigazione ($count)',
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 50),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: _navigateNext,
                  icon: const Icon(Icons.skip_next),
                  label: const Text('Prossima'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 50),
                    foregroundColor: kBrandCopper,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Toggle "Auto-ordina" personalizzato (si adatta sempre al testo).
  Widget _autoSortToggle() {
    final cs = Theme.of(context).colorScheme;
    final on = _autoOptimize;
    final color = on ? kBrandCopper : cs.onSurfaceVariant;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () async {
          setState(() => _autoOptimize = !_autoOptimize);
          if (_autoOptimize && _activeGeocoded.length > 1) {
            await _recomputeRoute();
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color:
                on ? kBrandCopper.withValues(alpha: 0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color:
                  on ? kBrandCopper.withValues(alpha: 0.5) : cs.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                'Auto-ordina',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: on ? kBrandCopper : cs.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Riepilogo inline compatto (km · tempo) mostrato accanto al titolo.
  Widget _inlineSummary() {
    final r = _route!;
    final cs = Theme.of(context).colorScheme;
    final style = TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w700,
      color: cs.onSurfaceVariant,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.route, size: 14, color: cs.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(r.distanceLabel, style: style),
        Text('  ·  ', style: style),
        Icon(Icons.schedule, size: 13, color: cs.onSurfaceVariant),
        const SizedBox(width: 3),
        Text(r.durationLabel, style: style),
      ],
    );
  }

  Widget _apiKeyBanner() {
    return Container(
      width: double.infinity,
      color: Colors.amber.shade100,
      padding: const EdgeInsets.all(12),
      child: const Text(
        'Chiave Google Maps non configurata: imposta MAPS_API_KEY in '
        'android/local.properties (vedi README).',
        style: TextStyle(fontSize: 12),
      ),
    );
  }

  Widget _buildStopsPanel() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2)),
        ],
      ),
      child: Column(
        children: [
          // Maniglia: tocca o trascina per espandere/chiudere il pannello.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _mapCollapsed = !_mapCollapsed),
            onVerticalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v < -50) {
                setState(() => _mapCollapsed = true);
              } else if (v > 50) {
                setState(() => _mapCollapsed = false);
              }
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 14, 0),
            child: Row(
              children: [
                Text(
                  'Da fare (${_pendingStops.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                if (_completedStops.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  ActionChip(
                    avatar: const Icon(Icons.check_circle,
                        size: 15, color: Colors.green),
                    label: Text('${_completedStops.length}'),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onPressed: _showCompletedSheet,
                  ),
                ],
                const Spacer(),
                _autoSortToggle(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
            child: Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: _openAddSingle,
                  icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                  label: const Text('Aggiungi'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                IconButton(
                  tooltip: 'Incolla lista',
                  onPressed: _openPasteList,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.playlist_add),
                ),
                const Spacer(),
                if (_route != null) _inlineSummary(),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _pendingStops.isEmpty
                ? _emptyOrAllDone()
                : ReorderableListView.builder(
                    padding: const EdgeInsets.only(bottom: 12),
                    itemCount: _pendingStops.length,
                    onReorder: _reorderPending,
                    // Rallenta lo scorrimento automatico durante il
                    // trascinamento, cosi con molte tappe e piu preciso.
                    autoScrollerVelocityScalar: 18,
                    itemBuilder: (context, i) {
                      final pending = _pendingStops;
                      return _buildStopTile(pending[i], i, pending.length);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _emptyOrAllDone() {
    final allDone = _stops.isNotEmpty && _pendingStops.isEmpty;
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                allDone ? Icons.task_alt : Icons.route_outlined,
                size: 44,
                color: allDone ? Colors.green : Colors.grey[400],
              ),
              const SizedBox(height: 10),
              Text(
                allDone
                    ? 'Giro completato! 🎉'
                    : 'Nessuna tappa.\n'
                        'Tocca "Aggiungi" per cercare un indirizzo '
                        'o l\'icona lista per incollarne diversi.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600]),
              ),
              if (allDone) ...[
                const SizedBox(height: 16),
                _roundSummaryCard(),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _showCompletedSheet,
                  child: Text('Vedi ${_completedStops.length} completate'),
                ),
                FilledButton.icon(
                  onPressed: _newRound,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Nuovo giro'),
                ),
              ],
              const SizedBox(height: 18),
              Text(
                'Creata da Roberto Rolle',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[500],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Scheda di riepilogo a fine giro: completate/non riuscite, km e durata.
  Widget _roundSummaryCard() {
    final cs = Theme.of(context).colorScheme;
    final delivered =
        _completedStops.where((s) => s.status == StopStatus.delivered).length;
    final failed =
        _completedStops.where((s) => s.status == StopStatus.failed).length;
    final km = _sessionMeters / 1000;
    final kmLabel = km >= 10
        ? '${km.toStringAsFixed(0)} km'
        : '${km.toStringAsFixed(1)} km';
    String? durationLabel;
    if (_sessionStart != null) {
      final mins = DateTime.now().difference(_sessionStart!).inMinutes;
      final h = mins ~/ 60;
      final m = mins % 60;
      durationLabel = h > 0 ? '${h}h ${m}min' : '${m}min';
    }

    Widget stat(IconData icon, String value, String label, Color color) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          Text(label,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ],
      );
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          stat(Icons.check_circle, '$delivered', 'completate',
              const Color(0xFF1E8E3E)),
          if (failed > 0)
            stat(Icons.cancel, '$failed', 'non riuscite',
                const Color(0xFFD93025)),
          if (_sessionMeters > 0)
            stat(Icons.straighten, kmLabel, 'percorsi', cs.primary),
          if (durationLabel != null)
            stat(Icons.schedule, durationLabel, 'durata', cs.primary),
        ],
      ),
    );
  }

  /// Avvia un nuovo giro: rimuove le tappe completate e azzera il riepilogo.
  Future<void> _newRound() async {
    setState(() {
      _stops.removeWhere((s) => s.isCompleted);
      _sessionMeters = 0;
      _sessionStart = null;
      _route = null;
      _polylines = {};
    });
    await StorageService.saveStops(_stops);
    await StorageService.saveSession(0, null);
    await _rebuildMapData();
    _fitCamera();
  }

  /// Colonna informazioni della tappa (comune, tratta, orari, avvisi).
  Widget _buildStopInfo(Stop s, int number, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (s.subtitle.isNotEmpty)
          Text(s.subtitle, style: const TextStyle(fontSize: 12)),
        if (s.legLabel != null)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    number == 1 ? Icons.my_location : Icons.directions_car,
                    size: 12,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      number == 1
                          ? 'dalla partenza · ${s.legLabel}'
                          : 'da tappa ${number - 1} · ${s.legLabel}',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (s.deadlineMinutes != null || s.etaMinutes != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(
                  s.isLate ? Icons.warning_amber : Icons.schedule,
                  size: 13,
                  color: s.isLate ? Colors.red : Colors.green,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    [
                      if (s.deadlineLabel != null) 'entro ${s.deadlineLabel}',
                      if (s.etaLabel != null) 'arrivo ~${s.etaLabel}',
                    ].join(' · '),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: s.isLate
                          ? Colors.red
                          : (s.deadlineMinutes != null
                              ? Colors.green.shade700
                              : cs.onSurfaceVariant),
                    ),
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (s.isClosedOnArrival)
                _infoChip(
                  Icons.block,
                  'Chiuso all\'arrivo${s.hoursLabel != null ? ' · ${s.hoursLabel}' : ''}',
                  Colors.red,
                )
              else if (s.hasHours || s.hasLunchBreak || s.continuousHours)
                _infoChip(
                  Icons.storefront,
                  s.hoursLabel ?? 'Orari indicati',
                  Colors.green.shade700,
                )
              else
                _infoChip(
                  Icons.schedule,
                  'Orari non definiti',
                  Colors.grey.shade600,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStopTile(Stop s, int index, int count) {
    final number = index + 1;
    final cs = Theme.of(context).colorScheme;
    final selected = _selectedStopId == s.id;

    return Padding(
      key: ValueKey(s.id),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Dismissible(
        key: ValueKey('dismiss_${s.id}'),
        direction: DismissDirection.endToStart,
        background: Container(
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          child: const Icon(Icons.delete, color: Colors.white),
        ),
        onDismissed: (_) => _removeStop(s.id),
        child: Card(
          margin: EdgeInsets.zero,
          color: selected
              ? cs.primary.withValues(alpha: 0.12)
              : cs.surfaceContainerHighest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: selected
                ? BorderSide(color: cs.primary, width: 1.4)
                : BorderSide.none,
          ),
          child: InkWell(
            onTap: () => _selectStop(s),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: CircleAvatar(
                      radius: 17,
                      backgroundColor:
                          s.isGeocoded ? kBrandCopper : Colors.grey,
                      foregroundColor: Colors.white,
                      child: Text(
                        s.isGeocoded ? '$number' : '!',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (s.pin != StopPin.none) ...[
                              Icon(
                                s.pin == StopPin.first
                                    ? Icons.vertical_align_top
                                    : Icons.vertical_align_bottom,
                                size: 16,
                                color: kBrandCopper,
                              ),
                              const SizedBox(width: 3),
                            ],
                            Expanded(
                              child: Text(
                                s.address,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w600,
                                  height: 1.2,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildCornerInfo(s),
                          ],
                        ),
                        const SizedBox(height: 3),
                        _buildStopInfo(s, number, cs),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                IconButton(
                  tooltip: 'Segna completata',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(6),
                  icon: const Icon(Icons.check_circle_outline,
                      color: Colors.green),
                  onPressed: () => _setStatus(s, StopStatus.delivered),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.grey),
                  padding: EdgeInsets.zero,
                  tooltip: 'Sposta / azioni',
                  onSelected: (v) {
                    switch (v) {
                      case 'up':
                        _movePending(index, index - 1);
                        break;
                      case 'down':
                        _movePending(index, index + 1);
                        break;
                      case 'end':
                        _movePending(index, count - 1);
                        break;
                      case 'delivered':
                        _setStatus(s, StopStatus.delivered);
                        break;
                      case 'failed':
                        _setStatus(s, StopStatus.failed);
                        break;
                      case 'maps':
                        MapsLauncher.openSingle(s);
                        break;
                      case 'pin_first':
                        _setPin(s, StopPin.first);
                        break;
                      case 'pin_last':
                        _setPin(s, StopPin.last);
                        break;
                      case 'unpin':
                        _setPin(s, StopPin.none);
                        break;
                      case 'deadline':
                        _setDeadline(s);
                        break;
                      case 'cleardeadline':
                        _clearDeadline(s);
                        break;
                      case 'details':
                        _editDetails(s);
                        break;
                      case 'delete':
                        _removeStop(s.id);
                        break;
                    }
                  },
                  itemBuilder: (_) => [
                    if (index > 0)
                      const PopupMenuItem(
                        value: 'up',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.arrow_upward),
                          title: Text('Sposta su'),
                        ),
                      ),
                    if (index < count - 1)
                      const PopupMenuItem(
                        value: 'down',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.arrow_downward),
                          title: Text('Sposta giù'),
                        ),
                      ),
                    if (index < count - 1)
                      const PopupMenuItem(
                        value: 'end',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.vertical_align_bottom),
                          title: Text('Fai per ultima'),
                        ),
                      ),
                    if (s.pin != StopPin.first)
                      const PopupMenuItem(
                        value: 'pin_first',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.vertical_align_top),
                          title: Text('Blocca come prima'),
                        ),
                      ),
                    if (s.pin != StopPin.last)
                      const PopupMenuItem(
                        value: 'pin_last',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.push_pin_outlined),
                          title: Text('Blocca come ultima'),
                        ),
                      ),
                    if (s.pin != StopPin.none)
                      const PopupMenuItem(
                        value: 'unpin',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.lock_open),
                          title: Text('Rimuovi blocco'),
                        ),
                      ),
                    PopupMenuItem(
                      value: 'deadline',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.schedule),
                        title: Text(s.deadlineMinutes == null
                            ? 'Imposta orario "entro le"'
                            : 'Modifica orario (${s.deadlineLabel})'),
                      ),
                    ),
                    if (s.deadlineMinutes != null)
                      const PopupMenuItem(
                        value: 'cleardeadline',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.timer_off_outlined),
                          title: Text('Rimuovi orario'),
                        ),
                      ),
                    PopupMenuItem(
                      value: 'details',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.edit_note),
                        title: Text(
                          s.serviceType == ServiceType.none &&
                                  (s.note == null || s.note!.isEmpty) &&
                                  !s.continuousHours &&
                                  !s.hasLunchBreak &&
                                  !s.hasHours
                              ? 'Dettagli / note'
                              : 'Modifica dettagli / note',
                        ),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'failed',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.cancel_outlined, color: Colors.red),
                        title: Text('Tappa non riuscita'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'maps',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.map_outlined),
                        title: Text('Apri in Google Maps'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.delete_outline, color: Colors.red),
                        title: Text('Elimina'),
                      ),
                    ),
                  ],
                ),
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.only(left: 2, right: 2),
                    child: Icon(Icons.drag_handle, color: Colors.grey, size: 22),
                  ),
                ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _snackDismissTimer?.cancel();
    accentColorNotifier.removeListener(_onAccentChanged);
    _mapController?.dispose();
    super.dispose();
  }
}
