/// M-01 · Cámara, vista previa y lectura OCR del recibo (RF-15 a RF-18,
/// RF-23, RF-29 a RF-31; CA-040 a CA-049, CA-064, CA-074 a CA-082,
/// CA-145).
///
/// Solo habla con M-04 ([CameraService] y [ReceiptService]), que a su vez
/// usa M-05; nunca con `lib/data/` (RNF-30). Regresa un [ScanOutcome] con
/// la foto ya comprimida (y, si se leyó, los datos del recibo), o `null`
/// si la persona registra a mano sin foto o sale.
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../modules/ocr/ocr_service.dart';
import '../../modules/receipts/camera_service.dart';
import '../../modules/receipts/receipt_service.dart';

enum _Phase {
  checking,
  denied,
  live,
  busy,
  preview,
  failed,
  reading,
  illegible,
  readFailed,
}

/// Lo que regresa [ScanScreen].
class ScanOutcome {
  const ScanOutcome({required this.photo, this.reading});

  /// Foto comprimida en `temp_recibos/`.
  final TempReceipt photo;

  /// Datos leídos por OCR; `null` si no se leyó (registro manual).
  final ParsedReceipt? reading;
}

/// Pantalla de captura de un recibo.
class ScanScreen extends StatefulWidget {
  const ScanScreen({
    super.key,
    required this.camera,
    required this.receipts,
    this.readReceipt = false,
  });

  final CameraService camera;
  final ReceiptService receipts;

  /// `true` para leer el recibo con OCR al tocar "Usar foto" (RF-23).
  final bool readReceipt;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with WidgetsBindingObserver {
  _Phase _phase = _Phase.checking;
  CameraPermissionState _permission = CameraPermissionState.denied;
  CameraHandle? _handle;
  TempReceipt? _capture;
  String? _error;
  String _busyText = 'Abriendo la cámara…';

  /// `true` cuando la foto se entregó: ya no se borra al salir.
  bool _delivered = false;

  /// Foto ya comprimida mientras se lee o si la lectura falló.
  TempReceipt? _photo;
  OcrRequest? _request;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final handle = _handle;
    if (handle != null) widget.camera.close(handle);
    _request?.cancel();
    if (!_delivered) {
      for (final temp in [_capture, _photo]) {
        if (temp != null) widget.receipts.discard(temp);
      }
    }
    super.dispose();
  }

  /// Al volver de los Ajustes del sistema se revisa otra vez el permiso.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _phase == _Phase.denied) {
      _start();
    }
  }

  /// Pide el permiso la primera vez (RF-15, CA-042) y abre la cámara.
  Future<void> _start() async {
    setState(() {
      _phase = _Phase.checking;
      _error = null;
    });
    final permission = await widget.camera.ensurePermission();
    if (!mounted) return;
    if (permission != CameraPermissionState.granted) {
      setState(() {
        _permission = permission;
        _phase = _Phase.denied;
      });
      return;
    }
    await _openCamera();
  }

  Future<void> _openCamera() async {
    _setBusy('Abriendo la cámara…');
    final result = await widget.camera.open();
    if (!mounted) {
      if (result.valueOrNull case final handle?) widget.camera.close(handle);
      return;
    }
    switch (result) {
      case Success(:final value):
        setState(() {
          _handle = value;
          _phase = _Phase.live;
        });
      case Failure(:final error):
        _showFailure(error);
    }
  }

  void _setBusy(String text) => setState(() {
        _busyText = text;
        _phase = _Phase.busy;
      });

  /// Permiso negado (RF-16) o fallo de la cámara (RF-17).
  void _showFailure(AppError error) => setState(() {
        _error = error.message;
        _phase = error.type == ErrorType.cameraPermission
            ? _Phase.denied
            : _Phase.failed;
      });

  /// Toma la foto, libera la cámara y muestra la vista previa (CA-040).
  Future<void> _takePhoto() async {
    final handle = _handle;
    if (handle == null || _phase != _Phase.live) return;
    _setBusy('Tomando la foto…');
    final shot = await widget.camera.capture(handle);
    if (!mounted) return;
    if (shot case Failure(:final error)) return _showFailure(error);
    final stored = await widget.receipts.storeCapture(shot.valueOrNull!);
    _handle = null;
    await widget.camera.close(handle);
    if (!mounted) return;
    switch (stored) {
      case Success(:final value):
        setState(() {
          _capture = value;
          _phase = _Phase.preview;
        });
      case Failure(:final error):
        _showFailure(error);
    }
  }

  /// "Repetir": borra la captura anterior y vuelve a abrir la cámara
  /// (CA-041).
  Future<void> _retake() async {
    final capture = _capture;
    _capture = null;
    if (capture != null) await widget.receipts.discard(capture);
    if (!mounted) return;
    await _openCamera();
  }

  /// "Usar foto": comprime a 1.5 MB o menos y regresa la foto (CA-043).
  Future<void> _usePhoto() async {
    final capture = _capture;
    if (capture == null) return;
    _setBusy('Preparando la foto…');
    final accepted = await widget.receipts.accept(capture);
    if (!mounted) return;
    _capture = null;
    switch (accepted) {
      case Success(:final value):
        _photo = value;
        if (widget.readReceipt && widget.receipts.canRead) {
          await _read();
        } else {
          _deliver();
        }
      case Failure(:final error):
        await widget.receipts.discard(capture);
        if (mounted) _showFailure(error);
    }
  }

  /// Lee el recibo con indicador de progreso y botón "Cancelar" (RF-23,
  /// CA-064). "Reintentar" vuelve a llamar aquí sin reiniciar la app
  /// (CA-146).
  Future<void> _read() async {
    final photo = _photo!;
    setState(() => _phase = _Phase.reading);
    final started = await widget.receipts.startReading(photo);
    if (!mounted) return;
    if (started case Failure(:final error)) return _showReadFailure(error);
    final request = started.valueOrNull!;
    _request = request;
    final outcome = await request.result;
    if (!mounted || !identical(_request, request)) return;
    _request = null;
    switch (outcome) {
      case OcrRead(:final receipt):
        _deliver(reading: receipt);
      case OcrIllegible():
        setState(() => _phase = _Phase.illegible);
      case OcrFailed(:final error):
        _showReadFailure(error);
      case OcrCancelled():
        break; // Ya se navegó al formulario en _cancelReading.
    }
  }

  void _showReadFailure(AppError error) => setState(() {
        _error = error.message;
        _phase = _Phase.readFailed;
      });

  /// "Cancelar": detiene la lectura y abre el registro manual con la foto;
  /// una respuesta que llegue después se ignora (RF-31, CA-080 a CA-082).
  void _cancelReading() {
    _request?.cancel();
    _request = null;
    _deliver();
  }

  /// "Repetir foto" tras una imagen ilegible: descarta la foto y vuelve a
  /// la cámara; al aceptar la nueva se vuelve a leer (CA-076).
  Future<void> _retakeAfterRead() async {
    final photo = _photo;
    _photo = null;
    if (photo != null) await widget.receipts.discard(photo);
    if (!mounted) return;
    await _openCamera();
  }

  /// Entrega la foto aceptada, con o sin datos leídos.
  void _deliver({ParsedReceipt? reading}) {
    final photo = _photo;
    if (photo == null || _delivered) return;
    _delivered = true;
    Navigator.of(context).pop(ScanOutcome(photo: photo, reading: reading));
  }

  /// "Registrar manualmente": si ya hay foto aceptada se conserva (CA-075,
  /// CA-077 a CA-079); si no, regresa sin foto y lo que ya se capturó en
  /// el formulario sigue ahí (CA-046, CA-049).
  void _manual() => _photo == null ? Navigator.of(context).pop() : _deliver();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear recibo')),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() => switch (_phase) {
        _Phase.checking => _progress('Revisando el permiso de la cámara…'),
        _Phase.busy => _progress(_busyText),
        _Phase.denied => _deniedView(),
        _Phase.failed => _failedView(),
        _Phase.live => _liveView(),
        _Phase.preview => _previewView(),
        _Phase.reading => _readingView(),
        _Phase.illegible => _illegibleView(),
        _Phase.readFailed => _readFailedView(),
      };

  Widget _readingView() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text('Leyendo el recibo…', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: _cancelReading,
              style: OutlinedButton.styleFrom(minimumSize: const Size(160, 48)),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      );

  /// Imagen ilegible (RF-29, CA-074 a CA-076).
  Widget _illegibleView() => ScanMessageView(
        icon: Icons.blur_on,
        title: 'No se pudo leer el recibo',
        text: OcrMessages.illegible,
        actions: [
          ScanAction('Repetir foto', _retakeAfterRead),
          ScanAction('Registrar manualmente', _manual, primary: false),
        ],
      );

  /// Sin internet, error del servicio o tiempo agotado (RF-30, CA-077 a
  /// CA-079, CA-145).
  Widget _readFailedView() => ScanMessageView(
        icon: Icons.cloud_off_outlined,
        title: 'No se pudo leer el recibo',
        text: _error ?? OcrMessages.server,
        actions: [
          ScanAction('Reintentar', _read),
          ScanAction('Registrar manualmente', _manual, primary: false),
        ],
      );

  Widget _progress(String text) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      );

  /// Explica para qué es la cámara y ofrece Ajustes o registro manual
  /// (RF-16, CA-044 a CA-046).
  Widget _deniedView() {
    final permanently =
        _permission == CameraPermissionState.permanentlyDenied ||
            _error != null;
    return ScanMessageView(
      icon: Icons.no_photography_outlined,
      title: 'Sin permiso para usar la cámara',
      text: CameraMessages.permissionDenied,
      actions: [
        if (permanently)
          ScanAction('Abrir Ajustes', widget.camera.openSettings)
        else
          ScanAction('Permitir cámara', _start),
        if (!permanently)
          ScanAction('Abrir Ajustes', widget.camera.openSettings),
        ScanAction('Registrar manualmente', _manual, primary: false),
      ],
    );
  }

  /// Cámara ocupada o con fallo (RF-17, CA-047 a CA-049).
  Widget _failedView() => ScanMessageView(
        icon: Icons.error_outline,
        title: 'No se pudo usar la cámara',
        text: _error ?? CameraMessages.cameraFailed,
        actions: [
          ScanAction('Reintentar', _openCamera),
          ScanAction('Registrar manualmente', _manual, primary: false),
        ],
      );

  Widget _liveView() {
    final handle = _handle;
    return Column(
      children: [
        Expanded(child: Center(child: handle?.buildPreview())),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _takePhoto,
            icon: const Icon(Icons.camera_alt),
            label: const Text('Tomar foto'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
          ),
        ),
      ],
    );
  }

  /// Vista previa con "Usar foto" y "Repetir" (RF-18, CA-040).
  Widget _previewView() {
    final capture = _capture!;
    return Column(
      children: [
        Expanded(
          child: Image.file(
            File(capture.path),
            fit: BoxFit.contain,
            semanticLabel: 'Vista previa del recibo',
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _retake,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text('Repetir'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _usePhoto,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text('Usar foto'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Una acción de [ScanMessageView].
class ScanAction {
  const ScanAction(this.label, this.onPressed, {this.primary = true});

  final String label;
  final VoidCallback onPressed;
  final bool primary;
}

/// Mensaje a pantalla completa con ícono, texto y botones grandes.
class ScanMessageView extends StatelessWidget {
  const ScanMessageView({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
    required this.actions,
  });

  final IconData icon;
  final String title;
  final String text;
  final List<ScanAction> actions;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(icon, size: 56),
        const SizedBox(height: 16),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(text, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        for (final action in actions) ...[
          _button(action),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _button(ScanAction action) {
    final style = ButtonStyle(
      minimumSize: WidgetStateProperty.all(const Size.fromHeight(48)),
    );
    return action.primary
        ? FilledButton(
            onPressed: action.onPressed,
            style: style,
            child: Text(action.label),
          )
        : OutlinedButton(
            onPressed: action.onPressed,
            style: style,
            child: Text(action.label),
          );
  }
}
