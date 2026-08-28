import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Ollama API Configuration
class OllamaConfig {
  static const String baseUrl = String.fromEnvironment(
    'OLLAMA_BASE_URL',
    defaultValue: 'https://ollama.com/api',
  );
  static const String apiKey = String.fromEnvironment(
    'OLLAMA_API_KEY',
    // Reminder: Be careful not to commit actual API keys to public repositories!
    defaultValue: 'f5484f2366244bc4be8700f77529270e.fAi3_8ME4CSdHXQrbUjwdBXI',
  );
  static const String model = String.fromEnvironment(
    'OLLAMA_MODEL',
    // Added the ':cloud' tag which is usually required for Ollama Cloud models
    defaultValue: 'kimi-k2.6:cloud',
  );
  static const String prompt =
      'You are an expert handwriting vision model that reads both English '
      'and Arabic handwriting. '
      'Read the following handwritten note, ignore crossed-out words, '
      'and fix spelling mistakes caused by bad handwriting. '
      'Preserve the original language exactly: '
      'if the note is in Arabic, output Arabic; '
      'if it is in English, output English; '
      'if it mixes both, output each part in its original language. '
      'Do not translate. Output only the clean, final text — '
      'no explanations, no quotes, no language tags.';
}

/// Builds the HTTP headers.
Map<String, String> get _ollamaHeaders => {
  'Content-Type': 'application/json',
  if (OllamaConfig.apiKey.isNotEmpty)
    'Authorization': 'Bearer ${OllamaConfig.apiKey}',
};

/// Builds the chat endpoint URL.
String get _chatUrl {
  final sanitized = OllamaConfig.baseUrl.replaceFirst(RegExp(r'/+$'), '');
  return sanitized.endsWith('/api') ? '$sanitized/chat' : '$sanitized/api/chat';
}

/// Sends the image to Ollama for OCR.
Future<String> recognizeText(String imagePath) async {
  final file = File(imagePath);
  if (!await file.exists()) {
    debugPrint('[OCR] Image file not found: $imagePath');
    return 'Error: Image file not found.';
  }

  final bytes = await file.readAsBytes();
  final base64Image = base64Encode(bytes);
  final url = _chatUrl;

  try {
    final response = await http
        .post(
          Uri.parse(url),
          headers: _ollamaHeaders,
          body: jsonEncode({
            'model': OllamaConfig.model,
            'messages': [
              {
                'role': 'user',
                'content': OllamaConfig.prompt,
                'images': [base64Image],
              },
            ],
            'stream': false,
            'options': {'temperature': 0.1},
          }),
        )
        // Increased timeout. Vision models can easily exceed 60s on complex images.
        .timeout(const Duration(seconds: 120));

    if (response.statusCode != 200) {
      // Log the actual response body to see the API's exact error message
      debugPrint('[OCR] HTTP Error ${response.statusCode}: ${response.body}');
      return 'API Error ${response.statusCode}: ${response.body}';
    }

    final data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final msg = data['message'] as Map<String, dynamic>?;
    final text = (msg?['content'] as String? ?? '').trim();

    if (text.isEmpty) {
      debugPrint(
        '[OCR] API returned a 200 OK, but the text content was empty.',
      );
    }

    return text;
  } catch (e) {
    // This will now catch and display TimeoutExceptions or SocketExceptions
    debugPrint('[OCR] Exception: $e');
    return 'Exception: $e';
  }
}
