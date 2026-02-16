import 'company_info.dart';
import 'receipt_item.dart';

/// Complete data for a tax invoice / receipt.
class ReceiptData {
  final CompanyInfo companyInfo;
  final String salesmanName;
  final String routeName;
  final String invoiceNumber;
  final DateTime dateTime;
  final String customerPhone;
  final String paymentMethod;
  final String customerName;
  final String customerAddress;
  final String customerCode;
  final String customerTRN;
  final List<ReceiptItem> items;
  final double totalBeforeTax;
  final double taxAmount;
  final double roundOff;
  final double totalAmount;

  const ReceiptData({
    required this.companyInfo,
    required this.salesmanName,
    required this.routeName,
    required this.invoiceNumber,
    required this.dateTime,
    required this.customerPhone,
    required this.paymentMethod,
    required this.customerName,
    required this.customerAddress,
    required this.customerCode,
    required this.customerTRN,
    required this.items,
    required this.totalBeforeTax,
    required this.taxAmount,
    required this.roundOff,
    required this.totalAmount,
  });
}
