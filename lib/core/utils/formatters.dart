/// Format 3721 dtk -> 1:02:01, 65 dtk -> 1:05.
String formatDuration(Duration d) {
  final total = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Audius artwork punya placeholder pola ?width=. Normalisasi kecil.
String? hiResArtwork(String? url, {int size = 1000}) {
  if (url == null || url.isEmpty) return null;
  if (url.contains('{w}')) return url.replaceAll('{w}', '$size');
  return url;
}

/// Bandingkan kesamaan judul setelah menghapus konten dalam kurung dan tanda kurung siku.
bool isSimilarTitle(String a, String b) {
  final la = a.toLowerCase().replaceAll(RegExp(r'\([^)]*\)'), '').replaceAll(RegExp(r'\[[^\]]*\]'), '').trim();
  final lb = b.toLowerCase().replaceAll(RegExp(r'\([^)]*\)'), '').replaceAll(RegExp(r'\[[^\]]*\]'), '').trim();
  return la == lb;
}
