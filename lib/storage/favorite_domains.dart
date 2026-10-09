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

import 'package:flutter/foundation.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/storage/path.dart';

/// 收藏域名存储（多选过滤请求列表），模式对齐 FavoritePathStorage
class FavoriteDomainStorage {
  static List<String>? list;

  /// 变更通知（增删改后自增），UI 用 ValueListenableBuilder 订阅
  static final ValueNotifier<int> changeNotifier = ValueNotifier<int>(0);

  /// 获取收藏域名列表
  static Future<List<String>> get domains async {
    if (list == null) {
      list = [];
      var file = await Paths.getPath("favorite_domains.json");
      if (await file.exists()) {
        var value = await file.readAsString();
        if (value.isEmpty) {
          return list!;
        }
        try {
          var config = jsonDecode(value) as List<dynamic>;
          for (var element in config) {
            addToList(list!, element.toString());
          }
        } catch (e, t) {
          logger.e('收藏域名列表解析失败', error: e, stackTrace: t);
        }
      }
    }
    return list!;
  }

  /// 从请求添加收藏域名，已存在返回 false
  static Future<bool> add(HttpRequest request) {
    return addHost(hostOf(request));
  }

  static Future<bool> addHost(String host) async {
    var domains = await FavoriteDomainStorage.domains;
    if (!addToList(domains, host)) {
      return false;
    }
    await flushConfig();
    return true;
  }

  static Future<void> remove(String host) async {
    var current = await domains;
    current.remove(normalize(host));
    await flushConfig();
  }

  //刷新配置
  static Future<void> flushConfig() async {
    var current = await domains;
    await Paths.getPath("favorite_domains.json").then((file) => file.writeAsString(jsonEncode(current)));
    changeNotifier.value++;
  }

  /// 规范化域名：去空白、转小写
  static String normalize(String host) => host.trim().toLowerCase();

  /// 加入列表（规范化 + 去重），成功返回 true，已存在或为空返回 false
  static bool addToList(List<String> domains, String host) {
    var key = normalize(host);
    if (key.isEmpty || domains.contains(key)) {
      return false;
    }
    domains.insert(0, key);
    return true;
  }

  /// 取请求 host（统一小写），无 host 时返回空串
  static String hostOf(HttpRequest request) {
    var uri = request.requestUri;
    return (request.hostAndPort?.host ?? uri?.host ?? '').trim().toLowerCase();
  }
}
