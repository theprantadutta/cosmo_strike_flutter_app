/// One format's load outcomes since the last flush.
class AdLoadSummary {
  const AdLoadSummary({
    required this.format,
    required this.requests,
    required this.filled,
    required this.failed,
    required this.errorCodes,
  });

  final String format;
  final int requests;
  final int filled;
  final int failed;

  /// Failure code → count, most frequent first, e.g. `"3:12,2:4"`
  /// (AdMob: 0 internal, 1 invalid request, 2 network, 3 no fill).
  /// Empty when nothing failed.
  final String errorCodes;
}

/// Session tally of ad load requests and their outcomes, per format.
///
/// Aggregated rather than one analytics event per load: banners and retries
/// generate a lot of requests, and per-request events would swamp every
/// other event. [drain] hands back one summary per format and starts over;
/// the AdService sends those as `ad_load` events when the app is
/// backgrounded (the last moment a session reliably reaches).
class AdLoadTally {
  final Map<String, _Counts> _counts = {};

  _Counts _of(String format) => _counts.putIfAbsent(format, _Counts.new);

  void requested(String format) => _of(format).requests++;

  void filled(String format) => _of(format).filled++;

  void failed(String format, int code) {
    final c = _of(format);
    c.failed++;
    c.codes[code] = (c.codes[code] ?? 0) + 1;
  }

  bool get isEmpty => _counts.values.every((c) => c.isEmpty);

  /// Everything counted since the last drain, then reset.
  List<AdLoadSummary> drain() {
    final out = <AdLoadSummary>[];
    for (final entry in _counts.entries) {
      final c = entry.value;
      if (c.isEmpty) continue;
      final codes = c.codes.entries.toList()
        ..sort((a, b) {
          final byCount = b.value.compareTo(a.value);
          return byCount != 0 ? byCount : a.key.compareTo(b.key);
        });
      out.add(
        AdLoadSummary(
          format: entry.key,
          requests: c.requests,
          filled: c.filled,
          failed: c.failed,
          errorCodes: codes.map((e) => '${e.key}:${e.value}').join(','),
        ),
      );
    }
    _counts.clear();
    return out;
  }
}

class _Counts {
  int requests = 0;
  int filled = 0;
  int failed = 0;
  final Map<int, int> codes = {};

  bool get isEmpty => requests == 0 && filled == 0 && failed == 0;
}
