import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/storage/favorite_domains.dart';
import 'package:proxypin/ui/component/model/search_model.dart';

void main() {
  test('FavoriteDomainStorage.hostOf extracts lowercased host from request', () {
    var request = HttpRequest(HttpMethod.get, 'https://API.Example.COM:8443/v1/chat?token=abc');
    expect(FavoriteDomainStorage.hostOf(request), 'api.example.com');

    // 带 hostAndPort 的请求
    request.hostAndPort = HostAndPort.of('https://Other.Example.com:443');
    expect(FavoriteDomainStorage.hostOf(request), 'other.example.com');
  });

  test('FavoriteDomainStorage.normalize trims and lowercases', () {
    expect(FavoriteDomainStorage.normalize('  A.Example.COM '), 'a.example.com');
  });

  test('FavoriteDomainStorage.addToList dedupes ignoring case and inserts first', () {
    var domains = <String>[];

    expect(FavoriteDomainStorage.addToList(domains, 'a.com'), isTrue);
    expect(domains, ['a.com']);

    // 大小写不同视为同一域名
    expect(FavoriteDomainStorage.addToList(domains, 'A.com'), isFalse);
    expect(domains.length, 1);

    // 后收藏的排在前面
    expect(FavoriteDomainStorage.addToList(domains, 'b.com'), isTrue);
    expect(domains, ['b.com', 'a.com']);

    // 空域名不入列
    expect(FavoriteDomainStorage.addToList(domains, '   '), isFalse);
    expect(domains.length, 2);
  });

  test('SearchModel.filter honors favoriteDomains host matching', () {
    var searchModel = SearchModel()..favoriteDomains = ['api.example.com'];

    expect(
        searchModel.filter(HttpRequest(HttpMethod.get, 'https://api.example.com/v1/stream?token=abc'), null), isTrue);
    // host 大小写不敏感
    expect(searchModel.filter(HttpRequest(HttpMethod.get, 'https://API.Example.com/other'), null), isTrue);
    expect(searchModel.filter(HttpRequest(HttpMethod.get, 'https://other.example.com/v1/stream'), null), isFalse);

    // 空列表不过滤
    var empty = SearchModel();
    expect(empty.isEmpty, isTrue);
    expect(empty.filter(HttpRequest(HttpMethod.get, 'https://other.example.com/v1/stream'), null), isTrue);
  });

  test('SearchModel.isNotEmpty includes favoriteDomains', () {
    var searchModel = SearchModel();
    expect(searchModel.isEmpty, isTrue);
    searchModel.favoriteDomains = ['a.com'];
    expect(searchModel.isNotEmpty, isTrue);
    expect(searchModel.isEmpty, isFalse);
  });

  test('SearchModel.clone copies favoriteDomains', () {
    var searchModel = SearchModel()..favoriteDomains = ['a.com'];
    var clone = searchModel.clone();
    expect(clone.favoriteDomains, ['a.com']);

    clone.favoriteDomains.add('b.com');
    expect(searchModel.favoriteDomains, ['a.com']);
  });
}
