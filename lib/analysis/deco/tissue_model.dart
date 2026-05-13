/// ZHL-16C tissue compartment constants. Verbatim from Subsurface's
/// core/deco.cpp — canonical Bühlmann ZHL-16C parameters.
///
/// Half-times in minutes; a/b are the Workman/Bühlmann coefficients
/// for the M-value linear relationship M = a + depth/b.
library;

class TissueCompartment {
  final double halfTimeN2Min;
  final double halfTimeHeMin;
  final double aN2;
  final double bN2;
  final double aHe;
  final double bHe;
  const TissueCompartment({
    required this.halfTimeN2Min,
    required this.halfTimeHeMin,
    required this.aN2,
    required this.bN2,
    required this.aHe,
    required this.bHe,
  });
}

/// 16 compartments, fast-to-slow. Values from Subsurface core/deco.cpp
/// (which sources Bühlmann ZHL-16C as published).
const List<TissueCompartment> zhl16cTissues = [
  TissueCompartment(halfTimeN2Min: 4.0,   halfTimeHeMin: 1.51,   aN2: 1.2599, bN2: 0.5050, aHe: 1.7424, bHe: 0.4245),
  TissueCompartment(halfTimeN2Min: 8.0,   halfTimeHeMin: 3.02,   aN2: 1.0000, bN2: 0.6514, aHe: 1.3830, bHe: 0.5747),
  TissueCompartment(halfTimeN2Min: 12.5,  halfTimeHeMin: 4.72,   aN2: 0.8618, bN2: 0.7222, aHe: 1.1919, bHe: 0.6527),
  TissueCompartment(halfTimeN2Min: 18.5,  halfTimeHeMin: 6.99,   aN2: 0.7562, bN2: 0.7825, aHe: 1.0458, bHe: 0.7223),
  TissueCompartment(halfTimeN2Min: 27.0,  halfTimeHeMin: 10.21,  aN2: 0.6200, bN2: 0.8126, aHe: 0.9220, bHe: 0.7582),
  TissueCompartment(halfTimeN2Min: 38.3,  halfTimeHeMin: 14.48,  aN2: 0.5043, bN2: 0.8434, aHe: 0.8205, bHe: 0.7957),
  TissueCompartment(halfTimeN2Min: 54.3,  halfTimeHeMin: 20.53,  aN2: 0.4410, bN2: 0.8693, aHe: 0.7305, bHe: 0.8279),
  TissueCompartment(halfTimeN2Min: 77.0,  halfTimeHeMin: 29.11,  aN2: 0.4000, bN2: 0.8910, aHe: 0.6502, bHe: 0.8553),
  TissueCompartment(halfTimeN2Min: 109.0, halfTimeHeMin: 41.20,  aN2: 0.3750, bN2: 0.9092, aHe: 0.5950, bHe: 0.8757),
  TissueCompartment(halfTimeN2Min: 146.0, halfTimeHeMin: 55.19,  aN2: 0.3500, bN2: 0.9222, aHe: 0.5545, bHe: 0.8903),
  TissueCompartment(halfTimeN2Min: 187.0, halfTimeHeMin: 70.69,  aN2: 0.3295, bN2: 0.9319, aHe: 0.5333, bHe: 0.8997),
  TissueCompartment(halfTimeN2Min: 239.0, halfTimeHeMin: 90.34,  aN2: 0.3065, bN2: 0.9403, aHe: 0.5189, bHe: 0.9073),
  TissueCompartment(halfTimeN2Min: 305.0, halfTimeHeMin: 115.29, aN2: 0.2835, bN2: 0.9477, aHe: 0.5181, bHe: 0.9122),
  TissueCompartment(halfTimeN2Min: 390.0, halfTimeHeMin: 147.42, aN2: 0.2610, bN2: 0.9544, aHe: 0.5176, bHe: 0.9171),
  TissueCompartment(halfTimeN2Min: 498.0, halfTimeHeMin: 188.24, aN2: 0.2480, bN2: 0.9602, aHe: 0.5172, bHe: 0.9217),
  TissueCompartment(halfTimeN2Min: 635.0, halfTimeHeMin: 240.03, aN2: 0.2327, bN2: 0.9653, aHe: 0.5119, bHe: 0.9267),
];
