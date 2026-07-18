// core/player_exceptions.dart

import 'package:flutter/services.dart';

/// Player exception base class
class PlayerException implements Exception {
  final String message;
  final String? code;
  final String? details; // Added details field
  final DateTime timestamp;
  final StackTrace? stackTrace;

  PlayerException(
    this.message, {
    this.code,
    this.details, // Added details field
    DateTime? timestamp,
    this.stackTrace,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() {
    var result = 'PlayerException';
    if (code != null) {
      result += ' [$code]';
    }
    result += ': $message';
    if (details != null) {
      result += '\nDetails: $details';
    }
    if (stackTrace != null) {
      result += '\n$stackTrace';
    }
    return result;
  }
}

/// Network exception
class NetworkException extends PlayerException {
  final Uri? url;
  final int? statusCode;
  final String? method;
  final Duration? timeout;

  NetworkException(
    super.message, {
    this.url,
    this.statusCode,
    this.method,
    this.timeout,
    String? code,
    super.timestamp,
    super.stackTrace,
  }) : super(code: code ?? 'NETWORK_ERROR');

  factory NetworkException.fromHttpError({
    required int statusCode,
    required String method,
    required Uri url,
    String? responseBody,
  }) {
    String message;
    String code;

    switch (statusCode) {
      case 400:
        code = 'BAD_REQUEST';
        message = 'Bad request to $url';
        break;
      case 401:
        code = 'UNAUTHORIZED';
        message = 'Unauthorized access to $url';
        break;
      case 403:
        code = 'FORBIDDEN';
        message = 'Access forbidden to $url';
        break;
      case 404:
        code = 'NOT_FOUND';
        message = 'Resource not found at $url';
        break;
      case 408:
        code = 'TIMEOUT';
        message = 'Request timeout for $url';
        break;
      case 429:
        code = 'RATE_LIMIT';
        message = 'Rate limit exceeded for $url';
        break;
      case 500:
        code = 'SERVER_ERROR';
        message = 'Server error from $url';
        break;
      case 502:
        code = 'BAD_GATEWAY';
        message = 'Bad gateway for $url';
        break;
      case 503:
        code = 'SERVICE_UNAVAILABLE';
        message = 'Service unavailable at $url';
        break;
      case 504:
        code = 'GATEWAY_TIMEOUT';
        message = 'Gateway timeout for $url';
        break;
      default:
        code = 'HTTP_ERROR';
        message = 'HTTP error $statusCode for $url';
    }

    return NetworkException(
      message,
      url: url,
      statusCode: statusCode,
      method: method,
      code: code,
    );
  }

  @override
  String toString() {
    var result = 'NetworkException [$code]: $message';
    if (statusCode != null) {
      result += ' (Status: $statusCode)';
    }
    if (timeout != null) {
      result += ' after ${timeout!.inSeconds}s';
    }
    return result;
  }
}

class ExceptionHandler {
  static PlayerException convertToPlayerException(
    Object e, {
    String? context,
    StackTrace? stackTrace,
  }) {
    if (e is PlayerException) return e;

    String message = 'Unexpected error${context != null ? ' in $context' : ''}';
    String? details;
    String code = 'UNEXPECTED_ERROR';

    if (e is PlatformException) {
      message = e.message ?? message;
      details = 'Platform Error [${e.code}]: ${e.details}';
      code = 'PLATFORM_ERROR';
    } else {
      String str = e.toString();
      // If it looks like a stringified PlatformException, try to extract the message
      if (str.startsWith('PlatformException(')) {
        // PlatformException(code, message, details, [stacktrace])
        final match = RegExp(
          r"PlatformException\(([^,]*),\s*([^,]*),\s*([^,)]*)",
        ).firstMatch(str);
        if (match != null) {
          final pCode = match.group(1)?.trim();
          final pMessage = match.group(2)?.trim();
          final pDetails = match.group(3)?.trim();

          message =
              (pMessage != null && pMessage != 'null' && pMessage.isNotEmpty)
              ? pMessage
              : message;
          details =
              'Platform Error [$pCode]${(pDetails != null && pDetails != 'null') ? ': $pDetails' : ''}';
          code = 'PLATFORM_ERROR';
        } else {
          message = str;
        }
      } else {
        message = str.startsWith('Unexpected error') ? str : '$message: $str';
      }
    }

    return PlayerException(
      message,
      code: code,
      details: details,
      stackTrace: stackTrace,
    );
  }
}
