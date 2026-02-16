/// A single line item on the receipt.
class ReceiptItem {
  final String productCode;
  final String name;
  final double quantity;
  final double price;
  final double netTotal;
  final double vatAmount;
  final double total;
  final double vatPercentage;

  const ReceiptItem({
    required this.productCode,
    required this.name,
    required this.quantity,
    required this.price,
    required this.netTotal,
    required this.vatAmount,
    required this.total,
    this.vatPercentage = 5.0,
  });
}
