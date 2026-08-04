import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  final db = FirebaseFirestore.instance;
  
  final vehiclesSnap = await db.collection('vehiculos').get();
  for (final doc in vehiclesSnap.docs) {
    final vehData = doc.data();
    final String patente = vehData['patente'];
    final String idEmpresa = vehData['idEmpresa'];
    
    final shiftSnap = await db.collection('jornadas')
      .where('idEmpresa', isEqualTo: idEmpresa)
      .where('patenteCamion', isEqualTo: patente)
      .orderBy('startTime', descending: true)
      .limit(1)
      .get();
      
    if (shiftSnap.docs.isNotEmpty) {
      final shiftData = shiftSnap.docs.first.data();
      final endOd = shiftData['endOdometer'];
      final startOd = shiftData['startOdometer'];
      
      num? finalOd;
      if (endOd != null) finalOd = endOd as num;
      else if (startOd != null) finalOd = startOd as num;
      
      if (finalOd != null) {
        await doc.reference.update({'currentOdometer': finalOd.toDouble()});
        print('Updated $patente to $finalOd');
      }
    }
  }
  print('Done syncing vehicles.');
}
