import test from 'node:test';
import assert from 'node:assert/strict';
import { governanceProposalFromRow } from '../cloudflare/src/governance-proposal.ts';
import fs from 'node:fs';

test('V5 proposal rows normalize into one canonical typed contract', () => {
  const proposal = governanceProposalFromRow({
    id: 'V5-GOV-1', title: 'Adopt a policy', body: 'A clear rationale.',
    subject_type: 'CORPORATION', subject_id: 'CORP-1', subject_name: 'Nova',
    action_type: 'CONSTITUTION_AMENDMENT', payload: { changes: [] }, status: 'VOTING',
    submitted_game_day: '10', voting_start_game_day: '11', voting_end_game_day: '15', effective_from_game_day: '20',
    electorate_size: '4', quorum_bps: '5000', quorum_required: 2, approval_bps: '6000',
    support_votes: '2', oppose_votes: '1', abstain_votes: '0', viewer_eligible: true, viewer_can_vote: true,
    viewer_voted: false, viewer_choice: null, governance_rule_snapshot: { votingPeriodDays: 5, implementationDelayDays: 4 },
  });

  assert.equal(proposal.identity.title, 'Adopt a policy');
  assert.equal(proposal.scope.subjectName, 'Nova');
  assert.equal(proposal.votes.uncast, 1);
  assert.equal(proposal.votes.participationBps, 7500);
  assert.equal(proposal.votes.decisiveApprovalBps, 6666);
  assert.equal(proposal.viewer.canVote, true);
  assert.equal(proposal.electorate.quorumRequired, 2);
});

test('V5 proposal impact remains structured and server-authored', () => {
  const proposal = governanceProposalFromRow({
    id: 'V5-GOV-IMPACT', subject_type: 'EARTH', action_type: 'CONSTITUTION_AMENDMENT',
    payload: { impact: { kind: 'CONSTITUTION_AMENDMENT', changes: [{ ruleCode: 'EARTH_HOUSE_CAPACITY_RATE', currentValue: '80', proposedValue: '100' }] } },
    status: 'VOTING', electorate_size: '1', support_votes: '0', oppose_votes: '0', abstain_votes: '0',
  });
  assert.equal(proposal.action.impact?.kind, 'CONSTITUTION_AMENDMENT');
  assert.equal((proposal.action.impact?.changes)[0].ruleCode, 'EARTH_HOUSE_CAPACITY_RATE');
});

test('Flutter governance API consumes the typed proposal model', () => {
  const api = fs.readFileSync('flutter_client/lib/core/api/earth_api_governance.dart', 'utf8');
  const panel = fs.readFileSync('flutter_client/lib/features/governance/governance_panels.dart', 'utf8');
  assert.match(api, /Future<List<GovernanceProposal>> listV5Proposals/);
  assert.match(panel, /List<GovernanceProposal> _proposals/);
  assert.doesNotMatch(panel, /support_votes|supportVotes|viewer_choice/);
  assert.match(panel, /PARTICIPATION/);
  assert.match(panel, /DECISIVE|APPROVAL/);
  assert.match(panel, /ACTION REQUIRED/);
  assert.match(panel, /PENDING VOTES/);
  assert.match(panel, /_proposalPriority/);
  assert.doesNotMatch(panel, /1 => 'WORLD'/);
});

test('V5 proposal eligibility is resolved from the frozen House electorate', () => {
  const service = fs.readFileSync('cloudflare/src/v5-governance-postgres.ts', 'utf8');
  assert.match(service, /v5_governance_electorate_snapshots_v5/);
  assert.match(service, /viewer_eligible/);
  assert.match(service, /viewer_can_vote/);
  assert.match(service, /p\.status = 'VOTING'/);
});

test('V5 proposal history and filters remain available', () => {
  const service = fs.readFileSync('cloudflare/src/v5-governance-postgres.ts', 'utf8');
  const routes = fs.readFileSync('cloudflare/src/governance-routes.ts', 'utf8');
  const api = fs.readFileSync('flutter_client/lib/core/api/earth_api_governance.dart', 'utf8');
  const panel = fs.readFileSync('flutter_client/lib/features/governance/governance_panels.dart', 'utf8');
  assert.match(service, /filters: \{ status\?: 'active' \| 'history'/);
  assert.match(service, /p\.status NOT IN \('VOTING','PASSED','SCHEDULED'\)/);
  assert.match(service, /executed_game_day/);
  assert.match(service, /v5_governance_activation_queue/);
  assert.match(routes, /url\.searchParams\.get\('status'\)/);
  assert.match(routes, /url\.searchParams\.get\('scope'\)/);
  assert.match(api, /listV5Proposals\(\{[\s\S]*String\? status/);
  assert.match(panel, /ACTION REQUIRED/);
  assert.match(panel, /HISTORY/);
  assert.match(panel, /EXECUTED|REJECTED/);
  assert.match(panel, /Executed day/);
});

test('V5 proposals expose server-authored impact before voting', () => {
  const service = fs.readFileSync('cloudflare/src/v5-governance-postgres.ts', 'utf8');
  const model = fs.readFileSync('flutter_client/lib/core/models/governance_proposal.dart', 'utf8');
  const panel = fs.readFileSync('flutter_client/lib/features/governance/governance_panels.dart', 'utf8');
  assert.match(service, /serverImpactSummary/);
  assert.match(service, /amendmentImpactSummary/);
  assert.match(service, /impactSummary: serverImpactSummary/);
  assert.match(service, /impact: toJsonSafe\(serverImpact\)/);
  assert.match(service, /COST \$\{creditImpact/);
  assert.match(model, /'impact_summary': impactSummary/);
  assert.match(model, /'impact': impact/);
  assert.match(panel, /ESTIMATED IMPACT/);
});

test('V5 governance exposes only Earth and the viewer House Corporation', () => {
  const service = fs.readFileSync('cloudflare/src/v5-governance-postgres.ts', 'utf8');
  const panelSource = fs.readFileSync('flutter_client/lib/features/governance/governance_panels.dart', 'utf8');
  const dashboard = fs.readFileSync('flutter_client/lib/features/command_center/dashboard.dart', 'utf8');
  const panel = panelSource.slice(panelSource.indexOf('class V5GovernancePanel'), panelSource.indexOf('class _ProposalTabContent'));
  assert.match(service, /p\.subject_type = 'EARTH'/);
  assert.match(service, /p\.subject_type = 'CORPORATION'/);
  assert.match(service, /house_affiliations/);
  assert.match(panel, /MY CORPORATION/);
  assert.match(panel, /'ALL'/);
  assert.match(panel, /if \(_hasCorporation\)/);
  assert.doesNotMatch(panel, /CITY|TERRITORY/);
  assert.doesNotMatch(panel, /legacyRules|legacyTaxRules/);
  assert.doesNotMatch(dashboard, /TabbedProposalPanel|PublicFinanceGovernancePanel|V5GovernanceReviewPanel/);
});

test('rules in force uses the V5 Constitution read model', () => {
  const source = fs.readFileSync('flutter_client/lib/features/governance/governance_panels.dart', 'utf8');
  const panel = source.slice(source.indexOf('class RulesInForcePanel'), source.length);
  const dashboard = fs.readFileSync('flutter_client/lib/features/command_center/dashboard.dart', 'utf8');
  assert.match(panel, /class RulesInForcePanel extends StatefulWidget/);
  assert.match(panel, /getV5Constitution/);
  assert.match(panel, /'MY CORPORATION'/);
  assert.match(panel, /'EARTH'/);
  assert.match(panel, /SOURCE \$source/);
  assert.match(panel, /EFFECTIVE DAY/);
  assert.match(panel, /effective_from_game_day/);
  const formatters = fs.readFileSync('flutter_client/lib/shared/widgets/format_helpers.dart', 'utf8');
  assert.match(formatters, /class ConstitutionValueFormatter/);
  assert.match(formatters, /case 'RATE_BPS'/);
  assert.match(formatters, /case 'CREDIT_UNITS'/);
  assert.match(formatters, /case 'PROGRESSIVE_SCHEDULE_REF'/);
  assert.doesNotMatch(panel, /minimum_rate_bps|maximum_rate_bps|rule\['category'\]|rule\['rate'\]/);
  assert.match(dashboard, /case 'public-finance':[\s\S]{0,120}RulesInForcePanel/);
});
