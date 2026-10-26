import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/field_data_repository.dart';
import '../models/field_observation.dart';
import '../models/irrigation_prediction.dart';
import '../models/soil_sensor_reading.dart';
import '../services/irrigation_prediction_service.dart';
import '../services/field_control_service.dart';

enum LoadStatus { loading, ready, empty, error }

class FieldController extends ChangeNotifier {
  FieldController({
    required this.repository,
    required this.predictionService,
    this.fieldControl,
  });

  final FieldDataRepository repository;
  final IrrigationPredictionService predictionService;

  /// Null when the data source can't take commands (sample or CSV data).
  final FieldControl? fieldControl;

  /// True from pressing "Stop watering" until a reading shows the pump off.
  bool stopRequested = false;

  /// The pump card (with its off button) shows whenever commands can be sent,
  /// even if the last reading says the pump is off.
  bool get canControlPump => fieldControl != null;

  bool get pumpOn => latest?.pumpOn == true;

  /// True from pressing "Turn pump on" until a reading shows the pump on.
  bool startRequested = false;

  /// Set when the pump did not start within [startTimeout] of a request.
  bool startNotConfirmed = false;

  static const startTimeout = Duration(seconds: 30);
  Timer? _startTimer;

  /// The ESP32 sends a live reading every 2 seconds. With none for this
  /// long, it is treated as offline (unpowered, no Wi-Fi, or old firmware).
  static const offlineAfter = Duration(seconds: 30);

  bool get controllerOnline {
    final l = latest;
    return l != null && DateTime.now().difference(l.timestamp) < offlineAfter;
  }

  /// Re-checks [controllerOnline] even when no new reading arrives.
  Timer? _clock;
  bool _wasOnline = false;

  /// Soil sensor 1 is on the main ESP32; 2 and 3 are separate node boards.
  static const soilSensorCount = 3;

  /// Newest reading from each soil sensor, by sensor number.
  final Map<int, SoilSensorReading> _sensors = {};

  /// Only a live source (Firebase) has per-sensor readings.
  bool get hasSoilSensors => repository is LiveFieldRepository;

  /// Each sensor for the Soil moisture card. A sensor with no new reading
  /// for [offlineAfter] is offline (board unpowered or no Wi-Fi).
  List<SoilSensorStatus> get soilSensors => [
        for (var n = 1; n <= soilSensorCount; n++) _sensorStatus(n),
      ];

  SoilSensorStatus _sensorStatus(int n) {
    final r = _sensors[n];
    final online = r != null && DateTime.now().difference(r.timestamp) < offlineAfter;
    return SoilSensorStatus(
      number: n,
      online: online,
      moisturePct: online ? r.moisturePct : null,
    );
  }

  String _sensorsOnlineKey() => soilSensors.map((s) => s.online ? '1' : '0').join();
  String _lastSensorsKey = '';

  bool get canSetGrowthStage => fieldControl != null;

  Future<void> setGrowthStage(String stage) async {
    await fieldControl?.setGrowthStage(stage);
    await load(quiet: true);
  }

  Future<void> stopWatering() async {
    final control = fieldControl;
    if (control == null) return;
    stopRequested = true;
    notifyListeners();
    try {
      await control.requestStop();
    } catch (_) {
      stopRequested = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> startWatering() async {
    final control = fieldControl;
    if (control == null) return;
    startRequested = true;
    startNotConfirmed = false;
    notifyListeners();
    try {
      await control.requestStart();
    } catch (_) {
      startRequested = false;
      notifyListeners();
      rethrow;
    }
    _startTimer?.cancel();
    _startTimer = Timer(startTimeout, () {
      if (!startRequested) return;
      startRequested = false;
      startNotConfirmed = true;
      notifyListeners();
      unawaited(control.cancelStart().catchError((_) {}));
    });
  }

  /// Readings older than this are labeled "Historical", not "Current".
  static const staleAfter = Duration(hours: 3);

  LoadStatus status = LoadStatus.loading;
  String? errorMessage;
  List<FieldObservation> history = const [];
  IrrigationPrediction? prediction;

  /// Newest reading from irrigation/live, shown as soon as it arrives.
  FieldObservation? _live;

  /// The full history (for charts) is re-read at most this often.
  static const historyRefresh = Duration(minutes: 1);
  DateTime _lastFullLoad = DateTime.fromMillisecondsSinceEpoch(0);

  FieldObservation? get latest {
    final saved = history.isEmpty ? null : history.last;
    final live = _live;
    if (live == null) return saved;
    if (saved == null || live.timestamp.isAfter(saved.timestamp)) return live;
    return saved;
  }

  bool get isLatestStale {
    final l = latest;
    if (l == null) return false;
    return DateTime.now().difference(l.timestamp) > staleAfter;
  }

  StreamSubscription<void>? _changes;
  StreamSubscription<FieldObservation>? _liveSub;
  StreamSubscription<SoilSensorReading>? _sensorSub;

  /// Updates the screen with every live reading, and reloads quietly when
  /// other data (prediction, growth stage) changes.
  void startListening() {
    final repo = repository;
    if (repo is! LiveFieldRepository || _changes != null) return;
    _changes = repo.changes.listen((_) => load(quiet: true));
    _liveSub = repo.liveReadings.listen(_onLive);
    _sensorSub = repo.soilSensorReadings.listen((r) {
      _sensors[r.number] = r;
      _lastSensorsKey = _sensorsOnlineKey();
      if (status == LoadStatus.ready) notifyListeners();
    });
    _clock = Timer.periodic(const Duration(seconds: 5), (_) {
      final online = controllerOnline;
      final sensorsKey = _sensorsOnlineKey();
      if (online != _wasOnline || sensorsKey != _lastSensorsKey) {
        _wasOnline = online;
        _lastSensorsKey = sensorsKey;
        notifyListeners();
      }
    });
  }

  void _onLive(FieldObservation reading) {
    _live = reading;
    _syncPumpFlags();
    if (status == LoadStatus.ready) notifyListeners();
    if (status != LoadStatus.loading &&
        DateTime.now().difference(_lastFullLoad) >= historyRefresh) {
      load(quiet: true);
    }
  }

  /// Clears "Turning on…" / "Turning off…" once the pump state matches.
  void _syncPumpFlags() {
    if (!pumpOn) stopRequested = false;
    if (pumpOn) {
      startRequested = false;
      startNotConfirmed = false;
      _startTimer?.cancel();
    }
  }

  @override
  void dispose() {
    _changes?.cancel();
    _liveSub?.cancel();
    _sensorSub?.cancel();
    _clock?.cancel();
    _startTimer?.cancel();
    super.dispose();
  }

  /// [quiet] keeps the current screen up instead of showing the spinner.
  Future<void> load({bool quiet = false}) async {
    if (!quiet || status != LoadStatus.ready) {
      status = LoadStatus.loading;
      errorMessage = null;
      notifyListeners();
    }

    _lastFullLoad = DateTime.now();
    try {
      final observations = await repository.loadObservations();
      history = observations;
      _syncPumpFlags();
      if (observations.isEmpty) {
        prediction = null;
        status = LoadStatus.empty;
      } else {
        prediction = await predictionService.predict(observations.last);
        status = LoadStatus.ready;
      }
    } on DatasetNotFoundException {
      history = const [];
      prediction = null;
      status = LoadStatus.empty;
    } on FormatException catch (e) {
      status = LoadStatus.error;
      errorMessage = 'The field data file has a problem: ${e.message}';
    } catch (_) {
      status = LoadStatus.error;
      errorMessage = 'Field data could not be loaded. Try again in a moment.';
    }
    notifyListeners();
  }
}

class FieldScope extends InheritedNotifier<FieldController> {
  const FieldScope({
    super.key,
    required FieldController controller,
    required super.child,
  }) : super(notifier: controller);

  static FieldController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FieldScope>()!.notifier!;
}
