import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'app_theme.dart';

/// Mapa pequeño de un lugar (ej. dónde atiende un comerciante).
///
/// Con internet muestra las calles (OpenStreetMap); sin internet, el marcador
/// sobre un fondo liso. Se puede mover y hacer zoom con los dedos.
class LocationMap extends StatelessWidget {
  const LocationMap({
    super.key,
    required this.lat,
    required this.lng,
    required this.label,
    this.myLat,
    this.myLng,
    this.height = 200,
    this.icon = Icons.storefront_rounded,
    this.showStreets,
    this.onTapPoint,
  });

  /// Si no es null, tocar el mapa mueve el punto (elegir dónde atiendes).
  final void Function(double lat, double lng)? onTapPoint;

  final double lat;
  final double lng;

  /// Para el lector de pantalla: "Ubicación de Gasfitería Don Pedro".
  final String label;

  /// Ubicación del vecino (punto azul), si se conoce.
  final double? myLat;
  final double? myLng;
  final double height;
  final IconData icon;

  /// Calles de OpenStreetMap (por defecto sí, salvo en los tests: sin red).
  final bool? showStreets;

  @override
  Widget build(BuildContext context) {
    final colores = MiBarrioColors.of(context);
    final streets =
        showStreets ?? !Platform.environment.containsKey('FLUTTER_TEST');
    final place = LatLng(lat, lng);
    return Semantics(
      label: label,
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          height: height,
          child: FlutterMap(
            options: MapOptions(
              initialCenter: place,
              initialZoom: 16.5,
              minZoom: 12,
              maxZoom: 19,
              backgroundColor: colores.accentSoft,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onTap: onTapPoint == null
                  ? null
                  : (_, point) => onTapPoint!(point.latitude, point.longitude),
            ),
            children: [
              if (streets)
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  // = applicationId de Android (OpenStreetMap pide identificar la app).
                  userAgentPackageName: 'com.example.mi_barrio_app',
                  maxNativeZoom: 19,
                ),
              MarkerLayer(
                markers: [
                  if (myLat != null && myLng != null)
                    Marker(
                      point: LatLng(myLat!, myLng!),
                      width: 22,
                      height: 22,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppPalette.daySecondary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                      ),
                    ),
                  Marker(
                    point: place,
                    width: 48,
                    height: 56,
                    alignment: Alignment.topCenter,
                    child: Column(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: colores.brand,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: const [
                              BoxShadow(blurRadius: 6, color: Colors.black26),
                            ],
                          ),
                          child: Icon(icon, color: Colors.white, size: 24),
                        ),
                        Container(width: 3, height: 10, color: colores.brand),
                      ],
                    ),
                  ),
                ],
              ),
              if (streets)
                const SimpleAttributionWidget(
                  source: Text('© OpenStreetMap'),
                  backgroundColor: Color(0xCCFFFFFF),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
