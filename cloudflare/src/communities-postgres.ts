import type { PostgresRepository } from './repository.ts';

const unavailable = { ok: false, error: 'Communities are not enabled in the baseline world' };
export async function listCommunities(): Promise<Record<string, unknown>> { return { ok: true, communities: [] }; }
export async function listCommunityMembers(): Promise<Record<string, unknown>> { return { ok: true, members: [] }; }
export async function listCommunityMembershipRequests(): Promise<Record<string, unknown>> { return { ok: true, requests: [] }; }
export async function listCommunityContributions(): Promise<Record<string, unknown>> { return { ok: true, contributions: [] }; }
export async function createCommunity(): Promise<Record<string, unknown>> { return unavailable; }
export async function updateCommunity(): Promise<Record<string, unknown>> { return unavailable; }
export async function changeCommunityMembership(): Promise<Record<string, unknown>> { return unavailable; }
export async function decideCommunityMembershipRequest(): Promise<Record<string, unknown>> { return unavailable; }
export async function setCommunityMemberRole(): Promise<Record<string, unknown>> { return unavailable; }
export async function disbandCommunity(): Promise<Record<string, unknown>> { return unavailable; }
export async function contributeToCommunity(_repository: PostgresRepository): Promise<Record<string, unknown>> { return unavailable; }
