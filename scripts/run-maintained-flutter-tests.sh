#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT_DIR}/flutter_client"

flutter test \
  test/account_screen_test.dart \
  test/activity_panel_test.dart \
  test/archive_page_test.dart \
  test/buildings_hub_screen_test.dart \
  test/comm_link_dialog_test.dart \
  test/command_center_screen_test.dart \
  test/communities_panel_test.dart \
  test/constitution_panel_test.dart \
  test/daily_summary_test.dart \
  test/dashboard_and_command_center_test.dart \
  test/decision_queue_test.dart \
  test/house_tree_dialog_test.dart \
  test/institutions_capacity_panel_test.dart \
  test/live_connection_fallback_test.dart \
  test/net_worth_analytics_test.dart \
  test/onboarding_test.dart \
  test/personal_finance_panel_test.dart \
  test/technology_panel_test.dart \
  test/top_fixed_hud_panel_test.dart \
  test/world_conditions_panel_test.dart \
  test/world_rankings_panel_test.dart
