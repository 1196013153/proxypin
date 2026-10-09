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
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/ui/component/multi_select_controller.dart';
import 'package:proxypin/storage/favorite_domains.dart';
import 'package:proxypin/storage/favorite_paths.dart';
import 'package:proxypin/ui/mobile/request/domians.dart';
import 'package:proxypin/ui/mobile/request/request.dart';
import 'package:proxypin/ui/mobile/request/request_sequence.dart';
import 'package:proxypin/utils/export_request.dart';
import 'package:proxypin/utils/listenable_list.dart';

import '../../component/model/search_model.dart';

/// 请求列表
/// @author wanghongen
class RequestListWidget extends StatefulWidget {
  final ProxyServer proxyServer;
  final ListenableList<HttpRequest>? list;
  final MultiSelectController selectionController;

  const RequestListWidget({super.key, required this.proxyServer, this.list, required this.selectionController});

  @override
  State<StatefulWidget> createState() {
    return RequestListState();
  }
}

class RequestListState extends State<RequestListWidget> {
  final GlobalKey<RequestSequenceState> requestSequenceKey = GlobalKey<RequestSequenceState>();
  final GlobalKey<DomainListState> domainListKey = GlobalKey<DomainListState>();

  //请求列表容器
  ListenableList<HttpRequest> container = ListenableList();

  //当前搜索模型
  SearchModel? _currentSearchModel;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    if (widget.list != null) {
      container = widget.list!;
    }
  }

  @override
  void dispose() {
    RequestRowState.removeAutoReadByIds(container.map((request) => request.requestId));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> tabs = [Tab(child: Text(localizations.sequence)), Tab(child: Text(localizations.domainList))];

    //double click scroll to top
    var tabClickHandles = [
      DoubleClickHandle(handle: () => requestSequenceKey.currentState?.scrollToTop()),
      DoubleClickHandle(handle: () => domainListKey.currentState?.scrollToTop())
    ];

    return DefaultTabController(
        length: tabs.length,
        child: Scaffold(
          appBar: AppBar(
              title: TabBar(tabs: tabs, onTap: (index) => tabClickHandles[index].call()),
              automaticallyImplyLeading: false,
              actions: [favoritePathFilter(), favoriteDomainFilter()]),
          body: TabBarView(
            children: [
              RequestSequence(
                  key: requestSequenceKey,
                  container: container,
                  proxyServer: widget.proxyServer,
                  onRemove: sequenceRemove,
                  selectionController: widget.selectionController),
              DomainList(
                  key: domainListKey,
                  list: container,
                  proxyServer: widget.proxyServer,
                  onRemove: domainListRemove,
                  onInitialized: () {
                    if (_currentSearchModel != null && _currentSearchModel!.isNotEmpty) {
                      domainListKey.currentState?.search(_currentSearchModel!);
                    }
                  }),
            ],
          ),
        ));
  }

  ///添加请求
  void add(Channel channel, HttpRequest request) {
    container.add(request);
    requestSequenceKey.currentState?.add(request);
    domainListKey.currentState?.add(request);
  }

  ///添加响应
  void addResponse(ChannelContext channelContext, HttpResponse response) {
    requestSequenceKey.currentState?.addResponse(response);
    domainListKey.currentState?.addResponse(response);
  }

  ///移除
  void domainListRemove(List<HttpRequest> list) {
    container.removeWhere((element) => list.contains(element));
    requestSequenceKey.currentState?.remove(list);
    RequestRowState.removeAutoReadByIds(list.map((request) => request.requestId));
  }

  ///全部请求删除
  void sequenceRemove(List<HttpRequest> list) {
    container.removeWhere((element) => list.contains(element));
    domainListKey.currentState?.remove(list);
    RequestRowState.removeAutoReadByIds(list.map((request) => request.requestId));
  }

  /// 当前生效的收藏路径过滤（null = 未启用）
  FavoritePath? activeFavoritePath;

  /// 收藏路径过滤按钮：底部弹层选择一个收藏路径过滤请求列表
  Widget favoritePathFilter() {
    return ValueListenableBuilder<int>(
        valueListenable: FavoritePathStorage.changeNotifier,
        builder: (context, _, __) {
          return FutureBuilder<List<FavoritePath>>(
              future: FavoritePathStorage.paths,
              builder: (context, snapshot) {
                var paths = snapshot.data ?? const <FavoritePath>[];
                var active = activeFavoritePath;
                return IconButton(
                    tooltip: localizations.favoritePath,
                    onPressed: () {
                      showModalBottomSheet(
                          context: context,
                          builder: (sheetContext) {
                            return SafeArea(
                                child: ListView(shrinkWrap: true, children: [
                              ListTile(
                                  leading: const Icon(Icons.filter_alt_off_outlined),
                                  title: Text(localizations.favoritePathAll),
                                  onTap: () {
                                    Navigator.of(sheetContext).pop();
                                    applyFavoritePathFilter(null);
                                  }),
                              const Divider(height: 1),
                              ...paths.map((e) => ListTile(
                                    dense: true,
                                    leading: Icon(
                                        identical(active, e) ? Icons.star : Icons.star_border_outlined,
                                        color: Colors.orangeAccent),
                                    title: Text('${e.method ?? "*"} ${e.name?.isNotEmpty == true ? "${e.name} " : ""}${e.url}',
                                        style: const TextStyle(fontSize: 13)),
                                    onTap: () {
                                      Navigator.of(sheetContext).pop();
                                      applyFavoritePathFilter(e);
                                    },
                                    onLongPress: () {
                                      Navigator.of(sheetContext).pop();
                                      e.replay();
                                    },
                                  )),
                              if (paths.isEmpty)
                                ListTile(
                                    enabled: false,
                                    title: Text(localizations.favoritePathEmpty,
                                        style: const TextStyle(fontSize: 13))),
                            ]));
                          });
                    },
                    icon: Icon(Icons.star_border_outlined,
                        color: active != null ? Colors.orangeAccent : null));
                });
              });
  }

  /// 应用/清除收藏路径过滤
  void applyFavoritePathFilter(FavoritePath? favoritePath) {
    setState(() {
      activeFavoritePath = favoritePath;
    });
    var searchModel = _currentSearchModel ?? SearchModel();
    searchModel.favoritePaths = favoritePath == null ? [] : [favoritePath];
    search(searchModel);
  }

  /// 当前生效的域名过滤（空 = 未启用）
  List<String> activeFavoriteDomains = [];

  /// 域名过滤按钮：底部弹层多选收藏域名过滤请求列表，角标显示已选数量
  Widget favoriteDomainFilter() {
    return ValueListenableBuilder<int>(
        valueListenable: FavoriteDomainStorage.changeNotifier,
        builder: (context, _, __) {
          return FutureBuilder<List<String>>(
              future: FavoriteDomainStorage.domains,
              builder: (context, snapshot) {
                var domains = snapshot.data ?? const <String>[];
                var active = activeFavoriteDomains;
                return Stack(clipBehavior: Clip.none, children: [
                  IconButton(
                      tooltip: localizations.favoriteDomainFilter,
                      onPressed: () => showFavoriteDomainFilterSheet(domains),
                      icon: Icon(Icons.language, color: active.isNotEmpty ? Colors.orangeAccent : null)),
                  if (active.isNotEmpty)
                    Positioned(
                        right: 4,
                        top: 4,
                        child: Text('${active.length}',
                            style: const TextStyle(fontSize: 10, color: Colors.orangeAccent))),
                ]);
              });
        });
  }

  /// 多选收藏域名弹层：勾选后点确定生效，长按删除收藏域名
  void showFavoriteDomainFilterSheet(List<String> domains) {
    var selected = List<String>.from(activeFavoriteDomains);
    showModalBottomSheet(
        context: context,
        builder: (sheetContext) {
          return SafeArea(
              child: StatefulBuilder(builder: (context, setSheetState) {
            return Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                  leading: const Icon(Icons.filter_alt_off_outlined),
                  title: Text(localizations.favoriteDomainAll),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    applyFavoriteDomainFilter([]);
                  }),
              const Divider(height: 1),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  ...domains.map((domain) => ListTile(
                        dense: true,
                        leading: Checkbox(
                            value: selected.contains(domain),
                            onChanged: (checked) => setSheetState(() {
                                  checked == true ? selected.add(domain) : selected.remove(domain);
                                })),
                        title: Text(domain, style: const TextStyle(fontSize: 13)),
                        onTap: () => setSheetState(() {
                              selected.contains(domain) ? selected.remove(domain) : selected.add(domain);
                            }),
                        onLongPress: () {
                          Navigator.of(sheetContext).pop();
                          deleteFavoriteDomain(domain);
                        },
                      )),
                  if (domains.isEmpty)
                    ListTile(
                        enabled: false,
                        title: Text(localizations.favoriteDomainEmpty, style: const TextStyle(fontSize: 13))),
                ]),
              ),
              const Divider(height: 1),
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                TextButton.icon(
                    onPressed: () => setSheetState(() => selected.clear()),
                    icon: const Icon(Icons.clear_all, size: 18),
                    label: Text(localizations.favoriteDomainClear)),
                TextButton.icon(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      applyFavoriteDomainFilter(selected);
                    },
                    icon: const Icon(Icons.check, size: 18),
                    label: Text(localizations.confirm)),
              ]),
            ]);
          }));
        });
  }

  /// 长按删除收藏域名，若删除的是生效中的过滤项则同步刷新列表
  Future<void> deleteFavoriteDomain(String domain) async {
    var confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(localizations.delete),
            content: Text(localizations.favoriteDomainDeleteConfirm),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(localizations.cancel)),
              TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(localizations.confirm)),
            ],
          );
        });
    if (confirmed != true) {
      return;
    }
    await FavoriteDomainStorage.remove(domain);
    var remaining = activeFavoriteDomains.where((e) => e != FavoriteDomainStorage.normalize(domain)).toList();
    applyFavoriteDomainFilter(remaining);
    if (mounted) FlutterToastr.show(localizations.deleteSuccess, context);
  }

  /// 应用/清除域名过滤
  void applyFavoriteDomainFilter(List<String> domains) {
    setState(() {
      activeFavoriteDomains = List.of(domains);
    });
    var searchModel = _currentSearchModel ?? SearchModel();
    searchModel.favoriteDomains = activeFavoriteDomains;
    search(searchModel);
  }

  void search(SearchModel searchModel) {
    _currentSearchModel = searchModel; // 保存当前搜索状态
    requestSequenceKey.currentState?.search(searchModel);
    domainListKey.currentState?.search(searchModel);
  }

  Iterable<HttpRequest>? currentView() {
    return requestSequenceKey.currentState?.currentView();
  }

  ///清理
  void clean() {
    setState(() {
      RequestRowState.removeAutoReadByIds(container.map((request) => request.requestId));
      container.clear();
      domainListKey.currentState?.clean();
      requestSequenceKey.currentState?.clean();
    });
  }

  ///清理早期数据
  void cleanupEarlyData(int retain) {
    var list = container.source;
    if (list.length <= retain) {
      return;
    }

    var removeRange = container.removeRange(0, list.length - retain);

    domainListKey.currentState?.clean();
    requestSequenceKey.currentState?.clean();
    RequestRowState.removeAutoReadByIds(removeRange.map((request) => request.requestId));
  }

  //导出har或文件夹
  Future<void> export(BuildContext context, String title) async {
    var view = currentView()!;
    var folderName = '${title.contains("ProxyPin") ? '' : 'ProxyPin'}$title'.replaceAll(" ", "_").replaceAll(":", "_");

    showExportDialog(context, view.toList(), folderName);
  }

  void sort(bool sortDesc) {
    requestSequenceKey.currentState?.sort(sortDesc);
    domainListKey.currentState?.sort(sortDesc);
  }
}

class DoubleClickHandle {
  int tabClickTime = 0;
  final Function()? handle;

  DoubleClickHandle({this.handle});

  void call() {
    if (handle == null) {
      return;
    }

    if (DateTime.now().millisecondsSinceEpoch - tabClickTime < 500) {
      handle?.call();
    }
    tabClickTime = DateTime.now().millisecondsSinceEpoch;
  }
}
