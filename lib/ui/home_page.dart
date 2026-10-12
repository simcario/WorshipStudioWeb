import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../data/cloud.dart';
import 'sidebar.dart';
import 'song_view.dart';

/// Width from which the library sits beside the song instead of in a drawer.
const wideBreakpoint = 900.0;

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.state, this.cloud});

  final AppState state;
  final Cloud? cloud;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _scaffold = GlobalKey<ScaffoldState>();
  bool _fullscreen = false;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= wideBreakpoint;
      final view = SongView(
        state: state,
        fullscreen: _fullscreen,
        onFullscreen: (v) => setState(() => _fullscreen = v),
        onMenu: wide ? null : () => _scaffold.currentState?.openDrawer(),
      );
      if (wide) {
        return Scaffold(
          body: Row(children: [
            if (!_fullscreen) ...[
              SizedBox(width: 360, child: Sidebar(state: state, cloud: widget.cloud)),
              const VerticalDivider(width: 1),
            ],
            Expanded(child: view),
          ]),
        );
      }
      return Scaffold(
        key: _scaffold,
        drawer: Drawer(
          width: box.maxWidth < 420 ? box.maxWidth * 0.9 : 380,
          child: Sidebar(state: state, cloud: widget.cloud, onPicked: () => _scaffold.currentState?.closeDrawer()),
        ),
        body: view,
      );
    });
  }
}
