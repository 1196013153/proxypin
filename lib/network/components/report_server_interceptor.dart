/*
 * Copyright 2024 Hongen Wang All rights reserved.
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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/http/websocket.dart';
import 'package:proxypin/network/util/compress.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/utils/har.dart';

import '../bin/listener.dart';
import '../http/http.dart';
import 'interceptor.dart';
import 'manager/report_server_manager.dart';

/// Hosts interceptor
/// @author wanghongen
class ReportServerInterceptor extends Interceptor {
  Future<ReportServerManager> get reportServerManager async => await ReportServerManager.instance;

  static HttpClient httpClient = HttpClient();

  @override
  int get priority => 1000;

  @override
  Future<HttpRequest?> onRequest(HttpRequest request) async {
    unawaited(_reportRequestIfSplit(request));
    return request;
  }

  @override
  Future<HttpResponse?> onResponse(HttpRequest request, HttpResponse response) async {
    unawaited(reportServer(request, response));
    return response;
  }

  @override
  Future<void> onError(HttpRequest? request, error, StackTrace? stackTrace) async {
    if (request != null) {
      unawaited(reportServer(request, null, error: error, stackTrace: stackTrace));
    }
    return;
  }

  Future<void> _reportRequestIfSplit(HttpRequest request) async {
    String requestUrl = request.requestUrl;
    var manager = await reportServerManager;
    var server = await manager.matchServer(requestUrl);
    if (server == null || !server.splitReport) {
      return;
    }
    var payload = Har.toHarRequest(request);
    await sendReport(server, payload, requestUrl, phase: "request");
  }

  Future<void> reportServer(HttpRequest request, HttpResponse? response,
      {dynamic error, StackTrace? stackTrace}) async {
    if (response != null) {
      request.response = response;
    }

    String requestUrl = request.requestUrl;
    var manager = await reportServerManager;
    var server = await manager.matchServer(requestUrl);
    if (server == null) {
      return;
    }

    Map payload;
    String? phase;
    if (server.splitReport) {
      if (request.response == null) {
        return;
      }
      payload = Har.toHarResponse(request);
      phase = "response";
    } else {
      payload = Har.toHar(request);
    }
    await sendReport(server, payload, requestUrl, phase: phase);
  }

  Future<void> sendReport(ReportServer server, dynamic payload, String requestUrl, {String? phase}) async {
    try {
      logger.i("reportServer start: $requestUrl -> ${server.name} (${server.serverUrl})");

      var serverUrl = (server.serverUrl).trim();
      if (serverUrl.isEmpty) {
        logger.w('reportServer skipped: serverUrl empty for ${server.name}');
        return;
      }
      if (!serverUrl.startsWith('http://') && !serverUrl.startsWith('https://')) {
        serverUrl = 'http://$serverUrl';
      }

      final uri = Uri.parse(serverUrl);

      List<int> body = utf8.encode(jsonEncode(payload));
      final compression = server.compression?.toLowerCase();
      if (compression == 'gzip') {
        try {
          body = gzipEncode(body);
        } catch (e) {
          logger.w('reportServer gzip compress failed: $e');
        }
      }

      final ioReq = await httpClient.postUrl(uri).timeout(const Duration(seconds: 5));

      final matchedRule = server.name;
      if (matchedRule.isNotEmpty) {
        // URL encode the server name to support non-ASCII characters (e.g., Chinese)
        final encodedName = Uri.encodeComponent(matchedRule);
        ioReq.headers.set('X-Report-Name', encodedName);
      }
      if (phase != null) {
        ioReq.headers.set('X-Report-Phase', phase);
      }

      ioReq.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
      if (compression == 'gzip') {
        ioReq.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
      }

      ioReq.add(body);
      final ioResp = await ioReq.close().timeout(const Duration(seconds: 30));
      final respText = await ioResp.transform(utf8.decoder).join();
      if (ioResp.statusCode >= 200 && ioResp.statusCode < 300) {
        logger.i('reportServer delivered to ${server.name} (${uri.toString()}), status=${ioResp.statusCode}');
      } else {
        logger.w('reportServer delivery to ${server.name} failed, status=${ioResp.statusCode}, body=$respText');
      }
    } catch (e, st) {
      logger.e("reportServer error $requestUrl", error: e, stackTrace: st);
    }
  }
}

/// SSE (text/event-stream) 流式接口的远程上报监听器。
///
/// SSE 响应走 `notSupportedForward -> onSseHandle` 的流式通道，
/// 绕过 `HttpResponseProxyHandler`，`Interceptor.onResponse` 不会触发；
/// 因此通过 `EventListener` 在响应头到达时上报一次，之后把每条 SSE event
/// 缓冲并批量增量上报（phase=message），服务端可按 `_id` 聚合出完整事件序列。
class ReportSseEventListener extends EventListener {
  final ReportServerInterceptor _reporter = ReportServerInterceptor();

  /// 已上报过响应头的 SSE 请求 id，防止 HTTP/2 下 onResponse 重复触发
  static final Set<String> _sseHeaderReported = {};

  /// requestId -> 待上报的 message entries
  final Map<String, List<Map>> _pending = {};

  /// requestId -> 已缓冲的消息序号
  final Map<String, int> _seq = {};

  /// 响应头已确认可上报的请求 id（onMessage 阶段据此快速过滤，避免每帧都做 URL 匹配）
  static final Set<String> _sseActive = {};

  static const int _flushThreshold = 20;
  static const int _maxPendingPerRequest = 500;
  static const int _maxTrackedRequests = 1024;
  static bool _dropWarned = false;

  Timer? _flushTimer;

  ReportSseEventListener() {
    // 定时兜底：不足阈值(低频 SSE)的缓冲也要在 1s 内送达
    _flushTimer = Timer.periodic(const Duration(seconds: 1), (_) => unawaited(_flush(force: true)));
  }

  /// 响应头到达即上报一次（对应 SSE 流式通道的 listener.onResponse 触发点）
  @override
  void onResponse(ChannelContext channelContext, HttpResponse response) async {
    try {
      if (!response.headers.contentType.toLowerCase().startsWith('text/event-stream')) {
        return;
      }
      final request = response.request;
      if (request == null) {
        return;
      }
      final id = request.requestId;
      if (_sseHeaderReported.contains(id)) {
        return;
      }

      String requestUrl = request.requestUrl;
      var manager = await _reporter.reportServerManager;
      var server = await manager.matchServer(requestUrl);
      if (server == null) {
        return;
      }

      if (_sseHeaderReported.length >= _maxTrackedRequests) {
        await _flushAllTracked();
      }
      _sseHeaderReported.add(id);
      _sseActive.add(id);
      _seq[id] = 0;
      _pending[id] = [];

      await _reporter.reportServer(request, response);
    } catch (e, st) {
      logger.e("reportSse onResponse error", error: e, stackTrace: st);
    }
  }

  /// 逐帧缓冲 SSE event，达到阈值或定时器到期时批量上报
  @override
  void onMessage(dynamic channel, HttpMessage message, WebSocketFrame frame) {
    try {
      if (frame.isFromClient || message is! HttpResponse) {
        return;
      }
      if (!message.headers.contentType.toLowerCase().startsWith('text/event-stream')) {
        return;
      }
      final request = message.request;
      if (request == null) {
        return;
      }
      final id = request.requestId;
      if (!_sseActive.contains(id)) {
        return;
      }

      var pending = _pending[id];
      if (pending == null) {
        pending = _pending[id] = [];
      }
      if (pending.length >= _maxPendingPerRequest) {
        if (!_dropWarned) {
          _dropWarned = true;
          logger.w('reportSse pending overflow, drop messages for $id');
        }
        return;
      }
      final seq = _seq[id] ?? 0;
      _seq[id] = seq + 1;
      pending.add(Har.toHarMessage(request, frame, seq));

      if (pending.length >= _flushThreshold) {
        unawaited(_flush(force: false));
      }
    } catch (e, st) {
      logger.e("reportSse onMessage error", error: e, stackTrace: st);
    }
  }

  /// 定时批量上报：把每个请求缓冲的 entries 逐请求发送（phase=message）
  Future<void> _flush({required bool force}) async {
    if (_pending.isEmpty) {
      return;
    }
    final ids = List.of(_pending.keys);
    for (final id in ids) {
      final pending = _pending[id];
      if (pending == null || pending.isEmpty) {
        continue;
      }
      if (!force && pending.length < _flushThreshold) {
        continue;
      }
      _pending[id] = [];
      try {
        var manager = await _reporter.reportServerManager;
        // entry 的 request.url 即该请求的完整 URL
        final url = pending.first['request'] is Map ? (pending.first['request']['url'] as String?) : null;
        if (url == null) {
          continue;
        }
        var server = await manager.matchServer(url);
        if (server == null) {
          continue;
        }
        await _reporter.sendReport(server, pending, url, phase: 'message');
      } catch (e, st) {
        logger.e('reportSse flush error', error: e, stackTrace: st);
      }
    }
  }

  /// 跟踪数量达到上限时，把全部缓冲先发出去再重置跟踪状态
  Future<void> _flushAllTracked() async {
    await _flush(force: true);
    _sseHeaderReported.clear();
    _sseActive.clear();
    _seq.clear();
  }

  void dispose() {
    _flushTimer?.cancel();
    _flushTimer = null;
  }
}
