import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n/app_strings.dart';
import 'main_connect.dart';
import 'main_constants.dart';
import 'main_pages.dart';
import 'main_update_notification.dart';
import 'services/vpn_controller.dart';
import 'services/windows_interference_service.dart';

enum _HomeSection { connect, add, settings, logs }

class _ReturnToMainSectionIntent extends Intent {
  const _ReturnToMainSectionIntent();
}

const _homeSections = <_HomeSection>[
  _HomeSection.connect,
  _HomeSection.add,
  _HomeSection.settings,
  _HomeSection.logs,
];

final _mobilePageSwipeSpring = SpringDescription.withDurationAndBounce(
  duration: mobilePageTransitionDuration,
);

class VpnHomePage extends StatefulWidget {
  const VpnHomePage({super.key, required this.controller});

  final VpnController controller;

  @override
  State<VpnHomePage> createState() => _VpnHomePageState();
}

class _VpnHomePageState extends State<VpnHomePage> {
  late final TextEditingController _textController;
  late final FocusNode _windowsShortcutFocusNode;
  late _HomeSection _section;
  late final bool _startedWithoutSources;
  bool _didAutoSwitchAfterRestore = false;
  bool _windowsInterferenceDialogOpen = false;
  bool _appUpdateDialogOpen = false;
  bool _connectFlowInProgress = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.controller.rawInput);
    _windowsShortcutFocusNode = FocusNode(
      debugLabel: 'Windows return-to-main shortcuts',
    );
    _textController.addListener(_handleTextChanged);
    widget.controller.addListener(_handleControllerUpdated);
    _startedWithoutSources = !widget.controller.hasSources;
    _section = widget.controller.hasSources
        ? _HomeSection.connect
        : _HomeSection.add;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _showPendingAppUpdateNotification(),
    );
  }

  @override
  void didUpdateWidget(covariant VpnHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_textController.text != widget.controller.rawInput) {
      _textController.text = widget.controller.rawInput;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerUpdated);
    _textController
      ..removeListener(_handleTextChanged)
      ..dispose();
    _windowsShortcutFocusNode.dispose();
    super.dispose();
  }

  void _handleTextChanged() {
    if (_textController.text != widget.controller.rawInput) {
      widget.controller.setRawInput(_textController.text);
    }
  }

  void _handleControllerUpdated() {
    if ((_section != _HomeSection.add) &&
        (widget.controller.isAddingSource ||
            widget.controller.rawInput.trim().isNotEmpty) &&
        mounted) {
      setState(() {
        _section = _HomeSection.add;
      });
      return;
    }
    if (_startedWithoutSources &&
        !_didAutoSwitchAfterRestore &&
        widget.controller.hasSources &&
        mounted) {
      _didAutoSwitchAfterRestore = true;
      setState(() {
        _section = _HomeSection.connect;
      });
      return;
    }
    _showPendingAppUpdateNotification();
  }

  void _showPendingAppUpdateNotification() {
    if (!mounted || _appUpdateDialogOpen) {
      return;
    }
    final update = widget.controller.pendingAppUpdateNotification;
    if (update == null) {
      return;
    }
    _appUpdateDialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _appUpdateDialogOpen = false;
        return;
      }
      await showAppUpdateNotificationDialog(
        context,
        controller: widget.controller,
        strings: AppStrings.of(context),
        update: update,
      );
      _appUpdateDialogOpen = false;
      if (mounted) {
        _showPendingAppUpdateNotification();
      }
    });
  }

  void _setSection(_HomeSection section) {
    if (_section == section) {
      return;
    }
    setState(() {
      _section = section;
    });
  }

  void _handleReturnToMainSection() {
    if (_section == _HomeSection.connect) {
      return;
    }
    final primaryFocus = FocusManager.instance.primaryFocus;
    if (primaryFocus != _windowsShortcutFocusNode) {
      primaryFocus?.unfocus();
    }
    _setSection(_HomeSection.connect);
    _restoreWindowsShortcutFocus();
  }

  void _restoreWindowsShortcutFocus() {
    if (!Platform.isWindows) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _windowsShortcutFocusNode.requestFocus();
    });
  }

  Future<void> _handlePowerButtonPressed() async {
    if (_connectFlowInProgress || widget.controller.isBusy) {
      return;
    }

    if (widget.controller.isConnected) {
      await widget.controller.toggleConnection();
      return;
    }

    _connectFlowInProgress = true;
    try {
      if (Platform.isWindows) {
        try {
          await widget.controller.hydration;
          final processes = await widget.controller.scanWindowsInterference();
          if (mounted && processes.isNotEmpty) {
            await _showWindowsInterferenceDialog(processes);
          }
        } catch (_) {
          // Interference detection is best-effort; connection should still work
          // if process enumeration or the service check fails.
        }
      }

      if (!mounted ||
          widget.controller.isBusy ||
          widget.controller.isConnected) {
        return;
      }
      await widget.controller.connect();
    } finally {
      _connectFlowInProgress = false;
    }
  }

  Future<void> _showWindowsInterferenceDialog(
    List<WindowsInterferenceProcess> initialProcesses,
  ) async {
    if (_windowsInterferenceDialogOpen) {
      return;
    }
    _windowsInterferenceDialogOpen = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) {
          var processes = initialProcesses;
          var busy = false;
          String? errorText;

          void closeDialog() {
            Navigator.of(dialogContext).pop();
          }

          Future<void> terminateProcesses(
            void Function(void Function()) setDialogState,
          ) async {
            setDialogState(() {
              busy = true;
              errorText = null;
            });
            try {
              final result = await widget.controller
                  .terminateWindowsInterferenceProcesses();
              final remaining = await widget.controller
                  .scanWindowsInterference();
              if (!dialogContext.mounted) {
                return;
              }
              final strings = AppStrings.of(dialogContext);
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                SnackBar(
                  content: Text(
                    strings.windowsInterferenceTerminatedMessage(
                      result.affected.length,
                      result.failures.length,
                    ),
                  ),
                ),
              );
              if (remaining.isEmpty) {
                Navigator.of(dialogContext).pop();
                return;
              }
              setDialogState(() {
                processes = remaining;
                busy = false;
                errorText = result.hasFailures
                    ? result.failures.first.message
                    : null;
              });
            } catch (error) {
              if (!dialogContext.mounted) {
                return;
              }
              final strings = AppStrings.of(dialogContext);
              setDialogState(() {
                busy = false;
                errorText = strings.windowsInterferenceActionFailed(
                  error.toString(),
                );
              });
            }
          }

          return StatefulBuilder(
            builder: (context, setDialogState) {
              final strings = AppStrings.of(context);
              final scheme = Theme.of(context).colorScheme;
              return AlertDialog(
                backgroundColor: scheme.surfaceContainerHigh,
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                title: Row(
                  children: <Widget>[
                    Icon(Icons.warning_amber_rounded, color: scheme.tertiary),
                    const SizedBox(width: 12),
                    Expanded(child: Text(strings.windowsInterferenceTitle)),
                  ],
                ),
                content: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(strings.windowsInterferenceMessage),
                      const SizedBox(height: 16),
                      Text(
                        strings.windowsInterferenceDetectedCount(
                          processes.length,
                        ),
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: scheme.outlineVariant.withValues(
                                alpha: 0.42,
                              ),
                            ),
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            padding: const EdgeInsets.all(12),
                            itemCount: processes.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final process = processes[index];
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Icon(
                                    Icons.memory_rounded,
                                    size: 20,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          process.label,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleSmall,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          process.reason,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                      if (errorText != null) ...<Widget>[
                        const SizedBox(height: 12),
                        Text(errorText!, style: TextStyle(color: scheme.error)),
                      ],
                    ],
                  ),
                ),
                actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                actions: <Widget>[
                  TextButton.icon(
                    onPressed: busy ? null : closeDialog,
                    icon: const Icon(Icons.close_rounded),
                    label: Text(strings.windowsInterferenceCloseAction),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () => terminateProcesses(setDialogState),
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: Text(strings.windowsInterferenceTerminateAction),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      _windowsInterferenceDialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final controller = widget.controller;
    final scheme = Theme.of(context).colorScheme;

    final page = Scaffold(
      body: Stack(
        children: <Widget>[
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(color: appBackgroundColor),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final shellPadding = constraints.maxWidth >= 1700
                    ? 28.0
                    : constraints.maxWidth >= 1300
                    ? 20.0
                    : 16.0;
                if (constraints.maxWidth < mobileShellBreakpoint) {
                  return ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) => _MobileShell(
                      selected: _section,
                      controller: controller,
                      strings: strings,
                      onChanged: _setSection,
                      textController: _textController,
                      onToggleConnection: _handlePowerButtonPressed,
                    ),
                  );
                }

                final sectionContent = ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) => _SectionContentSwitcher(
                    section: _section,
                    controller: controller,
                    strings: strings,
                    textController: _textController,
                    onToggleConnection: _handlePowerButtonPressed,
                  ),
                );

                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    0,
                    0,
                    shellPadding,
                    shellPadding,
                  ),
                  child: SizedBox.expand(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.surface.withValues(alpha: 0.84),
                        borderRadius: BorderRadius.circular(36),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.24),
                            blurRadius: 48,
                            offset: const Offset(0, 22),
                          ),
                        ],
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final compactShell = constraints.maxWidth < 760;
                          return Stack(
                            alignment: Alignment.bottomCenter,
                            children: <Widget>[
                              Positioned.fill(
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    compactShell ? 18 : 24,
                                    22,
                                    compactShell ? 18 : 24,
                                    compactShell ? 92 : 104,
                                  ),
                                  child: sectionContent,
                                ),
                              ),
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: compactShell ? 18 : 24,
                                child: Center(
                                  child: _SectionSelector(
                                    selected: _section,
                                    compact: compactShell,
                                    onChanged: _setSection,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );

    if (!Platform.isWindows) {
      return page;
    }

    return FocusableActionDetector(
      autofocus: true,
      focusNode: _windowsShortcutFocusNode,
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.escape):
            _ReturnToMainSectionIntent(),
      },
      actions: <Type, Action<Intent>>{
        _ReturnToMainSectionIntent: CallbackAction<_ReturnToMainSectionIntent>(
          onInvoke: (_) {
            _handleReturnToMainSection();
            return null;
          },
        ),
      },
      child: page,
    );
  }
}

class _MobileShell extends StatefulWidget {
  const _MobileShell({
    required this.selected,
    required this.controller,
    required this.strings,
    required this.onChanged,
    required this.textController,
    required this.onToggleConnection,
  });

  final _HomeSection selected;
  final VpnController controller;
  final AppStrings strings;
  final ValueChanged<_HomeSection> onChanged;
  final TextEditingController textController;
  final Future<void> Function() onToggleConnection;

  @override
  State<_MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<_MobileShell> {
  late final PageController _pageController;
  int? _programmaticPageTarget;
  int? _sourceOverflowDragStartIndex;
  int _pageSyncGeneration = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      initialPage: _homeSections.indexOf(widget.selected),
    );
  }

  @override
  void didUpdateWidget(covariant _MobileShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      _syncPageToSelected();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _syncPageToSelected() {
    final targetIndex = _homeSections.indexOf(widget.selected);

    void animateWhenReady() {
      if (!mounted || !_pageController.hasClients) {
        return;
      }
      final currentPage = _pageController.page;
      if (currentPage != null && currentPage.round() == targetIndex) {
        _programmaticPageTarget = null;
        return;
      }
      final syncGeneration = ++_pageSyncGeneration;
      _programmaticPageTarget = targetIndex;
      _pageController
          .animateToPage(
            targetIndex,
            duration: mobilePageTransitionDuration,
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() {
            if (!mounted || syncGeneration != _pageSyncGeneration) {
              return;
            }
            _programmaticPageTarget = null;
          });
    }

    if (_pageController.hasClients) {
      animateWhenReady();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => animateWhenReady());
    }
  }

  void _handlePageChanged(int index) {
    if (index < 0 || index >= _homeSections.length) {
      return;
    }
    if (_sourceOverflowDragStartIndex != null) {
      return;
    }
    final programmaticPageTarget = _programmaticPageTarget;
    if (programmaticPageTarget != null) {
      if (index != programmaticPageTarget) {
        return;
      }
      _programmaticPageTarget = null;
    }
    widget.onChanged(_homeSections[index]);
  }

  void _handleConnectSourcePagerOverflow() {
    final currentIndex = _homeSections.indexOf(widget.selected);
    if (currentIndex < 0 || currentIndex >= _homeSections.length - 1) {
      return;
    }
    widget.onChanged(_homeSections[currentIndex + 1]);
  }

  void _handleConnectSourcePagerOverflowDragUpdate(double deltaDx) {
    if (!_pageController.hasClients) {
      return;
    }

    final currentIndex = _homeSections.indexOf(widget.selected);
    if (currentIndex < 0 || currentIndex >= _homeSections.length - 1) {
      return;
    }

    final startIndex = _sourceOverflowDragStartIndex ?? currentIndex;
    if (_sourceOverflowDragStartIndex == null) {
      _pageSyncGeneration += 1;
      _programmaticPageTarget = null;
      _sourceOverflowDragStartIndex = startIndex;
    }

    final position = _pageController.position;
    final viewport = position.viewportDimension;
    if (viewport <= 0) {
      return;
    }

    final startPixels = startIndex * viewport;
    final targetPixels = (startIndex + 1) * viewport;
    final nextPixels = (position.pixels - deltaDx)
        .clamp(startPixels, targetPixels)
        .toDouble();
    position.jumpTo(nextPixels);
  }

  void _handleConnectSourcePagerOverflowDragEnd(double velocityDx) {
    final startIndex = _sourceOverflowDragStartIndex;
    if (startIndex == null) {
      _handleConnectSourcePagerOverflow();
      return;
    }
    if (!_pageController.hasClients || startIndex >= _homeSections.length - 1) {
      _sourceOverflowDragStartIndex = null;
      return;
    }

    final position = _pageController.position;
    final viewport = position.viewportDimension;
    final draggedPixels = viewport <= 0
        ? 0.0
        : position.pixels - startIndex * viewport;
    final completeByVelocity =
        velocityDx <= -mobileSourcePagerSwipeVelocityThreshold;
    final cancelByVelocity =
        velocityDx >= mobileSourcePagerSwipeVelocityThreshold;
    final shouldComplete =
        completeByVelocity ||
        (!cancelByVelocity &&
            draggedPixels >= mobileSourcePagerSwipeDistanceThreshold);
    _settleConnectSourcePagerOverflowDrag(
      shouldComplete ? startIndex + 1 : startIndex,
    );
  }

  void _handleConnectSourcePagerOverflowDragCancel() {
    final startIndex = _sourceOverflowDragStartIndex;
    if (startIndex == null) {
      return;
    }
    _settleConnectSourcePagerOverflowDrag(startIndex);
  }

  void _settleConnectSourcePagerOverflowDrag(int targetIndex) {
    final startIndex = _sourceOverflowDragStartIndex;
    if (startIndex == null || !_pageController.hasClients) {
      _sourceOverflowDragStartIndex = null;
      return;
    }

    final clampedTargetIndex = targetIndex
        .clamp(0, _homeSections.length - 1)
        .toInt();
    final completesOverflow = clampedTargetIndex != startIndex;
    final syncGeneration = ++_pageSyncGeneration;
    _programmaticPageTarget = clampedTargetIndex;
    _pageController
        .animateToPage(
          clampedTargetIndex,
          duration: mobilePageTransitionDuration,
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() {
          if (!mounted || syncGeneration != _pageSyncGeneration) {
            return;
          }
          _programmaticPageTarget = null;
          _sourceOverflowDragStartIndex = null;
          if (completesOverflow) {
            widget.onChanged(_homeSections[clampedTargetIndex]);
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pagePhysics = _FastPageSwipePhysics(
      parent: ScrollConfiguration.of(context).getScrollPhysics(context),
    );

    return DecoratedBox(
      decoration: BoxDecoration(color: scheme.surface.withValues(alpha: 0.84)),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SizedBox(height: 84),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: PageView(
                  controller: _pageController,
                  physics: pagePhysics,
                  onPageChanged: _handlePageChanged,
                  children: <Widget>[
                    ConnectPageBody(
                      controller: widget.controller,
                      strings: widget.strings,
                      onToggleConnection: widget.onToggleConnection,
                      onSwipePastLastSource: _handleConnectSourcePagerOverflow,
                      onSwipePastLastSourceDragUpdate:
                          _handleConnectSourcePagerOverflowDragUpdate,
                      onSwipePastLastSourceDragEnd:
                          _handleConnectSourcePagerOverflowDragEnd,
                      onSwipePastLastSourceDragCancel:
                          _handleConnectSourcePagerOverflowDragCancel,
                    ),
                    AddSourcePageBody(
                      controller: widget.controller,
                      strings: widget.strings,
                      textController: widget.textController,
                    ),
                    SettingsPageBody(
                      controller: widget.controller,
                      strings: widget.strings,
                    ),
                    LogsPageBody(
                      controller: widget.controller,
                      strings: widget.strings,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: _MobileSectionSelector(
                selected: widget.selected,
                onChanged: widget.onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FastPageSwipePhysics extends ScrollPhysics {
  const _FastPageSwipePhysics({super.parent});

  @override
  _FastPageSwipePhysics applyTo(ScrollPhysics? ancestor) {
    return _FastPageSwipePhysics(parent: buildParent(ancestor));
  }

  @override
  SpringDescription get spring => _mobilePageSwipeSpring;
}

class _SectionContentSwitcher extends StatelessWidget {
  const _SectionContentSwitcher({
    required this.section,
    required this.controller,
    required this.strings,
    required this.textController,
    required this.onToggleConnection,
  });

  final _HomeSection section;
  final VpnController controller;
  final AppStrings strings;
  final TextEditingController textController;
  final Future<void> Function() onToggleConnection;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        final children = <Widget>[...previousChildren];
        if (currentChild != null) {
          children.add(currentChild);
        }
        return Stack(
          alignment: Alignment.topCenter,
          clipBehavior: Clip.none,
          children: children,
        );
      },
      transitionBuilder: (child, animation) {
        final offsetAnimation = Tween<Offset>(
          begin: const Offset(0.02, 0),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offsetAnimation, child: child),
        );
      },
      child: switch (section) {
        _HomeSection.connect => ConnectPageBody(
          key: const ValueKey<String>('connect'),
          controller: controller,
          strings: strings,
          onToggleConnection: onToggleConnection,
        ),
        _HomeSection.add => AddSourcePageBody(
          key: const ValueKey<String>('add'),
          controller: controller,
          strings: strings,
          textController: textController,
        ),
        _HomeSection.settings => SettingsPageBody(
          key: const ValueKey<String>('settings'),
          controller: controller,
          strings: strings,
        ),
        _HomeSection.logs => LogsPageBody(
          key: const ValueKey<String>('logs'),
          controller: controller,
          strings: strings,
        ),
      },
    );
  }
}

class _SectionSelector extends StatelessWidget {
  const _SectionSelector({
    required this.selected,
    required this.compact,
    required this.onChanged,
  });

  final _HomeSection selected;
  final bool compact;
  final ValueChanged<_HomeSection> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final gap = compact ? 6.0 : 8.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(compact ? 22 : 24),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.24),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 6 : 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _SectionRailButton(
              icon: Icons.power_settings_new_rounded,
              selected: selected == _HomeSection.connect,
              compact: compact,
              onPressed: () => onChanged(_HomeSection.connect),
            ),
            SizedBox(width: gap),
            _SectionRailButton(
              icon: Icons.add_rounded,
              selected: selected == _HomeSection.add,
              compact: compact,
              onPressed: () => onChanged(_HomeSection.add),
            ),
            SizedBox(width: gap),
            _SectionRailButton(
              icon: Icons.settings_rounded,
              selected: selected == _HomeSection.settings,
              compact: compact,
              onPressed: () => onChanged(_HomeSection.settings),
            ),
            SizedBox(width: gap),
            _SectionRailButton(
              icon: Icons.receipt_long_outlined,
              selected: selected == _HomeSection.logs,
              compact: compact,
              onPressed: () => onChanged(_HomeSection.logs),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileSectionSelector extends StatelessWidget {
  const _MobileSectionSelector({
    required this.selected,
    required this.onChanged,
  });

  final _HomeSection selected;
  final ValueChanged<_HomeSection> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.24),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Row(
          children: <Widget>[
            Expanded(
              child: _MobileSectionButton(
                icon: Icons.power_settings_new_rounded,
                selected: selected == _HomeSection.connect,
                onPressed: () => onChanged(_HomeSection.connect),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MobileSectionButton(
                icon: Icons.add_rounded,
                selected: selected == _HomeSection.add,
                onPressed: () => onChanged(_HomeSection.add),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MobileSectionButton(
                icon: Icons.settings_rounded,
                selected: selected == _HomeSection.settings,
                onPressed: () => onChanged(_HomeSection.settings),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MobileSectionButton(
                icon: Icons.receipt_long_outlined,
                selected: selected == _HomeSection.logs,
                onPressed: () => onChanged(_HomeSection.logs),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileSectionButton extends StatelessWidget {
  const _MobileSectionButton({
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tileColor = _sectionButtonTileColor(scheme, selected);
    final iconColor = selected ? scheme.onSurface : scheme.onSurfaceVariant;

    return SizedBox(
      height: 50,
      child: Material(
        color: tileColor,
        borderRadius: BorderRadius.circular(17),
        child: InkWell(
          borderRadius: BorderRadius.circular(17),
          onTap: selected ? null : onPressed,
          child: Center(
            child: AnimatedScale(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              scale: selected ? 1.06 : 1,
              child: Icon(icon, size: 23, color: iconColor),
            ),
          ),
        ),
      ),
    );
  }
}

Color _sectionButtonTileColor(ColorScheme scheme, bool selected) {
  return selected
      ? scheme.surfaceContainerHighest.withValues(alpha: 0.9)
      : Colors.transparent;
}

class _SectionRailButton extends StatelessWidget {
  const _SectionRailButton({
    required this.icon,
    required this.selected,
    required this.compact,
    required this.onPressed,
  });

  final IconData icon;
  final bool selected;
  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final itemSize = compact ? 46.0 : 52.0;
    final tileColor = _sectionButtonTileColor(scheme, selected);
    final iconColor = selected ? scheme.onSurface : scheme.onSurfaceVariant;

    return SizedBox(
      width: itemSize,
      height: itemSize,
      child: Material(
        color: tileColor,
        borderRadius: BorderRadius.circular(compact ? 15 : 17),
        child: InkWell(
          borderRadius: BorderRadius.circular(compact ? 15 : 17),
          onTap: selected ? null : onPressed,
          child: Center(
            child: AnimatedScale(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              scale: selected ? 1.06 : 1,
              child: Icon(icon, size: compact ? 21 : 23, color: iconColor),
            ),
          ),
        ),
      ),
    );
  }
}
