import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Stato di lavorazione di una tappa.
enum StopStatus { pending, delivered, failed }

/// Vincolo di posizione di una tappa nel giro.
enum StopPin { none, first, last }

/// Tipo di intervento associato alla tappa.
enum ServiceType { none, lis, igt, sisal, tlc, gbo, global }

extension ServiceTypeLabel on ServiceType {
  /// Etichetta leggibile del tipo di intervento.
  String get label {
    switch (this) {
      case ServiceType.none:
        return 'Non definito';
      case ServiceType.lis:
        return 'LIS';
      case ServiceType.igt:
        return 'IGT';
      case ServiceType.sisal:
        return 'SISAL';
      case ServiceType.tlc:
        return 'TLC';
      case ServiceType.gbo:
        return 'GBO';
      case ServiceType.global:
        return 'GLOBAL';
    }
  }
}

/// Rappresenta una tappa (destinazione) del percorso.
class Stop {
  final String id;

  /// Indirizzo come inserito / formattato.
  String address;

  /// Stato della consegna (in attesa / consegnata / fallita).
  StopStatus status;

  /// Vincolo di posizione: nessuno / sempre prima / sempre ultima.
  StopPin pin;

  /// Coordinate (null finché non è stato fatto il geocoding).
  double? lat;
  double? lng;

  /// Componenti dell'indirizzo, utili per ordinare/raggruppare.
  String? city; // località / comune
  String? province; // provincia (es. "Torino")
  String? provinceCode; // sigla provincia (es. "TO")
  String? region; // regione
  String? postalCode;

  /// Distanza/tempo della tratta dalla tappa precedente (o dalla partenza),
  /// calcolati dal percorso reale. Valori transienti (non salvati).
  int? legDistanceMeters;
  int? legDurationSeconds;

  /// Orario limite di consegna ("entro le"), in minuti dalla mezzanotte.
  int? deadlineMinutes;

  /// Tipo di intervento (LIS, IGT, SISAL, TLC, GBO, GLOBAL).
  ServiceType serviceType;

  /// Note libere sulla tappa.
  String? note;

  /// True se l'attività fa orario continuato (nessuna pausa pranzo).
  bool continuousHours;

  /// Inizio pausa pranzo (minuti dalla mezzanotte), se non è orario continuato.
  int? lunchStartMinutes;

  /// Fine pausa pranzo (minuti dalla mezzanotte), se non è orario continuato.
  int? lunchEndMinutes;

  /// Orario di apertura del punto vendita (minuti dalla mezzanotte).
  int? openStartMinutes;

  /// Orario di chiusura del punto vendita (minuti dalla mezzanotte).
  int? openEndMinutes;

  /// Orario di arrivo stimato (ETA) in minuti dalla mezzanotte. Transiente.
  int? etaMinutes;

  /// True se il geocoding è andato a buon fine.
  bool get isGeocoded => lat != null && lng != null;

  /// True se l'arrivo stimato supera l'orario limite (in ritardo).
  bool get isLate =>
      deadlineMinutes != null &&
      etaMinutes != null &&
      etaMinutes! > deadlineMinutes!;

  static String formatMinutes(int m) {
    final h = (m ~/ 60) % 24;
    final mm = m % 60;
    return '${h.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
  }

  String? get deadlineLabel =>
      deadlineMinutes == null ? null : formatMinutes(deadlineMinutes!);

  String? get etaLabel => etaMinutes == null ? null : formatMinutes(etaMinutes!);

  /// True se è stata indicata una pausa pranzo valida.
  bool get hasLunchBreak =>
      !continuousHours &&
      lunchStartMinutes != null &&
      lunchEndMinutes != null;

  /// Etichetta leggibile della pausa pranzo (es. "13:00-15:00").
  String? get lunchLabel => hasLunchBreak
      ? '${formatMinutes(lunchStartMinutes!)}-${formatMinutes(lunchEndMinutes!)}'
      : null;

  /// True se l'arrivo stimato cade durante la pausa pranzo (trovi chiuso).
  bool get isDuringLunch =>
      hasLunchBreak &&
      etaMinutes != null &&
      etaMinutes! >= lunchStartMinutes! &&
      etaMinutes! < lunchEndMinutes!;

  /// True se sono stati indicati gli orari di apertura/chiusura.
  bool get hasHours => openStartMinutes != null && openEndMinutes != null;

  /// True se sono state indicate informazioni sugli orari (apertura o pausa).
  bool get hasAnyHours => hasHours || hasLunchBreak || continuousHours;

  /// True se il punto vendita risulta aperto all'orario [m] (minuti dalla
  /// mezzanotte), in base a orari di apertura ed eventuale pausa pranzo.
  /// Se non sono noti orari, si assume sempre aperto.
  bool isOpenAt(int m) {
    if (hasHours && (m < openStartMinutes! || m >= openEndMinutes!)) {
      return false;
    }
    if (hasLunchBreak &&
        m >= lunchStartMinutes! &&
        m < lunchEndMinutes!) {
      return false;
    }
    return true;
  }

  /// True se l'arrivo stimato cade quando il punto vendita è chiuso.
  bool get isClosedOnArrival =>
      etaMinutes != null &&
      (hasHours || hasLunchBreak) &&
      !isOpenAt(etaMinutes!);

  /// Etichetta leggibile degli orari (es. "8:30-13:00 · 15:00-19:30").
  String? get hoursLabel {
    if (hasHours && hasLunchBreak) {
      return '${formatMinutes(openStartMinutes!)}-${formatMinutes(lunchStartMinutes!)}'
          ' · ${formatMinutes(lunchEndMinutes!)}-${formatMinutes(openEndMinutes!)}';
    }
    if (hasHours) {
      return '${formatMinutes(openStartMinutes!)}-${formatMinutes(openEndMinutes!)}';
    }
    if (hasLunchBreak) {
      return 'pausa ${formatMinutes(lunchStartMinutes!)}-${formatMinutes(lunchEndMinutes!)}';
    }
    if (continuousHours) return 'orario continuato';
    return null;
  }

  /// True se la tappa è ancora da consegnare.
  bool get isPending => status == StopStatus.pending;

  /// True se la tappa è stata completata (consegnata o fallita).
  bool get isCompleted => status != StopStatus.pending;

  /// Etichetta leggibile della tratta dalla tappa precedente.
  String? get legLabel {
    if (legDistanceMeters == null) return null;
    final km = legDistanceMeters! / 1000.0;
    final dist = km < 1
        ? '$legDistanceMeters m'
        : '${km.toStringAsFixed(km < 10 ? 1 : 0)} km';
    if (legDurationSeconds == null) return dist;
    final min = (legDurationSeconds! / 60).round();
    final time = min < 60 ? '$min min' : '${min ~/ 60} h ${min % 60} min';
    return '$dist · $time';
  }

  Stop({
    String? id,
    required this.address,
    this.status = StopStatus.pending,
    this.pin = StopPin.none,
    this.deadlineMinutes,
    this.serviceType = ServiceType.none,
    this.note,
    this.continuousHours = false,
    this.lunchStartMinutes,
    this.lunchEndMinutes,
    this.openStartMinutes,
    this.openEndMinutes,
    this.lat,
    this.lng,
    this.city,
    this.province,
    this.provinceCode,
    this.region,
    this.postalCode,
  }) : id = id ?? _uuid.v4();

  Map<String, dynamic> toJson() => {
        'id': id,
        'address': address,
        'status': status.name,
        'pin': pin.name,
        'deadlineMinutes': deadlineMinutes,
        'serviceType': serviceType.name,
        'note': note,
        'continuousHours': continuousHours,
        'lunchStartMinutes': lunchStartMinutes,
        'lunchEndMinutes': lunchEndMinutes,
        'openStartMinutes': openStartMinutes,
        'openEndMinutes': openEndMinutes,
        'lat': lat,
        'lng': lng,
        'city': city,
        'province': province,
        'provinceCode': provinceCode,
        'region': region,
        'postalCode': postalCode,
      };

  factory Stop.fromJson(Map<String, dynamic> json) => Stop(
        id: json['id'] as String?,
        address: json['address'] as String? ?? '',
        status: StopStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => StopStatus.pending,
        ),
        pin: StopPin.values.firstWhere(
          (p) => p.name == json['pin'],
          orElse: () => StopPin.none,
        ),
        deadlineMinutes: (json['deadlineMinutes'] as num?)?.toInt(),
        serviceType: ServiceType.values.firstWhere(
          (t) => t.name == json['serviceType'],
          orElse: () => ServiceType.none,
        ),
        note: json['note'] as String?,
        continuousHours: json['continuousHours'] as bool? ?? false,
        lunchStartMinutes: (json['lunchStartMinutes'] as num?)?.toInt(),
        lunchEndMinutes: (json['lunchEndMinutes'] as num?)?.toInt(),
        openStartMinutes: (json['openStartMinutes'] as num?)?.toInt(),
        openEndMinutes: (json['openEndMinutes'] as num?)?.toInt(),
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
        city: json['city'] as String?,
        province: json['province'] as String?,
        provinceCode: json['provinceCode'] as String?,
        region: json['region'] as String?,
        postalCode: json['postalCode'] as String?,
      );

  /// Sottotitolo leggibile con città/provincia.
  String get subtitle {
    final parts = <String>[];
    if (city != null && city!.isNotEmpty) parts.add(city!);
    if (provinceCode != null && provinceCode!.isNotEmpty) {
      parts.add('(${provinceCode!})');
    } else if (province != null && province!.isNotEmpty) {
      parts.add(province!);
    }
    return parts.join(' ');
  }
}
