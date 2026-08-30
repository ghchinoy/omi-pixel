import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/device.dart';
import '../models/session.dart';
import '../services/ble_service.dart';
import '../services/session_manager.dart';
import 'live_screen.dart';
import 'session_detail_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    SessionManager.instance.refreshSessions();
    BleService.instance.tryReconnectLastDevice();
  }

  void _showScanBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return const _ScanBottomSheetContent();
      },
    );
  }

  Future<void> _handleStartRecording() async {
    final device = BleService.instance.currentDevice;
    if (device == null || !device.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please connect to an Omi device first')),
      );
      return;
    }

    final success = await SessionManager.instance.startRecording();
    if (success && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LiveScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('🎙️', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 8),
            Text(
              'Omi Pixel',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => SessionManager.instance.refreshSessions(),
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            // Device Status Card
            _buildDeviceCard(context),

            const SizedBox(height: 16),

            // Start Recording CTA
            _buildRecordingCta(context),

            const SizedBox(height: 24),

            // Recent Sessions Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Conversations',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: () => SessionManager.instance.refreshSessions(),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Sessions Stream List
            StreamBuilder<List<Session>>(
              stream: SessionManager.instance.sessionsStream,
              initialData: SessionManager.instance.cachedSessions,
              builder: (context, snapshot) {
                final sessions = snapshot.data ?? [];

                if (sessions.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(32.0),
                    alignment: Alignment.center,
                    child: Column(
                      children: [
                        Icon(
                          Icons.speaker_notes_off,
                          size: 48,
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No conversations recorded yet.',
                          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tap "Start Conversation" to record and diarize.',
                          style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7), fontSize: 13),
                        ),
                      ],
                    ),
                  );
                }

                return Column(
                  children: sessions.map((s) => _buildSessionCard(context, s)).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceCard(BuildContext context) {
    final theme = Theme.of(context);

    return StreamBuilder<bool>(
      stream: BleService.instance.reconnectingStream,
      initialData: BleService.instance.isReconnecting,
      builder: (context, reconnSnapshot) {
        final isReconnecting = reconnSnapshot.data ?? false;

        return StreamBuilder<OmiDeviceInfo?>(
          stream: BleService.instance.deviceStream,
          initialData: BleService.instance.currentDevice,
          builder: (context, snapshot) {
            final device = snapshot.data;
            final isConnected = device != null && device.isConnected;

            return Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: isConnected ? theme.colorScheme.primary.withValues(alpha: 0.5) : theme.colorScheme.outlineVariant,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            if (isReconnecting && !isConnected)
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            else
                              Icon(
                                isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
                                color: isConnected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                              ),
                            const SizedBox(width: 8),
                            Text(
                              isConnected
                                  ? device.name
                                  : (isReconnecting ? 'Reconnecting to Omi...' : 'No Device Connected'),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ],
                        ),
                        if (isConnected && device.batteryLevel >= 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.battery_std, size: 14, color: Colors.green),
                                const SizedBox(width: 2),
                                Text(
                                  '${device.batteryLevel}%',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    if (isConnected) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Codec: ${device.codec.label}',
                        style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => BleService.instance.disconnect(),
                        icon: const Icon(Icons.link_off),
                        label: const Text('Disconnect'),
                      ),
                    ] else ...[
                      const SizedBox(height: 8),
                      Text(
                        isReconnecting
                            ? 'Restoring connection to previously paired wearable...'
                            : 'Pair your Omi wearable to stream audio.',
                        style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: isReconnecting ? null : _showScanBottomSheet,
                        icon: const Icon(Icons.bluetooth_searching),
                        label: const Text('Scan for Omi Device'),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRecordingCta(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: _handleStartRecording,
        icon: const Icon(Icons.mic, size: 22),
        label: const Text(
          'Start Conversation',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildSessionCard(BuildContext context, Session session) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('MMM dd, HH:mm');

    Color statusColor = Colors.grey;
    if (session.status == SessionStatus.completed) statusColor = Colors.green;
    if (session.status == SessionStatus.processing) statusColor = Colors.amber;
    if (session.status == SessionStatus.failed) statusColor = Colors.red;

    return Card(
      margin: const EdgeInsets.only(bottom: 10.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SessionDetailScreen(session: session),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      session.title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      session.status.name.toUpperCase(),
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
                    ),
                  ),
                ],
              ),
              if (session.summary.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  session.summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    dateFormat.format(session.startedAt),
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
                  ),
                  if (session.durationSeconds > 0) ...[
                    const SizedBox(width: 12),
                    Text(
                      '⏱️ ${session.durationSeconds.toInt()}s',
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                  if (session.segments.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Text(
                      '👥 ${session.segments.length} turns',
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanBottomSheetContent extends StatefulWidget {
  const _ScanBottomSheetContent();

  @override
  State<_ScanBottomSheetContent> createState() => _ScanBottomSheetContentState();
}

class _ScanBottomSheetContentState extends State<_ScanBottomSheetContent> {
  List<OmiDeviceInfo> _devices = [];
  StreamSubscription? _scanSub;
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  void _startScan() {
    _scanSub?.cancel();
    setState(() {
      _devices = [];
    });

    _scanSub = BleService.instance.scanDevicesStream().listen((results) {
      if (!mounted) return;
      setState(() {
        _devices = results;
      });
    });
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StreamBuilder<bool>(
      stream: BleService.instance.scanningStream,
      initialData: BleService.instance.isScanning,
      builder: (context, snapshot) {
        final isScanning = snapshot.data ?? false;

        return Container(
          padding: const EdgeInsets.all(20.0),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.65,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Discover Omi Devices',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  if (isScanning || _connecting)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                isScanning
                    ? 'Scanning for nearby BLE devices...'
                    : (_devices.isEmpty ? 'No devices found.' : 'Select your Omi device to connect.'),
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _devices.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.bluetooth_searching,
                              size: 40,
                              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              isScanning
                                  ? 'Listening for Bluetooth signals...'
                                  : 'No devices found. Ensure device is blinking red.',
                              style: const TextStyle(color: Colors.grey),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: _devices.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, idx) {
                          final dev = _devices[idx];
                          final isOmi = dev.name.toLowerCase().contains('omi') ||
                              dev.name.toLowerCase().contains('friend') ||
                              dev.name.toLowerCase().contains('devkit');

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isOmi
                                  ? theme.colorScheme.primaryContainer
                                  : theme.colorScheme.surfaceContainerHighest,
                              child: Icon(
                                Icons.bluetooth,
                                color: isOmi ? theme.colorScheme.primary : Colors.grey,
                              ),
                            ),
                            title: Text(
                              dev.name,
                              style: TextStyle(
                                fontWeight: isOmi ? FontWeight.bold : FontWeight.w500,
                              ),
                            ),
                            subtitle: Text('RSSI: ${dev.rssi} dBm'),
                            trailing: ElevatedButton(
                              onPressed: _connecting
                                  ? null
                                  : () async {
                                      setState(() => _connecting = true);
                                      final messenger = ScaffoldMessenger.of(context);
                                      final navigator = Navigator.of(context);
                                      final success = await BleService.instance.connect(dev);
                                      if (mounted) {
                                        navigator.pop();
                                        messenger.showSnackBar(
                                          SnackBar(
                                            content: Text(success
                                                ? 'Connected to ${dev.name}'
                                                : 'Failed to connect to ${dev.name}'),
                                          ),
                                        );
                                      }
                                    },
                              child: const Text('Connect'),
                            ),
                          );
                        },
                      ),
              ),
              if (!isScanning && !_connecting)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _startScan,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Scan Again'),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
