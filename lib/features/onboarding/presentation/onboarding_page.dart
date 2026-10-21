import 'package:cutter/app/brand/brand_mark.dart';
import 'package:cutter/app/theme/app_theme.dart';
import 'package:cutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

const double _contentMaxWidth = 480;
const double _heroSize = 120;
const double _heroIconSize = 56;
const double _heroMarkSize = 64;
const double _dotSize = 8;
const int _pageCount = 3;

/// The introduction shown on first launch and from the help button of the
/// home screen: three pages on what Cutter does.
class OnboardingPage extends StatefulWidget {
  /// Creates the introduction; [onFinished] runs when the user taps "Get
  /// started" or skips it.
  const OnboardingPage({required this.onFinished, super.key});

  /// Called when the introduction is finished or skipped.
  final VoidCallback onFinished;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _controller = PageController();
  int _index = 0;

  bool get _isLast => _index == _pageCount - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_isLast) {
      widget.onFinished();
      return;
    }
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final target = _index + 1;
    if (reduceMotion) {
      _controller.jumpToPage(target);
      return;
    }
    _controller.animateToPage(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pages = [
      (
        icon: null,
        title: l10n.onboardingLayersTitle,
        body: l10n.onboardingLayersBody,
      ),
      (
        icon: Icons.content_cut,
        title: l10n.onboardingCutTitle,
        body: l10n.onboardingCutBody,
      ),
      (
        icon: Icons.tune,
        title: l10n.onboardingTuneTitle,
        body: l10n.onboardingTuneBody,
      ),
    ];
    final margin =
        MediaQuery.sizeOf(context).width >= 600 ? AppSpacing.lg : AppSpacing.md;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(margin),
          child: Column(
            children: [
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: _isLast
                    ? const SizedBox(height: kMinInteractiveDimension)
                    : TextButton(
                        onPressed: widget.onFinished,
                        child: Text(l10n.onboardingSkip),
                      ),
              ),
              Expanded(
                child: PageView(
                  controller: _controller,
                  onPageChanged: (value) => setState(() => _index = value),
                  children: [
                    for (final page in pages)
                      _Page(
                        icon: page.icon,
                        title: page.title,
                        body: page.body,
                      ),
                  ],
                ),
              ),
              Semantics(
                label: l10n.onboardingStep(_index + 1, _pageCount),
                excludeSemantics: true,
                child: _Dots(index: _index),
              ),
              const SizedBox(height: AppSpacing.md),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _next,
                    child: Text(
                      _isLast ? l10n.onboardingStart : l10n.onboardingNext,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.icon, required this.title, required this.body});

  /// The page's hero icon; null shows the brand mark on a primary disc.
  final IconData? icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: _heroSize,
                height: _heroSize,
                decoration: BoxDecoration(
                  color:
                      icon == null ? scheme.primary : scheme.tertiaryContainer,
                  shape: BoxShape.circle,
                ),
                child: icon == null
                    ? const Center(child: BrandMark(size: _heroMarkSize))
                    : ExcludeSemantics(
                        child: Icon(
                          icon,
                          size: _heroIconSize,
                          color: scheme.onTertiaryContainer,
                        ),
                      ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                title,
                style: theme.textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                body,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < _pageCount; i++)
          Container(
            width: _dotSize,
            height: _dotSize,
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i == index ? scheme.primary : scheme.outlineVariant,
            ),
          ),
      ],
    );
  }
}
