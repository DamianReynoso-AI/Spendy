/// M-04 · Permiso de cámara, captura y manejo de fallos de la cámara
/// (RF-15 a RF-17; RNF-20; CA-042, CA-044 a CA-049).
///
/// La interfaz (M-01) solo habla con [CameraService]. Los plugins de
/// Flutter quedan detrás de [CameraDevice], así las pruebas usan una
/// cámara simulada.
library;

import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/error_logger.dart';
import '../../core/result.dart';

/// Estado del permiso de cámara.
enum CameraPermissionState {
  granted,

  /// Negado, pero el sistema todavía puede volver a preguntar.
  denied,

  /// Negado "para siempre" o restringido: solo se puede activar desde los
  /// Ajustes del sistema (CA-045).
  permanentlyDenied,
}

/// La cámara negó el acceso al abrirse (el permiso se quitó desde Ajustes
/// con la app abierta, por ejemplo).
class CameraPermissionException implements Exception {
  const CameraPermissionException();
}

/// No hay cámara en el dispositivo.
class CameraUnavailableException implements Exception {
  const CameraUnavailableException();
}

/// Una cámara abierta y lista para tomar fotos.
abstract interface class CameraHandle {
  /// Vista en vivo de la cámara.
  Widget buildPreview();

  /// Toma una foto y devuelve la ruta del archivo que creó el sistema.
  Future<String> takePicture();

  Future<void> dispose();
}

/// Acceso al hardware y a los permisos. [PluginCameraDevice] es la
/// implementación real; las pruebas usan una simulada.
abstract interface class CameraDevice {
  Future<CameraPermissionState> requestPermission();
  Future<bool> openSettings();
  Future<CameraHandle> open();
}

/// Mensajes de la cámara: no técnicos, con causa y acción (RNF-05).
class CameraMessages {
  CameraMessages._();

  static const String permissionDenied =
      'SPENDY necesita la cámara solo para tomar la foto de tus recibos. '
      'La foto se guarda únicamente en tu teléfono. Puedes darle permiso en '
      'los Ajustes del sistema o registrar el movimiento a mano.';
  static const String cameraFailed =
      'No se pudo usar la cámara. Puede que otra app la esté usando. Toca '
      '"Reintentar" o registra el movimiento a mano; lo que ya capturaste '
      'se conserva.';
}

/// Lógica de permisos y captura.
class CameraService {
  CameraService(this._device, this._logger);

  static const String module = 'M-04';

  final CameraDevice _device;
  final ErrorLogger _logger;

  static const AppError _permissionError = AppError(
    type: ErrorType.cameraPermission,
    message: CameraMessages.permissionDenied,
  );

  /// Pide el permiso; la primera vez el sistema muestra su diálogo
  /// (RF-15, CA-042). Si ya estaba concedido, regresa de inmediato.
  Future<CameraPermissionState> ensurePermission() async {
    try {
      return await _device.requestPermission();
    } on Object catch (e) {
      await _logFailure(e);
      return CameraPermissionState.denied;
    }
  }

  /// Abre los Ajustes del sistema de la app (CA-045).
  Future<bool> openSettings() async {
    try {
      return await _device.openSettings();
    } on Object catch (e) {
      await _logFailure(e);
      return false;
    }
  }

  /// Abre la cámara. Distingue permiso negado (RF-16) de cámara ocupada o
  /// con fallo (RF-17); solo el fallo técnico va a la bitácora, con el
  /// nombre de la excepción y sin imágenes ni datos (RNF-20).
  Future<Result<CameraHandle>> open() async {
    try {
      return Success(await _device.open());
    } on Object catch (e) {
      return Failure(await _translate(e));
    }
  }

  /// Toma la foto y devuelve la ruta temporal que dejó la cámara.
  Future<Result<String>> capture(CameraHandle handle) async {
    try {
      return Success(await handle.takePicture());
    } on Object catch (e) {
      return Failure(await _translate(e));
    }
  }

  /// Libera la cámara; un fallo al cerrarla solo se registra.
  Future<void> close(CameraHandle handle) async {
    try {
      await handle.dispose();
    } on Object catch (e) {
      await _logFailure(e);
    }
  }

  Future<AppError> _translate(Object e) async {
    if (e is CameraPermissionException) return _permissionError;
    await _logFailure(e);
    return const AppError(
      type: ErrorType.camera,
      message: CameraMessages.cameraFailed,
    );
  }

  Future<void> _logFailure(Object e) =>
      _logger.log(type: ErrorType.camera, module: module, cause: e);
}

/// Implementación con los plugins `camera` y `permission_handler`.
class PluginCameraDevice implements CameraDevice {
  const PluginCameraDevice();

  static const Set<String> _permissionCodes = {
    'CameraAccessDenied',
    'CameraAccessDeniedWithoutPrompt',
    'CameraAccessRestricted',
  };

  @override
  Future<CameraPermissionState> requestPermission() async =>
      mapPermissionStatus(await Permission.camera.request());

  @override
  Future<bool> openSettings() => openAppSettings();

  @override
  Future<CameraHandle> open() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) throw const CameraUnavailableException();
    final back = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    final controller = CameraController(
      back,
      ResolutionPreset.veryHigh,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    try {
      await controller.initialize();
    } on CameraException catch (e) {
      await controller.dispose();
      if (_permissionCodes.contains(e.code)) {
        throw const CameraPermissionException();
      }
      rethrow;
    }
    return _PluginCameraHandle(controller);
  }
}

/// Convierte el estado del plugin al de SPENDY.
CameraPermissionState mapPermissionStatus(PermissionStatus status) {
  if (status.isGranted || status.isLimited) {
    return CameraPermissionState.granted;
  }
  if (status.isPermanentlyDenied || status.isRestricted) {
    return CameraPermissionState.permanentlyDenied;
  }
  return CameraPermissionState.denied;
}

class _PluginCameraHandle implements CameraHandle {
  _PluginCameraHandle(this._controller);

  final CameraController _controller;

  @override
  Widget buildPreview() => CameraPreview(_controller);

  @override
  Future<String> takePicture() async => (await _controller.takePicture()).path;

  @override
  Future<void> dispose() => _controller.dispose();
}
