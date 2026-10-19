import 'package:flutter/widgets.dart';

import '../../theme/cosmo_theme.dart';

/// Minimal Markdown renderer for bundled legal docs (PRIVACY.md). Covers the
/// subset those files use: `#`/`##`/`###` headings, `**bold**`, `*italic*`,
/// `>` quotes, `-` bullets, `1.` numbered items and `---` rules. Not a
/// general-purpose parser — keep the docs to this subset.
class CsMarkdown extends StatelessWidget {
  const CsMarkdown(this.source, {super.key});
  final String source;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final body = t.body.copyWith(color: CsColors.ink70, height: 1.55);
    final blocks = <Widget>[];
    final paragraph = <String>[]; // lines + separators, joined verbatim
    var hardBreak = false;

    void gap(double h) => blocks.add(SizedBox(height: cs(h)));
    void flush() {
      if (paragraph.isEmpty) return;
      blocks.add(Text.rich(_inline(paragraph.join(''), body)));
      paragraph.clear();
      gap(10);
    }

    // Split on CRLF too: PRIVACY.md has Windows line endings, and a stray
    // '\r' after the two trailing spaces hides the hard line break.
    for (final raw in source.split(RegExp(r'\r?\n'))) {
      final line = raw.trimRight();
      final trimmed = line.trimLeft();
      if (trimmed.isEmpty) {
        flush();
        continue;
      }
      final heading = RegExp(r'^(#{1,3})\s+(.*)$').firstMatch(trimmed);
      if (heading != null) {
        flush();
        final level = heading.group(1)!.length;
        if (blocks.isNotEmpty) gap(level == 1 ? 4 : 12);
        final style = switch (level) {
          1 => t.display(22, em: -0.02, height: 1.15),
          2 => t.rowTitle.copyWith(fontSize: cs(17)),
          _ => t.rowTitle.copyWith(fontSize: cs(14), color: CsColors.ink70),
        };
        blocks.add(Text.rich(_inline(heading.group(2)!, style)));
        gap(level == 1 ? 12 : 8);
        continue;
      }
      if (RegExp(r'^-{3,}$').hasMatch(trimmed)) {
        flush();
        blocks.add(Container(height: 1, color: CsColors.lineSubtle));
        gap(12);
        continue;
      }
      if (trimmed.startsWith('>')) {
        flush();
        // Consecutive quote lines merge into one bordered block.
        final text = trimmed.replaceFirst(RegExp(r'^>\s?'), '');
        final last = blocks.length >= 2 ? blocks[blocks.length - 2] : null;
        if (last is _Quote) {
          blocks[blocks.length - 2] = _Quote('${last.text} $text', body);
        } else {
          blocks.add(_Quote(text, body));
          gap(10);
        }
        continue;
      }
      final bullet = RegExp(r'^(?:[-*]|(\d+)\.)\s+(.*)$').firstMatch(trimmed);
      if (bullet != null) {
        flush();
        final marker = bullet.group(1) != null ? '${bullet.group(1)}.' : '•';
        blocks.add(Padding(
          padding: EdgeInsets.only(left: cs(line.length - trimmed.length > 0 ? 18 : 4), bottom: cs(4)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: cs(18), child: Text(marker, style: body)),
            Expanded(child: Text.rich(_inline(bullet.group(2)!, body))),
          ]),
        ));
        continue;
      }
      // Two trailing spaces = Markdown hard line break.
      if (paragraph.isNotEmpty) paragraph.add(hardBreak ? '\n' : ' ');
      paragraph.add(trimmed);
      hardBreak = raw.endsWith('  ');
    }
    flush();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: blocks);
  }
}

class _Quote extends StatelessWidget {
  const _Quote(this.text, this.style);
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Container(
      padding: EdgeInsets.only(left: cs(12)),
      decoration: const BoxDecoration(border: Border(left: BorderSide(color: CsColors.violet, width: 2))),
      child: Text.rich(_inline(text, style)),
    );
  }
}

/// `**bold**` and `*italic*` spans.
TextSpan _inline(String text, TextStyle base) {
  final spans = <InlineSpan>[];
  final re = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*');
  var at = 0;
  for (final m in re.allMatches(text)) {
    if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start)));
    spans.add(m.group(1) != null
        ? TextSpan(text: m.group(1), style: const TextStyle(fontWeight: FontWeight.w700, color: CsColors.ink))
        : TextSpan(text: m.group(2), style: const TextStyle(fontStyle: FontStyle.italic)));
    at = m.end;
  }
  if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
  return TextSpan(style: base, children: spans);
}
