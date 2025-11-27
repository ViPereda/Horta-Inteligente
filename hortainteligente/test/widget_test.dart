import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// VERIFIQUE SE O NOME ABAIXO ESTÁ IGUAL AO 'name:' DO SEU pubspec.yaml
import 'package:horta_app/main.dart';

void main() {
  testWidgets('O App carrega a tela inicial', (WidgetTester tester) async {
    // Constrói o app e dispara um frame.
    await tester.pumpWidget(const MyApp());

    // Verifica se o título da AppBar aparece, provando que o app abriu.
    // Se você estiver usando a versão Mobile, mude 'Horta Web' para 'Monitoramento Horta'
    expect(find.text('Horta Web'), findsOneWidget);
  });
}
