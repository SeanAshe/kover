import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart';
import 'package:kover/utils/extensions/document_fragment.dart';
import 'package:kover/utils/image_size.dart';

void main() {
  test('reads PNG pixel size from the IHDR header', () {
    final bytes = Uint8List(24);
    bytes[0] = 0x89;
    bytes[1] = 0x50;
    bytes[2] = 0x4E;
    bytes[3] = 0x47;
    bytes[16] = 0;
    bytes[17] = 0;
    bytes[18] = 0x04;
    bytes[19] = 0x00;
    bytes[20] = 0;
    bytes[21] = 0;
    bytes[22] = 0x03;
    bytes[23] = 0x00;

    expect(imagePixelSize(bytes), (width: 1024, height: 768));
  });

  test('comic EPUB keeps images and drops text', () {
    final root = DocumentFragment();
    final page = Element.tag('div')
      ..append(Element.tag('p')..text = 'caption')
      ..append(
        Element.tag('img')..attributes['src'] = 'data:image/png;base64,aaa',
      );
    root.append(page);

    final images = root.comicImagesOnly();

    expect(images.querySelectorAll('p'), isEmpty);
    expect(images.querySelectorAll('img'), hasLength(1));
    expect(
      images.querySelector('img')?.attributes['src'],
      'data:image/png;base64,aaa',
    );
  });
}
