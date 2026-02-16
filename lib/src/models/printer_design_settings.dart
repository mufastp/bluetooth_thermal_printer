/// Design options for receipt layout (logo, customer fields, decimals, etc.).
class PrinterDesignSettings {
  final bool enableLogo;
  final bool enableGstVat;
  final bool printSalesMan;
  final bool printItemTotal;
  final bool custName;
  final bool custAddress;
  final bool custCode;
  final bool custNumber;
  final bool custTrn;
  final bool custNameTrnBold;
  final bool itemNameBold;
  final int qtyDecimalPlaces;
  final int totalDecimalPlaces;
  final String logoPath;
  final bool logoTextOnly;

  const PrinterDesignSettings({
    this.enableLogo = true,
    this.enableGstVat = true,
    this.printSalesMan = false,
    this.printItemTotal = true,
    this.custName = true,
    this.custAddress = false,
    this.custCode = true,
    this.custNumber = false,
    this.custTrn = true,
    this.custNameTrnBold = false,
    this.itemNameBold = false,
    this.qtyDecimalPlaces = 2,
    this.totalDecimalPlaces = 2,
    this.logoPath = '',
    this.logoTextOnly = false,
  });

  /// From a map (e.g. from SQLite or shared_preferences).
  factory PrinterDesignSettings.fromMap(Map<String, dynamic> map) {
    return PrinterDesignSettings(
      enableLogo: _intToBool(map['enable_logo'], true),
      enableGstVat: _intToBool(map['enable_gst_vat'], true),
      printSalesMan: _intToBool(map['print_sales_man'], false),
      printItemTotal: _intToBool(map['print_item_total'], true),
      custName: _intToBool(map['cust_name'], true),
      custAddress: _intToBool(map['cust_address1'], false),
      custCode: _intToBool(map['cust_code'], true),
      custNumber: _intToBool(map['cust_mobile'], false),
      custTrn: _intToBool(map['cust_gst_vat'], true),
      custNameTrnBold: _intToBool(map['cust_name_trn_bold'], false),
      itemNameBold: _intToBool(map['item_name_bold'], false),
      qtyDecimalPlaces: map['qty_decimal_places'] as int? ?? 2,
      totalDecimalPlaces: map['total_decimal_places'] as int? ?? 2,
      logoPath: _stringFromDesign(map['logo_path']),
      logoTextOnly: _intToBool(map['logo_text_only'], false),
    );
  }

  static bool _intToBool(dynamic value, bool defaultValue) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    return (value as int?) == 1;
  }

  static String _stringFromDesign(dynamic value) {
    if (value == null) return '';
    if (value is String) return value.trim();
    return value.toString().trim();
  }
}
