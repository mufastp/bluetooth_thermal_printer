# mf_bluetooth_printer

A Flutter package for **MF Bluetooth Printer** — print receipts to Bluetooth thermal printers using ESC/POS commands. Supports 3-inch and 4-inch paper, configurable receipt layout (logo, customer fields, decimals), and reconnection to a saved printer.

## Features

- **Bluetooth LE**: Connect to thermal printers via `flutter_blue_plus`.
- **ESC/POS**: Generates standard and 4-inch full receipt layouts.
- **Design options**: Toggle logo, GST/TRN, customer name/address/code/TRN, salesman, item totals, bold fields, decimal places.
- **Logo**: Optional monogram/logo image (converted to ESC/POS raster).
- **Chunked write**: Sends data in small chunks to respect Bluetooth MTU limits.

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  mf_bluetooth_printer: ^1.0.0
```

Then run `flutter pub get`.

### Permissions

- **Android**: `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`, and location (for scanning). Declare in `AndroidManifest.xml` and request at runtime.
- **iOS**: Add `NSBluetoothAlwaysUsageDescription` (and related) in `Info.plist`.

## Usage

### 1. Create the service

```dart
final printer = BluetoothPrinterService();
```

### 2. Scan and connect

```dart
await printer.startScan();  // optional: requestPermissions = true

// Listen to scan results
printer.scanResults.addListener(() {
  final devices = printer.scanResults.value;
  // show in UI
});

// Connect when user selects a device
await printer.connectToDevice(scanResult.device);
```

### 3. Reconnect to saved printer

```dart
final mac = 'AA:BB:CC:DD:EE:FF';  // e.g. from your settings
await printer.reconnectToPrinter(mac);
```

### 4. Print a receipt

```dart
final receipt = ReceiptData(
  companyInfo: CompanyInfo(name: 'My Co', address1: '...', phone: '...', taxNo: '...'),
  salesmanName: 'John',
  routeName: 'Route 1',
  invoiceNumber: 'INV-001',
  dateTime: DateTime.now(),
  customerPhone: '...',
  paymentMethod: 'cash',
  customerName: '...',
  customerAddress: '...',
  customerCode: '...',
  customerTRN: '...',
  items: [
    ReceiptItem(
      productCode: 'P1',
      name: 'Product',
      quantity: 2,
      price: 10.0,
      netTotal: 20.0,
      vatAmount: 1.0,
      total: 21.0,
    ),
  ],
  totalBeforeTax: 20.0,
  taxAmount: 1.0,
  roundOff: 0.0,
  totalAmount: 21.0,
);

await printer.printReceipt(
  receipt,
  printerSize: PrinterSize.threeInch,  // or PrinterSize.fourInch
  design: PrinterDesignSettings(
    enableLogo: true,
    enableGstVat: true,
    custName: true,
    custCode: true,
    custTrn: true,
    logoPath: '/path/to/logo.png',  // optional
  ),
  use4InchFullLayout: false,  // true for 4" full layout when size is fourInch
);
```

### 5. State

- `printer.isConnected` – `ValueNotifier<bool>`
- `printer.isPrinting` – `ValueNotifier<bool>`
- `printer.scanResults` – `ValueNotifier<List<ScanResult>>`
- `printer.isScanning` – `ValueNotifier<bool>`
- `printer.savedPrinterMac` – current device MAC or null

### 6. Cleanup

```dart
printer.dispose();
```

## Migrating from your GetX controller

- Replace `PrinterController` with `BluetoothPrinterService`.
- Replace `GetxController` reactive vars with `ValueNotifier` and `ValueListenableBuilder`.
- Load printer format (3"/4") and design from your DB, then pass `PrinterSize` and `PrinterDesignSettings` into `printReceipt(...)`. You can build `PrinterDesignSettings` from your existing map with `PrinterDesignSettings.fromMap(yourMap)`.
- Keep using your app’s `PrinterSettingsDB` / `PrinterDesignSettingsDB` to persist format and design; the package only needs the in-memory values when calling `printReceipt` and when reconnecting (use `reconnectToPrinter(savedMac)` with the MAC you store).

## Publishing to pub.dev

1. **Validate**: Run `dart pub publish --dry-run` (or `flutter pub publish --dry-run`) and fix any reported issues.
2. **Publish**: Run `dart pub publish` (or `flutter pub publish`). You’ll need a [pub.dev account](https://pub.dev) and to confirm the upload.

## License

MIT
