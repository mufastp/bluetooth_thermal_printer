import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:image/image.dart' as img;

import 'models/printer_design_settings.dart';
import 'models/printer_size.dart';
import 'models/receipt_data.dart';

/// Generates ESC/POS byte streams for thermal receipt printers.
class EscPosGenerator {
  EscPosGenerator({
    required this.receiptData,
    required this.printerSize,
    this.design = const PrinterDesignSettings(),
    this.use4InchFullLayout = false,
  });

  final ReceiptData receiptData;
  final PrinterSize printerSize;
  final PrinterDesignSettings design;
  final bool use4InchFullLayout;

  /// Build bytes for 3-inch or 4-inch standard layout.
  Future<List<int>> generateStandardReceipt() async {
    final lineWidth = printerSize.lineWidth;
    final data = receiptData;
    final bytes = <int>[];

    final companyName = data.companyInfo.name.trim().isEmpty
        ? 'Company Name'
        : data.companyInfo.name;
    final address1 =
        data.companyInfo.address1.trim().isEmpty ? '' : data.companyInfo.address1;
    final address2 =
        data.companyInfo.address2.trim().isEmpty ? '' : data.companyInfo.address2;
    final companyPhone =
        data.companyInfo.phone.trim().isEmpty ? '' : data.companyInfo.phone;
    final companyTaxNo = data.companyInfo.taxNo?.trim();

    bytes.addAll([0x1B, 0x40]);
    bytes.addAll([0x1B, 0x21, 0x00]);
    bytes.addAll([0x1B, 0x33, 0x00]);
    bytes.addAll([0x1B, 0x4D, 0x00]);
    bytes.addAll([0x1D, 0x4C, 0x00, 0x00]);

    bytes.addAll([0x1B, 0x61, 0x01]);
    if (design.enableLogo && !design.logoTextOnly && design.logoPath.isNotEmpty) {
      try {
        final monogramBytes = await _imageToEscPosRaster(design.logoPath, lineWidth);
        if (monogramBytes.isNotEmpty) bytes.addAll(monogramBytes);
      } catch (e) {
        log('Monogram print error (skipping image): $e');
      }
    }
    if (design.enableLogo) {
      bytes.addAll([0x1D, 0x21, 0x11]);
      bytes.addAll(utf8.encode('$companyName\n\n'));
    }

    bytes.addAll([0x1D, 0x21, 0x00]);
    final addressLine =
        [address1, address2].where((s) => s.isNotEmpty).join(', ');
    if (addressLine.isNotEmpty) bytes.addAll(utf8.encode('$addressLine\n'));
    final email = data.companyInfo.email ?? 'sales@example.com';
    bytes.addAll(utf8.encode('$email\n'));
    if (companyPhone.isNotEmpty) {
      bytes.addAll(utf8.encode('Mobile : $companyPhone\n'));
    }
    if (design.enableGstVat &&
        companyTaxNo != null &&
        companyTaxNo.isNotEmpty) {
      bytes.addAll(utf8.encode('TRN : $companyTaxNo\n'));
    }

    _addSeparatorLine(bytes, lineWidth: lineWidth);
    bytes.addAll([0x1B, 0x45, 0x01]);
    bytes.addAll(utf8.encode('TAX INVOICE\n\n'));
    bytes.addAll([0x1B, 0x45, 0x00]);

    bytes.addAll([0x1B, 0x61, 0x00]);
    if (design.printSalesMan) {
      _addBillLine(
        bytes,
        'SalesMan : ${data.salesmanName}',
        '',
        lineWidth: lineWidth,
      );
      bytes.addAll(utf8.encode('\n'));
    }
    _addBillLine(bytes, 'Route : ${data.routeName}', '', lineWidth: lineWidth);
    bytes.addAll(utf8.encode('\n'));
    _addBillLine(
      bytes,
      'Inv Num : ${data.invoiceNumber}',
      'Date : ${_formatDate(data.dateTime)}',
      lineWidth: lineWidth,
    );
    bytes.addAll(utf8.encode('\n'));
    _addBillLine(
      bytes,
      'Phone No : ${data.customerPhone}',
      '',
      lineWidth: lineWidth,
    );
    bytes.addAll(utf8.encode('\n'));
    _addBillLine(
      bytes,
      'Pay Mode : ${data.paymentMethod.toUpperCase()} INVOICE',
      '',
      lineWidth: lineWidth,
    );
    _addSeparatorLine(bytes, lineWidth: lineWidth);

    if (design.custName ||
        design.custAddress ||
        design.custCode ||
        design.custNumber ||
        design.custTrn) {
      bytes.addAll(utf8.encode('\n'));
      if (design.custName) {
        if (design.custNameTrnBold) bytes.addAll([0x1B, 0x45, 0x01]);
        bytes.addAll(utf8.encode('Cust Name : ${data.customerName}\n'));
        if (design.custNameTrnBold) bytes.addAll([0x1B, 0x45, 0x00]);
        bytes.addAll(utf8.encode('\n'));
      }
      if (design.custAddress) {
        bytes.addAll(utf8.encode('Address : ${data.customerAddress}\n'));
        bytes.addAll(utf8.encode('\n'));
      }
      if (design.custCode) {
        bytes.addAll(utf8.encode('Cust Code : ${data.customerCode}\n'));
        bytes.addAll(utf8.encode('\n'));
      }
      if (design.custNumber) {
        bytes.addAll(utf8.encode('Number : ${data.customerPhone}\n'));
        bytes.addAll(utf8.encode('\n'));
      }
      if (design.custTrn) {
        if (design.custNameTrnBold) bytes.addAll([0x1B, 0x45, 0x01]);
        bytes.addAll(utf8.encode('Cust TRN  : ${data.customerTRN}\n'));
        if (design.custNameTrnBold) bytes.addAll([0x1B, 0x45, 0x00]);
        bytes.addAll(utf8.encode('\n'));
      }
    }

    _addSeparatorLine(bytes, lineWidth: lineWidth);

    String header = 'Sl '.padRight(3) +
        'Item Name'.padRight(14) +
        'Qty'.padLeft(4) +
        'Rate'.padLeft(7) +
        (design.printItemTotal ? 'Total'.padLeft(9) : '') +
        'VAT'.padLeft(4) +
        'Gross'.padLeft(7);
    bytes.addAll(utf8.encode(header + '\n'));
    _addSeparatorLine(bytes, lineWidth: lineWidth);

    const int slWidth = 3;
    const int nameWidth = 14;
    const int dataIndent = slWidth + nameWidth;
    for (int i = 0; i < data.items.length; i++) {
      final item = data.items[i];
      String nameLine = '${item.productCode}-${item.name}';
      if (design.itemNameBold) bytes.addAll([0x1B, 0x45, 0x01]);
      bytes.addAll(utf8.encode(
          '${(i + 1).toString().padRight(slWidth)}$nameLine\n'));
      if (design.itemNameBold) bytes.addAll([0x1B, 0x45, 0x00]);

      String qtyStr = _fmt(item.quantity, design.qtyDecimalPlaces).padLeft(4);
      String rateStr = _fmt(item.price, design.totalDecimalPlaces).padLeft(7);
      String netStr =
          _fmt(item.netTotal, design.totalDecimalPlaces).padLeft(9);
      String vatStr =
          _fmt(item.vatAmount, design.totalDecimalPlaces).padLeft(4);
      String grossStr = _fmt(item.total, design.totalDecimalPlaces).padLeft(7);
      String dataRow = ' ' * dataIndent + qtyStr + rateStr;
      if (design.printItemTotal) dataRow += netStr;
      dataRow += vatStr + grossStr + '\n';
      bytes.addAll(utf8.encode(dataRow));
    }

    _addSeparatorLine(bytes, lineWidth: lineWidth);
    bytes.addAll([0x1B, 0x45, 0x01]);
    _addBillLine(
      bytes,
      'Net Amount',
      _fmt(data.totalBeforeTax, design.totalDecimalPlaces),
      lineWidth: lineWidth,
    );
    bytes.addAll(utf8.encode('\n'));
    _addBillLine(
      bytes,
      'VAT 5%',
      _fmt(data.taxAmount, design.totalDecimalPlaces),
      lineWidth: lineWidth,
    );
    bytes.addAll(utf8.encode('\n'));
    _addBillLine(
      bytes,
      'Round Off',
      _fmt(data.roundOff, design.totalDecimalPlaces),
      lineWidth: lineWidth,
    );
    _addSeparatorLine(bytes, lineWidth: lineWidth);
    _addBillLine(
      bytes,
      'Gross Amount',
      _fmt(data.totalAmount, design.totalDecimalPlaces),
      lineWidth: lineWidth,
    );
    _addSeparatorLine(bytes, lineWidth: lineWidth);
    bytes.addAll([0x1D, 0x21, 0x01]);
    _addBillLine(
      bytes,
      'Gross inc. VAT',
      _fmt(data.totalAmount, design.totalDecimalPlaces),
      lineWidth: lineWidth,
    );
    bytes.addAll(utf8.encode('\n'));
    bytes.addAll([0x1D, 0x21, 0x00]);
    bytes.addAll(utf8.encode('Dirhams Only\n\n'));

    bytes.addAll([0x1B, 0x61, 0x00]);
    _addBillLine(bytes, 'CUST. SIG', 'AUTH. SIG', lineWidth: lineWidth);
    bytes.addAll([0x1B, 0x61, 0x01]);
    bytes.addAll(utf8.encode('\nThank You!\n\nPlease Visit Again\n'));

    bytes.addAll([0x1D, 0x56, 0x41, 0x03]);
    return bytes;
  }

  /// Build bytes for 4-inch full layout (64 chars).
  Future<List<int>> generate4InchFullReceipt() async {
    const lineWidth = 64;
    final data = receiptData;
    final bytes = <int>[];

    final companyName4 = data.companyInfo.name.trim().isEmpty
        ? 'Company Name'
        : data.companyInfo.name;
    final address14 = data.companyInfo.address1.trim();
    final address24 = data.companyInfo.address2.trim();
    final companyPhone4 = data.companyInfo.phone.trim();
    final companyTaxNo4 = data.companyInfo.taxNo?.trim();

    bytes.addAll([0x1B, 0x40]);
    bytes.addAll([0x1B, 0x61, 0x01]);

    if (design.enableLogo &&
        !design.logoTextOnly &&
        design.logoPath.isNotEmpty) {
      try {
        final monogramBytes =
            await _imageToEscPosRaster(design.logoPath, lineWidth);
        if (monogramBytes.isNotEmpty) {
          bytes.addAll(monogramBytes);
          bytes.addAll([0x0A]);
        }
      } catch (e) {
        log('Monogram print error (4") (skipping image): $e');
      }
    }
    if (design.enableLogo) {
      bytes.addAll([0x1D, 0x21, 0x11]);
      bytes.addAll(utf8.encode('$companyName4\n'));
    }
    bytes.addAll([0x1D, 0x21, 0x00]);
    final addressLine4 =
        [address14, address24].where((s) => s.isNotEmpty).join(', ');
    if (addressLine4.isNotEmpty) {
      bytes.addAll(utf8.encode('$addressLine4\n'));
    }
    final email = data.companyInfo.email ?? 'sales@example.com';
    bytes.addAll(utf8.encode('$email\n'));
    if (companyPhone4.isNotEmpty) {
      bytes.addAll(utf8.encode('Mobile : $companyPhone4\n'));
    }
    if (design.enableGstVat &&
        companyTaxNo4 != null &&
        companyTaxNo4.isNotEmpty) {
      bytes.addAll(utf8.encode('TRN : $companyTaxNo4\n'));
    }

    _addSeparatorLine(bytes, lineWidth: lineWidth);
    bytes.addAll([0x1B, 0x45, 0x01]);
    bytes.addAll(utf8.encode('TAX INVOICE\n\n'));
    bytes.addAll([0x1B, 0x45, 0x00]);

    bytes.addAll([0x1B, 0x61, 0x00]);
    if (design.printSalesMan) {
      _addBillLine(
        bytes,
        'SalesMan : ${data.salesmanName}',
        '',
        lineWidth: lineWidth,
      );
    }
    _addBillLine(bytes, 'Route : ${data.routeName}', '', lineWidth: lineWidth);
    _addBillLine(
      bytes,
      'Inv Num : ${data.invoiceNumber}',
      'Date : ${_formatDate4(data.dateTime)}',
      lineWidth: lineWidth,
    );
    _addBillLine(
      bytes,
      'Phone No : ${data.customerPhone}',
      '',
      lineWidth: lineWidth,
    );
    _addBillLine(
      bytes,
      'Pay Mode : ${data.paymentMethod.toUpperCase()} INVOICE',
      '',
      lineWidth: lineWidth,
    );

    if (design.custName ||
        design.custAddress ||
        design.custCode ||
        design.custNumber ||
        design.custTrn) {
      bytes.addAll(utf8.encode('\n'));
      if (design.custName) {
        if (design.custNameTrnBold) bytes.addAll([0x1B, 0x45, 0x01]);
        bytes.addAll(utf8.encode('Cust Name : ${data.customerName}\n'));
        if (design.custNameTrnBold) bytes.addAll([0x1B, 0x45, 0x00]);
      }
      if (design.custCode) {
        bytes.addAll(utf8.encode('Cust Code : ${data.customerCode}\n'));
      }
      if (design.custAddress) {
        bytes.addAll(utf8.encode('Address : ${data.customerAddress}\n'));
      }
      if (design.custNumber) {
        bytes.addAll(utf8.encode('Phone : ${data.customerPhone}\n'));
      }
      if (design.custTrn) {
        if (design.custNameTrnBold) bytes.addAll([0x1B, 0x45, 0x01]);
        bytes.addAll(utf8.encode('Cust TRN : ${data.customerTRN}\n'));
        if (design.custNameTrnBold) bytes.addAll([0x1B, 0x45, 0x00]);
      }
    }

    _addSeparatorLine(bytes, lineWidth: lineWidth);

    String header = 'Sl '.padRight(3) +
        'Item Name'.padRight(19) +
        'Qty'.padLeft(5) +
        'Rate'.padLeft(7) +
        'NetTotal'.padLeft(9) +
        'VAT'.padLeft(7) +
        'VAT%'.padLeft(5) +
        'Gross'.padLeft(9);
    bytes.addAll(utf8.encode(header + '\n'));
    _addSeparatorLine(bytes, lineWidth: lineWidth);

    for (int i = 0; i < data.items.length; i++) {
      final item = data.items[i];
      String sl = (i + 1).toString().padRight(3);
      String nameLine = '${item.productCode}-${item.name}';
      if (design.itemNameBold) bytes.addAll([0x1B, 0x45, 0x01]);
      bytes.addAll(utf8.encode(sl + nameLine + '\n'));
      if (design.itemNameBold) bytes.addAll([0x1B, 0x45, 0x00]);

      String qty =
          _fmt(item.quantity, design.qtyDecimalPlaces).padLeft(3 + 19 + 5 - 3);
      String rate = _fmt(item.price, design.totalDecimalPlaces).padLeft(7);
      String net = _fmt(item.netTotal, design.totalDecimalPlaces).padLeft(9);
      String vat = _fmt(item.vatAmount, design.totalDecimalPlaces).padLeft(7);
      String vatP = '${item.vatPercentage.toInt()}%'.padLeft(5);
      String gross = _fmt(item.total, design.totalDecimalPlaces).padLeft(9);
      bytes.addAll(utf8.encode(
          '   ' + ' ' * 19 + qty + rate + net + vat + vatP + gross + '\n'));
    }

    _addSeparatorLine(bytes, lineWidth: lineWidth);
    _addBillLine(
      bytes,
      'Net Amount',
      _fmt(data.totalBeforeTax, design.totalDecimalPlaces),
      lineWidth: lineWidth,
    );
    _addBillLine(
      bytes,
      'VAT 5%',
      _fmt(data.taxAmount, design.totalDecimalPlaces),
      lineWidth: lineWidth,
    );
    _addBillLine(
      bytes,
      'Round Off',
      _fmt(data.roundOff, design.totalDecimalPlaces),
      lineWidth: lineWidth,
    );
    _addSeparatorLine(bytes, lineWidth: lineWidth);
    bytes.addAll([0x1B, 0x45, 0x01]);
    _addBillLine(
      bytes,
      'Gross Amount',
      _fmt(data.totalAmount, design.totalDecimalPlaces),
      lineWidth: lineWidth,
    );
    bytes.addAll([0x1B, 0x45, 0x00]);
    _addSeparatorLine(bytes, lineWidth: lineWidth);
    bytes.addAll([0x1D, 0x21, 0x01]);
    _addBillLine(
      bytes,
      'Gross Amount inc. VAT',
      _fmt(data.totalAmount, design.totalDecimalPlaces),
      lineWidth: lineWidth,
    );
    bytes.addAll([0x1D, 0x21, 0x00]);
    bytes.addAll(utf8.encode('Dirhams Only\n\n\n'));
    _addBillLine(
      bytes,
      "CUSTOMER'S SIGNATURE",
      "AUTHORIZED SIGNATURE",
      lineWidth: lineWidth,
    );
    bytes.addAll([0x1B, 0x64, 0x04]);
    bytes.addAll([0x1D, 0x56, 0x41, 0x03]);
    return bytes;
  }

  /// Generate receipt bytes (standard or 4-inch full based on settings).
  Future<List<int>> generate() async {
    if (use4InchFullLayout && printerSize == PrinterSize.fourInch) {
      return generate4InchFullReceipt();
    }
    return generateStandardReceipt();
  }

  static String _formatDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year.toString().substring(2);
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d-$m-$y $h:$min';
  }

  static String _formatDate4(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year.toString();
    final h = dt.hour;
    final min = dt.minute.toString().padLeft(2, '0');
    final am = h < 12 ? 'AM' : 'PM';
    final h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    return '$d-$m-$y $h12:$min $am';
  }

  static String _fmt(num value, int decimals) {
    if (decimals == 0) return value.toInt().toString();
    return value.toStringAsFixed(decimals);
  }

  static void _addSeparatorLine(List<int> bytes, {int lineWidth = 32}) {
    bytes.addAll(utf8.encode('-' * lineWidth + '\n'));
  }

  static void _addBillLine(
    List<int> bytes,
    String left,
    String right, {
    int lineWidth = 32,
  }) {
    int leftWidth = (lineWidth / 2).floor();
    int rightWidth = lineWidth - leftWidth;
    String leftCol = left.length > leftWidth
        ? left.substring(0, leftWidth)
        : left.padRight(leftWidth);
    String rightCol = right.length > rightWidth
        ? right.substring(0, rightWidth)
        : right.padLeft(rightWidth);
    bytes.addAll(utf8.encode(leftCol + rightCol + '\n'));
  }

  static Future<List<int>> _imageToEscPosRaster(
    String imagePath,
    int lineWidth,
  ) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        log('Monogram file not found: $imagePath');
        return [];
      }
      final bytes = await file.readAsBytes();
      img.Image? decoded = img.decodeImage(bytes);
      if (decoded == null) {
        log('Monogram decode failed: $imagePath');
        return [];
      }
      const int maxWidth = 1024;
      const int maxHeight = 480;
      int w = decoded.width;
      int h = decoded.height;
      if (w > maxWidth || h > maxHeight) {
        final scaleW = maxWidth / w;
        final scaleH = maxHeight / h;
        final scale = scaleW < scaleH ? scaleW : scaleH;
        w = (decoded.width * scale).round();
        h = (decoded.height * scale).round();
        decoded = img.copyResize(decoded, width: w, height: h);
      }
      w = decoded.width;
      h = decoded.height;
      w = (w ~/ 8) * 8;
      h = (h ~/ 8) * 8;
      if (w < 8 || h < 8) return [];
      if (w != decoded.width || h != decoded.height) {
        decoded = img.copyResize(decoded, width: w, height: h);
      }
      final image = decoded;

      int luminanceAt(int x, int y) {
        if (x < 0 || x >= image.width || y < 0 || y >= image.height) {
          return 255;
        }
        final p = image.getPixel(x, y);
        return (p.r * 0.299 + p.g * 0.587 + p.b * 0.114).round();
      }

      final widthBytes = w ~/ 8;
      final out = <int>[];
      out.addAll([0x1D, 0x76, 0x30, 0x00]);
      out.add(widthBytes & 0xFF);
      out.add((widthBytes >> 8) & 0xFF);
      out.add(h & 0xFF);
      out.add((h >> 8) & 0xFF);
      for (int y = 0; y < h; y++) {
        for (int bx = 0; bx < widthBytes; bx++) {
          int byte = 0;
          for (int i = 0; i < 8; i++) {
            final x = bx * 8 + i;
            if (luminanceAt(x, y) < 128) byte |= (1 << (7 - i));
          }
          out.add(byte);
        }
      }
      log('Monogram ESC/POS: ${out.length} bytes (GS v 0) ${w}x$h');
      return out;
    } catch (e) {
      log('Monogram image to ESC/POS error: $e');
      return [];
    }
  }
}
