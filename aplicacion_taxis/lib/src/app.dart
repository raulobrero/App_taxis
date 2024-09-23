import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:convert';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Taxi App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Taxi App'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => Mapa()),
                );
              },
              child: Text('Página de Usuario'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => TaxistaPage()),
                );
              },
              child: Text('Página de Taxista'),
            ),
          ],
        ),
      ),
    );
  }
}

// Lista global de solicitudes de taxis
List<Map<String, dynamic>> solicitudes = [];

class Mapa extends StatefulWidget {
  @override
  _MapaState createState() => _MapaState();
}

class _MapaState extends State<Mapa> {
  LatLng origen = LatLng(-33.6118, -58.4173);  // Coordenadas predeterminadas
  LatLng destino = LatLng(-33.7118, -58.4173); 
  LatLng centro = LatLng(-33.6118, -58.4173);
  List<LatLng> ruta = [];
  TextEditingController _controllerDestino = TextEditingController();
  MapController _mapController = MapController();
  double _distanciaRuta = 0.0;
  double _tiempoRuta = 0.0; // Variable para almacenar el tiempo estimado de la ruta
  String _tarifaActual = ''; // Variable para almacenar el tipo de tarifa actual
  double _precioEstimado = 0.0; // Variable para almacenar el precio estimado

  @override
  void initState() {
    super.initState();
    _actualizarUbicacionActual();  
  }

  @override
  void dispose() {
    _controllerDestino.dispose();
    super.dispose();
  }

  Future<void> _actualizarUbicacionActual() async {
    try {
      Position position = await _determinePosition();
      setState(() {
        origen = LatLng(position.latitude, position.longitude);
        centro = origen;
        _mapController.move(centro, 13.0);
      });
    } catch (e) {
      // Manejo de errores si no se puede obtener la ubicación
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al obtener la ubicación: $e')),
      );
    }
  }

  Future<void> _obtenerRuta() async {
    final url = 'http://router.project-osrm.org/route/v1/driving/${origen.longitude},${origen.latitude};${destino.longitude},${destino.latitude}?geometries=geojson';
    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final jsonResponse = json.decode(response.body);
      final coordinates = jsonResponse['routes'][0]['geometry']['coordinates'];
      final distance = jsonResponse['routes'][0]['distance']; // Obtener la distancia de la ruta
      final duration = jsonResponse['routes'][0]['duration']; // Obtener el tiempo estimado de la ruta

      setState(() {
        ruta = coordinates.map<LatLng>((coord) {
          return LatLng(coord[1], coord[0]);
        }).toList();

        _distanciaRuta = distance / 1000;
        _tiempoRuta = duration / 60; // Convertir el tiempo a minutos
        _calcularTarifa(); // Calcular la tarifa y el precio estimado

        if (ruta.isNotEmpty) {
          centro = _calcularCentroRuta(ruta);
          _mapController.move(centro, 13.0); // Mover el centro del mapa al nuevo centro
        } else {
          centro = origen;
          _mapController.move(centro, 13.0); // Mover el centro del mapa al origen si no hay ruta
        }
      });
    } else {
      throw Exception('Error al obtener la ruta');
    }
  }

  Future<Position> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Verifica si los servicios de ubicación están habilitados.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Los servicios de ubicación no están habilitados. No continúes.
      return Future.error('Los servicios de ubicación están deshabilitados.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // Los permisos están denegados. No continúes.
        return Future.error('Los permisos de ubicación están denegados.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // Los permisos están denegados para siempre. No continúes.
      return Future.error('Los permisos de ubicación están denegados para siempre.');
    }

    // Cuando los permisos están concedidos, obtiene la ubicación actual.
    return await Geolocator.getCurrentPosition();
  }

  LatLng _calcularCentroRuta(List<LatLng> ruta) {
    double latSum = 0;
    double lonSum = 0;
    for (var punto in ruta) {
      latSum += punto.latitude;
      lonSum += punto.longitude;
    }
    return LatLng(latSum / ruta.length, lonSum / ruta.length);
  }

  void _calcularTarifa() {
    TimeOfDay now = TimeOfDay.now();
    double tarifaInicio;
    double tarifaKilometro;
    String tipoTarifa;

    DateTime ahora = DateTime.now();
    bool esLaborable = ahora.weekday >= 1 && ahora.weekday <= 5; // Lunes a viernes

    if (esLaborable && now.hour >= 7 && now.hour < 21) {
      tarifaInicio = 2.50;
      tarifaKilometro = 1.30;
      tipoTarifa = 'Tarifa Laborable (Día)';
    } else if (esLaborable && (now.hour < 7 || now.hour >= 21)) {
      tarifaInicio = 3.15;
      tarifaKilometro = 1.50;
      tipoTarifa = 'Tarifa Nocturna (Laborable)';
    } else {
      tarifaInicio = 3.15;
      tarifaKilometro = 1.50;
      tipoTarifa = 'Tarifa No Laborable (Sábado/Domingo)';
    }

    // Cálculo del precio estimado
    setState(() {
      _tarifaActual = tipoTarifa;
      _precioEstimado = tarifaInicio + (_distanciaRuta * tarifaKilometro);
    });
  }

  Future<LatLng> _obtenerCoordenadas(String direccion) async {
    final url = 'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(direccion)}&format=json&addressdetails=1';
    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final jsonResponse = json.decode(response.body);
      if (jsonResponse.isNotEmpty) {
        final lat = double.parse(jsonResponse[0]['lat']);
        final lon = double.parse(jsonResponse[0]['lon']);
        return LatLng(lat, lon);
      } else {
        throw Exception('No se encontraron coordenadas para la dirección');
      }
    } else {
      throw Exception('Error al obtener coordenadas');
    }
  }

  void _obtenerValores() {
    String direccionDestino = _controllerDestino.text;

    _obtenerCoordenadas(direccionDestino).then((coordenadas) {
      setState(() {
        destino = coordenadas;
        ruta.clear(); // Limpiar la ruta anterior
      });

      _obtenerRuta(); // Actualizar la ruta
    }).catchError((e) {
      // Manejo de errores si la dirección no es válida
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    });
  }

  void _solicitarTaxi() {
    final nuevaSolicitud = {
      'id': solicitudes.length + 1,
      'origen': origen,
      'destino': destino,
      'precio': _precioEstimado,
      'estado': 'pendiente'
    };

    setState(() {
      solicitudes.add(nuevaSolicitud);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('¡Taxi solicitado con éxito!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Mapa de Rutas'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controllerDestino,
                    decoration: InputDecoration(
                      labelText: 'Dirección de destino',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _obtenerValores,
                  child: Text('Obtener Ruta'),
                ),
              ],
            ),
          ),
          if (_distanciaRuta > 0)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Card(
                elevation: 5,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Distancia de la ruta: ${_distanciaRuta.toStringAsFixed(2)} km', style: TextStyle(fontSize: 16)),
                      Text('Tiempo estimado: ${_tiempoRuta.toStringAsFixed(2)} minutos', style: TextStyle(fontSize: 16)),
                      Text('Tarifa actual: $_tarifaActual', style: TextStyle(fontSize: 16)),
                      Text('Precio estimado: \$${_precioEstimado.toStringAsFixed(2)}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
          if (_distanciaRuta > 0)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: ElevatedButton.icon(
                onPressed: _solicitarTaxi,
                icon: Icon(Icons.local_taxi),
                label: Text('Solicitar Taxi'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                center: centro,
                zoom: 13.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                  subdomains: ['a', 'b', 'c'],
                  userAgentPackageName: 'com.example.app',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      width: 80.0,
                      height: 80.0,
                      point: origen,
                      builder: (ctx) => Icon(
                        Icons.location_on,
                        color: Colors.red,
                        size: 40.0,
                      ),
                    ),
                    Marker(
                      width: 80.0,
                      height: 80.0,
                      point: destino,
                      builder: (ctx) => Icon(
                        Icons.location_on,
                        color: Colors.blue,
                        size: 40.0,
                      ),
                    ),
                  ],
                ),
                if (ruta.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: ruta,
                        strokeWidth: 4.0,
                        color: Colors.blue,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TaxistaPage extends StatefulWidget {
  @override
  _TaxistaPageState createState() => _TaxistaPageState();
}

class _TaxistaPageState extends State<TaxistaPage> {
  void _aceptarSolicitud(int id) {
    setState(() {
      solicitudes = solicitudes.map((solicitud) {
        if (solicitud['id'] == id) {
          solicitud['estado'] = 'aceptado';
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => RutaTaxista(
                origenTaxista: LatLng(-33.6098, -58.4173), // Aquí puedes usar la ubicación actual del taxista
                origenUsuario: solicitud['origen'],
                destinoUsuario: solicitud['destino'],
              ),
            ),
          );
        }
        return solicitud;
      }).toList();
    });
  }

  void _rechazarSolicitud(int id) {
    setState(() {
      solicitudes = solicitudes.map((solicitud) {
        if (solicitud['id'] == id) {
          solicitud['estado'] = 'rechazado';
        }
        return solicitud;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Solicitudes de Taxis'),
      ),
      body: ListView.builder(
        itemCount: solicitudes.length,
        itemBuilder: (context, index) {
          final solicitud = solicitudes[index];
          return Card(
            margin: EdgeInsets.all(10),
            child: ListTile(
              title: Text('Solicitud ${solicitud['id']}'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Origen: ${solicitud['origen']}'),
                  Text('Destino: ${solicitud['destino']}'),
                  Text('Precio: \$${solicitud['precio']}'),
                  Text('Estado: ${solicitud['estado']}'),
                ],
              ),
              trailing: solicitud['estado'] == 'pendiente'
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.check, color: Colors.green),
                          onPressed: () => _aceptarSolicitud(solicitud['id']),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: Colors.red),
                          onPressed: () => _rechazarSolicitud(solicitud['id']),
                        ),
                      ],
                    )
                  : null,
            ),
          );
        },
      ),
    );
  }
}

class RutaTaxista extends StatefulWidget {
  final LatLng origenTaxista;
  final LatLng origenUsuario;
  final LatLng destinoUsuario;

  RutaTaxista({required this.origenTaxista, required this.origenUsuario, required this.destinoUsuario});

  @override
  _RutaTaxistaState createState() => _RutaTaxistaState();
}

class _RutaTaxistaState extends State<RutaTaxista> {
  List<LatLng> rutaTaxistaAUsuario = [];
  List<LatLng> rutaUsuarioADestino = [];
  MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _obtenerRutas();
  }

  Future<void> _obtenerRutas() async {
    await _obtenerRuta(widget.origenTaxista, widget.origenUsuario).then((ruta) {
      setState(() {
        rutaTaxistaAUsuario = ruta;
      });
    });

    await _obtenerRuta(widget.origenUsuario, widget.destinoUsuario).then((ruta) {
      setState(() {
        rutaUsuarioADestino = ruta;
      });
    });

    if (rutaTaxistaAUsuario.isNotEmpty) {
      _mapController.move(_calcularCentroRuta(rutaTaxistaAUsuario), 13.0);
    }
  }

  Future<List<LatLng>> _obtenerRuta(LatLng origen, LatLng destino) async {
    final url = 'http://router.project-osrm.org/route/v1/driving/${origen.longitude},${origen.latitude};${destino.longitude},${destino.latitude}?geometries=geojson';
    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final jsonResponse = json.decode(response.body);
      final coordinates = jsonResponse['routes'][0]['geometry']['coordinates'];
      return coordinates.map<LatLng>((coord) {
        return LatLng(coord[1], coord[0]);
      }).toList();
    } else {
      throw Exception('Error al obtener la ruta');
    }
  }

  LatLng _calcularCentroRuta(List<LatLng> ruta) {
    double latSum = 0;
    double lonSum = 0;
    for (var punto in ruta) {
      latSum += punto.latitude;
      lonSum += punto.longitude;
    }
    return LatLng(latSum / ruta.length, lonSum / ruta.length);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Ruta del Taxista'),
      ),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          center: LatLng((widget.origenTaxista.latitude + widget.destinoUsuario.latitude) / 2,
              (widget.origenTaxista.longitude + widget.destinoUsuario.longitude) / 2),
          zoom: 13.0,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
            subdomains: ['a', 'b', 'c'],
            userAgentPackageName: 'com.example.app',
          ),
          MarkerLayer(
            markers: [
              Marker(
                width: 80.0,
                height: 80.0,
                point: widget.origenTaxista,
                builder: (ctx) => Icon(
                  Icons.local_taxi,
                  color: Colors.green,
                  size: 40.0,
                ),
              ),
              Marker(
                width: 80.0,
                height: 80.0,
                point: widget.origenUsuario,
                builder: (ctx) => Icon(
                  Icons.location_on,
                  color: Colors.red,
                  size: 40.0,
                ),
              ),
              Marker(
                width: 80.0,
                height: 80.0,
                point: widget.destinoUsuario,
                builder: (ctx) => Icon(
                  Icons.flag,
                  color: Colors.blue,
                  size: 40.0,
                ),
              ),
            ],
          ),
          if (rutaTaxistaAUsuario.isNotEmpty)
            PolylineLayer(
              polylines: [
                Polyline(
                  points: rutaTaxistaAUsuario,
                  strokeWidth: 4.0,
                  color: Colors.green,
                ),
              ],
            ),
          if (rutaUsuarioADestino.isNotEmpty)
            PolylineLayer(
              polylines: [
                Polyline(
                  points: rutaUsuarioADestino,
                  strokeWidth: 4.0,
                  color: Colors.blue,
                ),
              ],
            ),
        ],
      ),
    );
  }
}
