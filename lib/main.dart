import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart' as web_socket_server;
import 'package:uuid/uuid.dart';

const serviceName = 'bonsoirtest';
const servicePort = 8080;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  HttpServer? _server;
  bool _broadcasting = false;
  bool _discovering = false;

  @override
  void dispose() {
    _broadcast?.stop();
    _discovery?.stop();
    _server?.close();
    super.dispose();
  }

  Future<void> _broadcastService() async {
    final info = NetworkInfo();
    final wifiIP = await info.getWifiIP();

    if (wifiIP != null) {
      _server = await shelf_io.serve(
        web_socket_server
            .webSocketHandler((websocket) => debugPrint('New connection !')),
        InternetAddress(wifiIP),
        servicePort,
      );

      debugPrint('Serving at http://${_server!.address.host}:${_server!.port}');

      BonsoirService service = BonsoirService(
        name: serviceName,
        type: '_http._tcp',
        port: servicePort,
        attributes: {
          'userId': const Uuid().v4().toString(),
        },
      );

      // And now we can broadcast it :
      _broadcast = BonsoirBroadcast(service: service);
      await _broadcast!.ready;

      _broadcast!.eventStream!.listen((event) {
        debugPrint('Broadcast event : ${event.type}');
      });

      await _broadcast!.start();

      setState(() {
        _broadcasting = true;
      });
    }
  }

  Future<void> _stopBroadcast() async {
    await _broadcast?.stop();
    await _server?.close(force: true);
    setState(() {
      _broadcasting = false;
    });
  }

  Future<void> _discoverService() async {
    // This is the type of service we're looking for :
    String type = '_http._tcp';

    // Once defined, we can start the discovery :
    _discovery = BonsoirDiscovery(type: type, printLogs: true);
    await _discovery!.ready;

    // If you want to listen to the discovery :
    _discovery?.eventStream!.listen((event) async {
      debugPrint('Discovery event : ${event.type}');
      // `eventStream` is not null as the discovery instance is "ready" !
      final service = event.service;
      if (service != null) {
        if (event.type == BonsoirDiscoveryEventType.discoveryServiceFound) {
          if (service.name == serviceName) {
            await event.service!.resolve(_discovery!.serviceResolver);
          }
        } else if (event.type ==
            BonsoirDiscoveryEventType.discoveryServiceResolved) {
          final resolvedService = service as ResolvedBonsoirService;

          if (service.attributes.containsKey('userId')) {
            final userId = service.attributes['userId']!;
            final host = resolvedService.host;
            final port = resolvedService.port;
            if (host != null && port != 0) {
              debugPrint('Connecting to server $userId at $host:$port');
            }
          }
        } else if (event.type ==
            BonsoirDiscoveryEventType.discoveryServiceLost) {
          debugPrint('Service lost : ${service.toJson()}');
        }
      }
    });

    // Start discovery **after** having listened to discovery events :
    await _discovery?.start();
    setState(() {
      _discovering = true;
    });
  }

  Future<void> _stopDiscovery() async {
    await _discovery?.stop();
    setState(() {
      _discovering = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            ElevatedButton(
              onPressed: _broadcasting ? _stopBroadcast : _broadcastService,
              child: Text(_broadcasting ? 'Stop broadcasting' : 'Broadcast'),
            ),
            const SizedBox(height: 50),
            ElevatedButton(
              onPressed: _discovering ? _stopDiscovery : _discoverService,
              child: Text(_discovering ? 'Stop discovery' : 'Discover'),
            ),
          ],
        ),
      ),
    );
  }
}
