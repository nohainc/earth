import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel connectRealtimeSocket(Uri uri, String? token) {
  final headers = <String, dynamic>{};
  if (token != null && token.isNotEmpty) {
    headers['authorization'] = 'Bearer $token';
  }
  return IOWebSocketChannel.connect(uri, headers: headers);
}
