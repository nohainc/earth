import 'package:http/http.dart' as http;
import 'earth_http_client_stub.dart'
    if (dart.library.html) 'earth_http_client_web.dart' as platform;

http.Client createEarthHttpClient() => platform.createEarthHttpClient();
