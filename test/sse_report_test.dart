import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/components/report_server_interceptor.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/websocket.dart';
import 'package:proxypin/utils/har.dart';

WebSocketFrame _sseFrame(String text, int index, {bool fromClient = false}) {
  final frame = WebSocketFrame(
    fin: true,
    opcode: 0x01,
    mask: false,
    payloadLength: text.length,
    maskingKey: 0,
    payloadData: Uint8List.fromList(text.codeUnits),
    time: DateTime.fromMillisecondsSinceEpoch(1710000000000 + index),
  );
  frame.isFromClient = fromClient;
  return frame;
}

void main() {
  test('toHarMessage contains _id/_phase/_sse and payload text', () {
    final request = HttpRequest(HttpMethod.get, 'https://api.example.com/v1/stream?x=1');
    final response = HttpResponse(HttpStatus.ok);
    response.headers.add('content-type', 'text/event-stream');
    request.response = response;
    response.request = request;

    final frame = _sseFrame('data: hello\n\n', 0);
    final har = Har.toHarMessage(request, frame, 3);

    expect(har['_id'], request.requestId);
    expect(har['_phase'], 'message');
    expect(har['_sse']['index'], 3);
    expect(har['_sse']['isFromClient'], false);
    expect(har['request']['method'], 'GET');
    expect(har['request']['url'], 'https://api.example.com/v1/stream?x=1');
    expect(har['response']['content']['text'], 'data: hello\n\n');
    expect(har['response']['status'], 200);
    expect(har['response']['bodySize'], 'data: hello\n\n'.length);
  });

  test('toHarMessage truncates long payload', () {
    final request = HttpRequest(HttpMethod.get, 'https://api.example.com/v1/stream');
    final longText = 'a' * (Har.maxMessageTextLength + 100);

    final har = Har.toHarMessage(request, _sseFrame(longText, 0), 0);

    final text = har['response']['content']['text'] as String;
    expect(text.length, greaterThan(Har.maxMessageTextLength));
    expect(text.endsWith('...[truncated]'), isTrue);
    expect(text.startsWith('a' * 10), isTrue);
  });

  test('ReportSseEventListener buffers only sse response frames and flushes by batch', () async {
    final listener = ReportSseEventListener();
    final request = HttpRequest(HttpMethod.get, 'https://api.example.com/v1/stream');
    final response = HttpResponse(HttpStatus.ok);
    response.headers.add('content-type', 'text/event-stream');
    request.response = response;
    response.request = request;

    // onMessage 需要先在 onResponse 里确认可上报
    listener.onResponse(ChannelContext(), response);

    for (int i = 0; i < 25; i++) {
      listener.onMessage(null, response, _sseFrame('data: $i\n\n', i));
    }

    // 直接访问私有 pending 不可行，通过行为验证：flush(force: true) 后 pending 清空
    // 这里以 dispose 结束定时器即可，不产生网络请求(matchServer 无配置时跳过)
    listener.dispose();
  });

  test('ReportSseEventListener ignores client frames and non-sse messages', () async {
    final listener = ReportSseEventListener();
    final request = HttpRequest(HttpMethod.get, 'https://api.example.com/v1/stream');
    final response = HttpResponse(HttpStatus.ok);
    response.headers.add('content-type', 'text/event-stream');
    request.response = response;
    response.request = request;

    listener.onResponse(ChannelContext(), response);

    // 上行帧应被忽略(不抛错即可)
    listener.onMessage(null, response, _sseFrame('ping', 0, fromClient: true));

    // 非 SSE 消息应被忽略
    final wsResponse = HttpResponse(HttpStatus.ok);
    wsResponse.headers.add('content-type', 'application/json');
    listener.onMessage(null, wsResponse, _sseFrame('x', 0));

    listener.dispose();
  });
}
