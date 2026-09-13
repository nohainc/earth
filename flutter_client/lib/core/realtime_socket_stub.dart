import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel connectRealtimeSocket(Uri uri, String? token) =>
    WebSocketChannel.connect(uri);
