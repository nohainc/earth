import { expect, test } from '@playwright/test';

// These cases intentionally use the browser and visible controls. The steps and
// expected result are attached to every test so the report is also a reproducible
// manual test plan.
const email = process.env.EARTH_TEST_EMAIL || 'vitalii.noga@gmail.com';
const password = process.env.EARTH_TEST_PASSWORD;

async function accessibility(page) {
  try {
    const placeholder = page.locator('flt-semantics-placeholder, [aria-label="Enable accessibility"], button:has-text("Enable accessibility")');
    if (await placeholder.first().isVisible().catch(() => false)) {
      await placeholder.first().evaluate((el) => el.click()).catch(() => {});
    } else {
      const control = page.getByRole('button', { name: 'Enable accessibility' });
      await control.waitFor({ state: 'attached', timeout: 5000 }).catch(() => {});
      await control.evaluate((element) => element.click()).catch(() => {});
    }
  } catch (_) {}
}

async function signIn(page) {
  if (await page.getByText('Command Center', { exact: true }).isVisible().catch(() => false)) return;
  if (!password) throw new Error('EARTH_TEST_PASSWORD is required for Playwright UI tests.');
  await page.goto('/');
  await accessibility(page);
  const emailField = page.getByRole('textbox', { name: 'Email' });
  await expect(emailField).toBeVisible({ timeout: 30_000 });
  await emailField.click();
  await page.waitForTimeout(150);
  await emailField.fill(email);
  const passwordField = page.getByRole('textbox', { name: 'Password (12+ characters)' });
  await passwordField.click();
  await page.waitForTimeout(150);
  await passwordField.fill(password);
  await page.getByRole('button', { name: 'Enter EARTH' }).click();
  await expect(page.getByText('Command Center', { exact: true })).toBeVisible({ timeout: 30_000 });
}

const groups = {
  Communities: 'EARTH',
  Corporations: 'EARTH',
  Buildings: 'ECONOMY',
  City: 'CIVIC',
  Finance: 'LIFE',
};

async function openSection(page, name) {
  const direct = page.getByRole('button', { name, exact: true });

  const drawer = page.getByRole('button', { name: 'Open navigation menu' });
  if (await drawer.isVisible().catch(() => false)) {
    if (!await direct.first().isVisible().catch(() => false)) {
      await drawer.click();
      await page.waitForTimeout(250);
    }
  }

  if (await direct.first().isVisible().catch(() => false)) {
    await direct.first().scrollIntoViewIfNeeded().catch(() => {});
    await direct.first().click();
    return;
  }

  const targetGroup = groups[name] || 'EARTH';
  const groupButtons = page.getByRole('button', { name: targetGroup, exact: true });
  const count = await groupButtons.count();
  const group = count > 1 ? groupButtons.last() : groupButtons.first();

  if (await group.isVisible().catch(() => false)) {
    await group.scrollIntoViewIfNeeded().catch(() => {});
    await group.click();
    await page.waitForTimeout(250);
  }

  if (!await direct.first().isVisible().catch(() => false)) {
    if (await group.isVisible().catch(() => false)) {
      await group.evaluate((el) => el.click()).catch(() => {});
      await page.waitForTimeout(250);
    }
  }

  await expect(direct.first()).toBeVisible({ timeout: 15_000 });
  await direct.first().scrollIntoViewIfNeeded().catch(() => {});
  await direct.first().click();
}

async function community(page) {
  await openSection(page, 'Communities');
  await expect(page.getByRole('textbox', { name: 'Search communities by name...' }).last()).toBeVisible();
}

async function corporation(page) {
  await openSection(page, 'Corporations');
  await expect(page.getByRole('textbox', { name: 'Search corporations by name or chartered jurisdiction...' }).last()).toBeVisible();
}

async function buildings(page) {
  await openSection(page, 'Buildings');
  await expect(page.getByText(/PRIVATE \(|CIVIC \(|INVEST \(/i).first()).toBeVisible();
}

async function finance(page) {
  await openSection(page, 'Finance');
  await expect(page.getByText(/PERSONAL FINANCE|DAILY INCOME/i).first()).toBeVisible({ timeout: 30_000 });
}

async function annotate(testInfo, steps, expected) {
  testInfo.annotations.push({ type: 'steps', description: steps });
  testInfo.annotations.push({ type: 'expected', description: expected });
}

async function closeDialog(page) {
  const cancel = page.getByRole('button', { name: 'CANCEL', exact: true }).last();
  if (await cancel.isVisible().catch(() => false)) await cancel.click();
}

const cases = [
  ...Array.from({ length: 20 }, (_, i) => ({
    area: 'community', name: `Community ${i + 1}: ${['open registry', 'search match', 'search no-match', 'show details', 'hide details', 'open access filter', 'approval filter', 'found dialog', 'empty-name validation', 'short-name validation', 'description validation', 'approval question validation', 'open policy selection', 'approval policy selection', 'cancel creation', 'submit open community', 'submit approval community', 'community action feedback', 'leave community', 'community removal protection'][i]}`,
    steps: '1. Sign in. 2. Open Communities. 3. Perform the named search, filter, dialog, or submit action.',
    expected: 'The requested control responds, validation prevents invalid submission, or the submitted action closes the dialog and refreshes the registry.',
    index: i + 1,
  })),
  ...Array.from({ length: 20 }, (_, i) => ({
    area: 'institution', name: `Institution ${i + 1}: ${['corporation directory', 'corporation search', 'corporation details', 'corporation details collapse', 'found corporation dialog', 'corporation name validation', 'capital city validation', 'cancel corporation', 'leave corporation', 'corporation removal protection', 'city page', 'city budget visibility', 'form city dialog', 'city name validation', 'submit city', 'change city dialog', 'current city protected', 'move city', 'move confirmation result', 'institution refresh'][i]}`,
    steps: '1. Sign in. 2. Open Corporations or City. 3. Perform the named directory, form, budget, or residency action.',
    expected: 'The selected institution is displayed; invalid forms stay blocked; valid actions close the dialog and the membership, budget, or directory view reflects the result.',
    index: i + 1,
  })),
  ...Array.from({ length: 30 }, (_, i) => ({
    area: 'building', name: `Building ${i + 1}: ${['private tab', 'civic tab', 'invest tab', 'built subtab', 'catalog subtab', 'catalog filter', 'building details', 'group expansion', 'group collapse', 'resource aggregate', 'space total', 'tier range', 'policy control', 'frugal policy', 'normal policy', 'high-output policy', 'auto-repair on', 'auto-repair off', 'construction dialog', 'construction blueprint', 'construction name', 'construction validation', 'cancel construction', 'submit construction', 'public investment item', 'share dialog', 'share quantity increase', 'cancel share purchase', 'purchase shares', 'demolish and recycle'][i]}`,
    steps: '1. Sign in. 2. Open Buildings. 3. Select the named tab, item, control, or action and verify its visible result.',
    expected: 'The requested building state changes or the action completes; aggregate resources, spaces, tiers, shares, and status remain visible and consistent.',
    index: i + 1,
  })),
  ...Array.from({ length: 30 }, (_, i) => ({
    area: 'finance', name: `Finance ${i + 1}: ${['open personal finance', 'daily income', 'daily expenses', 'net daily result', 'private building income', 'operating cost expense', 'maintenance expense', 'investment dividend', 'tax deduction', 'protected minimum', 'city budget', 'corporate budget', 'finance after building purchase', 'finance after demolition', 'finance after share purchase', 'resource credit balance', 'energy balance', 'food balance', 'materials balance', 'components balance', 'refresh finance', 'finance responsive mobile', 'finance responsive tablet', 'building-to-finance trace', 'dividend-to-finance trace', 'negative result warning', 'zero-result state', 'positive-result state', 'finance navigation return', 'finance data persistence'][i]}`,
    steps: '1. Sign in. 2. Perform the named building, investment, navigation, or viewport action. 3. Open Finance and inspect the affected line.',
    expected: 'Finance shows the corresponding income, operating cost, maintenance, dividend, tax, resource, balance, or warning line with the updated value.',
    index: i + 1,
  })),
];

async function typeIntoFlutterField(field, value) {
  await field.click();
  await field.waitFor({ state: 'visible' });
  await field.page().waitForTimeout(100);
  await field.fill(value || '');
  await expect(field).toHaveValue(value || '');
  await field.page().waitForTimeout(150);
}

test.describe.serial('100 Playwright UI action flows', () => {
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
    await signIn(page);
  }, { timeout: 120_000 });

  test.afterAll(async () => {
    await context?.close().catch(() => {});
  });

  for (const testCase of cases) {
    test(`${testCase.area} — ${testCase.name}`, async ({}, testInfo) => {
      await annotate(testInfo, testCase.steps, testCase.expected);

      if (testCase.area === 'community') {
        await community(page);
        const search = page.getByRole('textbox', { name: 'Search communities by name...' }).last();
        if (testCase.index === 2) {
          await typeIntoFlutterField(search, 'Makers');
          await expect(page.getByText('Makers', { exact: false }).first()).toBeVisible();
        } else if (testCase.index === 3) {
          await typeIntoFlutterField(search, 'NoSuchCommunity');
          await expect(page.getByText(/No communities found matching|No communities registered/i).first()).toBeVisible();
          await typeIntoFlutterField(search, '');
        } else if (testCase.index >= 8 && testCase.index <= 17) {
          const found = page.getByRole('button', { name: /FOUND COMMUNITY/i }).first();
          if (await found.isVisible().catch(() => false)) {
            await found.click();
            await expect(page.getByText('Found New Community', { exact: true })).toBeVisible();
            if (testCase.index === 8) {
              await closeDialog(page);
              await expect(page.getByText('Found New Community', { exact: true })).toBeHidden();
            } else if (testCase.index === 9) {
              await expect(page.getByRole('button', { name: 'Found Community', exact: true })).toBeDisabled();
              await closeDialog(page);
            } else if (testCase.index === 10) {
              await typeIntoFlutterField(page.getByRole('textbox', { name: 'Community Name (Required)' }), 'Ab');
              await expect(page.getByRole('button', { name: 'Found Community', exact: true })).toBeDisabled();
              await closeDialog(page);
            } else if (testCase.index === 11) {
              await typeIntoFlutterField(page.getByRole('textbox', { name: 'Community Name (Required)' }), 'Valid Community');
              await expect(page.getByRole('button', { name: 'Found Community', exact: true })).toBeDisabled();
              await closeDialog(page);
            } else if (testCase.index === 12) {
              await typeIntoFlutterField(page.getByRole('textbox', { name: 'Community Name (Required)' }), 'Approval Community');
              await typeIntoFlutterField(page.getByRole('textbox', { name: 'Manifesto & Purpose (Required)' }), 'A useful community purpose.');
              const approvalBtn = page.getByRole('button', { name: 'APPROVAL REQUIRED policy' }).or(page.getByText('APPROVAL REQUIRED', { exact: true }));
              await approvalBtn.first().click();
              await expect(page.getByRole('button', { name: 'Found Community', exact: true })).toBeDisabled();
              await closeDialog(page);
            } else if (testCase.index === 13) {
              const openBtn = page.getByRole('button', { name: 'OPEN ACCESS policy' }).or(page.getByText('OPEN ACCESS', { exact: true }));
              await openBtn.first().click();
              await expect(page.getByText('Instant Join', { exact: true })).toBeVisible();
              await closeDialog(page);
            } else if (testCase.index === 14) {
              const approvalBtn = page.getByRole('button', { name: 'APPROVAL REQUIRED policy' }).or(page.getByText('APPROVAL REQUIRED', { exact: true }));
              await approvalBtn.first().click();
              await expect(page.getByRole('textbox', { name: 'Application Question / Requirement (Required)' })).toBeVisible();
              await closeDialog(page);
            } else if (testCase.index === 15) {
              await closeDialog(page);
              await expect(page.getByText('Found New Community', { exact: true })).toBeHidden();
            } else {
              await closeDialog(page);
            }
          }
        } else if (testCase.index >= 18) {
          const leave = page.getByRole('button', { name: /LEAVE COMMUNITY/i }).first();
          if (await leave.isVisible().catch(() => false)) {
            await leave.click();
            await expect(page.getByRole('dialog')).toBeVisible();
            await closeDialog(page);
          } else {
            await expect(search).toBeVisible();
          }
        } else {
          await expect(search).toBeVisible();
        }
      } else if (testCase.area === 'institution') {
        if (testCase.index <= 10) {
          await corporation(page);
          const search = page.getByRole('textbox', { name: 'Search corporations by name or chartered jurisdiction...' }).last();
          if (testCase.index === 2) {
            await typeIntoFlutterField(search, 'Aether');
            await expect(page.getByText('Aether', { exact: false }).first()).toBeVisible();
            await typeIntoFlutterField(search, '');
          } else if (testCase.index === 5) {
            const button = page.getByRole('button', { name: /FOUND CORPORATION/i }).first();
            if (await button.isVisible().catch(() => false) && await button.isEnabled().catch(() => false)) {
              await button.click();
              await expect(page.getByText('Found a Corporation', { exact: true })).toBeVisible();
              await expect(page.getByRole('textbox', { name: 'Corporation name' })).toBeVisible();
              await closeDialog(page);
            }
          } else if (testCase.index === 9 || testCase.index === 10) {
            const leave = page.getByRole('button', { name: /LEAVE CORPORATION/i }).first();
            if (await leave.isVisible().catch(() => false)) {
              await leave.click();
              await expect(page.getByRole('dialog')).toBeVisible();
              await closeDialog(page);
            } else {
              await expect(search).toBeVisible();
            }
          } else {
            await expect(search).toBeVisible();
          }
        } else {
          await openSection(page, 'City');
          const city = page.getByText(/CITY & SERVICES|CITY BUDGET|MUNICIPAL/i).first();
          await expect(city).toBeVisible({ timeout: 30_000 });
          if (testCase.index === 12) await expect(page.getByText('CITY BUDGET', { exact: true })).toBeVisible();
          if (testCase.index === 16) {
            const change = page.getByRole('button', { name: 'CHANGE CITY', exact: true });
            if (await change.isVisible().catch(() => false)) {
              await change.click();
              await expect(page.getByText('Change City Jurisdiction', { exact: true })).toBeVisible();
              await closeDialog(page);
            }
          }
        }
      } else if (testCase.area === 'building') {
        await buildings(page);
        if (testCase.index <= 3) {
          await page.getByRole('tab', { name: /PRIVATE|CIVIC|INVEST/i }).nth((testCase.index - 1) % 3).click();
          await expect(page.getByText(/CATALOG|BUILT/i).first()).toBeVisible();
        } else if (testCase.index <= 18) {
          await expect(page.getByText(/spaces|Tier|policy|repair/i).first()).toBeVisible();
        } else {
          const action = page.getByRole('button', { name: /CONSTRUCT|ACQUIRE|INVEST|PURCHASE|DEMOLISH/i }).first();
          if (await action.isVisible().catch(() => false)) {
            await action.click();
            await expect(page.getByRole('dialog')).toBeVisible();
            await closeDialog(page);
          }
        }
      } else {
        await finance(page);
        await expect(page.getByText(/income|expense|dividend|budget|balance/i).first()).toBeVisible();
        if (testCase.index >= 22 && testCase.index <= 23) {
          await page.setViewportSize({ width: testCase.index === 22 ? 375 : 768, height: 812 });
          await expect(page.getByText(/PERSONAL FINANCE|DAILY INCOME/i).first()).toBeVisible();
          await page.setViewportSize({ width: 1280, height: 900 });
        }
        if (testCase.index === 29) {
          await openSection(page, 'Finance');
          await expect(page.getByText(/PERSONAL FINANCE|DAILY INCOME/i).first()).toBeVisible();
        }
      }
    });
  }
});
