import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/storage/favorite_paths.dart';

void main() {
  test('FavoritePath.fromRequest extracts scheme/host/path/method', () {
    final request = HttpRequest(HttpMethod.post, 'https://api.example.com:8443/v1/chat?token=abc');

    final fp = FavoritePath.fromRequest(request);
    expect(fp.scheme, 'https');
    expect(fp.host, 'api.example.com');
    expect(fp.port, 8443);
    expect(fp.path, '/v1/chat');
    expect(fp.method, 'POST');
    expect(fp.url, 'https://api.example.com:8443/v1/chat');
    expect(fp.key, 'POST https://api.example.com:8443/v1/chat');
  });

  test('FavoritePath omits default port in url', () {
    final https = FavoritePath.fromRequest(HttpRequest(HttpMethod.get, 'https://a.com/x'));
    expect(https.url, 'https://a.com/x');
    final http = FavoritePath.fromRequest(HttpRequest(HttpMethod.get, 'http://a.com/x'));
    expect(http.url, 'http://a.com/x');
  });

  test('FavoritePath.fromJson/toJson round trip', () {
    final fp = FavoritePath(method: 'GET', host: 'a.com', path: '/x', scheme: 'http', name: 'test');
    final restored = FavoritePath.fromJson(fp.toJson());
    expect(restored.method, 'GET');
    expect(restored.host, 'a.com');
    expect(restored.path, '/x');
    expect(restored.scheme, 'http');
    expect(restored.name, 'test');
    expect(restored.key, fp.key);
  });

  test('FavoritePath.matches honors host/path/method and ignores query', () {
    final fp = FavoritePath(method: 'GET', host: 'api.example.com', path: '/v1/stream');

    final matched = HttpRequest(HttpMethod.get, 'https://api.example.com/v1/stream?token=abc');
    expect(fp.matches(matched), isTrue);

    final wrongMethod = HttpRequest(HttpMethod.post, 'https://api.example.com/v1/stream');
    expect(fp.matches(wrongMethod), isFalse);

    final wrongPath = HttpRequest(HttpMethod.get, 'https://api.example.com/v1/other');
    expect(fp.matches(wrongPath), isFalse);

    final wrongHost = HttpRequest(HttpMethod.get, 'https://other.example.com/v1/stream');
    expect(fp.matches(wrongHost), isFalse);
  });

  test('FavoritePath.matches with null method matches any method', () {
    final fp = FavoritePath(host: 'api.example.com', path: '/v1/stream', method: null);
    expect(fp.matches(HttpRequest(HttpMethod.get, 'https://api.example.com/v1/stream')), isTrue);
    expect(fp.matches(HttpRequest(HttpMethod.post, 'https://api.example.com/v1/stream')), isTrue);
  });

  test('FavoritePath.matches honors port', () {
    final fp = FavoritePath.fromRequest(HttpRequest(HttpMethod.get, 'http://a.com:9000/x'));
    expect(fp.matches(HttpRequest(HttpMethod.get, 'http://a.com:9000/x?k=1')), isTrue);
    expect(fp.matches(HttpRequest(HttpMethod.get, 'http://a.com/x')), isFalse);
    expect(fp.matches(HttpRequest(HttpMethod.get, 'http://a.com:9001/x')), isFalse);

    final defaultPort = FavoritePath.fromRequest(HttpRequest(HttpMethod.get, 'https://a.com/x'));
    expect(defaultPort.matches(HttpRequest(HttpMethod.get, 'https://a.com/x')), isTrue);
  });
}
