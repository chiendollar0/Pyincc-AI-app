import 'package:flutter/material.dart';

import '../data/crm_repo.dart';
import '../screens/inbox/inbox_screen.dart';
import '../screens/schedule/schedule_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/studio/studio_screen.dart';

class CrmShell extends StatefulWidget {
  const CrmShell({
    super.key,
    required this.repo,
    required this.onSignOut,
  });

  final CrmRepo repo;
  final VoidCallback onSignOut;

  @override
  State<CrmShell> createState() => _CrmShellState();
}

class _CrmShellState extends State<CrmShell> {
  int _index = 0;
  int _catalogVersion = 0;
  int _inboxVersion = 0;

  void _openInboxAndRefresh() {
    setState(() {
      _inboxVersion += 1;
      _index = 0;
    });
  }

  void _notifyCatalogChanged() {
    setState(() => _catalogVersion += 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _index,
          children: [
            InboxScreen(
              repo: widget.repo,
              refreshVersion: _inboxVersion,
            ),
            StudioScreen(
              repo: widget.repo,
              catalogVersion: _catalogVersion,
              onOpenInbox: _openInboxAndRefresh,
              onCaseCreated: () => setState(() => _inboxVersion += 1),
            ),
            ScheduleScreen(repo: widget.repo),
            SettingsScreen(
              repo: widget.repo,
              onSignOut: widget.onSignOut,
              onCatalogChanged: _notifyCatalogChanged,
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.forum_outlined),
            selectedIcon: Icon(Icons.forum),
            label: 'Hộp thư',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'Studio',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Lịch',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Cài đặt',
          ),
        ],
      ),
    );
  }
}
