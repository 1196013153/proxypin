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
import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/storage/favorite_paths.dart';

/// 收藏路径管理对话框
Future<void> showFavoritePathManageDialog(BuildContext context) async {
  await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
            title: Text(AppLocalizations.of(context)!.favoritePathManage),
            content: SizedBox(width: 480, height: 420, child: FavoritePathManageWidget()),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(context).pop(), child: Text(AppLocalizations.of(context)!.cancel)),
            ]);
      });
}

class FavoritePathManageWidget extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _FavoritePathManageWidgetState();
}

class _FavoritePathManageWidgetState extends State<FavoritePathManageWidget> {
  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    FavoritePathStorage.paths;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
        valueListenable: FavoritePathStorage.changeNotifier,
        builder: (context, _, __) {
          return FutureBuilder<List<FavoritePath>>(
              future: FavoritePathStorage.paths,
              builder: (context, snapshot) {
                var paths = snapshot.data ?? const <FavoritePath>[];
                if (paths.isEmpty) {
                  return Center(child: Text(localizations.favoritePathEmpty, style: const TextStyle(fontSize: 13)));
                }
                return ListView.builder(
                    itemCount: paths.length,
                    itemBuilder: (context, index) {
                      var favoritePath = paths[index];
                      return ListTile(
                        dense: true,
                        leading: Text(favoritePath.method ?? "*",
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        title: Text(favoritePath.name?.isNotEmpty == true
                            ? "${favoritePath.name} (${favoritePath.url})"
                            : favoritePath.url,
                            style: const TextStyle(fontSize: 12.5)),
                        onTap: () => favoritePath.replay(),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                              icon: const Icon(Icons.play_arrow_outlined, size: 18),
                              tooltip: localizations.favoritePathReplay,
                              onPressed: () => favoritePath.replay()),
                          IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 16),
                              tooltip: localizations.rename,
                              onPressed: () => _rename(favoritePath)),
                          IconButton(
                              icon: const Icon(Icons.delete_outline, size: 16),
                              tooltip: localizations.delete,
                              onPressed: () async {
                                await FavoritePathStorage.remove(favoritePath);
                                if (mounted) setState(() {});
                              }),
                        ]),
                      );
                    });
              });
        });
  }

  Future<void> _rename(FavoritePath favoritePath) async {
    var name = favoritePath.name;
    await showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
              title: Text(localizations.rename),
              content: TextField(
                controller: TextEditingController(text: name),
                onChanged: (v) => name = v,
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(localizations.cancel)),
                TextButton(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await FavoritePathStorage.rename(favoritePath, name ?? '');
                      if (mounted) setState(() {});
                    },
                    child: Text(localizations.save))
              ]);
        });
  }
}
