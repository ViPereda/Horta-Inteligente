import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// CONFIGURAÇÕES MQTT
const String mqttBroker = 'broker.hivemq.com';
const String topicSolo = 'ifsp-grupo5/horta/umidade_solo';
const String topicLuz = 'ifsp-grupo5/horta/luminosidade';
const String uniqueId = 'App_Horta_Final_Production_V4';

// CONFIGURAÇÕES DE NOTIFICAÇÃO
const int intervaloNotificacaoSegundos = 10;

// ESTADO GLOBAL
double limiteUmidade = 60.0;
double limiteLuz = 30.0;
List<String> logMudancasUmidade = [];
List<String> logMudancasLuz = [];

// NOTIFICAÇÕES
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // CONFIGURAÇÃO MANUAL
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: 'AIzaSyD9hlnvx9zsbSlVtoKXA_P5JwK3B5QT9WY',
      appId: '1:726991202664:android:f69f764f6e1e06db304edd',
      messagingSenderId: '726991202664',
      projectId: 'hortainteligente-8d7af',
    ),
  );

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

  // Timers separados para cada tipo de alerta não bloquear o outro
  DateTime lastTimeUmidade = DateTime.now().subtract(const Duration(days: 1));
  DateTime lastTimeLuz = DateTime.now().subtract(const Duration(days: 1));

  @override
  void initState() {
    super.initState();
    setupMqtt();
    requestNotificationPermission();
  }

  Future<void> requestNotificationPermission() async {
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  // Agora recebe o 'tipo' para checar o timer correto ('umidade' ou 'luz')
  Future<void> showNotification(
      String titulo, String corpo, String tipo) async {
    DateTime agora = DateTime.now();
    DateTime ultimoEnvio = (tipo == 'umidade') ? lastTimeUmidade : lastTimeLuz;

    // Verifica tempo
    if (agora.difference(ultimoEnvio).inSeconds <
        intervaloNotificacaoSegundos) {
      return;
    }

    // Atualiza o timer correto
    if (tipo == 'umidade') {
      lastTimeUmidade = agora;
    } else {
      lastTimeLuz = agora;
    }

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'horta_channel_id',
      'Alertas da Horta',
      channelDescription: 'Notificações críticas de irrigação',
      importance: Importance.max,
      priority: Priority.high,
      color: Colors.red,
    );

    // Usamos IDs diferentes (0 e 1) para que uma notificação não substitua a outra na barra de status
    int notificationId = (tipo == 'umidade') ? 0 : 1;

    await flutterLocalNotificationsPlugin.show(notificationId, titulo, corpo,
        const NotificationDetails(android: androidPlatformChannelSpecifics));
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
            double valorRecebido = double.tryParse(pt) ?? 0;

            if (c[0].topic == topicSolo) {
              umidadeSolo = valorRecebido;
              checkAlert();
            } else if (c[0].topic == topicLuz) {
              luminosidade = valorRecebido;
              checkAlert();
            }
          });
        }
      });
    }
  }

  void checkAlert() {
    // Verifica Umidade
    if (umidadeSolo < limiteUmidade) {
      showNotification(
          "ALERTA DE UMIDADE",
          "Solo seco (${umidadeSolo.toStringAsFixed(0)}%). Regue agora!",
          'umidade');
    }

    // Verifica Luz
    if (luminosidade < limiteLuz) {
      showNotification(
          "ALERTA DE LUZ",
          "Luminosidade baixa (${luminosidade.toStringAsFixed(0)}%). Precisa de sol!",
          'luz');
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
                  label: const Text("VER HISTÓRICO (BANCO DE DADOS)",
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
                Row(children: [
                  Icon(icon, color: color, size: 28),
                  const SizedBox(width: 10),
                  Text(title,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold))
                ]),
                IconButton(
                    icon: const Icon(Icons.settings, color: Colors.grey),
                    onPressed: () => abrirConfiguracoes(tipoConfig))
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
                      NeedlePointer(value: value, enableAnimation: true)
                    ],
                    annotations: <GaugeAnnotation>[
                      GaugeAnnotation(
                          widget: Text('${value.toStringAsFixed(0)}%',
                              style: const TextStyle(
                                  fontSize: 25, fontWeight: FontWeight.bold)),
                          angle: 90,
                          positionFactor: 0.5)
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

// TELA DE CONFIGURAÇÕES --
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

      // Salva apenas LOGS DE CONFIGURAÇÃO, não leituras de sensores
      FirebaseFirestore.instance.collection('logs_configuracoes').add({
        'data_hora': Timestamp.now(),
        'parametro': widget.tipo,
        'valor_novo': _currentValue,
        'log_texto': log
      });
    });

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text("Configuração Salva!")));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(titulo)),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            const Text("Definir Limite Mínimo:",
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
                        onChanged: (v) => setState(() => _currentValue = v))),
              ],
            ),
            SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                    onPressed: _salvar, child: const Text("SALVAR"))),
            const Divider(height: 40),
            const Text("Histórico Recente (Sessão):",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Expanded(
              child: ListView.builder(
                  itemCount: _historico.length,
                  itemBuilder: (ctx, i) => ListTile(
                      leading: const Icon(Icons.history),
                      title: Text(_historico[i]))),
            ),
          ],
        ),
      ),
    );
  }
}

// TELA DE GRÁFICOS
class HistoricoPage extends StatefulWidget {
  const HistoricoPage({super.key});

  @override
  State<HistoricoPage> createState() => _HistoricoPageState();
}

class _HistoricoPageState extends State<HistoricoPage> {
  final Stream<QuerySnapshot> _historicoStream = FirebaseFirestore.instance
      .collection('historico_leituras')
      .orderBy('data_hora', descending: true)
      .limit(50)
      .snapshots();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Histórico do Banco")),
      body: StreamBuilder<QuerySnapshot>(
        stream: _historicoStream,
        builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (snapshot.hasError)
            return const Center(child: Text('Erro ao carregar dados'));
          if (snapshot.connectionState == ConnectionState.waiting)
            return const Center(child: CircularProgressIndicator());

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
                child: Text('Nenhum dado salvo no histórico ainda.'));
          }

          List<FlSpot> pontosUmidade = [];
          List<FlSpot> pontosLuz = [];

          final docs = snapshot.data!.docs;

          for (int i = 0; i < docs.length; i++) {
            var data = docs[i].data() as Map<String, dynamic>;
            double yUmidade = (data['umidade_solo'] ?? 0).toDouble();
            double yLuz = (data['luminosidade'] ?? 0).toDouble();
            double x = (docs.length - 1 - i).toDouble();

            pontosUmidade.add(FlSpot(x, yUmidade));
            pontosLuz.add(FlSpot(x, yLuz));
          }

          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  const Text("Umidade do Solo (%)",
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue)),
                  const SizedBox(height: 10),
                  _buildChart(pontosUmidade, Colors.blue),
                  const SizedBox(height: 30),
                  const Text("Luminosidade (%)",
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange)),
                  const SizedBox(height: 10),
                  _buildChart(pontosLuz, Colors.orange),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildChart(List<FlSpot> pontos, Color cor) {
    return Container(
      height: 250,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [const BoxShadow(blurRadius: 5, color: Colors.black12)]),
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: 100,
          gridData: const FlGridData(show: true),
          titlesData: const FlTitlesData(
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: pontos,
              isCurved: true,
              color: cor,
              barWidth: 3,
              dotData: const FlDotData(show: true),
              belowBarData:
                  BarAreaData(show: true, color: cor.withOpacity(0.2)),
            ),
          ],
        ),
      ),
    );
  }
}
