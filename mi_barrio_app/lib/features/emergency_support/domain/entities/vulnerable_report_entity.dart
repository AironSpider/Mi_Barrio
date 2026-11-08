/// Reporte de vecino en situación vulnerable (contrato `vulnerable_reports`).
///
/// Es la entidad que consume la UI. Dev 2 la llena desde SQLite / sync
/// (ver `domain/repositories/emergency_repository.dart`).
class VulnerableReport {
  const VulnerableReport({
    required this.id,
    required this.tenantId,
    required this.reporterUserId,
    required this.urgencyLevel,
    required this.vulnerabilityType,
    required this.description,
    required this.lat,
    required this.lng,
    this.status = ReportStatus.pendienteApoyo,
    this.helperUserId,
    required this.updatedAt,
    this.isPending = false,
    this.otherTypeLabel,
    this.peopleCount,
    this.hasInjured,
    this.vulnerableGroups = const [],
    this.contactPhone,
  });

  final String id;
  final String tenantId;
  final String reporterUserId;

  /// [UrgencyLevel.critica], [UrgencyLevel.alta] o [UrgencyLevel.media].
  final String urgencyLevel;

  /// Uno de [VulnerabilityType.values].
  final String vulnerabilityType;
  final String description;
  final double lat;
  final double lng;

  /// Uno de [ReportStatus.values].
  final String status;
  final String? helperUserId;

  /// ISO-8601 UTC.
  final String updatedAt;

  /// true si todavía no llegó al servidor (se muestra "Pendiente").
  final bool isPending;

  // ── Datos para decidir a quién ayudar primero (todos opcionales) ──
  /// Lo que escribió el vecino si eligió "Otro" (máx. 30 caracteres).
  final String? otherTypeLabel;
  final int? peopleCount;
  final bool? hasInjured;

  /// Valores de [VulnerableGroup] (puede haber varios).
  final List<String> vulnerableGroups;
  final String? contactPhone;

  /// Qué pasa, en palabras simples (con "Otro", lo que escribió el vecino).
  String get typeLabel =>
      vulnerabilityType == VulnerabilityType.otro &&
          (otherTypeLabel?.trim().isNotEmpty ?? false)
      ? otherTypeLabel!.trim()
      : VulnerabilityType.labels[vulnerabilityType] ?? vulnerabilityType;

  bool get needsHelp => status == ReportStatus.pendienteApoyo;

  VulnerableReport copyWith({String? status, String? helperUserId, bool? isPending, String? updatedAt}) {
    return VulnerableReport(
      id: id,
      tenantId: tenantId,
      reporterUserId: reporterUserId,
      urgencyLevel: urgencyLevel,
      vulnerabilityType: vulnerabilityType,
      description: description,
      lat: lat,
      lng: lng,
      status: status ?? this.status,
      helperUserId: helperUserId ?? this.helperUserId,
      updatedAt: updatedAt ?? this.updatedAt,
      isPending: isPending ?? this.isPending,
      otherTypeLabel: otherTypeLabel,
      peopleCount: peopleCount,
      hasInjured: hasInjured,
      vulnerableGroups: vulnerableGroups,
      contactPhone: contactPhone,
    );
  }
}

/// Nivel de urgencia (contrato: `urgency_level`).
class UrgencyLevel {
  UrgencyLevel._();
  static const critica = 'CRITICA';
  static const alta = 'ALTA';
  static const media = 'MEDIA';

  static const labels = {critica: 'Crítica', alta: 'Alta', media: 'Media'};

  /// Orden de prioridad: menor número = más urgente.
  static int rank(String level) => switch (level) {
    critica => 0,
    alta => 1,
    _ => 2,
  };

  static Set<String> get values => labels.keys.toSet();
}

/// Tipo de vulnerabilidad (contrato: `vulnerability_type`).
class VulnerabilityType {
  VulnerabilityType._();
  static const atencionMedica = 'ATENCION_MEDICA';
  static const adultoMayorSolo = 'ADULTO_MAYOR_SOLO';
  static const movilidadReducida = 'MOVILIDAD_REDUCIDA';
  static const viviendaAfectada = 'VIVIENDA_AFECTADA';
  static const faltaSuministros = 'FALTA_SUMINISTROS';
  // Lluvias e incendios
  static const inundacion = 'INUNDACION';
  static const incendio = 'INCENDIO';
  static const atrapados = 'ATRAPADOS';

  /// "Otro": el vecino escribe qué pasa (máx. [maxOtherLabel] caracteres).
  static const otro = 'OTRO';
  static const maxOtherLabel = 30;

  /// Lenguaje simple (lo entiende una niña de 10 años o una persona bajo
  /// estrés). El valor que viaja al servidor NO cambia, solo el texto.
  static const labels = {
    atencionMedica: 'Alguien está enfermo o herido',
    adultoMayorSolo: 'Persona mayor sola',
    movilidadReducida: 'No puede caminar o moverse',
    viviendaAfectada: 'Se dañó la casa',
    faltaSuministros: 'No hay agua o comida',
    inundacion: 'Se inundó o entró el agua',
    incendio: 'Hay fuego o humo',
    atrapados: 'Quedamos atrapados o aislados',
    otro: 'Otro',
  };

  /// Urgencia sugerida por tipo (el vecino no tiene que pensar en eso al pedir ayuda).
  static String defaultUrgency(String type) => switch (type) {
    atencionMedica || incendio || atrapados => UrgencyLevel.critica,
    faltaSuministros => UrgencyLevel.media,
    _ => UrgencyLevel.alta,
  };

  static Set<String> get values => labels.keys.toSet();
}

/// Estado del reporte (contrato: `status`).
class ReportStatus {
  ReportStatus._();
  static const pendienteApoyo = 'PENDIENTE_APOYO';
  static const vecinosEnCamino = 'VECINOS_EN_CAMINO';
  static const atendido = 'ATENDIDO';

  static const labels = {
    pendienteApoyo: 'Necesita apoyo',
    vecinosEnCamino: 'Vecinos en camino',
    atendido: 'Atendido',
  };

  static Set<String> get values => labels.keys.toSet();
}

/// Personas que necesitan más cuidado en una emergencia (contrato:
/// `vulnerable_groups`, separados por coma).
class VulnerableGroup {
  VulnerableGroup._();
  static const ninos = 'NINOS';
  static const mayores = 'MAYORES';
  static const discapacidad = 'DISCAPACIDAD';
  static const embarazada = 'EMBARAZADA';
  static const mascotas = 'MASCOTAS';

  static const labels = {
    ninos: 'Niños',
    mayores: 'Personas mayores',
    discapacidad: 'Con discapacidad',
    embarazada: 'Embarazada',
    mascotas: 'Mascotas',
  };

  static List<String> parse(String? raw) => [
    for (final g in (raw ?? '').split(','))
      if (labels.containsKey(g.trim())) g.trim(),
  ];
}
