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

import 'package:proxypin/storage/path.dart';

/// ProxyPin 配置备份：把应用支持目录下的配置文件打包为单一 JSON 便于迁移/恢复。
///
/// 导入采用「整文件替换」语义，写回后各配置管理器内存态仍是旧值，
/// 重启应用后完全生效（UI 上需提示）。
class ConfigBackup {
  static const String bundleType = 'proxypin-config-backup';
  static const int bundleVersion = 1;

  /// 主目录下的配置文件（不含抓包历史 histories.json 与设备相关的 ui_config.json）
  static const List<String> configFiles = [
    'config.cnf',
    'hosts.json',
    'request_rewrite.json',
    'request_map.json',
    'script.json',
    'request_breakpoint.json',
    'request_block.json',
    'network_condition.json',
    'environments.json',
    'request_crypto.json',
    'report_servers.json',
    'favorites.json',
    'favorite_paths.json',
  ];

  /// 规则附件子目录（请求体替换文本 / map-local 文件 / 脚本）
  static const List<String> configDirs = ['rewrite', 'request_map', 'scripts'];

  /// 打包当前配置为 bundle Map
  static Future<Map<String, dynamic>> exportAll() async {
    final home = await Paths.homePath();
    return exportFromDir(home);
  }

  static Future<Map<String, dynamic>> exportFromDir(String homePath) async {
    final files = <String, String>{};
    for (final name in configFiles) {
      final f = File('$homePath${Platform.pathSeparator}$name');
      if (await f.exists()) {
        files[name] = await f.readAsString();
      }
    }

    final dirs = <String, Map<String, String>>{};
    for (final dirName in configDirs) {
      final dir = Directory('$homePath${Platform.pathSeparator}$dirName');
      if (!await dir.exists()) {
        continue;
      }
      final entries = <String, String>{};
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is! File) {
          continue;
        }
        final rel = entity.path.substring(homePath.length + 1).replaceAll('\\', '/');
        entries[rel] = await entity.readAsString();
      }
      if (entries.isNotEmpty) {
        dirs[dirName] = entries;
      }
    }

    return {
      'app': bundleType,
      'version': bundleVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'files': files,
      'dirs': dirs,
    };
  }

  /// 导出为 JSON 字符串
  static Future<String> exportJson() async {
    return jsonEncode(await exportAll());
  }

  static Future<void> exportToFile(String path) async {
    await File(path).writeAsString(await exportJson(), flush: true);
  }

  static Future<int> importFromFile(String path) async {
    final content = await File(path).readAsString();
    return importFromJson(content);
  }

  /// 从 bundle JSON 导入，返回写入的文件数
  static Future<int> importFromJson(String content) async {
    final data = jsonDecode(content);
    if (data is! Map || data['app'] != bundleType) {
      throw const FormatException('not a proxypin config backup');
    }
    final homePath = await Paths.homePath();
    return importData(data, homePath);
  }

  /// 把 bundle 数据写入指定主目录（文件相对路径需通过安全校验），返回写入文件数
  static Future<int> importData(Map data, String homePath) async {
    int count = 0;
    final files = data['files'];
    if (files is Map) {
      for (final entry in files.entries) {
        final name = entry.key.toString();
        if (!configFiles.contains(name) || !_safeRelativePath(name)) {
          continue;
        }
        final f = File('$homePath${Platform.pathSeparator}$name');
        await f.parent.create(recursive: true);
        await f.writeAsString(entry.value.toString(), flush: true);
        count++;
      }
    }

    final dirs = data['dirs'];
    if (dirs is Map) {
      for (final dirEntry in dirs.entries) {
        final dirName = dirEntry.key.toString();
        if (!configDirs.contains(dirName) || dirEntry.value is! Map) {
          continue;
        }
        for (final entry in (dirEntry.value as Map).entries) {
          final rel = entry.key.toString().replaceAll('/', Platform.pathSeparator);
          if (!_safeRelativePath(rel) || !rel.startsWith('$dirName${Platform.pathSeparator}')) {
            continue;
          }
          final f = File('$homePath${Platform.pathSeparator}$rel');
          await f.parent.create(recursive: true);
          await f.writeAsString(entry.value.toString(), flush: true);
          count++;
        }
      }
    }
    return count;
  }

  /// 防路径穿越：禁止绝对路径与 .. 跳转
  static bool _safeRelativePath(String name) {
    if (name.isEmpty) {
      return false;
    }
    if (name.startsWith('/') || name.startsWith('\\') || name.contains(':')) {
      return false;
    }
    for (final part in name.split(RegExp(r'[/\\]'))) {
      if (part == '..' || part.isEmpty) {
        return false;
      }
    }
    return true;
  }
}
