import 'package:material_ui/material_ui.dart';

import 'screens/tryon/tryon_studio_screen.dart';

void main() {
  runApp(const BeautyCrmApp());
}

class BeautyCrmApp extends StatelessWidget {
  const BeautyCrmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Beauty Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFD81B60)),
        useMaterial3: true,
      ),
      home: const MainDashboardScreen(),
    );
  }
}

class MainDashboardScreen extends StatefulWidget {
  const MainDashboardScreen({super.key});

  @override
  State<MainDashboardScreen> createState() => _MainDashboardScreenState();
}

class _MainDashboardScreenState extends State<MainDashboardScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const AiTriageInboxScreen(),
    const TryOnStudioScreen(
      apiBaseUrl: String.fromEnvironment('TRYON_API_URL', defaultValue: ''),
    ),
    const ShiftAndBookingScreen(),
    const OwnerSettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.forum_outlined),
            label: 'Hộp thư AI',
          ),
          NavigationDestination(
            icon: Icon(Icons.face_retouching_natural),
            label: 'Thử Mày/Môi',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month),
            label: 'Ca & Lịch',
          ),
          NavigationDestination(
            icon: Icon(Icons.admin_panel_settings),
            label: 'Chủ tiệm',
          ),
        ],
      ),
    );
  }
}

class AiTriageInboxScreen extends StatelessWidget {
  const AiTriageInboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> triageChats = [
      {
        'name': 'Chị Minh Thư (FB)',
        'tag': 'CA KHÓ / SỬA MÀY',
        'color': Colors.red,
        'summary':
            'Từng làm mày nơi khác bị trổ xanh, cần hút màu và làm sợi mới gấp.',
        'aiSuggestion':
            'Dạ chị Thư ơi, bên em chuyên xử lý nền mày trổ xanh bằng công nghệ Laser kết hợp đi sợi Hairstroke tự nhiên. Chị gửi em xin ảnh cận chân mày hiện tại để chuyên gia bên em lên phác đồ cho mình nhé!',
        'staff': 'Sale: Ngọc Lan (Đang trực)',
      },
      {
        'name': 'Thanh Trúc (Zalo)',
        'tag': 'ĐÃ THỬ MẪU MÔI',
        'color': Colors.orange,
        'summary':
            'Đã chọn mẫu Môi Cam Đào #02, hỏi lịch trống chiều nay lúc 15h.',
        'aiSuggestion':
            'Dạ mẫu Môi Cam Đào #02 rất tôn da chị Trúc ạ! Chiều nay 15h bên em còn trống lịch chuyên viên trưởng, em giữ chỗ cho chị nhé?',
        'staff': 'Sale: Thu Hà (Đang trực)',
      },
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Sàng lọc AI (Meta & Zalo)')),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: triageChats.length,
        itemBuilder: (context, index) {
          final chat = triageChats[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        chat['name'],
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: chat['color'].withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          chat['tag'],
                          style: TextStyle(
                            color: chat['color'],
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tóm tắt AI: ${chat['summary']}',
                    style: const TextStyle(color: Colors.black87),
                  ),
                  const Divider(),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.pink.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '✨ Gợi ý chốt đơn chuẩn giọng Chủ tiệm:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.pink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          chat['aiSuggestion'],
                          style: const TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.send, size: 16),
                            label: const Text('Gửi ngay cho khách'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class ShiftAndBookingScreen extends StatelessWidget {
  const ShiftAndBookingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ca trực & Lịch hẹn hôm nay')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const Text(
              'Trạng thái Ca trực của bạn',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text(
              'Bật để hệ thống tự động chia khách từ Meta & Zalo',
            ),
            value: true,
            onChanged: (val) {},
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.schedule, color: Colors.pink),
            title: Text('14:30 - Chị Lan Anh (0909xxxxxx)'),
            subtitle: Text(
              'Dịch vụ: Mày Hairstroke Nâu Tây • Thợ: Master Linh',
            ),
            trailing: Chip(label: Text('Đã chốt')),
          ),
        ],
      ),
    );
  }
}

class OwnerSettingsScreen extends StatelessWidget {
  const OwnerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cấu hình Chủ tiệm (0đ)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.facebook, color: Colors.blue),
              label: const Text('Kết nối Meta Business Suite (Miễn phí)'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Google Gemini API Key (Gói miễn phí):',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const TextField(
              obscureText: true,
              decoration: InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Dán mã AIzaSy... từ Google AI Studio vào đây',
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Kịch bản & Bảng giá để Gemini đóng vai Chủ tiệm:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const TextField(
              maxLines: 4,
              decoration: InputDecoration(
                border: OutlineInputBorder(),
                hintText:
                    'VD: Mày sợi 3tr5, Môi collagen 4tr. Ca khó sửa mày cũ báo chủ tiệm duyệt...',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {},
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
              child: const Text('Lưu cấu hình hệ thống'),
            ),
          ],
        ),
      ),
    );
  }
}
