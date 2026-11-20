/// The automatic output follows the operating system's default device.
const systemDefaultAudioDeviceId = 'auto';

class PlayerAudioDevice {
  const PlayerAudioDevice({required this.id, required this.name});

  final String id;
  final String name;
}

class PlayerAudioOutputState {
  const PlayerAudioOutputState({
    this.supported = false,
    this.devices = const [],
    this.selectedDeviceId = systemDefaultAudioDeviceId,
  });

  final bool supported;
  final List<PlayerAudioDevice> devices;

  /// The device configured for this player. This is a preference, rather than
  /// a guarantee about the hardware currently rendering audio.
  final String selectedDeviceId;
}

/// Optional capability for selecting this player's output without changing
/// the system output or other applications' audio.
abstract interface class PlayerAudioOutput {
  PlayerAudioOutputState get audioOutputState;
  Stream<PlayerAudioOutputState> get audioOutputStream;
  Future<void> selectAudioOutput(String deviceId);
}
