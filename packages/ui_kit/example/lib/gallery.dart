import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

class ComponentGallery extends StatelessWidget {
  const ComponentGallery({
    required this.mode,
    required this.onModeChanged,
    super.key,
  });

  final ThemeMode mode;
  final ValueChanged<ThemeMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paasel UI Kit'),
        actions: [
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.light,
                icon: Icon(Icons.light_mode_outlined),
                label: Text('Light'),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode_outlined),
                label: Text('Dark'),
              ),
            ],
            selected: {mode},
            onSelectionChanged: (selection) => onModeChanged(selection.first),
            showSelectedIcon: false,
          ),
          const SizedBox(width: AppSpacing.lg),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: const [
          _BrandHeader(),
          SizedBox(height: AppSpacing.xxl),
          _TokenSection(),
          _ButtonSection(),
          _StatusSection(),
          _CardAndPriceSection(),
          _TimelineSection(),
          _InputSection(),
          _FeedbackSection(),
          _EmptySection(),
          _GuidedFrameSection(),
        ],
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Paasel', style: AppTypography.displayMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'by theScaleOn · Scale Beyond Limits',
          style: AppTypography.body.copyWith(color: AppColors.ash),
        ),
      ],
    );
  }
}

class _TokenSection extends StatelessWidget {
  const _TokenSection();

  @override
  Widget build(BuildContext context) {
    const colors = <(String, Color)>[
      ('Ink', AppColors.ink),
      ('Paper', AppColors.paper),
      ('Gold', AppColors.gold),
      ('Graphite', AppColors.graphite),
      ('Cloud', AppColors.cloud),
      ('Ash', AppColors.ash),
      ('Success', AppColors.success),
      ('Warning', AppColors.warning),
      ('Danger', AppColors.danger),
    ];
    return _Section(
      title: 'Tokens',
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        children: [
          for (final token in colors)
            Column(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: token.$2,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(
                      color: AppColors.ash.withValues(alpha: 0.3),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(token.$1, style: AppTypography.caption),
              ],
            ),
        ],
      ),
    );
  }
}

class _ButtonSection extends StatelessWidget {
  const _ButtonSection();

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Actions',
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          PrimaryButton(label: 'Place order', onPressed: () {}),
          PrimaryButton(label: 'Loading', onPressed: () {}, loading: true),
          const PrimaryButton(label: 'Unavailable', onPressed: null),
          SecondaryButton(label: 'Track order', onPressed: () {}),
          SecondaryButton(label: 'Loading', onPressed: () {}, loading: true),
          const SecondaryButton(label: 'Unavailable', onPressed: null),
          TextActionButton(label: 'Change address', onPressed: () {}),
          const TextActionButton(label: 'Unavailable', onPressed: null),
        ],
      ),
    );
  }
}

class _StatusSection extends StatelessWidget {
  const _StatusSection();

  @override
  Widget build(BuildContext context) {
    return const _Section(
      title: 'Order status',
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          StatusBadge(status: StatusBadgeState.preparing),
          StatusBadge(status: StatusBadgeState.readyForPickup),
          StatusBadge(status: StatusBadgeState.outForDelivery),
          StatusBadge(status: StatusBadgeState.delivered),
          StatusBadge(status: StatusBadgeState.cancelled),
        ],
      ),
    );
  }
}

class _CardAndPriceSection extends StatelessWidget {
  const _CardAndPriceSection();

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Cards and prices',
      child: ScaleOnCard(
        elevation: 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your order', style: AppTypography.title),
            const SizedBox(height: AppSpacing.lg),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text('Paneer tikka bowl'), PriceText(amount: 249)],
            ),
            const SizedBox(height: AppSpacing.sm),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text('Delivery'), PriceText(amount: 0)],
            ),
            const Divider(height: AppSpacing.xl),
            const PriceText(amount: 329, originalAmount: 379, large: true),
          ],
        ),
      ),
    );
  }
}

class _TimelineSection extends StatelessWidget {
  const _TimelineSection();

  @override
  Widget build(BuildContext context) {
    return const _Section(
      title: 'Order timeline',
      child: ScaleOnCard(
        child: Column(
          children: [
            OrderTimelineTile(
              icon: Icons.receipt_long_outlined,
              label: 'Order placed',
              timestamp: '19:42',
              state: TimelineStepState.complete,
            ),
            OrderTimelineTile(
              icon: Icons.restaurant_outlined,
              label: 'Preparing your order',
              timestamp: '8 min',
              state: TimelineStepState.active,
            ),
            OrderTimelineTile(
              icon: Icons.delivery_dining_outlined,
              label: 'Out for delivery',
              state: TimelineStepState.pending,
              isLast: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _InputSection extends StatelessWidget {
  const _InputSection();

  @override
  Widget build(BuildContext context) {
    return const _Section(
      title: 'Inputs',
      child: Column(
        children: [
          AppTextField(
            label: 'Delivery instructions',
            hintText: 'e.g. Leave it with security',
            helperText: 'Help your rider find you faster',
            prefixIcon: Icon(Icons.notes_rounded),
          ),
          SizedBox(height: AppSpacing.lg),
          AppTextField(
            label: 'Phone number',
            hintText: '10-digit mobile number',
            errorText: 'Enter a valid 10-digit mobile number',
          ),
        ],
      ),
    );
  }
}

class _FeedbackSection extends StatelessWidget {
  const _FeedbackSection();

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Feedback and sheets',
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        children: [
          SecondaryButton(
            label: 'Show success',
            onPressed: () => AppSnackbar.show(
              context,
              message: 'Order placed',
              variant: AppSnackbarVariant.success,
            ),
          ),
          SecondaryButton(
            label: 'Show error',
            onPressed: () => AppSnackbar.show(
              context,
              message: 'Payment didn’t go through. Try another method.',
              variant: AppSnackbarVariant.error,
            ),
          ),
          PrimaryButton(
            label: 'Open bottom sheet',
            onPressed: () => AppBottomSheet.show<void>(
              context: context,
              builder: (context) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Confirm address', style: AppTypography.title),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '12 Residency Road, Bengaluru',
                    style: AppTypography.body.copyWith(color: AppColors.ash),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  PrimaryButton(
                    label: 'Deliver here',
                    onPressed: () => Navigator.of(context).pop(),
                    expand: true,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptySection extends StatelessWidget {
  const _EmptySection();

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Empty state',
      child: ScaleOnCard(
        child: EmptyStateView(
          icon: const Icon(Icons.shopping_bag_outlined),
          title: 'Your cart’s ready for something good',
          subtitle: 'Explore nearby shops and add your favourites.',
          actionLabel: 'Find nearby shops',
          onAction: () {},
        ),
      ),
    );
  }
}

class _GuidedFrameSection extends StatelessWidget {
  const _GuidedFrameSection();

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Guided capture overlay',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: SizedBox(
          height: 360,
          child: GuidedFrameOverlay(
            instruction: 'Place the package inside the frame',
            child: ColoredBox(
              color: AppColors.graphite,
              child: Center(
                child: Icon(
                  Icons.inventory_2_outlined,
                  size: 72,
                  color: AppColors.ash.withValues(alpha: 0.45),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.headline),
          const SizedBox(height: AppSpacing.lg),
          child,
        ],
      ),
    );
  }
}
