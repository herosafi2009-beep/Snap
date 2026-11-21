// Prepares icon source images from assets/branding/snap_logo.png.
//
//   dart run tool/make_icons.dart
//   dart run flutter_launcher_icons
//
// The source logo sits on a pale background. Pixels of that colour connected
// to the image border are treated as background and removed, so light areas
// enclosed by the artwork (screen, highlights) stay intact. The logo itself is
// never recoloured or redrawn: it is only trimmed, uniformly scaled (aspect
// ratio kept) and centred, on a canvas filled with the artwork's own
// background colour.
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

void main() {
  final source = img.decodeImage(File('assets/branding/snap_logo.png').readAsBytesSync())!;
  final logo = source.convert(numChannels: 4);
  // The corner is background by definition; every canvas uses that exact
  // colour so the icon looks like the artwork as supplied.
  final corner = logo.getPixel(0, 0);
  final backdrop = img.ColorRgba8(corner.r.toInt(), corner.g.toInt(), corner.b.toInt(), 255);
  _removeBackground(logo);
  final trimmed = _trim(logo);

  // In-app logo without a background, to sit flush on app surfaces.
  _write('assets/branding/snap_logo_transparent.png', _fit(trimmed, 512, 1.0));
  // In-app logo: filled square with comfortable padding.
  _write('assets/branding/snap_logo_white.png', _onBackdrop(trimmed, 512, 0.72, backdrop));
  // Legacy launcher icon (Android < 8): filled square, logo centred.
  _write('assets/branding/icon_full.png', _onBackdrop(trimmed, 1024, 0.72, backdrop));
  // Adaptive icon foreground on the solid background layer. The layer is
  // 108dp and the launcher icon tool insets it 16 %, so this 1024px canvas
  // spans 72.6dp. Launchers may mask the icon to a circle, and only a 66dp
  // circle is guaranteed visible, so the logo is sized by its farthest
  // pixel from the centre (not its box: the guitar runs corner to corner,
  // and a box sized fit put its neck outside the circle). A 30dp radius
  // keeps a little air inside the 33dp safe circle at every launcher size.
  const safeRadius = 30 / 72.64 * 1024;
  _write('assets/branding/icon_foreground.png', _fitRadius(trimmed, 1024, safeRadius));
  // Android 13 themed icon: the artwork's own shading as a single tintable
  // layer, so the player still reads as a player once the launcher recolours
  // it, rather than a flat blob.
  _write('assets/branding/icon_monochrome.png', _monochrome(_fitRadius(trimmed, 1024, safeRadius), backdrop));

  // Splash screen logo (96 dp at xxxhdpi), drawn on the boot-colour window.
  final splash = File('android/app/src/main/res/drawable-xxxhdpi/splash_logo.png');
  splash.parent.createSync(recursive: true);
  _write(splash.path, _fit(trimmed, 384, 1.0));
  stdout.writeln('Backdrop #${backdrop.r.toInt().toRadixString(16)}'
      '${backdrop.g.toInt().toRadixString(16)}${backdrop.b.toInt().toRadixString(16)} '
      '(set it as ic_launcher_background in colors.xml)');
  stdout.writeln('Icons written to assets/branding/ and the Android splash drawable');
}

bool _isBackground(img.Pixel p) => p.a > 0 && p.r > 232 && p.g > 232 && p.b > 232;

void _removeBackground(img.Image image) {
  final w = image.width, h = image.height;
  final visited = List<bool>.filled(w * h, false);
  final queue = Queue<int>();
  void seed(int x, int y) {
    final i = y * w + x;
    if (!visited[i] && _isBackground(image.getPixel(x, y))) {
      visited[i] = true;
      queue.add(i);
    }
  }

  for (var x = 0; x < w; x++) {
    seed(x, 0);
    seed(x, h - 1);
  }
  for (var y = 0; y < h; y++) {
    seed(0, y);
    seed(w - 1, y);
  }
  while (queue.isNotEmpty) {
    final i = queue.removeFirst();
    final x = i % w, y = i ~/ w;
    image.setPixelRgba(x, y, 255, 255, 255, 0);
    if (x > 0) seed(x - 1, y);
    if (x < w - 1) seed(x + 1, y);
    if (y > 0) seed(x, y - 1);
    if (y < h - 1) seed(x, y + 1);
  }
  // Soften the anti-aliased fringe next to removed pixels.
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final p = image.getPixel(x, y);
      if (p.a == 0) continue;
      final light = p.r > 215 && p.g > 215 && p.b > 215;
      if (!light) continue;
      final touchesClear = image.getPixel(x - 1, y).a == 0 ||
          image.getPixel(x + 1, y).a == 0 ||
          image.getPixel(x, y - 1).a == 0 ||
          image.getPixel(x, y + 1).a == 0;
      if (touchesClear) image.setPixelRgba(x, y, p.r, p.g, p.b, 110);
    }
  }
}

/// Crops to the visible logo so centering uses its real bounds.
img.Image _trim(img.Image image) {
  var minX = image.width, minY = image.height, maxX = 0, maxY = 0;
  for (final p in image) {
    if (p.a > 20) {
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
    }
  }
  return img.copyCrop(image, x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1);
}

/// Uniformly scales the logo so its longer side is [fraction] of the canvas
/// and centers it on a transparent square.
img.Image _fit(img.Image logo, int size, double fraction) {
  final canvas = img.Image(width: size, height: size, numChannels: 4);
  final target = size * fraction;
  final scale = target / (logo.width > logo.height ? logo.width : logo.height);
  final resized = img.copyResize(
    logo,
    width: (logo.width * scale).round(),
    height: (logo.height * scale).round(),
    interpolation: img.Interpolation.cubic,
  );
  img.compositeImage(canvas, resized,
      dstX: ((size - resized.width) / 2).round(), dstY: ((size - resized.height) / 2).round());
  return canvas;
}

/// Scales the logo so no visible pixel is further than [radius] from the
/// canvas centre, and centres it on a transparent square. Used where the
/// launcher may cut the icon to a circle.
img.Image _fitRadius(img.Image logo, int size, double radius) {
  final cx = (logo.width - 1) / 2, cy = (logo.height - 1) / 2;
  var far = 0.0;
  for (final p in logo) {
    if (p.a <= 20) continue;
    final dx = p.x - cx, dy = p.y - cy;
    final d = dx * dx + dy * dy;
    if (d > far) far = d;
  }
  final scale = radius / (far == 0 ? 1 : math.sqrt(far));
  final canvas = img.Image(width: size, height: size, numChannels: 4);
  final resized = img.copyResize(
    logo,
    width: (logo.width * scale).round(),
    height: (logo.height * scale).round(),
    interpolation: img.Interpolation.cubic,
  );
  img.compositeImage(canvas, resized,
      dstX: ((size - resized.width) / 2).round(), dstY: ((size - resized.height) / 2).round());
  return canvas;
}

/// Solid square with the centred logo. No borders, shadows or corners.
img.Image _onBackdrop(img.Image logo, int size, double fraction, img.Color backdrop) {
  final canvas = img.Image(width: size, height: size, numChannels: 4);
  img.fill(canvas, color: backdrop);
  img.compositeImage(canvas, _fit(logo, size, fraction));
  return canvas;
}

/// White pixels whose opacity follows how much darker the artwork is than its
/// own background: outlines come through solid, mid tones stay soft.
img.Image _monochrome(img.Image image, img.Color backdrop) {
  double luminance(num r, num g, num b) => (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
  final base = luminance(backdrop.r, backdrop.g, backdrop.b);
  final out = image.clone();
  for (final p in out) {
    if (p.a == 0) continue;
    final darkness = ((base - luminance(p.r, p.g, p.b)) / base).clamp(0.0, 1.0);
    // A gentle curve: barely-tinted pixels fade out, the drawing stays.
    final alpha = (255 * (darkness * 1.6).clamp(0.0, 1.0)) * (p.a / 255);
    p
      ..r = 255
      ..g = 255
      ..b = 255
      ..a = alpha.round();
  }
  return out;
}

void _write(String path, img.Image image) => File(path).writeAsBytesSync(img.encodePng(image));
