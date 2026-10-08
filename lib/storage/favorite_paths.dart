/*
 * Copyright 2023 Hongen Wang All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_client.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/storage/path.dart';

/// 收藏接口路径存储（host+path 快捷过滤/重放），模式对齐 [FavoriteStorage]
class FavoritePathStorage {
  static List<FavoritePath>? list;

  /// 变更通知（增删改后自增），UI 用 ValueListenableBuilder 订阅
  static final ValueNotifier<int> changeNotifier = ValueNotifier<int>(0);

  /// 获取收藏路径列表
  static Future<List<FavoritePath>> get paths async {
    if (list == null) {
      list = [];
      var file = await Paths.getPath("favorite_paths.json");
      if (await file.exists()) {
        var value = await file.readAsString();
        if (value.isEmpty) {
          return list!;
        }
        try {
          var config = jsonDecode(value) as List<dynamic>;
          for (var element in config) {
            list?.add(FavoritePath.fromJson(element));
          }
        } catch (e, t) {
          logger.e('收藏路径列表解析失败', error: e, stackTrace: t);
        }
      }
    }
    return list!;
  }

  /// 从请求添加收藏路径，已存在返回 false
  static Future<bool> add(HttpRequest request) async {
    final favoritePath = FavoritePath.fromRequest(request);
    return addPath(favoritePath);
  }

  static Future<bool> addPath(FavoritePath favoritePath) async {
    var paths = await FavoritePathStorage.paths;
    if (paths.any((element) => element.key == favoritePath.key)) {
      return false;
    }
    paths.insert(0, favoritePath);
    await flushConfig();
    return true;
  }

  static Future<void> remove(FavoritePath favoritePath) async {
    var current = await paths;
    current.remove(favoritePath);
    await flushConfig();
  }

  static Future<void> rename(FavoritePath favoritePath, String name) async {
    favoritePath.name = name;
    await flushConfig();
  }

  //刷新配置
  static Future<void> flushConfig() async {
    var paths = await paths;
    await Paths.getPath("favorite_paths.json").then((file) => file.writeAsString(jsonEncode(paths)));
    changeNotifier.value++;
  }
}

/// 收藏的接口路径：host + path（不含 query），method 为空表示任意方法
class FavoritePath {
  String? name;
  String? method;
  String host;
  int? port;
  String path;
  String scheme;
  DateTime createdAt;

  FavoritePath({
    this.name,
    this.method,
    required this.host,
    this.port,
    required this.path,
    this.scheme = 'https',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory FavoritePath.fromRequest(HttpRequest request) {
    var uri = request.requestUri;
    HostAndPort? hostAndPort = request.hostAndPort;
    var scheme = 'https';
    if (hostAndPort != null) {
      scheme = hostAndPort.scheme.startsWith('https') ? 'https' : 'http';
    } else if (request.requestUrl.startsWith('http://')) {
      scheme = 'http';
    }
    return FavoritePath(
      method: request.method.name,
      host: hostAndPort?.host ?? uri?.host ?? '',
      port: uri?.port ?? hostAndPort?.port,
      path: uri?.path ?? '/',
      scheme: scheme,
    );
  }

  factory FavoritePath.fromJson(Map<String, dynamic> json) {
    return FavoritePath(
      name: json['name'],
      method: json['method'],
      host: json['host'] ?? '',
      port: json['port'] == null ? null : int.tryParse(json['port'].toString()),
      path: json['path'] ?? '/',
      scheme: json['scheme'] ?? 'https',
      createdAt: json['createdAt'] == null ? null : DateTime.tryParse(json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'method': method,
      'host': host,
      if (port != null) 'port': port,
      'path': path,
      'scheme': scheme,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// 是否为 scheme 默认端口
  bool get _isDefaultPort =>
      port == null || (scheme == 'https' && port == 443) || (scheme == 'http' && port == 80);

  /// 去重键
  String get key => '${method ?? "*"} $url';

  /// 完整 URL（不含 query，默认端口省略）
  String get url => '$scheme://$host${_isDefaultPort ? '' : ':$port'}$path';

  /// 请求是否命中：host 精确 + path 精确（忽略 query）+ method 可选
  bool matches(HttpRequest request) {
    if (method != null && method!.isNotEmpty && method != request.method.name) {
      return false;
    }
    var uri = request.requestUri;
    if (uri == null) {
      return false;
    }
    if (uri.host != host || uri.path != path) {
      return false;
    }
    if (_isDefaultPort) {
      return true;
    }
    return uri.port == port;
  }

  @override
  String toString() {
    return '${method ?? "*"} $url';
  }

  /// 重放该路径：用 method+URL 构造最小请求（无 body/历史 headers），走自身代理
  Future<void> replay() async {
    var request = HttpRequest(
        method == null || method!.isEmpty ? HttpMethod.get : HttpMethod.values.byName(method!), url);
    request.hostAndPort = HostAndPort.of(url);
    var proxyServer = ProxyServer.current;
    var proxyInfo = proxyServer?.isRunning == true ? ProxyInfo.of("127.0.0.1", proxyServer!.port) : null;
    await HttpClients.proxyRequest(request, proxyInfo: proxyInfo);
  }
}
