import 'dart:async';

import 'package:http/http.dart';
import 'package:signalr_core/src/logger.dart';
import 'package:signalr_core/src/transport.dart';
import 'package:signalr_core/src/utils.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'web_socket_channel_api.dart'
    // ignore: uri_does_not_exist
    if (dart.library.html) 'web_socket_channel_html.dart'
    // ignore: uri_does_not_exist
    if (dart.library.io) 'web_socket_channel_io.dart' as platform;

class WebSocketTransport implements Transport {
  final Logging? _logging;
  final AccessTokenFactory? _accessTokenFactory;
  final bool? _logMessageContent;
  final BaseClient? _client;
  final Map<String, String>? customHeaders;

  StreamSubscription<dynamic>? _streamSubscription;
  WebSocketChannel? _channel;

  WebSocketTransport({
    BaseClient? client,
    AccessTokenFactory? accessTokenFactory,
    Logging? logging,
    bool? logMessageContent,
    this.customHeaders,
  })  : _logging = logging,
        _accessTokenFactory = accessTokenFactory,
        _logMessageContent = logMessageContent,
        _client = client {
    onreceive = null;
    onclose = null;
  }

  @override
  OnClose? onclose;

  @override
  OnReceive? onreceive;

  @override
  Future<void> connect(String? url, TransferFormat? transferFormat) async {
    assert(url != null);
    assert(transferFormat != null);

    _logging!(LogLevel.trace, '(WebSockets transport) Connecting.');


    if (_accessTokenFactory != null) {
      _logging!(LogLevel.trace, '(WebSockets transport) AccessTokenFactory');
      final token = await _accessTokenFactory!();
      if (token!.isNotEmpty) {
        final encodedToken = Uri.encodeComponent(token);
        if (url!=null) {
          url = url + (url.contains('?') ? '&' : '?') +
              'access_token=$encodedToken';
        }

      }
    }
    if (customHeaders!=null && customHeaders!.isNotEmpty){
      _logging!(LogLevel.trace, '(WebSockets transport) CustomHeaders');
      for (var entry in customHeaders!.entries){
        if (url!=null) {
          url = url + (url.contains('?') ? '&' : '?') +
              '${entry.key}=${entry.value}';
        }
      }

    }
    final connectFuture = Completer<void>();
    var opened = false;

    url = url?.replaceFirst(RegExp(r'^http'), 'ws');

    if (url!=null) {
      _channel =
      await platform.connect(Uri.parse(url), customHeaders ?? {}, client: _client!);
    }

    _logging!(LogLevel.information, 'WebSocket connected to $url.');
    opened = true;

    _streamSubscription = _channel?.stream.listen((data) {
      var dataDetail = getDataDetail(data, _logMessageContent);
      _logging!(
          LogLevel.trace, '(WebSockets transport) data received. $dataDetail');
      if (onreceive != null) {
        try {
          onreceive!(data);
        } on Exception catch (e1) {
          _close(e1);
          return;
        }
      }
    }, onError: (e) {
      _logging!(LogLevel.error,
          '(WebSockets transport) socket error: ${e.toString()}}');
    }, onDone: () {
      if (opened == true) {
        _close(null);
      } else {}
    }, cancelOnError: false);

    return connectFuture.complete();
  }

  @override
  Future<void> send(dynamic data) {
    if ((_channel == null) || (_channel?.closeCode != null)) {
      return Future.error(Exception('WebSocket is not in the OPEN state'));
    }

    _logging!(LogLevel.trace,
        '(WebSockets transport) sending data. ${getDataDetail(data, _logMessageContent)}.');
    _channel!.sink.add(data);
    return Future.value();
  }

  @override
  Future<void> stop() {
    if (_channel != null) {
      _close(null);
    }
    return Future.value();
  }

  void _close(Exception? error) {
    var closeCode = 0;
    String? closeReason;
    if (_channel != null) {
      closeCode = _channel!.closeCode ?? 0;
      closeReason = _channel!.closeReason;
      _streamSubscription!.cancel();
      _streamSubscription = null;
      _channel!.sink.close();
      _channel = null;
    }

    _logging!(LogLevel.trace, '(WebSockets transport) socket closed.');
    if (onclose != null) {
      if (error != null) {
        onclose!(error);
      } else {
        if (closeCode != 0 && closeCode != 1000) {
          onclose!(
            Exception(
                'WebSocket closed with status code: $closeCode ($closeReason).'),
          );
        }
        onclose!(null);
      }
    }
  }
}
