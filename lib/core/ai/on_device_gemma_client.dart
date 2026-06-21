import 'dart:convert';
import 'dart:io';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';

import 'llm_client.dart';
import 'on_device_models.dart';

/// Download/lifecycle helpers for on-device Gemma models, wrapping
/// flutter_gemma's modern API. Initialization is lazy: nothing touches the
/// native plugin until the user actually uses an on-device model, so users who
/// stick to cloud providers pay no startup cost.
class OnDeviceGemma {
  OnDeviceGemma._();

  static bool _initialized = false;

  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    await FlutterGemma.initialize();
    _initialized = true;
  }

  static Future<bool> isInstalled(String modelId) async {
    await ensureInitialized();
    return FlutterGemma.isModelInstalled(modelId);
  }

  static Future<List<String>> installed() async {
    await ensureInitialized();
    return FlutterGemma.listInstalledModels();
  }

  /// Downloads [model] (with an optional Hugging Face [token] for gated models),
  /// reporting progress 0–100. Idempotent: an already-installed model just gets
  /// re-activated. Pass a [cancelToken] to allow aborting.
  static Future<void> download(
    OnDeviceModel model, {
    String? token,
    required void Function(int percent) onProgress,
    CancelToken? cancelToken,
  }) async {
    await ensureInitialized();
    final tok = (token == null || token.trim().isEmpty) ? null : token.trim();
    // foreground: true keeps a multi-GB download alive through backgrounding/doze.
    // install() is idempotent and resumes from the partial (flutter_gemma keys the
    // download by a deterministic taskId), so re-calling this continues, not restarts.
    var builder = FlutterGemma.installModel(modelType: model.modelType, fileType: model.fileType)
        .fromNetwork(model.url, token: tok, foreground: true)
        .withProgress(onProgress);
    if (cancelToken != null) builder = builder.withCancelToken(cancelToken);
    await builder.install();
  }

  static Future<void> remove(String modelId) async {
    await ensureInitialized();
    await FlutterGemma.uninstallModel(modelId);
  }

  /// Path where a sideloaded model file is expected — the app's external files
  /// dir, e.g. `/sdcard/Android/data/<pkg>/files/<modelId>`. Reliable mobile
  /// downloads are fragile, so the file can instead be `adb push`ed here (or
  /// copied by the user) and imported without any in-app download.
  static Future<String?> localModelPath(String modelId) async {
    final dir = await getExternalStorageDirectory();
    return dir == null ? null : '${dir.path}/$modelId';
  }

  static Future<bool> hasLocalFile(String modelId) async {
    final path = await localModelPath(modelId);
    return path != null && File(path).existsSync();
  }

  /// Registers a sideloaded model from its file. flutter_gemma references the
  /// file in place (no re-download, no extra copy), then sets it active.
  static Future<void> importFromFile(OnDeviceModel model) async {
    await ensureInitialized();
    final path = await localModelPath(model.id);
    if (path == null || !File(path).existsSync()) {
      throw AiException('No se encontró el archivo del modelo en el dispositivo.');
    }
    await FlutterGemma.installModel(modelType: model.modelType, fileType: model.fileType)
        .fromFile(path)
        .install();
  }
}

/// [LlmClient] backed by a Gemma model running on the device via MediaPipe.
///
/// Gemma has no native forced-tool-use, so structured output is obtained by
/// prompting the model for a bare JSON object and parsing it loosely. The
/// loaded model is cached across calls because loading weights is expensive.
class OnDeviceGemmaClient implements LlmClient {
  OnDeviceGemmaClient({required this.modelId, this.maxTokens = 1024});

  final String modelId;
  final int maxTokens;

  @override
  String get defaultModel => modelId;

  @override
  String get label => 'Gemma on-device';

  static InferenceModel? _model;
  static String? _loadedId;

  Future<InferenceModel> _ensureModel() async {
    await OnDeviceGemma.ensureInitialized();
    if (!await FlutterGemma.isModelInstalled(modelId)) {
      throw AiException('El modelo on-device no está descargado. Ve a Ajustes → IA y descárgalo.');
    }
    if (_model != null && _loadedId == modelId) return _model!;

    await _model?.close();
    _model = null;
    _loadedId = null;

    // Re-activate the installed spec (needed after an app restart). install() is
    // idempotent — it skips the download/registration and just sets the active
    // model. Crucially, re-activate from the SAME source the model was installed
    // with: a sideloaded file (fromFile) must not be re-pointed at the network,
    // or its active spec would reference a file that isn't there.
    final spec = onDeviceModelById(modelId);
    if (spec != null) {
      final builder = FlutterGemma.installModel(modelType: spec.modelType, fileType: spec.fileType);
      final localPath = await OnDeviceGemma.localModelPath(modelId);
      if (localPath != null && File(localPath).existsSync()) {
        await builder.fromFile(localPath).install();
      } else {
        await builder.fromNetwork(spec.url).install();
      }
    }

    final model = await FlutterGemma.getActiveModel(maxTokens: maxTokens);
    _model = model;
    _loadedId = modelId;
    return model;
  }

  Future<String> _run(String prompt) async {
    final model = await _ensureModel();
    final session = await model.createSession();
    try {
      await session.addQueryChunk(Message.text(text: prompt, isUser: true));
      return await session.getResponse();
    } finally {
      await session.close();
    }
  }

  @override
  Future<Map<String, dynamic>> extractStructured({
    required String system,
    required String userText,
    required String toolName,
    required String toolDescription,
    required Map<String, dynamic> inputSchema,
    List<AiImage> images = const [],
    String? model,
    int maxTokens = 1024,
  }) async {
    if (images.isNotEmpty) {
      throw AiException(
        'El modelo on-device aún no procesa imágenes en Nexo. Para escanear recibos usa un proveedor con visión.',
      );
    }
    final prompt = '$system\n\n'
        'Tarea: $toolDescription\n'
        'Responde ÚNICAMENTE con un objeto JSON válido que cumpla este JSON Schema. '
        'Sin texto adicional, sin explicaciones, sin markdown ni comillas de código:\n'
        '${jsonEncode(inputSchema)}\n\n'
        'Entrada del usuario:\n$userText';
    final raw = await _run(prompt);
    final parsed = parseJsonObjectLoose(raw);
    if (parsed == null) {
      throw AiException('El modelo on-device no devolvió un JSON válido. Prueba un modelo más grande.');
    }
    return parsed;
  }

  @override
  Future<String> complete({
    required String system,
    required String userText,
    String? model,
    int maxTokens = 1024,
  }) async {
    final text = (await _run('$system\n\n$userText')).trim();
    if (text.isEmpty) throw AiException('Respuesta vacía del modelo on-device.');
    return text;
  }
}
