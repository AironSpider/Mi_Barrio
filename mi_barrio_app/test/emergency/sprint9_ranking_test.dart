import 'package:flutter_test/flutter_test.dart';
import 'package:mi_barrio_app/features/proximity_services/data/models/service_model.dart';
import 'package:mi_barrio_app/features/solidarity_network/data/models/solidarity_post_model.dart';
import 'package:mi_barrio_app/shared/emergency_ranking.dart';

/// Sprint 9 · Dev 2: orden del podio "Prioridad 1-3" en emergencia.
void main() {
  const tenant = 'a1b2c3d4-e5f6-4a8b-9c0d-1e2f3a4b5c6d';
  const owner = '9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d';
  // Vecino en el centro de Piura.
  const lat = -5.1945;
  const lng = -80.6328;
  // ~0,1 km y ~1,1 km al norte.
  const nearLat = -5.1936;
  const farLat = -5.1845;

  LocalServiceModel service(
    String id, {
    bool emergency = false,
    String category = ServiceCategory.gasfiteria,
    double? rating,
    double pLat = lat,
    bool deleted = false,
  }) =>
      LocalServiceModel(
        id: id,
        tenantId: tenant,
        providerUserId: owner,
        category: category,
        title: 'Servicio $id',
        isAvailableInEmergency: emergency,
        ratingAvg: rating,
        lat: pLat,
        lng: lng,
        isDeleted: deleted,
        updatedAt: '2026-11-07T10:00:00Z',
      );

  SolidarityPostModel post(
    String id, {
    bool emergencyContext = false,
    String modality = SolidarityModality.prestamoHerramienta,
    String status = SolidarityStatus.disponible,
    double pLat = lat,
    String updatedAt = '2026-11-07T10:00:00Z',
    bool deleted = false,
  }) =>
      SolidarityPostModel(
        id: id,
        tenantId: tenant,
        authorUserId: owner,
        flowType: SolidarityFlowType.solicitoAyuda,
        modality: modality,
        title: 'Favor $id',
        isEmergencyContext: emergencyContext,
        status: status,
        lat: pLat,
        lng: lng,
        isDeleted: deleted,
        updatedAt: updatedAt,
      );

  List<String> ids<T>(List<Ranked<T>> ranked, String Function(T) id) =>
      ranked.map((r) => id(r.item)).toList();

  group('rankServices', () {
    test('disponible en emergencia → SOPORTE_EMERGENCIA → estrellas → cercanía', () {
      final ranked = EmergencyRanking.rankServices([
        service('normal-5', rating: 5),
        service('soporte', category: ServiceCategory.soporteEmergencia, rating: 3),
        service('emerg-lejos', emergency: true, rating: 4, pLat: farLat),
        service('emerg-cerca', emergency: true, rating: 4, pLat: nearLat),
        service('emerg-soporte', emergency: true, category: ServiceCategory.soporteEmergencia),
        service('emerg-5', emergency: true, rating: 5, pLat: farLat),
      ], lat: lat, lng: lng);

      expect(ids(ranked, (s) => s.id), [
        'emerg-soporte', // disponible + categoría de emergencia
        'emerg-5', // mejor promedio gana aunque esté lejos
        'emerg-cerca', // mismo promedio: el más cercano
        'emerg-lejos',
        'soporte', // categoría de emergencia sin disponibilidad
        'normal-5',
      ]);
    });

    test('sin calificaciones va después de los calificados', () {
      final ranked = EmergencyRanking.rankServices([
        service('sin-estrellas', pLat: nearLat),
        service('una-estrella', rating: 1, pLat: farLat),
      ], lat: lat, lng: lng);
      expect(ids(ranked, (s) => s.id), ['una-estrella', 'sin-estrellas']);
    });

    test('podio: solo los 3 primeros llevan Prioridad 1, 2 y 3', () {
      final ranked = EmergencyRanking.rankServices([
        for (var i = 1; i <= 5; i++) service('s$i', rating: i.toDouble()),
      ]);
      expect(ranked.map((r) => r.priority), [1, 2, 3, null, null]);
      expect(ranked.map((r) => r.position), [1, 2, 3, 4, 5]);
      expect(ranked.where((r) => r.isPodium).map((r) => r.item.id), ['s5', 's4', 's3']);
    });

    test('los borrados no aparecen y una lista vacía no falla', () {
      final ranked = EmergencyRanking.rankServices([
        service('borrado', emergency: true, deleted: true),
        service('vivo'),
      ]);
      expect(ids(ranked, (s) => s.id), ['vivo']);
      expect(ranked.single.priority, 1);
      expect(EmergencyRanking.rankServices(const []), isEmpty);
    });

    test('sin ubicación del vecino no usa la distancia (distanceKm = null)', () {
      final ranked = EmergencyRanking.rankServices([
        service('b', pLat: farLat),
        service('a', pLat: nearLat),
      ]);
      expect(ids(ranked, (s) => s.id), ['a', 'b']); // desempate estable por id
      expect(ranked.every((r) => r.distanceKm == null), isTrue);
    });

    test('con ubicación calcula la distancia de cada tarjeta', () {
      final ranked = EmergencyRanking.rankServices(
        [service('a', pLat: farLat)],
        lat: lat,
        lng: lng,
      );
      expect(ranked.single.distanceKm, closeTo(1.1, 0.05));
    });

    test('el resultado es el mismo sin importar el orden de entrada', () {
      final input = [
        service('x', rating: 4),
        service('y', emergency: true),
        service('z', rating: 4),
      ];
      final a = ids(EmergencyRanking.rankServices(input), (s) => s.id);
      final b = ids(EmergencyRanking.rankServices(input.reversed), (s) => s.id);
      expect(a, b);
      expect(a, ['y', 'x', 'z']);
    });
  });

  group('rankPosts', () {
    test('emergencia o RECURSO_CRITICO → DISPONIBLE → cercanía → más reciente', () {
      final ranked = EmergencyRanking.rankPosts([
        post('normal-cerca', pLat: nearLat),
        post('critico-coordinando',
            modality: SolidarityModality.recursoCritico,
            status: SolidarityStatus.enCoordinacion),
        post('emerg-lejos', emergencyContext: true, pLat: farLat),
        post('critico-cerca', modality: SolidarityModality.recursoCritico, pLat: nearLat),
        post('normal-cerca-nuevo', pLat: nearLat, updatedAt: '2026-11-07T12:00:00Z'),
      ], lat: lat, lng: lng);

      expect(ids(ranked, (p) => p.id), [
        'critico-cerca',
        'emerg-lejos',
        'critico-coordinando', // urgente pero ya alguien lo coordina
        'normal-cerca-nuevo', // misma distancia: el más reciente primero
        'normal-cerca',
      ]);
    });

    test('COMPLETADO va al final y nunca ocupa el podio', () {
      final ranked = EmergencyRanking.rankPosts([
        post('critico-hecho',
            modality: SolidarityModality.recursoCritico,
            status: SolidarityStatus.completado),
        post('normal'),
      ]);
      expect(ids(ranked, (p) => p.id), ['normal', 'critico-hecho']);
      expect(ranked.map((r) => r.priority), [1, null]);
    });

    test('podio de 3 aunque haya muchos favores urgentes', () {
      final ranked = EmergencyRanking.rankPosts([
        for (var i = 0; i < 6; i++)
          post('p$i', emergencyContext: true, updatedAt: '2026-11-07T1$i:00:00Z'),
      ]);
      expect(ranked.where((r) => r.isPodium).map((r) => r.item.id), ['p5', 'p4', 'p3']);
      expect(ranked.where((r) => r.isPodium).map((r) => r.priority), [1, 2, 3]);
    });

    test('borrados fuera; isUrgentPost reconoce ambos casos', () {
      final ranked = EmergencyRanking.rankPosts([
        post('borrado', emergencyContext: true, deleted: true),
        post('vivo'),
      ]);
      expect(ids(ranked, (p) => p.id), ['vivo']);
      expect(EmergencyRanking.isUrgentPost(post('e', emergencyContext: true)), isTrue);
      expect(
        EmergencyRanking.isUrgentPost(post('c', modality: SolidarityModality.recursoCritico)),
        isTrue,
      );
      expect(EmergencyRanking.isUrgentPost(post('n')), isFalse);
    });
  });
}
