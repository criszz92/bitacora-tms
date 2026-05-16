import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Modelo simple para guardar el borrador del viaje
class TripDraft {
  final String client;
  final String origin;
  final String destination;
  final String container;
  final String value;
  final String mandante;
  final String cargoType;
  final bool isZiyu;
  final String? preAssignmentId;

  TripDraft({
    this.client = '',
    this.origin = '',
    this.destination = '',
    this.container = '',
    this.value = '',
    this.mandante = '',
    this.cargoType = 'completo',
    this.isZiyu = true,
    this.preAssignmentId,
  });

  Map<String, dynamic> toMap() => {
    'client': client,
    'origin': origin,
    'destination': destination,
    'container': container,
    'value': value,
    'mandante': mandante,
    'cargoType': cargoType,
    'isZiyu': isZiyu,
    'preAssignmentId': preAssignmentId,
  };

  factory TripDraft.fromMap(Map<String, dynamic> map) => TripDraft(
    client: map['client'] ?? '',
    origin: map['origin'] ?? '',
    destination: map['destination'] ?? '',
    container: map['container'] ?? '',
    value: map['value'] ?? '',
    mandante: map['mandante'] ?? '',
    cargoType: map['cargoType'] ?? 'completo',
    isZiyu: map['isZiyu'] ?? true,
    preAssignmentId: map['preAssignmentId'],
  );
}

/// Notifier que gestiona la persistencia local del borrador del viaje
class TripDraftNotifier extends Notifier<TripDraft> {
  static const _key = 'trip_draft';
  
  @override
  TripDraft build() {
    _loadFromPrefs();
    return TripDraft();
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_key);
    if (jsonStr != null) {
      state = TripDraft.fromMap(json.decode(jsonStr));
    }
  }

  Future<void> updateDraft(TripDraft draft) async {
    state = draft;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, json.encode(draft.toMap()));
  }

  Future<void> clearDraft() async {
    state = TripDraft();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

final tripDraftProvider = NotifierProvider<TripDraftNotifier, TripDraft>(() => TripDraftNotifier());
