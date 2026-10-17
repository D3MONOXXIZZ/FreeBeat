import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Represents the extracted color palette and edge aura colors for album artwork.
class ArtworkPalette {
  const ArtworkPalette({
    required this.dominantColor,
    required this.edgeColor,
    required this.topEdgeColor,
    required this.bottomEdgeColor,
    required this.leftEdgeColor,
    required this.rightEdgeColor,
    required this.accentColor,
    this.isExtracted = true,
  });

  /// The vibrant dominant color representing the artwork's identity.
  final Color dominantColor;

  /// The weighted average color of all perimeter border pixels.
  final Color edgeColor;

  /// The average color of the top edge pixels of the artwork.
  final Color topEdgeColor;

  /// The average color of the bottom edge pixels of the artwork.
  final Color bottomEdgeColor;

  /// The average color of the left edge pixels of the artwork.
  final Color leftEdgeColor;

  /// The average color of the right edge pixels of the artwork.
  final Color rightEdgeColor;

  /// The most saturated, vibrant accent color found in the artwork.
  final Color accentColor;

  /// Whether this palette was extracted from actual image pixels (true)
  /// or is a neutral fallback (false).
  final bool isExtracted;

  /// Default neutral dark slate palette when no artwork is available or before extraction.
  /// Strictly avoids any green tint.
  static const fallback = ArtworkPalette(
    dominantColor: Color(0xFF1E293B), // Slate 800
    edgeColor: Color(0xFF0F172A),     // Slate 900
    topEdgeColor: Color(0xFF1E293B),
    bottomEdgeColor: Color(0xFF0F172A),
    leftEdgeColor: Color(0xFF1E293B),
    rightEdgeColor: Color(0xFF1E293B),
    accentColor: Color(0xFF38BDF8),   // Sky 400
    isExtracted: false,
  );

  @override
  String toString() =>
      'ArtworkPalette(dominant: $dominantColor, edge: $edgeColor, top: $topEdgeColor, bottom: $bottomEdgeColor, isExtracted: $isExtracted)';
}

/// Fast native image decoder & color extractor for album artwork.
/// Decodes images down to 32x32 thumbnails using native hardware acceleration
/// (`ui.instantiateImageCodec`), extracts exact perimeter edge colors and scores
/// the most vibrant dominant color without third-party dependencies.
class ArtworkPaletteExtractor {
  static final Map<String, ArtworkPalette> _cache = {};
  static http.Client? _httpClient;

  /// Visible for testing to inject mock http client or clear cache
  static void clearCache() => _cache.clear();

  /// Sets an optional HTTP client (useful for unit tests)
  static void setHttpClient(http.Client? client) => _httpClient = client;

  /// Retrieves a previously extracted palette synchronously from in-memory cache.
  static ArtworkPalette? getCached(String? artworkUrlOrPath) {
    if (artworkUrlOrPath == null || artworkUrlOrPath.isEmpty) return null;
    return _cache[artworkUrlOrPath];
  }

  /// Manually injects a palette into cache (useful for testing or pre-extraction)
  static void injectCached(String key, ArtworkPalette palette) {
    _cache[key] = palette;
  }

  /// Extracts the palette from an artwork file path, URI, or network URL.
  static Future<ArtworkPalette> extractPalette(
    String? artworkUrlOrPath, {
    Uint8List? bytes,
  }) async {
    if ((artworkUrlOrPath == null || artworkUrlOrPath.isEmpty) &&
        (bytes == null || bytes.isEmpty)) {
      return ArtworkPalette.fallback;
    }

    final cacheKey = artworkUrlOrPath ?? 'bytes_${bytes.hashCode}';
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    try {
      Uint8List? rawBytes = bytes;

      if (rawBytes == null || rawBytes.isEmpty) {
        if (artworkUrlOrPath!.startsWith('http://') ||
            artworkUrlOrPath.startsWith('https://')) {
          final client = _httpClient ?? http.Client();
          final resp = await client
              .get(Uri.parse(artworkUrlOrPath))
              .timeout(const Duration(seconds: 4));
          if (resp.statusCode == 200 && resp.bodyBytes.length > 64) {
            rawBytes = resp.bodyBytes;
          }
        } else {
          final file = File(artworkUrlOrPath);
          if (await file.exists() && await file.length() > 64) {
            rawBytes = await file.readAsBytes();
          }
        }
      }

      if (rawBytes == null || rawBytes.length < 64) {
        return ArtworkPalette.fallback;
      }

      final palette = await _extractFromBytes(rawBytes);
      _cache[cacheKey] = palette;
      return palette;
    } catch (_) {
      return ArtworkPalette.fallback;
    }
  }

  /// Decodes raw image bytes down to a 32x32 thumbnail and computes perimeter edge
  /// colors and dominant vibrant color.
  static Future<ArtworkPalette> _extractFromBytes(Uint8List bytes) async {
    ui.Codec? codec;
    ui.FrameInfo? frameInfo;
    ui.Image? image;

    try {
      codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 32,
        targetHeight: 32,
      );
      frameInfo = await codec.getNextFrame();
      image = frameInfo.image;

      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) {
        return ArtworkPalette.fallback;
      }

      return _processRgbaData(byteData, image.width, image.height);
    } catch (_) {
      return ArtworkPalette.fallback;
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  /// Analyzes raw 32x32 RGBA pixels to extract edge colors and dominant palette.
  static ArtworkPalette _processRgbaData(
    ByteData data,
    int width,
    int height,
  ) {
    if (width <= 0 || height <= 0) return ArtworkPalette.fallback;

    final topPoints = <Point<int>>[];
    final bottomPoints = <Point<int>>[];
    final leftPoints = <Point<int>>[];
    final rightPoints = <Point<int>>[];
    final allEdgePoints = <Point<int>>[];

    // Top & Bottom rows
    for (int x = 0; x < width; x++) {
      final topPt = Point(x, 0);
      final bottomPt = Point(x, height - 1);
      topPoints.add(topPt);
      bottomPoints.add(bottomPt);
      allEdgePoints.add(topPt);
      allEdgePoints.add(bottomPt);
    }

    // Left & Right columns (excluding corners already added)
    for (int y = 1; y < height - 1; y++) {
      final leftPt = Point(0, y);
      final rightPt = Point(width - 1, y);
      leftPoints.add(leftPt);
      rightPoints.add(rightPt);
      allEdgePoints.add(leftPt);
      allEdgePoints.add(rightPt);
    }

    final topEdge = _averageColor(data, width, topPoints);
    final bottomEdge = _averageColor(data, width, bottomPoints);
    final leftEdge = _averageColor(data, width, leftPoints);
    final rightEdge = _averageColor(data, width, rightPoints);
    final overallEdge = _averageColor(data, width, allEdgePoints);

    // Color quantization & scoring across all 1024 pixels for dominant & accent
    final bins = <int, _ColorBin>{};
    final totalPixels = width * height;

    for (int i = 0; i < totalPixels; i++) {
      final offset = i * 4;
      final a = data.getUint8(offset + 3);
      if (a < 50) continue; // Skip transparent

      final r = data.getUint8(offset);
      final g = data.getUint8(offset + 1);
      final b = data.getUint8(offset + 2);

      final maxC = max(r, max(g, b));
      final minC = min(r, min(g, b));
      final chroma = maxC - minC;
      final lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;

      // 4-bit bin key: (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4) -> 4096 bins
      final binKey = ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4);
      final bin = bins.putIfAbsent(binKey, () => _ColorBin());
      bin.count++;
      bin.rSum += r;
      bin.gSum += g;
      bin.bSum += b;
      if (chroma > bin.maxChroma) bin.maxChroma = chroma;
      bin.lumSum += lum;
    }

    if (bins.isEmpty) {
      return ArtworkPalette(
        dominantColor: overallEdge,
        edgeColor: overallEdge,
        topEdgeColor: topEdge,
        bottomEdgeColor: bottomEdge,
        leftEdgeColor: leftEdge,
        rightEdgeColor: rightEdge,
        accentColor: overallEdge,
      );
    }

    // Score bins: prioritize moderate brightness and high chroma (vibrancy)
    _ColorBin? bestDominantBin;
    double bestDominantScore = -1.0;

    _ColorBin? bestAccentBin;
    double bestAccentScore = -1.0;

    for (final bin in bins.values) {
      final avgLum = bin.lumSum / bin.count;
      final chroma = bin.maxChroma;

      // Penalize near black or near white
      double lumFactor = 1.0;
      if (avgLum < 24) {
        lumFactor = 0.2;
      } else if (avgLum > 235) {
        lumFactor = 0.3;
      } else if (avgLum >= 50 && avgLum <= 190) {
        lumFactor = 1.6;
      }

      // Dominant score combines population with chroma & optimal luminance
      final dominantScore = bin.count * (chroma + 25.0) * lumFactor;
      if (dominantScore > bestDominantScore) {
        bestDominantScore = dominantScore;
        bestDominantBin = bin;
      }

      // Accent score heavily prioritizes highest saturation (chroma)
      final accentScore = (chroma * 2.5 + bin.count) * lumFactor;
      if (accentScore > bestAccentScore) {
        bestAccentScore = accentScore;
        bestAccentBin = bin;
      }
    }

    final dominantColor = bestDominantBin != null
        ? Color.fromARGB(
            255,
            bestDominantBin.rSum ~/ bestDominantBin.count,
            bestDominantBin.gSum ~/ bestDominantBin.count,
            bestDominantBin.bSum ~/ bestDominantBin.count,
          )
        : overallEdge;

    final accentColor = bestAccentBin != null
        ? Color.fromARGB(
            255,
            bestAccentBin.rSum ~/ bestAccentBin.count,
            bestAccentBin.gSum ~/ bestAccentBin.count,
            bestAccentBin.bSum ~/ bestAccentBin.count,
          )
        : dominantColor;

    return ArtworkPalette(
      dominantColor: dominantColor,
      edgeColor: overallEdge,
      topEdgeColor: topEdge,
      bottomEdgeColor: bottomEdge,
      leftEdgeColor: leftEdge,
      rightEdgeColor: rightEdge,
      accentColor: accentColor,
    );
  }

  static Color _averageColor(
    ByteData data,
    int width,
    List<Point<int>> points,
  ) {
    int rSum = 0, gSum = 0, bSum = 0, count = 0;
    for (final pt in points) {
      final offset = (pt.y * width + pt.x) * 4;
      final a = data.getUint8(offset + 3);
      if (a > 30) {
        rSum += data.getUint8(offset);
        gSum += data.getUint8(offset + 1);
        bSum += data.getUint8(offset + 2);
        count++;
      }
    }
    if (count == 0) return const Color(0xFF1E293B);
    return Color.fromARGB(255, rSum ~/ count, gSum ~/ count, bSum ~/ count);
  }
}

class _ColorBin {
  int count = 0;
  int rSum = 0;
  int gSum = 0;
  int bSum = 0;
  int maxChroma = 0;
  double lumSum = 0.0;
}
