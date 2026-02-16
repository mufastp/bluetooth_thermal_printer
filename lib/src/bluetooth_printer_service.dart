import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:permission_handler/permission_handler.dart';

import 'esc_pos_generator.dart';
import 'models/printer_design_settings.dart';
import 'models/printer_size.dart';
import 'models/receipt_data.dart';

/// RSSI threshold (dBm) for "nearby" devices. Stronger than this = shown.
const int nearbyRssiThreshold = -80;

/// Service for connecting to Bluetooth thermal printers and printing receipts.
class BluetoothPrinterService {
  BluetoothPrinterService();

  fbp.BluetoothDevice? _selectedDevice;
  fbp.BluetoothCharacteristic? _writeCharacteristic;

  final _isConnected = ValueNotifier<bool>(false);
  final _isPrinting = ValueNotifier<bool>(false);
  final _scanResults = ValueNotifier<List<fbp.ScanResult>>([]);
  final _isScanning = ValueNotifier<bool>(false);
  StreamSubscription<fbp.BluetoothConnectionState>? _connectionSubscription;

  /// Whether a printer is currently connected.
  ValueNotifier<bool> get isConnected => _isConnected;

  /// Whether a print job is in progress.
  ValueNotifier<bool> get isPrinting => _isPrinting;

  /// Current scan results (sorted by RSSI, strongest first).
  ValueNotifier<List<fbp.ScanResult>> get scanResults => _scanResults;

  /// Whether a scan is in progress.
  ValueNotifier<bool> get isScanning => _isScanning;

  /// Currently selected device (if any).
  fbp.BluetoothDevice? get selectedDevice => _selectedDevice;

  /// MAC address of the connected/saved printer, or null.
  String? get savedPrinterMac => _selectedDevice?.remoteId.str;

  /// Connect to a Bluetooth printer device.
  Future<void> connectToDevice(fbp.BluetoothDevice device) async {
    try {
      await device.connect(
        timeout: const Duration(seconds: 15),
        autoConnect: false,
      );

      _selectedDevice = device;
      _isConnected.value = true;

      List<fbp.BluetoothService> services = await device.discoverServices();

      for (var service in services) {
        for (var characteristic in service.characteristics) {
          if (characteristic.properties.write) {
            _writeCharacteristic = characteristic;
            break;
          }
        }
        if (_writeCharacteristic != null) break;
      }

      _connectionSubscription?.cancel();
      _connectionSubscription = device.connectionState.listen((state) {
        if (state == fbp.BluetoothConnectionState.disconnected) {
          _isConnected.value = false;
          _writeCharacteristic = null;
        }
      });
    } catch (e, s) {
      log('Error connecting to device: $e');
      log('Stack: $s');
      _isConnected.value = false;
      rethrow;
    }
  }

  /// Reconnect to a previously known printer by MAC.
  Future<bool> reconnectToPrinter(String mac) async {
    try {
      if (!await fbp.FlutterBluePlus.isSupported) return false;

      final bondedDevices = await fbp.FlutterBluePlus.bondedDevices;
      final matches = bondedDevices.where((d) => d.remoteId.str == mac).toList();

      if (matches.isNotEmpty) {
        await connectToDevice(matches.first);
        return _isConnected.value;
      }
    } catch (e) {
      log('Error reconnecting to saved printer: $e');
      _isConnected.value = false;
    }
    return false;
  }

  /// Start scanning for Bluetooth devices. On Android, ensure Bluetooth and
  /// location permissions are granted.
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 15),
    bool requestPermissions = true,
  }) async {
    try {
      if (!await fbp.FlutterBluePlus.isSupported) {
        throw Exception('Bluetooth is not supported on this device');
      }

      if (requestPermissions) {
        final statuses = await [
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.location,
        ].request();

        if (statuses[Permission.bluetoothScan] != PermissionStatus.granted ||
            statuses[Permission.bluetoothConnect] != PermissionStatus.granted) {
          throw Exception(
            'Bluetooth permissions are required to scan for printers.',
          );
        }
      }

      if (await fbp.FlutterBluePlus.adapterState.first !=
          fbp.BluetoothAdapterState.on) {
        throw Exception('Please turn on Bluetooth');
      }

      _scanResults.value = [];
      _isScanning.value = true;

      fbp.FlutterBluePlus.onScanResults.listen((results) {
        final nearby = results
            .where((r) => r.rssi > nearbyRssiThreshold)
            .toList()
          ..sort((a, b) => b.rssi.compareTo(a.rssi));
        _scanResults.value = nearby;
      });

      await fbp.FlutterBluePlus.startScan(timeout: timeout);
    } catch (e) {
      log('Error starting scan: $e');
      rethrow;
    } finally {
      _isScanning.value = false;
    }
  }

  /// Stop scanning.
  Future<void> stopScan() async {
    await fbp.FlutterBluePlus.stopScan();
    _isScanning.value = false;
  }

  /// Check if the printer is ready (connected and write characteristic available).
  Future<bool> isPrinterReady() async {
    if (_selectedDevice == null) return false;

    try {
      if (!await fbp.FlutterBluePlus.isSupported) return false;

      final bondedDevices = await fbp.FlutterBluePlus.bondedDevices;
      final isBonded = bondedDevices.any(
        (d) => d.remoteId.str == _selectedDevice!.remoteId.str,
      );

      if (!isBonded) return false;

      if (!_isConnected.value) {
        await reconnectToPrinter(_selectedDevice!.remoteId.str);
      }

      return _isConnected.value && _writeCharacteristic != null;
    } catch (e) {
      log('Error checking printer readiness: $e');
      return false;
    }
  }

  /// Print raw ESC/POS bytes to the connected printer (in chunks).
  Future<void> writeBytes(List<int> bytes, {int chunkSize = 128}) async {
    if (_writeCharacteristic == null) {
      throw StateError('No write characteristic. Is the printer connected?');
    }

    for (int i = 0; i < bytes.length; i += chunkSize) {
      final end = (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
      final chunk = bytes.sublist(i, end);
      await _writeCharacteristic!.write(chunk, withoutResponse: true);
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  /// Generate receipt bytes and print. Uses [printerSize], [design], and
  /// [use4InchFullLayout] for layout.
  Future<bool> printReceipt(
    ReceiptData receiptData, {
    PrinterSize printerSize = PrinterSize.threeInch,
    PrinterDesignSettings design = const PrinterDesignSettings(),
    bool use4InchFullLayout = false,
  }) async {
    if (_isPrinting.value) return false;

    try {
      _isPrinting.value = true;

      if (!await isPrinterReady()) {
        throw Exception(
          'Printer is not connected. Please check Bluetooth connection.',
        );
      }

      final generator = EscPosGenerator(
        receiptData: receiptData,
        printerSize: printerSize,
        design: design,
        use4InchFullLayout: use4InchFullLayout,
      );

      final bytes = await generator.generate();
      await writeBytes(bytes);
      return true;
    } catch (e) {
      log('Error printing receipt: $e');
      rethrow;
    } finally {
      _isPrinting.value = false;
    }
  }

  /// Disconnect from the current device.
  Future<void> disconnect() async {
    if (_selectedDevice != null) {
      await _selectedDevice!.disconnect();
      _connectionSubscription?.cancel();
    }
    _selectedDevice = null;
    _writeCharacteristic = null;
    _isConnected.value = false;
  }

  /// Release resources. Call when the service is no longer needed.
  void dispose() {
    _connectionSubscription?.cancel();
    disconnect();
  }
}
