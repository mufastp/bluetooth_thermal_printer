import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:bluetooth_thermal_printer/bluetooth_thermal_printer.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bluetooth Thermal Printer Example',
      theme: ThemeData(useMaterial3: true),
      home: const PrinterExamplePage(),
    );
  }
}

class PrinterExamplePage extends StatefulWidget {
  const PrinterExamplePage({super.key});

  @override
  State<PrinterExamplePage> createState() => _PrinterExamplePageState();
}

class _PrinterExamplePageState extends State<PrinterExamplePage> {
  final BluetoothPrinterService _printer = BluetoothPrinterService();

  @override
  void dispose() {
    _printer.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    try {
      await _printer.startScan();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan error: $e')),
        );
      }
    }
  }

  Future<void> _connect(fbp.BluetoothDevice device) async {
    try {
      await _printer.connectToDevice(device);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connected')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connect error: $e')),
        );
      }
    }
  }

  Future<void> _printTest() async {
    final receipt = ReceiptData(
      companyInfo: const CompanyInfo(
        name: 'Example Co',
        address1: '123 Street',
        phone: '1234567890',
        taxNo: 'TRN123',
        email: 'sales@example.com',
      ),
      salesmanName: 'John',
      routeName: 'Route A',
      invoiceNumber: 'INV-001',
      dateTime: DateTime.now(),
      customerPhone: '9876543210',
      paymentMethod: 'cash',
      customerName: 'Customer Name',
      customerAddress: 'Address',
      customerCode: 'C001',
      customerTRN: 'TRN456',
      items: [
        ReceiptItem(
          productCode: 'P1',
          name: 'Product One',
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

    try {
      await _printer.printReceipt(
        receipt,
        printerSize: PrinterSize.threeInch,
        design: const PrinterDesignSettings(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Printed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Print error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bluetooth Thermal Printer')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: _printer.isConnected,
            builder: (_, connected, __) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      connected ? 'Connected' : 'Not connected',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _printer.isScanning.value ? null : _scan,
                      child: Text(
                        _printer.isScanning.value ? 'Scanning...' : 'Scan',
                      ),
                    ),
                    if (connected)
                      TextButton(
                        onPressed: _printTest,
                        child: const Text('Print test receipt'),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<List<fbp.ScanResult>>(
            valueListenable: _printer.scanResults,
            builder: (_, results, __) {
              if (results.isEmpty) {
                return const Text('No devices found. Tap Scan.');
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Devices (${results.length})',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  ...results.map((r) => ListTile(
                        title: Text(r.device.platformName.isNotEmpty
                            ? r.device.platformName
                            : r.device.remoteId.str),
                        subtitle: Text('${r.device.remoteId.str}  RSSI: ${r.rssi}'),
                        onTap: () => _connect(r.device),
                      )),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
