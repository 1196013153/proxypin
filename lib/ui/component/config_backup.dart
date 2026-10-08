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

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/utils/config_backup.dart';
import 'package:proxypin/utils/lang.dart';

/// 配置备份共享入口（桌面/移动端复用）
class ConfigBackupHelper {
  /// 导出全部配置到用户选择的 JSON 文件
  static Future<void> export(BuildContext context) async {
    final localizations = AppLocalizations.of(context)!;
    try {
      final json = await ConfigBackup.exportJson();
      final date = DateTime.now().dateFormat();
      final path = await FilePicker.saveFile(
        fileName: 'proxypin_config_$date.json',
        bytes: utf8.encode(json),
      );
      if (path == null) {
        return;
      }
      if (context.mounted) {
        FlutterToastr.show(localizations.exportSuccess, context);
      }
    } catch (e) {
      if (context.mounted) {
        FlutterToastr.show('${localizations.exportFailed}: $e', context);
      }
    }
  }

  /// 从 JSON 文件导入配置，成功后提示重启生效
  static Future<void> import(BuildContext context) async {
    final localizations = AppLocalizations.of(context)!;
    try {
      final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['json']);
      if (file == null) {
        return;
      }
      var path = file.path;
      if (path == null) {
        // 部分平台仅返回字节流，先落临时文件
        final bytes = await file.readAsBytes();
        final tmp = await File('${Directory.systemTemp.path}/${file.name}').create();
        await tmp.writeAsBytes(bytes, flush: true);
        path = tmp.path;
      }

      final count = await ConfigBackup.importFromFile(path);
      if (!context.mounted) {
        return;
      }
      await showDialog(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: Text(localizations.importSuccess),
              content: Text(localizations.configBackupRestartHint(count)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(), child: Text(AppLocalizations.of(context)!.save)),
              ],
            );
          });
    } catch (e) {
      if (context.mounted) {
        FlutterToastr.show('${localizations.importFailed}: $e', context);
      }
    }
  }
}
