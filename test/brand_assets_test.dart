import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  const String brandRoot = 'assets/brand';

  test('brand package contains the audited SVG variants and PNG sizes', () {
    final File source = File('$brandRoot/seeko-logo-source.svg');
    expect(source.existsSync(), isTrue);
    final String svg = source.readAsStringSync();
    expect(svg, contains('Synced S Rails'));
    expect(RegExp(r'<use ').allMatches(svg), hasLength(3));
    expect(svg, contains('#16C79A'));
    expect(svg, contains('#4C7DFF'));
    expect(svg, contains('#07111F'));

    for (final String name in <String>[
      'seeko-mark-light.svg',
      'seeko-mark-dark.svg',
      'seeko-mark-monochrome.svg',
      'seeko-app-icon.svg',
      'seeko-social-preview.svg',
      'seeko-social-preview.png',
      'BRAND.md',
    ]) {
      expect(File('$brandRoot/$name').existsSync(), isTrue, reason: name);
    }
    for (final int size in <int>[16, 32, 64, 128, 256, 512, 1024]) {
      expect(
        File('$brandRoot/seeko-app-icon-$size.png').existsSync(),
        isTrue,
        reason: 'Missing $size px brand export',
      );
    }
  });

  test('social preview keeps the canonical dimensions and brand palette', () {
    final String source =
        File('$brandRoot/seeko-social-preview.svg').readAsStringSync();
    expect(source, contains('width="1280" height="640"'));
    expect(source, contains('Synced S Rails'));
    expect(source, contains('#16C79A'));
    expect(source, contains('#4C7DFF'));
    expect(source, contains('#07111F'));
    expect(
      File('$brandRoot/seeko-social-preview.png').lengthSync(),
      greaterThan(10000),
    );
  });

  test('platform launcher icons use Seeko ink and mint pixels', () async {
    for (final String path in <String>[
      'example/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
      'example/ios/Runner/Assets.xcassets/AppIcon.appiconset/'
          'Icon-App-1024x1024@1x.png',
      'example/macos/Runner/Assets.xcassets/AppIcon.appiconset/'
          'app_icon_1024.png',
      'example/web/icons/Icon-512.png',
      'example/web/icons/Icon-maskable-512.png',
      'example/linux/runner/resources/app_icon.png',
    ]) {
      await _expectSeekoIcon(path);
    }
  });

  test('Windows launcher icon remains a real multi-image ICO', () {
    final Uint8List bytes = File(
      'example/windows/runner/resources/app_icon.ico',
    ).readAsBytesSync();
    expect(bytes.length, greaterThan(10000));
    expect(bytes.sublist(0, 4), <int>[0, 0, 1, 0]);
  });
}

Future<void> _expectSeekoIcon(String path) async {
  final Uint8List bytes = File(path).readAsBytesSync();
  final ui.Codec codec = await ui.instantiateImageCodec(bytes);
  final ui.FrameInfo frame = await codec.getNextFrame();
  final ui.Image image = frame.image;
  final ByteData data = (await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  ))!;

  final _Rgba corner = _pixel(data, image.width, 1, 1);
  final _Rgba target = _pixel(
    data,
    image.width,
    image.width ~/ 2,
    image.height ~/ 2,
  );
  expect(corner, const _Rgba(7, 17, 31, 255), reason: '$path background');
  expect(target, const _Rgba(22, 199, 154, 255), reason: '$path target');

  image.dispose();
  codec.dispose();
}

_Rgba _pixel(ByteData data, int width, int x, int y) {
  final int offset = (y * width + x) * 4;
  return _Rgba(
    data.getUint8(offset),
    data.getUint8(offset + 1),
    data.getUint8(offset + 2),
    data.getUint8(offset + 3),
  );
}

final class _Rgba {
  const _Rgba(this.red, this.green, this.blue, this.alpha);

  final int red;
  final int green;
  final int blue;
  final int alpha;

  @override
  bool operator ==(Object other) =>
      other is _Rgba &&
      other.red == red &&
      other.green == green &&
      other.blue == blue &&
      other.alpha == alpha;

  @override
  int get hashCode => Object.hash(red, green, blue, alpha);

  @override
  String toString() => 'rgba($red, $green, $blue, $alpha)';
}
