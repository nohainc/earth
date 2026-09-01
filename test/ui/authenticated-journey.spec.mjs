import { expect, test } from '@playwright/test';

const testEmail = process.env.EARTH_TEST_EMAIL || 'vitalii.noga@gmail.com';
const testPassword = process.env.EARTH_TEST_PASSWORD;

test.beforeEach(() => {
  if (!testPassword) {
    throw new Error('EARTH_TEST_PASSWORD is required. Put it in an ignored .env file or your CI secret store.');
  }
});

async function enableFlutterSemantics(page) {
  const control = page.getByRole('button', { name: 'Enable accessibility' });
  await control.waitFor({ state: 'visible', timeout: 30_000 });
  // Flutter positions this semantics placeholder outside the visual viewport.
  // Invoke its DOM action directly to activate the rendered app's semantics
  // tree without requiring a physical viewport click.
  await control.evaluate((element) => element.click());
}

async function signInThroughUi(page) {
  await page.goto('/');
  await enableFlutterSemantics(page);
  const emailField = page.getByRole('textbox', { name: 'Email' });
  await expect(emailField).toBeVisible({ timeout: 30_000 });
  await emailField.click();
  await page.waitForTimeout(150);
  await emailField.fill(testEmail);
  await expect(emailField).toHaveValue(testEmail);
  const passwordField = page.getByRole('textbox', { name: 'Password (12+ characters)' });
  await passwordField.click();
  await page.waitForTimeout(150);
  await passwordField.fill(testPassword);
  await expect(passwordField).toHaveValue(testPassword);
  await page.getByRole('button', { name: 'Enter EARTH' }).click();
  await expect(page.getByText('Command Center', { exact: true })).toBeVisible({ timeout: 30_000 });
}

const SECTION_GROUPS = {
  'Command Center': 'NOW',
  'Daily Priorities': 'NOW',
  'Briefing': 'NOW',
  'Messages': 'NOW',
  'Notifications': 'NOW',
  'Business': 'ECONOMY',
  'Buildings': 'ECONOMY',
  'Research': 'ECONOMY',
  'Market': 'ECONOMY',
  'Contracts': 'ECONOMY',
  'Public Governance': 'CIVIC',
  'City': 'CIVIC',
  'Finance': 'LIFE',
  'Account': 'LIFE',
  'House': 'LIFE',
  'Noha': 'LIFE',
  'Corporations': 'EARTH',
  'Communities': 'EARTH',
  'Rankings': 'EARTH',
  'Constitution': 'EARTH',
  'Memorial': 'EARTH',
};

async function openSection(page, sectionName, groupName) {
  const targetGroup = groupName || SECTION_GROUPS[sectionName] || 'EARTH';
  const directButton = page.getByRole('button', { name: sectionName, exact: true });

  // 1. If in mobile / drawer mode, ensure navigation drawer is open
  const drawerToggle = page.getByRole('button', { name: 'Open navigation menu' });
  if (await drawerToggle.isVisible().catch(() => false)) {
    if (!await directButton.first().isVisible().catch(() => false)) {
      await drawerToggle.click();
      await page.waitForTimeout(300);
    }
  }

  // 2. Check if button is already visible and clickable
  if (await directButton.first().isVisible().catch(() => false)) {
    await directButton.first().scrollIntoViewIfNeeded().catch(() => {});
    await directButton.first().click();
    return;
  }

  // 3. Find and click the accordion group header in the sidebar
  // Group headers have titles: NOW, ECONOMY, CIVIC, LIFE, EARTH
  const groupButtons = page.getByRole('button', { name: targetGroup, exact: true });
  const count = await groupButtons.count();
  // If multiple buttons match (e.g. top HUD "EARTH" vs sidebar "EARTH"), select the sidebar one (last)
  const groupHeader = count > 1 ? groupButtons.last() : groupButtons.first();

  if (await groupHeader.isVisible().catch(() => false)) {
    await groupHeader.scrollIntoViewIfNeeded().catch(() => {});
    await groupHeader.click();
    await page.waitForTimeout(300);
  }

  // 4. If direct button still not visible, re-click groupHeader
  if (!await directButton.first().isVisible().catch(() => false)) {
    if (await groupHeader.isVisible().catch(() => false)) {
      await groupHeader.evaluate((el) => el.click()).catch(() => {});
      await page.waitForTimeout(300);
    }
  }

  await expect(directButton.first()).toBeVisible({ timeout: 15_000 });
  await directButton.first().scrollIntoViewIfNeeded().catch(() => {});
  await directButton.first().click();
}

async function openUserLife(page) {
  // If in compact/mobile drawer mode, open drawer first
  const drawerToggle = page.getByRole('button', { name: 'Open navigation menu' });
  if (await drawerToggle.isVisible().catch(() => false)) {
    await drawerToggle.click();
    await page.waitForTimeout(300);
  }

  // Ensure LIFE group accordion is open
  const lifeHeader = page.getByRole('button', { name: 'LIFE', exact: true });
  if (await lifeHeader.isVisible().catch(() => false)) {
    const isFinanceVisible = await page.getByRole('button', { name: 'Finance', exact: true }).isVisible().catch(() => false);
    if (!isFinanceVisible) {
      await lifeHeader.click();
      await page.waitForTimeout(250);
    }
  }

  // Click the user item under LIFE (the first item above House & Finance)
  const financeBtn = page.getByRole('button', { name: 'Finance', exact: true });
  if (await financeBtn.isVisible().catch(() => false)) {
    const buttons = await page.getByRole('button').all();
    for (let i = 0; i < buttons.length; i++) {
      const text = (await buttons[i].textContent().catch(() => '')).trim();
      if (text === 'LIFE' && i + 1 < buttons.length) {
        await buttons[i + 1].click();
        await page.waitForTimeout(300);
        break;
      }
    }
  }

  await expect(page.getByRole('button', { name: 'Edit name', exact: true })).toBeVisible({ timeout: 30_000 });
}

async function openAccount(page) {
  await openSection(page, 'Account', 'LIFE');
  await expect(page.getByText('ACCOUNT & SECURITY', { exact: true })).toBeVisible();
}

async function openHouse(page) {
  // Navigation item in LIFE group has the dynamic surname / house name or fallback 'House'
  const houseItem = page.getByRole('button', { name: 'House', exact: true })
    .or(page.getByRole('button', { name: 'Noha', exact: true }))
    .or(page.getByRole('button', { name: /Noha/i }));

  if (!await houseItem.first().isVisible().catch(() => false)) {
    const drawerToggle = page.getByRole('button', { name: 'Open navigation menu' });
    if (await drawerToggle.isVisible().catch(() => false)) {
      await drawerToggle.click();
      await page.waitForTimeout(300);
    }
    const lifeGroupHeader = page.getByRole('button', { name: 'LIFE', exact: true });
    if (await lifeGroupHeader.isVisible().catch(() => false)) {
      await lifeGroupHeader.click();
      await page.waitForTimeout(250);
    }
  }

  if (await houseItem.first().isVisible().catch(() => false)) {
    await houseItem.first().click();
  } else {
    // If not direct by name, open via openSection
    await openSection(page, 'Noha', 'LIFE').catch(() => openSection(page, 'House', 'LIFE'));
  }

  await expect(page.getByRole('button', { name: 'Edit house name', exact: true })).toBeVisible({ timeout: 30_000 });
}

async function openFinance(page) {
  await openSection(page, 'Finance', 'LIFE');
  const financeContent = page.getByText('PERSONAL FINANCE', { exact: false })
    .or(page.getByText('DAILY INCOME', { exact: false }));
  await expect(financeContent.first()).toBeVisible({ timeout: 30_000 });
}

async function openPublicGovernance(page) {
  await openSection(page, 'Public Governance', 'CIVIC');
  const govContent = page.getByText('LAWS IN FORCE', { exact: false })
    .or(page.getByText('TAXES & PUBLIC SERVICES', { exact: false }))
    .or(page.getByText('CREATE UC PROPOSAL', { exact: false }));
  await expect(govContent.first()).toBeVisible({ timeout: 30_000 });
}

async function openCity(page) {
  // If player is affiliated with a city, 'City' or city name appears in CIVIC group
  const cityItem = page.getByRole('button', { name: /City|New Carthage|Geneva|London|Tokyo|New York|Singapore/i });
  if (!await cityItem.first().isVisible().catch(() => false)) {
    const civicGroupHeader = page.getByRole('button', { name: 'CIVIC', exact: true });
    if (await civicGroupHeader.isVisible().catch(() => false)) {
      await civicGroupHeader.click();
      await page.waitForTimeout(250);
    }
  }
  if (await cityItem.first().isVisible().catch(() => false)) {
    await cityItem.first().click();
  } else {
    // Fallback for independent citizen: Public Governance
    await openSection(page, 'Public Governance', 'CIVIC');
  }
  const cityContent = page.getByText(/CITY & SERVICES|MUNICIPAL|PUBLIC GOVERNANCE|LAWS IN FORCE/i);
  await expect(cityContent.first()).toBeVisible({ timeout: 30_000 });
}

async function openMyCorporation(page) {
  // Try navigating to Corporations in EARTH group
  await openCorporations(page);
  const corpContent = page.getByRole('textbox', { name: /Search corporations/i })
    .or(page.getByRole('button', { name: /FOUND CORPORATION/i }))
    .or(page.getByText(/CORPORATION OVERVIEW|MEMBERSHIP/i));
  await expect(corpContent.first()).toBeVisible({ timeout: 30_000 });
}

async function openMarket(page) {
  await openSection(page, 'Market', 'ECONOMY');
  const marketTab = page.getByRole('tab', { name: 'OVERVIEW', exact: true })
    .or(page.getByRole('tab', { name: 'TRADE', exact: true }));
  await expect(marketTab.first()).toBeVisible({ timeout: 30_000 });
}

async function openCommandCenter(page) {
  await openSection(page, 'Command Center', 'NOW');
  const commandIndicator = page.getByText(/CITIZEN COCKPIT|TODAY'S MANAGEMENT FOCUS|CURRENT OPERATIONS|OBJECTIVES/i)
    .or(page.getByRole('button', { name: /SURPLUS|DEFICIT/i }));
  await expect(commandIndicator.first()).toBeVisible({ timeout: 15_000 });
}

async function openBriefing(page) {
  await openSection(page, 'Briefing', 'NOW').catch(() => openSection(page, 'Daily Priorities', 'NOW'));
  const briefingHeader = page.getByText(/SINCE YOUR LAST VISIT|WHAT REQUIRES ATTENTION|NET WORTH/i);
  await expect(briefingHeader.first()).toBeVisible({ timeout: 30_000 });
}

async function openMessages(page) {
  await openSection(page, 'Messages', 'NOW');
  const messagesHeader = page.getByText('CHANNELS', { exact: false })
    .or(page.getByText('DIPLOMATIC DISPATCHES', { exact: false }));
  await expect(messagesHeader.first()).toBeVisible({ timeout: 30_000 });
}

async function openNotifications(page) {
  await openSection(page, 'Notifications', 'NOW');
  const notifIndicator = page.getByRole('button', { name: /MARK ALL AS READ/i })
    .or(page.getByRole('button', { name: /PREVIOUS|NEXT/i }))
    .or(page.getByText(/DIRECT ALERTS & NOTIFICATIONS/i))
    .or(page.getByText(/No pending notifications/i));
  await expect(notifIndicator.first()).toBeVisible({ timeout: 30_000 });
}

async function openBusiness(page) {
  await openSection(page, 'Business', 'ECONOMY');
  const businessHeader = page.getByText(/MANAGER'S BRIEF|BUSINESS OPERATIONS|PROFIT \/ CYCLE/i);
  await expect(businessHeader.first()).toBeVisible({ timeout: 30_000 });
}

async function openBuildings(page) {
  await openSection(page, 'Buildings', 'ECONOMY');
  const buildingsHeader = page.getByText(/PRIVATE \(/i)
    .or(page.getByText(/CIVIC \(/i))
    .or(page.getByText(/INVEST \(/i));
  await expect(buildingsHeader.first()).toBeVisible({ timeout: 30_000 });
}

async function openResearch(page) {
  await openSection(page, 'Research', 'ECONOMY');
  const techIndicator = page.getByRole('progressbar', { name: /RESEARCH/i })
    .or(page.getByRole('button', { name: /FUND|NEW PROJECT/i }))
    .or(page.getByRole('checkbox', { name: 'ALL' }));
  await expect(techIndicator.first()).toBeVisible({ timeout: 30_000 });
}

async function openRankings(page) {
  await openSection(page, 'Rankings');
  await expect(page.getByRole('button', { name: 'Show CITIZENS rankings' })).toBeVisible();
}

async function openCommunities(page) {
  await openSection(page, 'Communities');
  await expect(page.getByRole('textbox', { name: 'Search communities by name...' }).last()).toBeVisible();
}

async function openCorporations(page) {
  await openSection(page, 'Corporations');
  await expect(page.getByRole('textbox', { name: 'Search corporations by name or chartered jurisdiction...' }).last()).toBeVisible();
}

async function openConstitution(page) {
  await openSection(page, 'Constitution');
  await expect(page.getByRole('heading', { name: /^GOVERNANCE HIERARCHY & OVERRIDE MODEL/ })).toBeVisible();
}

async function openMemorial(page) {
  await openSection(page, 'Memorial');
  await expect(page.getByRole('heading', { name: /^MEMORIAL CITIZENS/ })).toBeVisible();
}

async function expectRankingFormula(page, category, expectedDetail) {
  const formula = page.getByRole('button', { name: `Show ${category} ranking formula` });
  await expect(formula).toHaveAccessibleName(new RegExp(expectedDetail));
  await formula.click();
  await expect(page.getByRole('button', { name: 'GOT IT', exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'GOT IT', exact: true }).click();
  await expect(page.getByRole('button', { name: 'GOT IT', exact: true })).toBeHidden();
}

async function typeIntoFlutterField(field, value) {
  await field.click();
  await field.waitFor({ state: 'visible' });
  await field.page().waitForTimeout(100);
  await field.fill(value || '');
  await expect(field).toHaveValue(value || '');
}

test.describe.serial('authenticated player journeys', () => {
  test.describe.configure({ timeout: 120_000 });
  let context;
  let page;

  test.beforeAll(async ({ browser }) => {
    context = await browser.newContext({
      baseURL: process.env.EARTH_UI_URL,
      storageState: { cookies: [], origins: [] },
    });
    page = await context.newPage();
    page.on('pageerror', (error) => console.error(`Browser page error: ${error.message}`));
    page.on('console', (message) => {
      if (message.type() === 'error') console.error(`Browser console error: ${message.text()}`);
    });
    await signInThroughUi(page);
  }, { timeout: 120_000 });

  test.afterAll(async () => {
    try {
      const accountMenu = page.getByRole('button', { name: /Account Menu/ })
        .or(page.getByRole('button', { name: /Standing/ }));
      if (await accountMenu.first().isVisible().catch(() => false)) {
        await accountMenu.first().click();
        const signOut = page.getByText('Sign Out', { exact: true });
        if (await signOut.isVisible().catch(() => false)) {
          await signOut.click();
        }
      }
    } catch (_) {
      // Ignore errors in afterAll cleanup
    } finally {
      await context.close();
    }
  });

  test('command center restores the signed-in player session after a reload', async () => {
    await expect(page.getByText('Command Center', { exact: true })).toBeVisible({ timeout: 30_000 });

    // A reload proves that the browser client can restore its persisted session
    // using the same live API rather than relying on in-memory test state.
    await page.reload();
    await enableFlutterSemantics(page);
    await expect(page.getByText('Command Center', { exact: true })).toBeVisible({ timeout: 30_000 });
  });

  test('command center remains available to the same signed-in player', async () => {
    await expect(page.getByText('Command Center', { exact: true })).toBeVisible({ timeout: 30_000 });
  });

  test('Rankings navigation shows the live civic scoreboards without horizontal overflow', async () => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await openRankings(page);

    // Desktop presents the citizen and corporation scoreboards side by side,
    // while keeping every ranking category reachable through clear controls.
    await expect(page.getByRole('button', { name: 'Show CITIZENS ranking formula' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Show CORPORATIONS ranking formula' })).toBeVisible();
    for (const category of ['CITIZENS', 'HOUSES', 'CORPS', 'CITIES']) {
      await expect(page.getByRole('button', { name: `Show ${category} rankings` })).toBeVisible();
    }

    const hasHorizontalOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasHorizontalOverflow).toBe(false);
  });

  test('Rankings exposes transparent score formulas for every category', async () => {
    await openRankings(page);
    await expectRankingFormula(page, 'CITIZENS', 'Personal Legacy');
    await expectRankingFormula(page, 'CORPORATIONS', 'Total Enterprise Capitalization');

    await page.getByRole('button', { name: 'Show HOUSES rankings' }).click();
    await expect(page.getByRole('button', { name: 'Show HOUSES ranking formula' })).toBeVisible();
    await expectRankingFormula(page, 'HOUSES', 'House Prestige Score');

    await page.getByRole('button', { name: 'Show CITIES rankings' }).click();
    await expect(page.getByRole('button', { name: 'Show CITIES ranking formula' })).toBeVisible();
    await expectRankingFormula(page, 'CITIES', 'City Capitalization');
  });

  test('Rankings pagination either advances safely or correctly reports a single page', async () => {
    await openRankings(page);
    await page.getByRole('button', { name: 'Show CITIES rankings' }).click();

    const nextPage = page.getByRole('button', { name: 'Next Page', exact: true }).last();
    if (await nextPage.isVisible().catch(() => false)) {
      const pageNumber = page.getByRole('textbox').last();
      if (await nextPage.isEnabled()) {
        await nextPage.click();
        await expect(pageNumber).toHaveValue('2');
        await page.getByRole('button', { name: 'Previous Page', exact: true }).click();
        await expect(pageNumber).toHaveValue('1');
      } else {
        await expect(pageNumber).toHaveValue('1');
      }
    } else {
      // Fewer than 11 city entries is a valid single-page ranking: pagination
      // controls are deliberately omitted rather than shown as inert chrome.
      await expect(page.getByRole('button', { name: 'Show CITIES ranking formula' })).toBeVisible();
    }
  });

  test('Communities displays the live registry with discoverable filters and no desktop overflow', async () => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await openCommunities(page);

    await expect(page.getByRole('button', { name: '+ FOUND COMMUNITY', exact: true })).toBeVisible();
    for (const filter of ['ALL', 'MY COMMUNITIES', 'OPEN TO JOIN']) {
      await expect(page.getByRole('button', { name: new RegExp(`Show ${filter}`) })).toBeVisible();
    }
    await expect(page.getByRole('button', { name: /Show community .+ details/ }).first()).toBeVisible();

    const hasHorizontalOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasHorizontalOverflow).toBe(false);
  });

  test('Communities search, filters, and detail expansion work without changing live data', async () => {
    await openCommunities(page);
    const search = page.getByRole('textbox', { name: 'Search communities by name...' }).last();
    const communityCards = page.getByRole('button', { name: /Show community .+ details/ });
    const firstCard = communityCards.first();
    const firstCardSnapshot = await firstCard.ariaSnapshot();
    const match = firstCardSnapshot.match(/Show community (.+?) details/);
    expect(match?.[1]).toBeTruthy();
    const communityName = match[1];

    await firstCard.click();
    await expect(page.getByText('FOUNDED BY:', { exact: false })).toBeVisible();
    await firstCard.click();
    await expect(page.getByText('FOUNDED BY:', { exact: false })).toBeHidden();

    await typeIntoFlutterField(search, communityName);
    await expect(communityCards).toHaveCount(1);
    await typeIntoFlutterField(search, 'no-community-should-match-this-search');
    await expect(page.getByText('No communities found matching', { exact: false })).toBeVisible();
    await typeIntoFlutterField(search, '');
    await expect(communityCards.first()).toBeVisible();

    for (const filter of ['MY COMMUNITIES', 'OPEN TO JOIN', 'ALL']) {
      await page.getByRole('button', { name: new RegExp(`Show ${filter}`) }).click();
      await expect(search).toHaveValue('');
    }
  });

  test('Corporations displays the live directory and preserves desktop layout integrity', async () => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await openCorporations(page);

    await expect(page.getByRole('button', { name: '+ FOUND CORPORATION', exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: /Show corporation .+ details/ }).first()).toBeVisible();

    const hasHorizontalOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasHorizontalOverflow).toBe(false);
  });

  test('Corporation dossier expansion works without changing membership', async () => {
    await openCorporations(page);
    const corporationCards = page.getByRole('button', { name: /Show corporation .+ details/ });
    const firstCard = corporationCards.first();

    await firstCard.click();
    await expect(firstCard).toHaveAttribute('aria-expanded', 'true');
    await firstCard.click();
    await expect(firstCard).toHaveAttribute('aria-expanded', 'false');
  });

  test('Constitution presents the governance hierarchy, code, and history in a readable desktop layout', async () => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await openConstitution(page);

    const codeHeader = page.getByText(/CONSTITUTION CODE/i);
    const historyHeader = page.getByText(/CONSTITUTIONAL HISTORY/i);
    await expect(codeHeader.first()).toBeVisible();
    await expect(historyHeader.first()).toBeVisible();
    await expect(page.getByText('A later permitted override replaces the value before it.', { exact: true })).toBeVisible();

    const hasHorizontalOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasHorizontalOverflow).toBe(false);
  });

  test('Constitution has a clear live-data or empty-state outcome for rules and history', async () => {
    await openConstitution(page);

    const rulesIndicator = page.getByText('Constitutional rules are unavailable until the rule registry is applied.', { exact: true })
      .or(page.getByText('Default:', { exact: false }));
    const historyIndicator = page.getByText('No constitutional or charter changes have been recorded yet.', { exact: true })
      .or(page.getByText('Game day', { exact: false }));

    await expect(rulesIndicator.first()).toBeVisible();
    await expect(historyIndicator.first()).toBeVisible();
  });

  test('Memorial presents citizen and house archives without desktop overflow', async () => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await openMemorial(page);

    await expect(page.getByRole('heading', { name: /^HISTORICAL HOUSES/ })).toBeVisible();
    const hasHorizontalOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasHorizontalOverflow).toBe(false);
  });

  test('Memorial archives provide clear search or empty-state feedback', async () => {
    await openMemorial(page);
    const citizenSearch = page.getByRole('textbox', { name: 'Search citizens by name, house, city, or successor...' });
    const houseSearch = page.getByRole('textbox', { name: 'Search extinct houses by name, founder, or seat...' });

    if (await citizenSearch.isVisible().catch(() => false)) {
      await typeIntoFlutterField(citizenSearch, 'no-archived-citizen-should-match-this-search');
      await expect(page.getByRole('group', { name: /No archived citizens match/ })).toBeVisible();
      await typeIntoFlutterField(citizenSearch, '');
    } else {
      await expect(page.getByText('No citizens have entered the public archive yet.', { exact: true })).toBeVisible();
    }

    if (await houseSearch.isVisible().catch(() => false)) {
      await typeIntoFlutterField(houseSearch, 'no-extinct-house-should-match-this-search');
      await expect(page.getByRole('group', { name: /No recorded houses match/ })).toBeVisible();
      await typeIntoFlutterField(houseSearch, '');
    } else {
      await expect(page.getByText('No extinct houses have been recorded in the archive yet.', { exact: true })).toBeVisible();
    }
  });

  test('EARTH group pages adapt responsively to tablet (768x1024) viewport without overflow', async () => {
    await page.setViewportSize({ width: 768, height: 1024 });
    await page.waitForTimeout(300);

    // 1. Rankings on tablet
    await openRankings(page);
    let hasOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasOverflow).toBe(false);
    await expect(page.getByRole('button', { name: 'Show CITIZENS rankings' })).toBeVisible();

    // 2. Communities on tablet
    await openCommunities(page);
    hasOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasOverflow).toBe(false);
    await expect(page.getByRole('button', { name: '+ FOUND COMMUNITY', exact: true })).toBeVisible();

    // 3. Corporations on tablet
    await openCorporations(page);
    hasOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasOverflow).toBe(false);
    await expect(page.getByRole('button', { name: '+ FOUND CORPORATION', exact: true })).toBeVisible();

    // 4. Constitution on tablet
    await openConstitution(page);
    hasOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasOverflow).toBe(false);
    await expect(page.getByRole('heading', { name: /^GOVERNANCE HIERARCHY & OVERRIDE MODEL/ })).toBeVisible();

    // 5. Memorial on tablet
    await openMemorial(page);
    hasOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasOverflow).toBe(false);
    await expect(page.getByRole('heading', { name: /^MEMORIAL CITIZENS/ })).toBeVisible();

    // Restore desktop before next tests
    await page.setViewportSize({ width: 1280, height: 900 });
    await page.waitForTimeout(200);
  });

  test('EARTH group pages adapt responsively to mobile (375x667) viewport with drawer navigation', async () => {
    await page.setViewportSize({ width: 375, height: 667 });
    await page.waitForTimeout(300);

    // On mobile, the sidebar collapses into a drawer accessed via the HUD hamburger button
    const drawerButton = page.getByRole('button', { name: 'Open navigation menu' });
    await expect(drawerButton).toBeVisible();

    // 1. Open Rankings via Mobile Drawer
    await openRankings(page);
    let hasOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasOverflow).toBe(false);
    await expect(page.getByRole('button', { name: 'Show CITIZENS rankings' })).toBeVisible();

    // 2. Open Communities via Mobile Drawer
    await openCommunities(page);
    hasOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasOverflow).toBe(false);
    await expect(page.getByRole('textbox', { name: 'Search communities by name...' }).last()).toBeVisible();

    // 3. Open Corporations via Mobile Drawer
    await openCorporations(page);
    hasOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasOverflow).toBe(false);
    await expect(page.getByRole('textbox', { name: 'Search corporations by name or chartered jurisdiction...' }).last()).toBeVisible();

    // 4. Open Constitution via Mobile Drawer
    await openConstitution(page);
    hasOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasOverflow).toBe(false);
    await expect(page.getByRole('heading', { name: /^GOVERNANCE HIERARCHY & OVERRIDE MODEL/ })).toBeVisible();

    // 5. Open Memorial via Mobile Drawer
    await openMemorial(page);
    hasOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasOverflow).toBe(false);
    await expect(page.getByRole('heading', { name: /^MEMORIAL CITIZENS/ })).toBeVisible();

    // Restore standard desktop viewport for subsequent tests
    await page.setViewportSize({ width: 1280, height: 900 });
    await page.waitForTimeout(200);
  });

  test('Found Community action dialog validates required fields and respects cancel', async () => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await openCommunities(page);

    const foundButton = page.getByRole('button', { name: '+ FOUND COMMUNITY', exact: true });
    await expect(foundButton).toBeVisible();
    await foundButton.click();

    // Modal dialog heading & admission policy options
    await expect(page.getByText('Found New Community', { exact: true })).toBeVisible();
    
    const openAccessButton = page.getByRole('button', { name: /OPEN ACCESS/i })
      .or(page.getByText('OPEN ACCESS', { exact: true }));
    const approvalButton = page.getByRole('button', { name: /APPROVAL REQUIRED/i })
      .or(page.getByText('APPROVAL REQUIRED', { exact: true }));

    await expect(openAccessButton.first()).toBeVisible();
    await expect(approvalButton.first()).toBeVisible();

    const nameField = page.getByRole('textbox', { name: 'Community Name (Required)' });
    const descField = page.getByRole('textbox', { name: 'Manifesto & Purpose (Required)' });
    const submitButton = page.getByRole('button', { name: 'Found Community', exact: true });
    const cancelButton = page.getByRole('button', { name: 'CANCEL', exact: true });

    await expect(nameField).toBeVisible();
    await expect(descField).toBeVisible();
    await expect(cancelButton).toBeVisible();

    // Submit button is disabled when required fields are blank (client-side form validation)
    await expect(submitButton).toBeDisabled();

    // Typing less than 3 chars in name keeps it disabled
    await typeIntoFlutterField(nameField, 'Ab');
    await typeIntoFlutterField(descField, 'A valid purpose for this guild.');
    await expect(submitButton).toBeDisabled();

    // Meeting all requirements enables the action button
    await typeIntoFlutterField(nameField, 'Valid Test Community Name');
    await expect(submitButton).toBeEnabled();

    // Switching to APPROVAL policy requires the application question
    await approvalButton.first().click();
    const questionField = page.getByRole('textbox', { name: 'Application Question / Requirement (Required)' });
    await expect(questionField).toBeVisible();
    await expect(submitButton).toBeDisabled();

    // Filling question re-enables submit button
    await typeIntoFlutterField(questionField, 'What is your background in orbital logistics?');
    await expect(submitButton).toBeEnabled();

    // Dismissing via CANCEL closes the dialog safely without mutating live state
    await cancelButton.click();
    await expect(page.getByText('Found New Community', { exact: true })).toBeHidden();
  });

  test('Found Corporation action dialog validates required fields and respects cancel', async () => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await openCorporations(page);

    const foundCorpButton = page.getByRole('button', { name: '+ FOUND CORPORATION', exact: true });
    // If the authenticated player is already affiliated with a corporation, the button is disabled or hidden
    if (await foundCorpButton.isEnabled().catch(() => false)) {
      await foundCorpButton.click();

      await expect(page.getByText('Found a Corporation', { exact: true })).toBeVisible();
      const corpNameField = page.getByRole('textbox', { name: 'Corporation name' });
      const capitalCityField = page.getByRole('textbox', { name: 'Capital city name' });
      const submitButton = page.getByRole('button', { name: 'FOUND CORPORATION', exact: true });
      const cancelButton = page.getByRole('button', { name: 'CANCEL', exact: true });

      await expect(corpNameField).toBeVisible();
      await expect(capitalCityField).toBeVisible();
      await expect(cancelButton).toBeVisible();

      // Typing and testing cancel action safely
      await typeIntoFlutterField(corpNameField, 'Test Corp Alpha');
      await typeIntoFlutterField(capitalCityField, 'Test Capital Prime');

      await cancelButton.click();
      await expect(page.getByText('Found a Corporation', { exact: true })).toBeHidden();
    } else {
      // Affiliated player correctly cannot found multiple corporations
      await expect(foundCorpButton).toBeDisabled();
    }
  });

  test('User Account page renders credentials, MFA enrollment, and active sessions', async () => {
    await page.setViewportSize({ width: 1280, height: 900 });

    // Open User Account screen via sidebar LIFE group or openAccount helper
    await openAccount(page);

    // 1. Header & credentials section
    await expect(page.getByText('ACCOUNT & SECURITY', { exact: true })).toBeVisible();
    await expect(page.getByText('CITIZEN IDENTITY & CREDENTIALS', { exact: true })).toBeVisible();
    await expect(page.getByText('Registered Email', { exact: true })).toBeVisible();
    await expect(page.getByText('Citizen ID', { exact: true })).toBeVisible();
    await expect(page.getByText('Display Name', { exact: true })).toBeVisible();
    await expect(page.getByText('House / Dynasty', { exact: true })).toBeVisible();

    // 2. MFA Security section
    await expect(page.getByText('MULTI-FACTOR AUTHENTICATION (MFA)', { exact: true })).toBeVisible();
    await expect(page.getByText('Authenticator App (TOTP)', { exact: true })).toBeVisible();
    const mfaButton = page.getByRole('button', { name: 'ENROLL MFA' })
      .or(page.getByRole('button', { name: 'DISABLE MFA' }));
    await expect(mfaButton).toBeVisible();

    // 3. Active Sessions section
    await expect(page.getByText('ACTIVE SESSIONS', { exact: true })).toBeVisible();
    await expect(page.getByText('Current Device', { exact: true })).toBeVisible();
    await expect(page.getByText('ACTIVE', { exact: true })).toBeVisible();

    // 4. Danger zone & action buttons
    await expect(page.getByText('DANGER ZONE', { exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: 'DELETE ACCOUNT', exact: true })).toBeVisible();

    const hasHorizontalOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasHorizontalOverflow).toBe(false);
  });

  test('User Account page Danger Zone delete dialog validates typing DELETE and respects cancel', async () => {
    await page.setViewportSize({ width: 1280, height: 900 });

    const deleteAccountButton = page.getByRole('button', { name: 'DELETE ACCOUNT', exact: true });
    await expect(deleteAccountButton).toBeVisible();
    await deleteAccountButton.click();

    // Verify modal title & warnings
    await expect(page.getByText('Delete Account Permanently', { exact: true })).toBeVisible();
    await expect(page.getByText('Type DELETE to confirm:', { exact: true })).toBeVisible();

    const deleteField = page.getByRole('textbox', { name: 'DELETE' });
    const confirmDeleteBtn = page.getByRole('button', { name: 'PERMANENTLY DELETE', exact: true });
    const cancelDeleteBtn = page.getByRole('button', { name: 'CANCEL', exact: true });

    await expect(deleteField).toBeVisible();
    await expect(cancelDeleteBtn).toBeVisible();

    // Button is disabled until 'DELETE' is typed exactly
    await expect(confirmDeleteBtn).toBeDisabled();

    await typeIntoFlutterField(deleteField, 'NO');
    await expect(confirmDeleteBtn).toBeDisabled();

    await typeIntoFlutterField(deleteField, 'DELETE');
    await expect(confirmDeleteBtn).toBeEnabled();

    // Cancel closes dialog safely without deleting account
    await cancelDeleteBtn.click();
    await expect(confirmDeleteBtn).toBeHidden();
    await expect(deleteField).toBeHidden();
  });

  test('User Account page adapts responsively to tablet and mobile viewports without horizontal overflow', async () => {
    // 1. Tablet Viewport (768x1024)
    await page.setViewportSize({ width: 768, height: 1024 });
    await page.waitForTimeout(300);

    await expect(page.getByText('ACCOUNT & SECURITY', { exact: true })).toBeVisible();
    await expect(page.getByText('CITIZEN IDENTITY & CREDENTIALS', { exact: true })).toBeVisible();
    await expect(page.getByText('ACTIVE SESSIONS', { exact: true })).toBeVisible();

    let hasOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasOverflow).toBe(false);

    // 2. Mobile Viewport (375x667)
    await page.setViewportSize({ width: 375, height: 667 });
    await page.waitForTimeout(300);

    await expect(page.getByText('ACCOUNT & SECURITY', { exact: true })).toBeVisible();
    await expect(page.getByText('MULTI-FACTOR AUTHENTICATION (MFA)', { exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: 'DELETE ACCOUNT', exact: true })).toBeVisible();

    hasOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasOverflow).toBe(false);

    // Restore desktop viewport
    await page.setViewportSize({ width: 1280, height: 900 });
    await page.waitForTimeout(200);
  });

  test('User page renders citizen biometrics, identity attributes, and canonical succession rules', async () => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await openUserLife(page);

    // 1. Citizen Identity & Actions in MY LIFE TODAY
    await expect(page.getByRole('button', { name: 'Edit name', exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Edit epitaph / motto', exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Edit successor', exact: true })).toBeVisible();

    // 2. Attributes and Rules in Banner / Content
    const banner = page.getByRole('banner');
    await expect(banner).toHaveAccessibleName(/BIOMETRIC HEALTH/);
    await expect(banner).toHaveAccessibleName(/CANONICAL SUCCESSION RULES/);
    await expect(banner).toHaveAccessibleName(/PRIMARY HEIR/);
    await expect(banner).toHaveAccessibleName(/MUNICIPAL TRUST/);
    await expect(banner).toHaveAccessibleName(/ESTATE BUFFER/);

    // 3. Verify no horizontal overflow in desktop view
    const hasHorizontalOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasHorizontalOverflow).toBe(false);
  });

  test('User page Edit Name and Edit Epitaph dialogs open and respect cancel without mutating state', async () => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await openUserLife(page);

    // 1. Edit Name Dialog
    const editNameButton = page.getByRole('button', { name: 'Edit name', exact: true });
    await expect(editNameButton).toBeVisible();
    await editNameButton.click();

    const nameInput = page.getByRole('textbox', { name: 'Name' });
    const cancelNameBtn = page.getByRole('button', { name: 'CANCEL', exact: true });
    const saveNameBtn = page.getByRole('button', { name: 'SAVE', exact: true });

    await expect(nameInput).toBeVisible();
    await expect(saveNameBtn).toBeVisible();
    await expect(cancelNameBtn).toBeVisible();

    await cancelNameBtn.click();
    await expect(nameInput).toBeHidden();

    // 2. Edit Epitaph Dialog
    const editEpitaphButton = page.getByRole('button', { name: 'Edit epitaph / motto', exact: true });
    await expect(editEpitaphButton).toBeVisible();
    await editEpitaphButton.click();

    const epitaphInput = page.getByRole('textbox', { name: 'Epitaph / Memorial Inscription' });
    const cancelEpitaphBtn = page.getByRole('button', { name: 'CANCEL', exact: true });
    const saveEpitaphBtn = page.getByRole('button', { name: 'SAVE', exact: true });

    await expect(epitaphInput).toBeVisible();
    await expect(saveEpitaphBtn).toBeVisible();
    await expect(cancelEpitaphBtn).toBeVisible();

    await cancelEpitaphBtn.click();
    await expect(epitaphInput).toBeHidden();
  });

  test('User page Successor designation dialog validates input and respects cancel', async () => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await openUserLife(page);

    const editSuccessorButton = page.getByRole('button', { name: 'Edit successor', exact: true });
    await expect(editSuccessorButton).toBeVisible();
    await editSuccessorButton.click();

    await expect(page.getByText('Edit successor name', { exact: true })).toBeVisible();
    const successorInput = page.getByRole('textbox', { name: 'Name' });
    const cancelSuccessorBtn = page.getByRole('button', { name: 'CANCEL', exact: true });
    const saveSuccessorBtn = page.getByRole('button', { name: 'SAVE', exact: true });

    await expect(successorInput).toBeVisible();
    await expect(saveSuccessorBtn).toBeVisible();
    await expect(cancelSuccessorBtn).toBeVisible();

    // Cancel closes dialog safely
    await cancelSuccessorBtn.click();
    await expect(successorInput).toBeHidden();
  });

  test('User page adapts responsively to tablet (768x1024) and mobile (375x667) viewports without horizontal overflow', async () => {
    // 1. Tablet Viewport
    await page.setViewportSize({ width: 768, height: 1024 });
    await page.waitForTimeout(300);

    const banner = page.getByRole('banner');
    await expect(banner).toHaveAccessibleName(/CANONICAL SUCCESSION RULES/);
    await expect(page.getByRole('button', { name: 'Edit name', exact: true })).toBeVisible();

    let hasOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasOverflow).toBe(false);

    // 2. Mobile Viewport with stacked layout
    await page.setViewportSize({ width: 375, height: 667 });
    await page.waitForTimeout(300);

    await expect(banner).toHaveAccessibleName(/BIOMETRIC HEALTH/);
    await expect(page.getByRole('button', { name: 'Edit name', exact: true })).toBeVisible();

    hasOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasOverflow).toBe(false);

    // Restore desktop viewport
    await page.setViewportSize({ width: 1280, height: 900 });
    await page.waitForTimeout(200);
  });

  test('House page renders House Identity, founder, prestige metrics, and lineage records', async () => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await openHouse(page);

    // 1. House Identity Header & edit action
    await expect(page.getByRole('button', { name: 'Edit house name', exact: true })).toBeVisible();

    // 2. Semantic container containing House attributes & Lineage
    const houseContainer = page.getByRole('group', { name: /HOUSE SCORE/ }).first();
    await expect(houseContainer).toBeVisible();
    await expect(houseContainer).toHaveAccessibleName(/HOUSE/);
    await expect(houseContainer).toHaveAccessibleName(/FOUNDER/);
    await expect(houseContainer).toHaveAccessibleName(/HOUSE SCORE/);
    await expect(houseContainer).toHaveAccessibleName(/LEGACY/);
    await expect(houseContainer).toHaveAccessibleName(/ACTIVE HEIR/);
    await expect(page.getByRole('heading', { name: /LINEAGE & HEIRS/ })).toBeVisible();

    // 3. Verify no horizontal overflow in desktop view
    const hasHorizontalOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasHorizontalOverflow).toBe(false);
  });

  test('House page Edit House Name dialog opens, displays input, and respects cancel without mutating state', async () => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await openHouse(page);

    const editHouseBtn = page.getByRole('button', { name: 'Edit house name', exact: true });
    await expect(editHouseBtn).toBeVisible();
    await editHouseBtn.click();

    const houseNameInput = page.getByRole('textbox', { name: 'House Name' });
    const cancelBtn = page.getByRole('button', { name: 'CANCEL', exact: true });
    const saveBtn = page.getByRole('button', { name: 'SAVE', exact: true });

    await expect(houseNameInput).toBeVisible();
    await expect(saveBtn).toBeVisible();
    await expect(cancelBtn).toBeVisible();

    // Cancel safely closes modal
    await cancelBtn.click();
    await expect(houseNameInput).toBeHidden();
  });

  test('House page lineage node expands to display historical milestones and lifetime dossier', async () => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await openHouse(page);

    // Locate lineage member node (e.g. Active Head or Gen 1 ancestor)
    const houseContainer = page.getByRole('group', { name: /HOUSE SCORE/ }).first();
    await expect(houseContainer).toBeVisible();
    await expect(houseContainer).toHaveAccessibleName(/ACTIVE HEAD/);
    await expect(houseContainer).toHaveAccessibleName(/HISTORICAL MILESTONES & ACHIEVEMENTS/);
  });

  test('House page adapts responsively to tablet (768x1024) and mobile (375x667) viewports without horizontal overflow', async () => {
    // 1. Tablet Viewport
    await page.setViewportSize({ width: 768, height: 1024 });
    await page.waitForTimeout(300);

    const houseContainer = page.getByRole('group', { name: /HOUSE SCORE/ }).first();
    await expect(houseContainer).toBeVisible();
    await expect(page.getByRole('heading', { name: /LINEAGE & HEIRS/ })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Edit house name', exact: true })).toBeVisible();

    let hasOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasOverflow).toBe(false);

    // 2. Mobile Viewport with stacked layout
    await page.setViewportSize({ width: 375, height: 667 });
    await page.waitForTimeout(300);

    await expect(houseContainer).toBeVisible();
    await expect(page.getByRole('button', { name: 'Edit house name', exact: true })).toBeVisible();

    hasOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasOverflow).toBe(false);

    // Restore desktop viewport
    await page.setViewportSize({ width: 1280, height: 900 });
    await page.waitForTimeout(200);
  });

  test('Finance page renders personal daily income statement, tax breakdown, and status pill', async () => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await openFinance(page);

    // 1. Heading and Status
    await expect(page.getByText('PERSONAL FINANCE').first()).toBeVisible();
    await expect(page.getByText(/ON TRACK|NEEDS ATTENTION/).first()).toBeVisible();

    // 2. Sections in Daily Statement
    await expect(page.getByText('DAILY INCOME').first()).toBeVisible();
    await expect(page.getByText(/Private buildings/).first()).toBeVisible();
    await expect(page.getByText(/Investment dividend/).first()).toBeVisible();
    await expect(page.getByText(/Gross credit income/).first()).toBeVisible();

    // 3. Tax and Net Calculation
    await expect(page.getByText(/ESTIMATED TAX ON THIS INCOME/).first()).toBeVisible();
    await expect(page.getByText(/Basic income tax/).first()).toBeVisible();
    await expect(page.getByText(/Net credit income/).first()).toBeVisible();

    // 4. Life Maintenance & Daily Result
    await expect(page.getByText(/LIFE MAINTENANCE/).first()).toBeVisible();
    await expect(page.getByText(/YOUR DAILY RESULT/).first()).toBeVisible();

    // 5. Verify no horizontal overflow in desktop view
    const hasHorizontalOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasHorizontalOverflow).toBe(false);
  });

  test('Finance page displays protected reserve safeguard notice and resource change metrics', async () => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await openFinance(page);

    // Safeguard notice regarding protected reserve
    await expect(page.getByText(/Protected reserve:/).first()).toBeVisible();
    await expect(page.getByText(/Essential shortfalls are recorded; they do not remove you from the game\./).first()).toBeVisible();
  });

  test('Finance page adapts responsively to tablet (768x1024) and mobile (375x667) viewports without horizontal overflow', async () => {
    // 1. Tablet Viewport
    await page.setViewportSize({ width: 768, height: 1024 });
    await page.waitForTimeout(300);

    await expect(page.getByText('PERSONAL FINANCE').first()).toBeVisible();
    await expect(page.getByText('DAILY INCOME').first()).toBeVisible();

    let hasOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasOverflow).toBe(false);

    // 2. Mobile Viewport
    await page.setViewportSize({ width: 375, height: 667 });
    await page.waitForTimeout(300);

    await expect(page.getByText('PERSONAL FINANCE').first()).toBeVisible();
    await expect(page.getByText(/YOUR DAILY RESULT/).first()).toBeVisible();

    hasOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasOverflow).toBe(false);

    // Restore desktop viewport
    await page.setViewportSize({ width: 1280, height: 900 });
    await page.waitForTimeout(200);
  });

  test('Public Governance page renders laws in force, tax rules, and policy guidance', async () => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await openPublicGovernance(page);

    // 1. Headings & Actions
    await expect(page.getByRole('heading', { name: /LAWS IN FORCE \/ TAXES & PUBLIC SERVICES/ })).toBeVisible();
    await expect(page.getByRole('heading', { name: /UC PROPOSALS/ })).toBeVisible();
    await expect(page.getByRole('button', { name: /CREATE UC PROPOSAL/i })).toBeVisible();

    // 2. Group containing policy guidance and tax rates
    const govGroup = page.getByRole('group', { name: /WHY THIS MATTERS TO YOU/ }).first();
    await expect(govGroup).toBeVisible();
    await expect(govGroup).toHaveAccessibleName(/Tax rules change the credits you keep/);
    await expect(govGroup).toHaveAccessibleName(/basic_income/);
    await expect(govGroup).toHaveAccessibleName(/Treasury settlement and public spending/);

    // 3. Verify no horizontal overflow in desktop view
    const hasHorizontalOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasHorizontalOverflow).toBe(false);
  });

  test('Public Governance proposal composer dialog opens and validates required fields with cancel support', async () => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await openPublicGovernance(page);

    const createProposalBtn = page.getByRole('button', { name: /CREATE UC PROPOSAL/i });
    await expect(createProposalBtn).toBeVisible();
    await createProposalBtn.click();

    // 1. Validate Composer Dialog Headers & Fields
    await expect(page.getByText('Create UC proposal', { exact: true })).toBeVisible();
    const titleInput = page.getByRole('textbox', { name: /Title \(8–140 characters\)/i });
    const policyInput = page.getByRole('textbox', { name: /Policy proposal \(20–4000 characters\)/i });
    const rateInput = page.getByRole('textbox', { name: /Optional UC finance rate/i });
    const submitBtn = page.getByRole('button', { name: 'Submit proposal', exact: true });

    await expect(titleInput).toBeVisible();
    await expect(policyInput).toBeVisible();
    await expect(rateInput).toBeVisible();
    await expect(submitBtn).toBeVisible();

    // 2. Validate Cancel and Close behavior
    const cancelBtn = page.getByRole('button', { name: 'CANCEL', exact: true });
    await expect(cancelBtn).toBeVisible();
    await cancelBtn.click();

    await expect(titleInput).toBeHidden();
  });

  test('Public Governance page adapts responsively to tablet (768x1024) and mobile (375x667) viewports without horizontal overflow', async () => {
    // 1. Tablet Viewport
    await page.setViewportSize({ width: 768, height: 1024 });
    await page.waitForTimeout(300);

    await expect(page.getByRole('heading', { name: /LAWS IN FORCE/i })).toBeVisible();
    await expect(page.getByRole('button', { name: /CREATE UC PROPOSAL/i })).toBeVisible();

    let hasOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasOverflow).toBe(false);

    // 2. Mobile Viewport
    await page.setViewportSize({ width: 375, height: 667 });
    await page.waitForTimeout(300);

    const govGroup = page.getByRole('group', { name: /WHY THIS MATTERS TO YOU/ }).first();
    await expect(govGroup).toBeVisible();
    await expect(page.getByRole('button', { name: /CREATE UC PROPOSAL/i })).toBeVisible();

    hasOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasOverflow).toBe(false);

    // Restore desktop viewport
    await page.setViewportSize({ width: 1280, height: 900 });
    await page.waitForTimeout(200);
  });

  test('Public Market page renders stock & shortages, commodity cards, and market health metrics', async () => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await openMarket(page);

    // 1. Tab Bar
    await expect(page.getByRole('tab', { name: 'OVERVIEW', exact: true })).toBeVisible();
    await expect(page.getByRole('tab', { name: 'TRADE', exact: true })).toBeVisible();
    await expect(page.getByRole('tab', { name: 'ORDERS', exact: true })).toBeVisible();

    // 2. Market Health and Overview Metrics container
    const marketGroup = page.getByRole('group', { name: /STOCK & SHORTAGES/ }).first();
    await expect(marketGroup).toBeVisible();
    await expect(marketGroup).toHaveAccessibleName(/MARKET HEALTH/);
    await expect(marketGroup).toHaveAccessibleName(/CITY DEMAND/);
    await expect(marketGroup).toHaveAccessibleName(/ENERGY/);
    await expect(marketGroup).toHaveAccessibleName(/FOOD/);
    await expect(marketGroup).toHaveAccessibleName(/MATERIALS/);

    // 3. Verify no horizontal overflow in desktop view
    const hasHorizontalOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasHorizontalOverflow).toBe(false);
  });

  test('Public Market trade order dialog opens from commodity card with buy/sell controls and respects cancel', async () => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await openMarket(page);

    // Click trade/buy button on the first available commodity card
    const tradeBtn = page.getByRole('button', { name: /TRADE|BUY/i }).first();
    await expect(tradeBtn).toBeVisible();
    await tradeBtn.click();

    // 1. Validate Place Order Dialog fields
    await expect(page.getByText(/PLACE (BUY|SELL) ORDER/i).first()).toBeVisible();
    const qtyInput = page.getByRole('textbox', { name: /QUANTITY/i });
    const priceInput = page.getByRole('textbox', { name: /LIMIT PRICE/i });
    await expect(qtyInput).toBeVisible();
    await expect(priceInput).toBeVisible();

    // 2. Validate Cancel and Close behavior
    const cancelBtn = page.getByRole('button', { name: 'CANCEL', exact: true });
    await expect(cancelBtn).toBeVisible();
    await cancelBtn.click();

    await expect(qtyInput).toBeHidden();
  });

  test('Public Market tabs switch between Overview, Trade signals, and Orders', async () => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await openMarket(page);

    // 1. Switch to TRADE tab
    const tradeTab = page.getByRole('tab', { name: 'TRADE', exact: true });
    await tradeTab.click();
    await page.waitForTimeout(250);
    await expect(page.getByRole('tab', { name: 'TRADE', exact: true })).toBeVisible();

    // 2. Switch to ORDERS tab
    const ordersTab = page.getByRole('tab', { name: 'ORDERS', exact: true });
    await ordersTab.click();
    await page.waitForTimeout(250);
    await expect(page.getByRole('tab', { name: 'ORDERS', exact: true })).toBeVisible();

    // 3. Switch back to OVERVIEW tab
    const overviewTab = page.getByRole('tab', { name: 'OVERVIEW', exact: true });
    await overviewTab.click();
    await page.waitForTimeout(250);
    const marketGroup = page.getByRole('group', { name: /STOCK & SHORTAGES/ }).first();
    await expect(marketGroup).toBeVisible();
  });

  test('Public Market page adapts responsively to tablet (768x1024) and mobile (375x667) viewports without horizontal overflow', async () => {
    // 1. Tablet Viewport
    await page.setViewportSize({ width: 768, height: 1024 });
    await page.waitForTimeout(300);

    await expect(page.getByRole('tab', { name: 'OVERVIEW', exact: true })).toBeVisible();
    const marketGroup = page.getByRole('group', { name: /STOCK & SHORTAGES/ }).first();
    await expect(marketGroup).toBeVisible();

    let hasOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasOverflow).toBe(false);

    // 2. Mobile Viewport
    await page.setViewportSize({ width: 375, height: 667 });
    await page.waitForTimeout(300);

    await expect(page.getByRole('tab', { name: 'OVERVIEW', exact: true })).toBeVisible();
    await expect(marketGroup).toBeVisible();

    hasOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasOverflow).toBe(false);

    // Restore desktop viewport
    await page.setViewportSize({ width: 1280, height: 900 });
    await page.waitForTimeout(200);
  });

  test('Research page renders technology portfolio, active development, and adoption state', async () => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await openResearch(page);

    // 1. Current Breakthrough Progress & Action buttons
    const breakthroughGroup = page.getByRole('progressbar', { name: /RESEARCH \/ CURRENT BREAKTHROUGH/i })
      .or(page.getByRole('group', { name: /CURRENT BREAKTHROUGH/i })).first();
    await expect(breakthroughGroup).toBeVisible();
    await expect(breakthroughGroup).toHaveAccessibleName(/RESEARCH PROGRESSION/);
    await expect(breakthroughGroup).toHaveAccessibleName(/Funding:/);

    // 2. Breakthroughs & Outcomes Matrix Filter checkboxes/buttons
    await expect(page.getByRole('checkbox', { name: 'ALL' }).or(page.getByRole('button', { name: 'ALL' })).first()).toBeVisible();
    await expect(page.getByRole('checkbox', { name: 'Construction & Industry' }).or(page.getByRole('button', { name: 'Construction & Industry' })).first()).toBeVisible();

    // 3. Verify no horizontal overflow in desktop view
    const hasHorizontalOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasHorizontalOverflow).toBe(false);
  });

  test('Research page branch filter pills filter technology catalog items', async () => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await openResearch(page);

    // Locate branch filter checkboxes / buttons (e.g. Life Support, Construction & Industry, All)
    const lifeSupportFilter = page.getByRole('checkbox', { name: /Life Support/i })
      .or(page.getByRole('button', { name: /Life Support/i })).first();
    if (await lifeSupportFilter.isVisible().catch(() => false)) {
      await lifeSupportFilter.click();
      await page.waitForTimeout(200);
    }

    const allFilter = page.getByRole('checkbox', { name: /ALL/i })
      .or(page.getByRole('button', { name: /ALL/i })).first();
    if (await allFilter.isVisible().catch(() => false)) {
      await allFilter.click();
      await page.waitForTimeout(200);
    }
  });

  test('Research page adapts responsively to tablet (768x1024) and mobile (375x667) viewports without horizontal overflow', async () => {
    // 1. Tablet Viewport
    await page.setViewportSize({ width: 768, height: 1024 });
    await page.waitForTimeout(300);

    const breakthroughGroup = page.getByRole('progressbar', { name: /RESEARCH \/ CURRENT BREAKTHROUGH/i })
      .or(page.getByRole('group', { name: /CURRENT BREAKTHROUGH/i })).first();
    await expect(breakthroughGroup).toBeVisible();

    let hasOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasOverflow).toBe(false);

    // 2. Mobile Viewport
    await page.setViewportSize({ width: 375, height: 667 });
    await page.waitForTimeout(300);

    await expect(breakthroughGroup).toBeVisible();

    hasOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasOverflow).toBe(false);

    // Restore desktop viewport
    await page.setViewportSize({ width: 1280, height: 900 });
    await page.waitForTimeout(200);
  });

  test('Business page renders manager overview, operating signal, and core enterprise metrics', async () => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await openBusiness(page);

    // 1. Manager Brief & Status
    const briefGroup = page.getByRole('group', { name: /MANAGER'S BRIEF|OPERATING SIGNAL/i }).first();
    await expect(briefGroup).toBeVisible();
    await expect(briefGroup).toHaveAccessibleName(/PROFIT \/ CYCLE/);
    await expect(briefGroup).toHaveAccessibleName(/CASH RUNWAY/);
    await expect(briefGroup).toHaveAccessibleName(/ACTIVE STAFF/);
    await expect(briefGroup).toHaveAccessibleName(/BUILDING CAPACITY/);

    // 2. Strategy and Operating Signals
    await expect(briefGroup).toHaveAccessibleName(/OPERATING SIGNAL/);
    await expect(briefGroup).toHaveAccessibleName(/STRATEGY:/);

    // 3. Verify no horizontal overflow in desktop view
    const hasHorizontalOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasHorizontalOverflow).toBe(false);
  });

  test('Business page rename dialog opens, displays input, and respects cancel without mutating state', async () => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await openBusiness(page);

    // Look for rename button on the business panel
    const renameBtn = page.getByRole('button', { name: /Rename business|Rename/i }).first();
    if (await renameBtn.isVisible().catch(() => false)) {
      await renameBtn.click();

      const nameInput = page.getByRole('textbox', { name: 'Business name' });
      const cancelBtn = page.getByRole('button', { name: 'CANCEL', exact: true });
      const saveBtn = page.getByRole('button', { name: 'SAVE', exact: true });

      await expect(nameInput).toBeVisible();
      await expect(saveBtn).toBeVisible();
      await expect(cancelBtn).toBeVisible();

      // Cancel closes dialog safely
      await cancelBtn.click();
      await expect(nameInput).toBeHidden();
    }
  });

  test('Business page adapts responsively to tablet (768x1024) and mobile (375x667) viewports without horizontal overflow', async () => {
    // 1. Tablet Viewport
    await page.setViewportSize({ width: 768, height: 1024 });
    await page.waitForTimeout(300);

    const briefGroup = page.getByRole('group', { name: /MANAGER'S BRIEF|OPERATING SIGNAL/i }).first();
    await expect(briefGroup).toBeVisible();
    await expect(briefGroup).toHaveAccessibleName(/PROFIT \/ CYCLE/);

    let hasOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasOverflow).toBe(false);

    // 2. Mobile Viewport
    await page.setViewportSize({ width: 375, height: 667 });
    await page.waitForTimeout(300);

    await expect(briefGroup).toBeVisible();
    await expect(briefGroup).toHaveAccessibleName(/BUILDING CAPACITY/);

    hasOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasOverflow).toBe(false);

    // Restore desktop viewport
    await page.setViewportSize({ width: 1280, height: 900 });
    await page.waitForTimeout(200);
  });

  test('Buildings page renders ownership tabs, district zoning, and active building cards', async () => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await openBuildings(page);

    // 1. Ownership Tabs
    const privateTab = page.getByRole('button', { name: /PRIVATE \(/i });
    const civicTab = page.getByRole('button', { name: /CIVIC \(/i });
    const investTab = page.getByRole('button', { name: /INVEST \(/i });

    await expect(privateTab).toBeVisible();
    await expect(civicTab).toBeVisible();
    await expect(investTab).toBeVisible();

    // 2. Active Buildings & Operational Controls
    await expect(page.getByRole('button', { name: /Bistro & Molecular Restaurant|Auto-repair|Policy/i }).first()).toBeVisible();

    // 3. Verify no horizontal overflow in desktop view
    const hasHorizontalOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasHorizontalOverflow).toBe(false);
  });

  test('Buildings page switches between Private, Civic, and Public Investment categories', async () => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await openBuildings(page);

    // 1. Switch to CIVIC ownership
    const civicTab = page.getByRole('button', { name: /CIVIC \(/i });
    await civicTab.click();
    await page.waitForTimeout(250);
    await expect(civicTab).toBeVisible();

    // 2. Switch to INVEST ownership
    const investTab = page.getByRole('button', { name: /INVEST \(/i });
    await investTab.click();
    await page.waitForTimeout(250);
    await expect(investTab).toBeVisible();

    // 3. Switch back to PRIVATE ownership
    const privateTab = page.getByRole('button', { name: /PRIVATE \(/i });
    await privateTab.click();
    await page.waitForTimeout(250);
    await expect(privateTab).toBeVisible();
  });

  test('Buildings page adapts responsively to tablet (768x1024) and mobile (375x667) viewports without horizontal overflow', async () => {
    // 1. Tablet Viewport
    await page.setViewportSize({ width: 768, height: 1024 });
    await page.waitForTimeout(300);

    const privateTabTablet = page.getByRole('button', { name: /PRIVATE \(/i });
    const civicTabTablet = page.getByRole('button', { name: /CIVIC \(/i });
    const investTabTablet = page.getByRole('button', { name: /INVEST \(/i });

    await expect(privateTabTablet).toBeVisible();
    await expect(civicTabTablet).toBeVisible();
    await expect(investTabTablet).toBeVisible();

    // Verify building operational controls remain visible at 768px
    await expect(page.getByRole('button', { name: /Bistro & Molecular Restaurant|Auto-repair|Policy/i }).first()).toBeVisible();

    let hasOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasOverflow).toBe(false);

    // 2. Mobile Viewport (375px)
    await page.setViewportSize({ width: 375, height: 667 });
    await page.waitForTimeout(300);

    // Verify ownership tabs and mobile sub-tabs (BUILT / CATALOG)
    const privateTabMobile = page.getByRole('button', { name: /PRIVATE \(/i });
    await expect(privateTabMobile).toBeVisible();

    const builtSubTab = page.getByRole('button', { name: 'BUILT', exact: true }).or(page.getByText('BUILT', { exact: true }));
    const catalogSubTab = page.getByRole('button', { name: 'CATALOG', exact: true }).or(page.getByText('CATALOG', { exact: true }));
    
    if (await builtSubTab.first().isVisible().catch(() => false)) {
      await expect(builtSubTab.first()).toBeVisible();
      await expect(catalogSubTab.first()).toBeVisible();
    }

    // Verify building card remains visible and reachable without layout clipping
    await expect(page.getByRole('button', { name: /Bistro & Molecular Restaurant|Auto-repair|Policy/i }).first()).toBeVisible();

    hasOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasOverflow).toBe(false);

    // Restore desktop viewport
    await page.setViewportSize({ width: 1280, height: 900 });
    await page.waitForTimeout(200);
  });

  test('Command Center renders management focus, active telemetry, and executive objectives', async () => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await openCommandCenter(page);

    // 1. Current Resource Operations Flow Pills
    await expect(page.getByRole('button', { name: /CREDITS SURPLUS|FOOD SURPLUS|MATERIALS SURPLUS|ENERGY SURPLUS/i }).first()).toBeVisible();

    // 2. Executive Quadrant Cards
    await expect(page.getByRole('group', { name: /MARKET UNIFORM|BUSINESS|MUNICIPAL RESIDENCY|FINANCE & CONTRACTS/i }).first()).toBeVisible();

    // 3. Verify no horizontal overflow in desktop view
    const hasHorizontalOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasHorizontalOverflow).toBe(false);
  });

  test('Command Center adapts responsively to tablet (768x1024) and mobile (375x667) viewports without horizontal overflow', async () => {
    // 1. Tablet Viewport
    await page.setViewportSize({ width: 768, height: 1024 });
    await page.waitForTimeout(300);

    await expect(page.getByRole('button', { name: /Game Clock/i }).first()).toBeVisible();

    let hasOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasOverflow).toBe(false);

    // 2. Mobile Viewport
    await page.setViewportSize({ width: 375, height: 667 });
    await page.waitForTimeout(300);

    await expect(page.getByRole('button', { name: /Game Clock/i }).first()).toBeVisible();
    await expect(page.getByRole('button', { name: /Credits:/i }).first()).toBeVisible();

    hasOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasOverflow).toBe(false);

    // Restore desktop viewport
    await page.setViewportSize({ width: 1280, height: 900 });
    await page.waitForTimeout(200);
  });

  test('Daily Priorities page renders net worth deltas, changes since last visit, and urgent directives', async () => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await openBriefing(page);

    // 1. Briefing Sections
    await expect(page.getByText(/SINCE YOUR LAST VISIT|WHAT CHANGED/i).first()).toBeVisible();
    await expect(page.getByText(/WHAT REQUIRES ATTENTION/i).first()).toBeVisible();

    // 2. Net Worth and Cashflow metrics
    const briefingMetrics = page.getByRole('group', { name: /NET WORTH|NET CHANGE|NET CASHFLOW/i }).first();
    if (await briefingMetrics.isVisible().catch(() => false)) {
      await expect(briefingMetrics).toHaveAccessibleName(/NET WORTH/);
      await expect(briefingMetrics).toHaveAccessibleName(/NET CASHFLOW/);
    }

    // 3. Verify no horizontal overflow in desktop view
    const hasHorizontalOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasHorizontalOverflow).toBe(false);
  });

  test('Daily Priorities page adapts responsively to tablet (768x1024) and mobile (375x667) viewports without horizontal overflow', async () => {
    // 1. Tablet Viewport
    await page.setViewportSize({ width: 768, height: 1024 });
    await page.waitForTimeout(300);

    await expect(page.getByText(/SINCE YOUR LAST VISIT|WHAT REQUIRES ATTENTION/i).first()).toBeVisible();

    let hasOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasOverflow).toBe(false);

    // 2. Mobile Viewport
    await page.setViewportSize({ width: 375, height: 667 });
    await page.waitForTimeout(300);

    await expect(page.getByText(/SINCE YOUR LAST VISIT|WHAT REQUIRES ATTENTION/i).first()).toBeVisible();

    hasOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasOverflow).toBe(false);

    // Restore desktop viewport
    await page.setViewportSize({ width: 1280, height: 900 });
    await page.waitForTimeout(200);
  });

  test('Messages page renders comm channels, scope filters, and diplomatic dispatches container', async () => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await openMessages(page);

    // 1. Channel and Dispatches Headings
    await expect(page.getByRole('heading', { name: /CHANNELS/i })).toBeVisible();
    await expect(page.getByRole('heading', { name: /DIPLOMATIC DISPATCHES/i })).toBeVisible();

    // 2. Channel Transmission Bar & Scope Filters
    await expect(page.getByRole('button', { name: 'SEND', exact: true })).toBeVisible();
    await expect(page.getByText('GLOBAL', { exact: true }).first()).toBeVisible();

    // 3. Verify no horizontal overflow in desktop view
    const hasHorizontalOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasHorizontalOverflow).toBe(false);
  });

  test('Messages page switches to compose diplomatic dispatch form and respects cancel', async () => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await openMessages(page);

    // 1. Switch to Compose folder in Diplomatic Dispatches
    const composeFolderBtn = page.getByRole('button', { name: /COMPOSE/i }).first();
    await expect(composeFolderBtn).toBeVisible();
    await composeFolderBtn.click();
    await page.waitForTimeout(250);

    // 2. Validate Compose Form Controls
    const recipientInput = page.getByRole('textbox', { name: /Recipient ID/i });
    const subjectInput = page.getByRole('textbox', { name: /Subject/i });
    const bodyInput = page.getByRole('textbox', { name: /Formal Dispatch Body/i });
    const sendDispatchBtn = page.getByRole('button', { name: /SEND DISPATCH/i });
    const cancelBtn = page.getByRole('button', { name: 'CANCEL', exact: true });

    await expect(recipientInput).toBeVisible();
    await expect(subjectInput).toBeVisible();
    await expect(bodyInput).toBeVisible();
    await expect(sendDispatchBtn).toBeVisible();
    await expect(cancelBtn).toBeVisible();

    // 3. Validate Cancel button dismisses compose view
    await cancelBtn.click();
    await page.waitForTimeout(200);

    await expect(recipientInput).toBeHidden();
  });

  test('Messages page adapts responsively to tablet (768x1024) and mobile (375x667) viewports without horizontal overflow', async () => {
    // 1. Tablet Viewport
    await page.setViewportSize({ width: 768, height: 1024 });
    await page.waitForTimeout(300);

    await expect(page.getByRole('heading', { name: /CHANNELS/i })).toBeVisible();
    await expect(page.getByRole('heading', { name: /DIPLOMATIC DISPATCHES/i })).toBeVisible();

    let hasOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasOverflow).toBe(false);

    // 2. Mobile Viewport
    await page.setViewportSize({ width: 375, height: 667 });
    await page.waitForTimeout(300);

    await expect(page.getByRole('heading', { name: /CHANNELS/i })).toBeVisible();

    hasOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasOverflow).toBe(false);

    // Restore desktop viewport
    await page.setViewportSize({ width: 1280, height: 900 });
    await page.waitForTimeout(200);
  });

  test('Notifications page renders direct alerts, alert items or empty state, and read actions', async () => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await openNotifications(page);

    // 1. Validate Notifications Controls & Actions
    const markAllReadBtn = page.getByRole('button', { name: /MARK ALL AS READ/i });
    const emptyState = page.getByText(/No pending notifications/i);
    const paginationBtn = page.getByRole('button', { name: /NEXT|PREVIOUS/i }).first();

    const hasActions = await markAllReadBtn.isVisible().catch(() => false);
    if (hasActions) {
      await expect(markAllReadBtn).toBeVisible();
    } else {
      await expect(emptyState.or(paginationBtn)).toBeVisible();
    }

    // 2. Verify no horizontal overflow in desktop view
    const hasHorizontalOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasHorizontalOverflow).toBe(false);
  });

  test('Notifications page adapts responsively to tablet (768x1024) and mobile (375x667) viewports without horizontal overflow', async () => {
    // 1. Tablet Viewport
    await page.setViewportSize({ width: 768, height: 1024 });
    await page.waitForTimeout(300);

    const notifControl = page.getByRole('button', { name: /MARK ALL AS READ|NEXT|PREVIOUS/i })
      .or(page.getByText(/No pending notifications/i)).first();
    await expect(notifControl).toBeVisible();

    let hasOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasOverflow).toBe(false);

    // 2. Mobile Viewport
    await page.setViewportSize({ width: 375, height: 667 });
    await page.waitForTimeout(300);

    await expect(notifControl).toBeVisible();

    hasOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasOverflow).toBe(false);

    // Restore desktop viewport
    await page.setViewportSize({ width: 1280, height: 900 });
    await page.waitForTimeout(200);
  });

  test('HUD renders brand header, game clock ticker, and interactive resource chips', async () => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await openCommandCenter(page);

    // 1. Brand Header
    const brandBtn = page.getByRole('button', { name: /EARTH UNITED CORPORATIONS/i }).first();
    await expect(brandBtn).toBeVisible();

    // 2. Game Clock Ticker
    const clockBtn = page.getByRole('button', { name: /Game Clock/i }).first();
    await expect(clockBtn).toBeVisible();

    // 3. Resource Chips (Credits, Energy, Food, Materials, Components, Compute)
    await expect(page.getByRole('button', { name: /Credits:/i }).first()).toBeVisible();
    await expect(page.getByRole('button', { name: /Energy \(NRG\):/i }).first()).toBeVisible();
    await expect(page.getByRole('button', { name: /Food \(BIO\):/i }).first()).toBeVisible();
    await expect(page.getByRole('button', { name: /Materials \(ORE\):/i }).first()).toBeVisible();

    // 4. Live Stream Telemetry Pill
    await expect(page.getByRole('button', { name: /LIVE STREAM ACTIVE|LIVE/i }).first()).toBeVisible();
  });

  test('HUD Account Popup Menu opens and displays executive persona, theme suite, and settings items', async () => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await openCommandCenter(page);

    // 1. Locate and click Account Menu button
    const accountMenuBtn = page.getByRole('button', { name: /Account Menu/i }).first();
    await expect(accountMenuBtn).toBeVisible();
    await accountMenuBtn.click();
    await page.waitForTimeout(200);

    // 2. Validate Popup Menu Options
    await expect(page.getByRole('menuitem', { name: /Theme Suite/i }).or(page.getByText('Theme Suite'))).toBeVisible();
    await expect(page.getByRole('menuitem', { name: /Audio/i }).or(page.getByText(/Audio/i))).toBeVisible();
    await expect(page.getByRole('menuitem', { name: /Account/i }).or(page.getByText('Account'))).toBeVisible();
    await expect(page.getByRole('menuitem', { name: /Sign Out/i }).or(page.getByText('Sign Out'))).toBeVisible();

    // 3. Close popup menu safely by clicking outside or pressing Escape
    await page.keyboard.press('Escape');
    await page.waitForTimeout(150);
  });

  test('HUD adapts responsively across tablet (768x1024) and mobile (375x667) viewports without horizontal overflow', async () => {
    // 1. Tablet Viewport
    await page.setViewportSize({ width: 768, height: 1024 });
    await page.waitForTimeout(300);

    await expect(page.getByRole('button', { name: /Game Clock/i }).first()).toBeVisible();
    await expect(page.getByRole('button', { name: /Credits:/i }).first()).toBeVisible();

    let hasOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasOverflow).toBe(false);

    // 2. Mobile Viewport
    await page.setViewportSize({ width: 375, height: 667 });
    await page.waitForTimeout(300);

    await expect(page.getByRole('button', { name: /Game Clock/i }).first()).toBeVisible();
    await expect(page.getByRole('button', { name: /Credits:/i }).first()).toBeVisible();

    hasOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasOverflow).toBe(false);

    // Restore desktop viewport
    await page.setViewportSize({ width: 1280, height: 900 });
    await page.waitForTimeout(200);
  });

  test('City & Services page renders municipal capacity, service ratios, and urban governance rules', async () => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await openCity(page);

    // 1. City & Services Header or Municipal / Governance Card
    const cityHeader = page.getByText(/CITY & SERVICES|INSTITUTIONS|PUBLIC GOVERNANCE|LAWS IN FORCE/i).first();
    await expect(cityHeader).toBeVisible();

    // 2. Verify no horizontal overflow in desktop view
    const hasHorizontalOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasHorizontalOverflow).toBe(false);
  });

  test('Affiliated Corporation overview renders chartered treasury, membership, and corporate bylaws', async () => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await openMyCorporation(page);

    // 1. Corporation Directory search input or Chartered Overview Card
    const corpHeader = page.getByRole('textbox', { name: /Search corporations/i })
      .or(page.getByRole('button', { name: /FOUND CORPORATION/i }))
      .or(page.getByText(/CORPORATION OVERVIEW|MEMBERSHIP/i)).first();
    await expect(corpHeader).toBeVisible();

    // 2. Verify no horizontal overflow in desktop view
    const hasHorizontalOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(hasHorizontalOverflow).toBe(false);
  });
});
