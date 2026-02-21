import 'package:flutter/widgets.dart';

abstract final class DsRadius {
  static const xs = Radius.circular(8);
  static const sm = Radius.circular(12);
  static const md = Radius.circular(16);
  static const lg = Radius.circular(22);
  static const xl = Radius.circular(28);
  static const full = Radius.circular(999);

  static const brXs = BorderRadius.all(xs);
  static const brSm = BorderRadius.all(sm);
  static const brMd = BorderRadius.all(md);
  static const brLg = BorderRadius.all(lg);
  static const brXl = BorderRadius.all(xl);
  static const brFull = BorderRadius.all(full);
}
