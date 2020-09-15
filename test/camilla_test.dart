import 'dart:io';

import 'package:test/test.dart';
import '../bin/camilla.dart' as qx;

void main() {
  test('main method runs through', () {
    var args = ['-v'];
    qx.main(args);
  });
}
