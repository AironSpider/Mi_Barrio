import 'package:flutter/material.dart';

import '../widgets/service_card.dart';

class _ServicioDemo {
  _ServicioDemo({
    required this.titulo,
    required this.categoria,
    required this.icono,
    required this.descripcion,
    required this.conteo,
    required this.enEmergencia,
  });

  final String titulo;
  final String categoria;
  final IconData icono;
  final String descripcion;
  final bool enEmergencia;
  int conteo;
  bool dado = false;
}

class ServicesDirectoryScreen extends StatefulWidget {
  const ServicesDirectoryScreen({super.key, this.emergencyOnly = false});

  final bool emergencyOnly;

  @override
  State<ServicesDirectoryScreen> createState() =>
      _ServicesDirectoryScreenState();
}

class _ServicesDirectoryScreenState extends State<ServicesDirectoryScreen> {
  final List<_ServicioDemo> _servicios = [
    _ServicioDemo(
      titulo: 'Don Pedro, gasfitero',
      categoria: 'Gasfitería',
      icono: Icons.plumbing_rounded,
      descripcion: 'Reparación de caños y fugas. Atiende en todo el barrio.',
      conteo: 12,
      enEmergencia: true,
    ),
    _ServicioDemo(
      titulo: 'Rosa, electricista',
      categoria: 'Electricidad',
      icono: Icons.electrical_services_rounded,
      descripcion: 'Instalaciones y cortocircuitos. Trabajo garantizado.',
      conteo: 9,
      enEmergencia: true,
    ),
    _ServicioDemo(
      titulo: 'Julio, carpintero',
      categoria: 'Carpintería',
      icono: Icons.carpenter_rounded,
      descripcion: 'Puertas, ventanas y muebles a medida.',
      conteo: 5,
      enEmergencia: false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final visibles = widget.emergencyOnly
        ? _servicios.where((s) => s.enEmergencia).toList()
        : _servicios;

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 96),
      itemCount: visibles.length,
      itemBuilder: (context, i) {
        final servicio = visibles[i];
        return ServiceCard(
          title: servicio.titulo,
          categoryLabel: servicio.categoria,
          categoryIcon: servicio.icono,
          description: servicio.descripcion,
          endorsementsCount: servicio.conteo,
          isEndorsed: servicio.dado,
          isPending: servicio.dado,
          isAvailableInEmergency: servicio.enEmergencia,
          onEndorse: () => setState(() {
            servicio.dado = !servicio.dado;
            servicio.conteo += servicio.dado ? 1 : -1;
          }),
        );
      },
    );
  }
}
