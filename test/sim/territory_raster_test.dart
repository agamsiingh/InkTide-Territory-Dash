import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:inktide/game/territory_raster.dart';

void main() {
  const k = 8;
  const red = 0xFFFF0000, darkRed = 0xFF800000, blue = 0xFF0000FF, darkBlue = 0xFF000080;

  TerritoryRasterJob job(Uint8List owner, int w, int h) => TerritoryRasterJob(
        owner: owner,
        width: w,
        height: h,
        colors: Int32List.fromList([0, red, blue]),
        darks: Int32List.fromList([0, darkRed, darkBlue]),
        pixelsPerCell: k,
      );

  List<int> px(Uint8List img, int iw, int x, int y) {
    final j = (y * iw + x) * 4;
    return [img[j], img[j + 1], img[j + 2], img[j + 3]];
  }

  test('a 4x4 block is opaque in its colour, empty space is transparent', () {
    const w = 10, h = 10;
    final owner = Uint8List(w * h);
    for (var y = 3; y < 7; y++) {
      for (var x = 3; x < 7; x++) {
        owner[y * w + x] = 1;
      }
    }
    final j = job(owner, w, h);
    final img = rasterTerritory(j);
    expect(img.length, j.imageWidth * j.imageHeight * 4);
    expect(px(img, j.imageWidth, 5 * k, 5 * k), [255, 0, 0, 255], reason: 'inside the block');
    expect(px(img, j.imageWidth, 1 * k, 1 * k)[3], 0, reason: 'far outside');
    // Straight edge stays at the cell border: just inside opaque, just outside clear.
    expect(px(img, j.imageWidth, 3 * k + 2, 5 * k)[3], 255);
    expect(px(img, j.imageWidth, 3 * k - 3, 5 * k)[3], 0);
    // Axis-aligned edges land on pixel borders (crisp); the rounded corners
    // produce anti-aliased partial-alpha pixels.
    var partial = 0;
    for (var i = 3; i < img.length; i += 4) {
      if (img[i] > 0 && img[i] < 255) partial++;
    }
    expect(partial, greaterThan(0));
  });

  test('darker side layer appears just below the block', () {
    const w = 10, h = 10;
    final owner = Uint8List(w * h);
    for (var x = 3; x < 7; x++) {
      owner[5 * w + x] = 1;
      owner[4 * w + x] = 1;
    }
    final j = job(owner, w, h);
    final img = rasterTerritory(j);
    // Bottom edge of the block is at y = 6 cells; the side layer extends ~0.3 cell below.
    final below = px(img, j.imageWidth, 5 * k, 6 * k + 1);
    expect(below[3], greaterThan(200));
    expect(below[0], closeTo(0x80, 12), reason: 'side uses the dark colour (premultiplied blend)');
  });

  test('corners are rounded (diagonal corner pixel is clear)', () {
    const w = 10, h = 10;
    final owner = Uint8List(w * h);
    for (var y = 3; y < 7; y++) {
      for (var x = 3; x < 7; x++) {
        owner[y * w + x] = 1;
      }
    }
    final j = job(owner, w, h);
    final img = rasterTerritory(j);
    // The exact top-left corner pixel of the square is outside the rounded shape.
    expect(px(img, j.imageWidth, 3 * k, 3 * k)[3], lessThan(128));
    expect(px(img, j.imageWidth, 3 * k + k ~/ 2, 3 * k + k ~/ 2)[3], 255);
  });

  test('two owners keep their own colours', () {
    const w = 12, h = 6;
    final owner = Uint8List(w * h);
    for (var y = 1; y < 5; y++) {
      for (var x = 1; x < 5; x++) {
        owner[y * w + x] = 1;
      }
      for (var x = 7; x < 11; x++) {
        owner[y * w + x] = 2;
      }
    }
    final j = job(owner, w, h);
    final img = rasterTerritory(j);
    expect(px(img, j.imageWidth, 3 * k, 2 * k).sublist(0, 3), [255, 0, 0]);
    expect(px(img, j.imageWidth, 9 * k, 2 * k).sublist(0, 3), [0, 0, 255]);
  });
}
