import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:pdf_render/pdf_render.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDF Ebook Reader',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const PdfViewerScreen(),
    );
  }
}

class PdfViewerScreen extends StatefulWidget {
  const PdfViewerScreen({super.key});

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen>
    with TickerProviderStateMixin {
  PdfDocument? _doc;
  int _currentPage = 0;
  late AnimationController _animationController;
  bool _isFlipping = false;
  bool _flipDirection = true;
  final Map<int, Uint8List?> _pageCache = {};

  @override
  void initState() {
    super.initState();
    _loadPdf();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 650),
      vsync: this,
    );
  }

  Future<void> _loadPdf() async {
    final doc = await PdfDocument.openAsset('assets/Ada_Zangemann-id_new_cover.pdf');
    setState(() {
      _doc = doc;
    });
    _renderPage(0); // Preload first page
  }

  Future<Uint8List?> _renderPage(int pageIndex) async {
    if (_doc == null) return null;
    if (pageIndex < 0 || pageIndex >= _doc!.pageCount) return null;
    if (_pageCache.containsKey(pageIndex)) return _pageCache[pageIndex];

    final page = await _doc!.getPage(pageIndex + 1);
    final width = page.width;
    final height = page.height;

    final image = await page.render(
      x: 0,
      y: 0,
      width: (width * 2).toInt(),
      height: (height * 2).toInt(),
    );

    final ui.Image uiImage = await image.createImageDetached();
    final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData?.buffer.asUint8List();
    image.dispose();

    _pageCache[pageIndex] = bytes;
    return bytes;
  }

  @override
  void dispose() {
    _animationController.dispose();
    _doc?.dispose();
    super.dispose();
  }

  void _flipPage(bool forward) {
    if (_isFlipping ||
        _doc == null ||
        (forward && _currentPage >= _doc!.pageCount - 1) ||
        (!forward && _currentPage <= 0)) {
      return;
    }

    final targetPage = forward ? _currentPage + 1 : _currentPage - 1;
    _renderPage(targetPage); // Pre-render

    setState(() {
      _isFlipping = true;
      _flipDirection = forward;
    });

    _animationController.forward(from: 0).then((_) {
      setState(() {
        _currentPage = targetPage;
        _isFlipping = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_doc == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final doc = _doc!;

    return Scaffold(
      appBar: AppBar(
        title: Text('Page ${_currentPage + 1} of ${doc.pageCount}'),
        backgroundColor: Colors.indigo,
      ),
      body: Center(
        child: LayoutBuilder(builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final target = _flipDirection ? _currentPage + 1 : _currentPage - 1;
          return Stack(children: [
            Positioned.fill(child: _fullPageWidget(target)),
            Positioned.fill(
              child: _isFlipping
                  ? _buildPageTurn(_currentPage, target, width, height)
                  : _fullPageWidget(_currentPage),
            ),
          ]);
        }),
      ),
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: "prev",
            onPressed: () => _flipPage(false),
            child: const Icon(Icons.arrow_back),
          ),
          const SizedBox(width: 8),
          FloatingActionButton(
            heroTag: "next",
            onPressed: () => _flipPage(true),
            child: const Icon(Icons.arrow_forward),
          ),
        ],
      ),
    );
  }

  Widget _fullPageWidget(int pageIndex) {
    if (_doc == null) return Container();
    if (pageIndex < 0 || pageIndex >= _doc!.pageCount) return Container();

    return FutureBuilder<Uint8List?>(
      future: _renderPage(pageIndex),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return Image.memory(
            snapshot.data!,
            fit: BoxFit.contain,
            alignment: Alignment.center,
          );
        } else {
          return const Center(child: CircularProgressIndicator());
        }
      },
    );
  }

  Widget _buildPageTurn(int fromPage, int toPage, double width, double height) {
    final animation = CurvedAnimation(parent: _animationController, curve: Curves.easeInOut);

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final p = animation.value.clamp(0.0, 1.0);

        final backTransform = Matrix4.identity()
          ..setEntry(3, 2, 0.001)
          ..rotateY(_flipDirection ? 0.06 * (1 - p) : -0.06 * (1 - p));

        final maxAngle = pi * 0.45;
        final angle = _flipDirection ? maxAngle * p : -maxAngle * p;

        return Stack(children: [
          Transform(
            transform: backTransform,
            alignment: Alignment.center,
            child: _fullPageWidget(toPage),
          ),

          Align(
            alignment: Alignment.center,
            child: LayoutBuilder(builder: (context, c) {
              final hingeAlignment = _flipDirection ? Alignment.centerLeft : Alignment.centerRight;

              final pageTransform = Matrix4.identity()..setEntry(3, 2, 0.001);
              pageTransform.rotateY(angle);

              return Transform(
                transform: pageTransform,
                alignment: hingeAlignment,
                child: Stack(children: [
                  _fullPageWidget(fromPage),

                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: _flipDirection ? Alignment.centerLeft : Alignment.centerRight,
                            end: _flipDirection ? Alignment.centerRight : Alignment.centerLeft,
                            colors: [
                              Color.fromRGBO(0, 0, 0, (0.6 * p)),
                              Color.fromRGBO(0, 0, 0, 0.0),
                            ],
                            stops: [0.0, 0.6],
                          ),
                        ),
                      ),
                    ),
                  ),

                  Positioned.fill(
                    child: IgnorePointer(
                      child: Align(
                        alignment: _flipDirection ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          width: c.maxWidth * 0.25 * p,
                          height: c.maxHeight,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color.fromRGBO(0, 0, 0, 0.25 * p),
                                Color.fromRGBO(0, 0, 0, 0.0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ]),
              );
            }),
          ),
        ]);
      },
    );
  }
}
