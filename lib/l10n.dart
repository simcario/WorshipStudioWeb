/// Minimal two-language localisation: every string is written in place as
/// `tr('italiano', 'English')`.
library;

String appLocale = 'it';

String tr(String it, String en) => appLocale == 'it' ? it : en;

String formatDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return appLocale == 'it' ? '${two(d.day)}/${two(d.month)}/${d.year}' : '${d.year}-${two(d.month)}-${two(d.day)}';
}

String formatDuration(int seconds) =>
    '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
