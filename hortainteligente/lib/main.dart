import 'dart:io';
import 'dart:async';
import 'dart:math'; // Para gerar dados falsos de histórico
import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // Para formatar datas
import 'package:fl_chart/fl_chart.dart'; // Para gráficos de histórico
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// CONFIGURAÇÕES MQTT
const String mqttBroker = 'broker.hivemq.com';
const String topicSolo = 'ifsp-grupo5/horta/umidade_solo';
const String topicLuz = 'ifsp-grupo5/horta/luminosidade';
const String uniqueId = 'App_Horta_Final_V2';

// VARIÁVEIS GLOBAIS DE ESTADO (Simulando um Banco de Dados Local)
// Limites de Alerta
double limiteUmidade = 60.0;
double limiteLuz = 30.0;

// Histórico de Mudanças nas Configurações
List<String> logMudancasUmidade = [];
List<String> logMudancasLuz = [];

// Dados simulados para os Gráficos de Histórico
List<FlSpot> historicoUmidade = [];
List<FlSpot> historicoLuz = [];
List<FlSpot> pontosDeAlerta = [];

// CONFIGURAÇÃO DE NOTIFICAÇÕES
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Horta Inteligente',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const DashboardPage(),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  double umidadeSolo = 0;
  double luminosidade = 0;
  String connectionStatus = 'Desconectado';
  MqttServerClient? client;
  DateTime lastNotificationTime =
      DateTime.now().subtract(const Duration(minutes: 10));

  @override
  void initState() {
    super.initState();
    setupMqtt();
    gerarHistoricoFalso();
    requestNotificationPermission();
  }

  void gerarHistoricoFalso() {
    // Cria um histórico fake para as últimas horas
    DateTime now = DateTime.now();
    Random random = Random();
    for (int i = 0; i < 20; i++) {
      // Fake Umidade
      double valUmidade = 40 + random.nextInt(40).toDouble();
      historicoUmidade.add(FlSpot(i.toDouble(), valUmidade));

      // Fake Luz [NOVO]
      double valLuz = random.nextInt(100).toDouble();
      historicoLuz.add(FlSpot(i.toDouble(), valLuz));

      if (valUmidade < 50) {
        pontosDeAlerta.add(FlSpot(i.toDouble(), valUmidade));
      }
    }
  }

  Future<void> requestNotificationPermission() async {
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  Future<void> showNotification(String titulo, String corpo) async {
    if (DateTime.now().difference(lastNotificationTime).inMinutes < 1) return;
    lastNotificationTime = DateTime.now();

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'horta_channel_id',
      'Alertas da Horta',
      channelDescription: 'Notificações críticas de irrigação',
      importance: Importance.max,
      priority: Priority.high,
      color: Colors.red,
    );

    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
        0, titulo, corpo, platformChannelSpecifics);
  }

  Future<void> setupMqtt() async {
    client = MqttServerClient(mqttBroker, uniqueId);
    client!.logging(on: false);
    client!.keepAlivePeriod = 20;

    try {
      setState(() => connectionStatus = 'Conectando...');
      await client!.connect();
    } catch (e) {
      setState(() => connectionStatus = 'Erro: $e');
      client!.disconnect();
    }

    if (client!.connectionStatus!.state == MqttConnectionState.connected) {
      setState(() => connectionStatus = 'Conectado (Ao Vivo)');
      client!.subscribe(topicSolo, MqttQos.atMostOnce);
      client!.subscribe(topicLuz, MqttQos.atMostOnce);

      client!.updates!.listen((List<MqttReceivedMessage<MqttMessage?>> c) {
        final MqttPublishMessage recMess = c[0].payload as MqttPublishMessage;
        final String pt =
            MqttPublishPayload.bytesToStringAsString(recMess.payload.message);

        if (mounted) {
          setState(() {
            if (c[0].topic == topicSolo) {
              umidadeSolo = double.tryParse(pt) ?? 0;
              // Atualiza gráfico Umidade
              if (historicoUmidade.length > 20) historicoUmidade.removeAt(0);
              historicoUmidade
                  .add(FlSpot(historicoUmidade.length.toDouble(), umidadeSolo));

              checkAlert();
            } else if (c[0].topic == topicLuz) {
              luminosidade = double.tryParse(pt) ?? 0;
              // Atualiza gráfico Luz
              if (historicoLuz.length > 20) historicoLuz.removeAt(0);
              historicoLuz
                  .add(FlSpot(historicoLuz.length.toDouble(), luminosidade));
            }
          });
        }
      });
    }
  }

  void checkAlert() {
    if (umidadeSolo < limiteUmidade) {
      showNotification("ALERTA CRÍTICO!",
          "Umidade em ${umidadeSolo.toStringAsFixed(1)}%. Regue agora!");
      pontosDeAlerta
          .add(FlSpot((historicoUmidade.length - 1).toDouble(), umidadeSolo));
    }
  }

  void abrirConfiguracoes(String tipo) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ConfigPage(tipo: tipo)),
    );
    setState(() {});
  }

  void abrirHistorico() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const HistoricoPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Horta Inteligente'),
        backgroundColor: Colors.green.shade100,
        actions: [
          IconButton(onPressed: setupMqtt, icon: const Icon(Icons.refresh))
        ],
      ),
      backgroundColor: Colors.grey[100],
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Text('MQTT: $connectionStatus',
                  style: TextStyle(
                      color: connectionStatus.contains('Conectado')
                          ? Colors.green
                          : Colors.red,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              _buildSensorCard(
                  "Umidade do Solo",
                  umidadeSolo,
                  Colors.blue,
                  Icons.water_drop,
                  "Limite Alerta: < ${limiteUmidade.toInt()}%",
                  "umidade"),
              const SizedBox(height: 15),
              _buildSensorCard(
                  "Luminosidade",
                  luminosidade,
                  Colors.orange,
                  Icons.wb_sunny,
                  "Limite Alerta: < ${limiteLuz.toInt()}%",
                  "luz"),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: abrirHistorico,
                  icon: const Icon(Icons.show_chart),
                  label: const Text("VER HISTÓRICO E ALERTAS",
                      style: TextStyle(fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSensorCard(String title, double value, Color color,
      IconData icon, String subtitle, String tipoConfig) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(icon, color: color, size: 28),
                    const SizedBox(width: 10),
                    Text(title,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.settings, color: Colors.grey),
                  onPressed: () => abrirConfiguracoes(tipoConfig),
                )
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 180,
              child: SfRadialGauge(
                axes: <RadialAxis>[
                  RadialAxis(
                    minimum: 0,
                    maximum: 100,
                    ranges: <GaugeRange>[
                      GaugeRange(
                          startValue: 0,
                          endValue: tipoConfig == 'umidade'
                              ? limiteUmidade
                              : limiteLuz,
                          color: Colors.red),
                      GaugeRange(
                          startValue: tipoConfig == 'umidade'
                              ? limiteUmidade
                              : limiteLuz,
                          endValue: 100,
                          color: Colors.green),
                    ],
                    pointers: <GaugePointer>[
                      NeedlePointer(value: value, enableAnimation: true),
                    ],
                    annotations: <GaugeAnnotation>[
                      GaugeAnnotation(
                        widget: Text('${value.toStringAsFixed(0)}%',
                            style: const TextStyle(
                                fontSize: 25, fontWeight: FontWeight.bold)),
                        angle: 90,
                        positionFactor: 0.5,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Text(subtitle,
                style: TextStyle(
                    color: Colors.grey[700], fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

// TELA DE CONFIGURAÇÕES
class ConfigPage extends StatefulWidget {
  final String tipo;
  const ConfigPage({super.key, required this.tipo});

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage> {
  double _currentValue = 0;
  List<String> _historico = [];
  String titulo = "";

  @override
  void initState() {
    super.initState();
    if (widget.tipo == 'umidade') {
      _currentValue = limiteUmidade;
      _historico = logMudancasUmidade;
      titulo = "Configurar Umidade";
    } else {
      _currentValue = limiteLuz;
      _historico = logMudancasLuz;
      titulo = "Configurar Luz";
    }
  }

  void _salvar() {
    setState(() {
      String data = DateFormat('dd/MM HH:mm').format(DateTime.now());
      String log =
          "Alterado de ${widget.tipo == 'umidade' ? limiteUmidade.toInt() : limiteLuz.toInt()}% para ${_currentValue.toInt()}% em $data";

      if (widget.tipo == 'umidade') {
        limiteUmidade = _currentValue;
        logMudancasUmidade.insert(0, log);
      } else {
        limiteLuz = _currentValue;
        logMudancasLuz.insert(0, log);
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Configuração Salva!")),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(titulo)),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Definir Limite Mínimo de Alerta:",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Row(
              children: [
                Text("${_currentValue.toInt()}%",
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue)),
                Expanded(
                  child: Slider(
                    value: _currentValue,
                    min: 0,
                    max: 100,
                    divisions: 100,
                    label: _currentValue.round().toString(),
                    onChanged: (double value) {
                      setState(() {
                        _currentValue = value;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                  onPressed: _salvar, child: const Text("SALVAR NOVO LIMITE")),
            ),
            const Divider(height: 40),
            const Text("Histórico de Mudanças:",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Expanded(
              child: _historico.isEmpty
                  ? const Center(child: Text("Nenhuma alteração feita ainda."))
                  : ListView.builder(
                      itemCount: _historico.length,
                      itemBuilder: (context, index) {
                        return ListTile(
                          leading:
                              const Icon(Icons.history, color: Colors.grey),
                          title: Text(_historico[index]),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// TELA DE GRÁFICOS E HISTÓRICO
class HistoricoPage extends StatefulWidget {
  const HistoricoPage({super.key});

  @override
  State<HistoricoPage> createState() => _HistoricoPageState();
}

class _HistoricoPageState extends State<HistoricoPage> {
  String periodo = "24h";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Histórico Completo")),
      body: SingleChildScrollView(
        // Scroll para caber os dois gráficos
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Filtros
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildFilterBtn("1h"),
                  const SizedBox(width: 10),
                  _buildFilterBtn("24h"),
                  const SizedBox(width: 10),
                  _buildFilterBtn("7 Dias"),
                ],
              ),
              const SizedBox(height: 20),

              // GRÁFICO 1:
              const Text("Umidade do Solo (%)",
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue)),
              const SizedBox(height: 10),

              Container(
                height: 250,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(blurRadius: 5, color: Colors.black12)
                    ]),
                child: LineChart(
                  LineChartData(
                    minY: 0,
                    maxY: 100,
                    gridData: const FlGridData(show: true),
                    titlesData: const FlTitlesData(
                      rightTitles:
                          AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles:
                          AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: historicoUmidade,
                        isCurved: true,
                        color: Colors.blue,
                        barWidth: 3,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                            show: true, color: Colors.blue.withOpacity(0.2)),
                      ),
                      LineChartBarData(
                        spots: pontosDeAlerta,
                        color: Colors.red,
                        barWidth: 0,
                        dotData: FlDotData(
                          show: true,
                          getDotPainter: (spot, percent, barData, index) =>
                              FlDotCirclePainter(
                                  radius: 6, color: Colors.red, strokeWidth: 0),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 30),

              //GRÁFICO 2:
              const Text("Luminosidade (%)",
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange)),
              const SizedBox(height: 10),

              Container(
                height: 250,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(blurRadius: 5, color: Colors.black12)
                    ]),
                child: LineChart(
                  LineChartData(
                    minY: 0,
                    maxY: 100,
                    gridData: const FlGridData(show: true),
                    titlesData: const FlTitlesData(
                      rightTitles:
                          AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles:
                          AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: historicoLuz,
                        isCurved: true,
                        color: Colors.orange,
                        barWidth: 3,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                            show: true, color: Colors.orange.withOpacity(0.2)),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterBtn(String label) {
    bool isSelected = periodo == label;
    return ElevatedButton(
      onPressed: () => setState(() => periodo = label),
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? Colors.green : Colors.grey[300],
        foregroundColor: isSelected ? Colors.white : Colors.black,
      ),
      child: Text(label),
    );
  }
}
