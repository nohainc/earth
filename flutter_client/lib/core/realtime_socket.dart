import 'realtime_socket_stub.dart'
    if (dart.library.io) 'realtime_socket_io.dart' as platform;

import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel connectRealtimeSocket(Uri uri, String? token) =>
    platform.connectRealtimeSocket(uri, token);
