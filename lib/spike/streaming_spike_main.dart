// lib/spike/streaming_spike_main.dart
//
// THROWAWAY SPIKE — delete after the streaming transport question is answered.
//
// Standalone Flutter entrypoint. It does NOT touch the real app routing, state,
// Hive, RevenueCat, or Supabase auth. It only proves whether iOS receives an
// NDJSON Edge response *incrementally*.
//
// Run on a connected iPhone (must be done on a Mac — WSL cannot build iOS):
//   flutter run -t lib/spike/streaming_spike_main.dart -d <iphone-device-id>
//
// What to read off the screen:
//   - "首位元組 (first byte)" = seconds until the connection produced ANY data.
//   - Each row shows the wall-clock second the client *received* that event.
//   - Verdict banner: INCREMENTAL means rows arrived spread out over ~15s
//     (streaming works); BUFFERED means every row landed together near the end
//     (this whole streaming path is dead — change approach).
//
// Transport per the contract: raw http.Client().send(), NOT
// supabase.functions.invoke, with a manually attached Authorization header.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// Public values, already committed in lib/core/config/environment.dart.
const String _supabaseUrl = 'https://fcmwrmwdoqiqdnbisdpg.supabase.co';
const String _anonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZjbXdybXdkb3FpcWRuYmlzZHBnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzIyMDUzMjUsImV4cCI6MjA4Nzc4MTMyNX0.xqorAcT0NUTNxzktd-SgI3ePG8jJdeqCRU730Brzmlg';

const String _endpoint = '$_supabaseUrl/functions/v1/spike-stream';

void main() => runApp(const _SpikeApp());

class _SpikeApp extends StatelessWidget {
  const _SpikeApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const _SpikeScreen(),
    );
  }
}

/// One received NDJSON line plus the client-side elapsed time when it landed.
class _ReceivedEvent {
  _ReceivedEvent({
    required this.elapsed,
    required this.raw,
    required this.parsed,
  });

  final Duration elapsed;
  final String raw;
  final Map<String, dynamic>? parsed;

  String get type => parsed?['type']?.toString() ?? 'unparsed';
}

enum _SpikeStatus { idle, connecting, streaming, done, error, cancelled }

class _SpikeScreen extends StatefulWidget {
  const _SpikeScreen();

  @override
  State<_SpikeScreen> createState() => _SpikeScreenState();
}

class _SpikeScreenState extends State<_SpikeScreen> {
  final List<_ReceivedEvent> _events = [];
  _SpikeStatus _status = _SpikeStatus.idle;
  String? _errorText;

  Stopwatch? _clock;
  Duration? _firstByte;
  http.Client? _client;
  StreamSubscription<String>? _sub;
  Timer? _ticker; // repaints the live clock while streaming

  Future<void> _start() async {
    await _reset();
    setState(() => _status = _SpikeStatus.connecting);

    final clock = Stopwatch()..start();
    _clock = clock;
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });

    final client = http.Client();
    _client = client;

    try {
      final request = http.Request('POST', Uri.parse(_endpoint))
        ..headers['Authorization'] = 'Bearer $_anonKey'
        ..headers['apikey'] = _anonKey
        ..headers['Content-Type'] = 'application/json'
        // Be explicit that we accept a stream and do not want it transformed.
        ..headers['Accept'] = 'application/x-ndjson'
        ..body = jsonEncode({'spike': true});

      // .send() returns as soon as headers arrive — the body is a byte stream.
      final response = await client.send(request);

      if (response.statusCode != 200) {
        final dump = await response.stream.bytesToString();
        throw http.ClientException(
          'HTTP ${response.statusCode}: ${dump.isEmpty ? '(empty body)' : dump}',
        );
      }

      setState(() => _status = _SpikeStatus.streaming);

      // Decode bytes -> utf8 text -> split on newlines. Each complete line is
      // one NDJSON event. LineSplitter buffers partial lines for us.
      final lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      _sub = lines.listen(
        (line) {
          if (line.trim().isEmpty) return;
          _firstByte ??= clock.elapsed;
          Map<String, dynamic>? parsed;
          try {
            parsed = jsonDecode(line) as Map<String, dynamic>;
          } catch (_) {
            parsed = null; // record malformed lines too
          }
          setState(() {
            _events.add(_ReceivedEvent(
              elapsed: clock.elapsed,
              raw: line,
              parsed: parsed,
            ));
          });
        },
        onError: (Object e) => _fail(e.toString()),
        onDone: () {
          if (_status == _SpikeStatus.streaming) {
            setState(() => _status = _SpikeStatus.done);
          }
          _stopClock();
        },
        cancelOnError: true,
      );
    } catch (e) {
      _fail(e.toString());
    }
  }

  void _fail(String message) {
    setState(() {
      _status = _SpikeStatus.error;
      _errorText = message;
    });
    _stopClock();
  }

  Future<void> _cancel() async {
    // Simulates "中途返回 / 中途斷線": tear down the client mid-stream.
    await _sub?.cancel();
    _client?.close();
    setState(() => _status = _SpikeStatus.cancelled);
    _stopClock();
  }

  void _stopClock() {
    _clock?.stop();
    _ticker?.cancel();
    _ticker = null;
    _client?.close();
  }

  Future<void> _reset() async {
    await _sub?.cancel();
    _sub = null;
    _stopClock();
    setState(() {
      _events.clear();
      _firstByte = null;
      _errorText = null;
      _clock = null;
      _status = _SpikeStatus.idle;
    });
  }

  /// Heuristic verdict: streaming works only if events arrived spread out.
  /// Buffered responses dump every line within a tight window at the end.
  String _verdict() {
    if (_events.length < 2) return '—';
    final first = _events.first.elapsed;
    final last = _events.last.elapsed;
    final spreadMs = (last - first).inMilliseconds;
    if (spreadMs >= 4000) {
      return 'INCREMENTAL ✓  (事件分散 ${(spreadMs / 1000).toStringAsFixed(1)}s 到達)';
    }
    return 'BUFFERED ✗  (全部 ${_events.length} 行在 ${(spreadMs / 1000).toStringAsFixed(1)}s 內到達 — 串流不成立)';
  }

  @override
  void dispose() {
    _sub?.cancel();
    _stopClock();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final busy = _status == _SpikeStatus.connecting ||
        _status == _SpikeStatus.streaming;
    final liveSeconds =
        _clock == null ? 0.0 : _clock!.elapsed.inMilliseconds / 1000;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Streaming Spike (NDJSON)'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _summaryCard(liveSeconds),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: busy ? null : _start,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('開始 spike'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? _cancel : _reset,
                    icon: Icon(busy ? Icons.stop : Icons.refresh),
                    label: Text(busy ? '中途取消' : '清除'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),
            Expanded(child: _eventList()),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(double liveSeconds) {
    final verdictColor = _verdict().startsWith('INCREMENTAL')
        ? Colors.green.shade700
        : _verdict().startsWith('BUFFERED')
            ? Colors.red.shade700
            : Colors.grey.shade600;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('狀態: ${_status.name}',
                style: Theme.of(context).textTheme.titleMedium),
            Text('現在時鐘: ${liveSeconds.toStringAsFixed(1)}s'),
            Text(
              '首位元組 (first byte): '
              '${_firstByte == null ? '—' : '${(_firstByte!.inMilliseconds / 1000).toStringAsFixed(2)}s'}',
            ),
            Text('已收事件數: ${_events.length}'),
            const SizedBox(height: 6),
            Text('判定: ${_verdict()}',
                style: TextStyle(
                    color: verdictColor, fontWeight: FontWeight.bold)),
            if (_errorText != null) ...[
              const SizedBox(height: 6),
              Text('錯誤: $_errorText',
                  style: TextStyle(color: Colors.red.shade700)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _eventList() {
    if (_events.isEmpty) {
      return const Center(
        child: Text('按「開始 spike」。每收到一行就會記下到達秒數。'),
      );
    }
    return ListView.separated(
      itemCount: _events.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final e = _events[i];
        final secs = (e.elapsed.inMilliseconds / 1000).toStringAsFixed(2);
        final message = e.parsed?['message']?.toString() ??
            e.parsed?['title']?.toString() ??
            e.raw;
        return ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 16,
            child: Text(secs, style: const TextStyle(fontSize: 9)),
          ),
          title: Text(
            e.parsed?['name'] != null
                ? '${e.type} · ${e.parsed!['name']}'
                : e.type,
          ),
          subtitle: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: Text('+${secs}s'),
        );
      },
    );
  }
}
