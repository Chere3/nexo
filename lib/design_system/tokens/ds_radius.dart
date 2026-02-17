import 'package:flutter/widgets.dart';

abstract final class DsRadius {
  static const sm = Radius.circular(10);
  static const md = Radius.circular(14);
  static const lg = Radius.circular(18);
  static const xl = Radius.circular(24);

  static const brSm = BorderRadius.all(sm);
  static const brMd = BorderRadius.all(md);
  static const brLg = BorderRadius.all(lg);
  static const brXl = BorderRadius.all(xl);
}
