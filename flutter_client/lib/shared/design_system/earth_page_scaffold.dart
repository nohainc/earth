import 'package:flutter/material.dart';
import 'earth_theme_context.dart';
import 'earth_empty_state.dart';

/// Standardized responsive page scaffold & rendering engine for all Earth feature pages.
class EarthPageScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget>? headerPills;
  final Widget? headerAction;
  final String? infoDescription;
  final List<String>? infoBulletPoints;
  final List<Widget> primaryColumn;
  final List<Widget> secondaryColumn;
  final bool isLoading;
  final String? error;
  final String? successMessage;
  final VoidCallback? onDismissAlert;
  final bool isPageMode;
  final double? dialogWidth;
  final double? dialogHeight;

  const EarthPageScaffold({
    super.key,
    required this.title,
    this.subtitle,
    this.headerPills,
    this.headerAction,
    this.infoDescription,
    this.infoBulletPoints,
    required this.primaryColumn,
    this.secondaryColumn = const [],
    this.isLoading = false,
    this.error,
    this.successMessage,
    this.onDismissAlert,
    this.isPageMode = true,
    this.dialogWidth,
    this.dialogHeight,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading && primaryColumn.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(context.spacingPage),
          child: CircularProgressIndicator(color: context.primaryColor),
        ),
      );
    }

    final header = _buildHeader(context);

    final alertBanner = error != null
        ? EarthAlertBanner(
            message: error!,
            isError: true,
            onClose: onDismissAlert,
          )
        : (successMessage != null
            ? EarthAlertBanner(
                message: successMessage!,
                isError: false,
                onClose: onDismissAlert,
              )
            : null);

    final pageBody = LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth > 1000 && secondaryColumn.isNotEmpty;

        if (isDesktop) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _joinWithSpacing(primaryColumn, context.spacingSection),
                ),
              ),
              const SizedBox(width: 56),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _joinWithSpacing(secondaryColumn, context.spacingSection),
                ),
              ),
            ],
          );
        }

        final combined = [...primaryColumn, ...secondaryColumn];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _joinWithSpacing(combined, context.spacingSection),
        );
      },
    );

    if (isPageMode) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (header != null) header,
          if (alertBanner != null) alertBanner,
          pageBody,
        ],
      );
    }

    // Dialog mode wrapper
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.all(context.spacingTitleOffset),
      child: Container(
        width: dialogWidth ?? 1060,
        height: dialogHeight ?? 740,
        decoration: BoxDecoration(
          color: context.canvasColor,
          borderRadius: BorderRadius.circular(context.radiusPanel),
          border: Border.all(color: context.primaryColor.withValues(alpha: .35)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .85),
              blurRadius: 36,
              spreadRadius: 8,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(context.radiusPanel),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (header != null) header,
              if (alertBanner != null) alertBanner,
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(context.spacingTopic),
                  child: pageBody,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _buildHeader(BuildContext context) {
    if (title.isEmpty && subtitle == null && headerPills == null && headerAction == null) {
      return null;
    }

    return Container(
      padding: isPageMode
          ? EdgeInsets.only(bottom: context.spacingTitleOffset)
          : EdgeInsets.symmetric(
              horizontal: context.spacingTopic,
              vertical: context.spacingTitleOffset,
            ),
      decoration: BoxDecoration(
        color: isPageMode ? Colors.transparent : context.surfaceColor,
        border: isPageMode
            ? null
            : Border(bottom: BorderSide(color: context.subtleBorderColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  title.toUpperCase(),
                  style: context.pageTitleStyle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (headerAction != null) ...[
                SizedBox(width: context.spacingInline),
                headerAction!,
              ],
            ],
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: context.topicTitleStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (headerPills != null && headerPills!.isNotEmpty) ...[
            SizedBox(height: context.spacingControl),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: _joinWithSpacing(headerPills!, context.spacingInline),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _joinWithSpacing(List<Widget> items, double spacing) {
    if (items.isEmpty) return [];
    final list = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      list.add(items[i]);
      if (i < items.length - 1) {
        list.add(SizedBox(height: spacing));
      }
    }
    return list;
  }
}
