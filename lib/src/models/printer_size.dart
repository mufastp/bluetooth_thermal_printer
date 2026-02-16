/// Thermal printer paper width.
enum PrinterSize {
  threeInch(32),
  fourInch(48);

  const PrinterSize(this.lineWidth);
  final int lineWidth;
}
