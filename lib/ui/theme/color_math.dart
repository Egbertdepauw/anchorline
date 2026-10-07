// Pure colour maths used to check theme palettes: WCAG contrast and the
// CIEDE2000 colour difference. No widgets, no theme state.

import 'dart:math' as math;
import 'dart:ui' show Color;

double _linear(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

/// WCAG 2.x relative luminance of an opaque sRGB colour (0 black, 1 white).
double relativeLuminance(Color c) =>
    0.2126 * _linear(c.r) + 0.7152 * _linear(c.g) + 0.0722 * _linear(c.b);

/// WCAG 2.x contrast ratio between two opaque colours, 1.0 to 21.0.
double contrastRatio(Color a, Color b) {
  final la = relativeLuminance(a);
  final lb = relativeLuminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// A CIE L*a*b* colour (D65 white point).
typedef Lab = ({double l, double a, double b});

Lab labOf(Color c) {
  final r = _linear(c.r);
  final g = _linear(c.g);
  final b = _linear(c.b);
  final x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047;
  final y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b;
  final z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883;
  double f(double t) => t > 216 / 24389
      ? math.pow(t, 1 / 3).toDouble()
      : (24389 / 27 * t + 16) / 116;
  final fx = f(x);
  final fy = f(y);
  final fz = f(z);
  return (l: 116 * fy - 16, a: 500 * (fx - fy), b: 200 * (fy - fz));
}

double _rad(double deg) => deg * math.pi / 180;

double _hueDeg(double b, double a) {
  if (a == 0 && b == 0) return 0;
  final h = math.atan2(b, a) * 180 / math.pi;
  return h < 0 ? h + 360 : h;
}

/// CIEDE2000 colour difference. Around 1 is a just-noticeable difference.
double deltaE2000Lab(Lab p, Lab q) {
  const pow25to7 = 6103515625.0; // 25^7
  final c1 = math.sqrt(p.a * p.a + p.b * p.b);
  final c2 = math.sqrt(q.a * q.a + q.b * q.b);
  final cBar7 = math.pow((c1 + c2) / 2, 7).toDouble();
  final g = 0.5 * (1 - math.sqrt(cBar7 / (cBar7 + pow25to7)));
  final a1 = (1 + g) * p.a;
  final a2 = (1 + g) * q.a;
  final c1p = math.sqrt(a1 * a1 + p.b * p.b);
  final c2p = math.sqrt(a2 * a2 + q.b * q.b);
  final h1 = _hueDeg(p.b, a1);
  final h2 = _hueDeg(q.b, a2);

  final dL = q.l - p.l;
  final dC = c2p - c1p;
  var dh = 0.0;
  if (c1p * c2p != 0) {
    dh = h2 - h1;
    if (dh > 180) {
      dh -= 360;
    } else if (dh < -180) {
      dh += 360;
    }
  }
  final dH = 2 * math.sqrt(c1p * c2p) * math.sin(_rad(dh / 2));

  final lBar = (p.l + q.l) / 2;
  final cBarP = (c1p + c2p) / 2;
  double hBar;
  if (c1p * c2p == 0) {
    hBar = h1 + h2;
  } else if ((h1 - h2).abs() <= 180) {
    hBar = (h1 + h2) / 2;
  } else if (h1 + h2 < 360) {
    hBar = (h1 + h2 + 360) / 2;
  } else {
    hBar = (h1 + h2 - 360) / 2;
  }

  final t = 1 -
      0.17 * math.cos(_rad(hBar - 30)) +
      0.24 * math.cos(_rad(2 * hBar)) +
      0.32 * math.cos(_rad(3 * hBar + 6)) -
      0.20 * math.cos(_rad(4 * hBar - 63));
  final dTheta = 30 * math.exp(-math.pow((hBar - 275) / 25, 2));
  final cBarP7 = math.pow(cBarP, 7).toDouble();
  final rC = 2 * math.sqrt(cBarP7 / (cBarP7 + pow25to7));
  final lTerm = (lBar - 50) * (lBar - 50);
  final sL = 1 + 0.015 * lTerm / math.sqrt(20 + lTerm);
  final sC = 1 + 0.045 * cBarP;
  final sH = 1 + 0.015 * cBarP * t;
  final rT = -math.sin(_rad(2 * dTheta)) * rC;

  final xL = dL / sL;
  final xC = dC / sC;
  final xH = dH / sH;
  return math.sqrt(xL * xL + xC * xC + xH * xH + rT * xC * xH);
}

double deltaE2000(Color a, Color b) => deltaE2000Lab(labOf(a), labOf(b));
