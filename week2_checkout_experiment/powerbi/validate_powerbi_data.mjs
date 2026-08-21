import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const processedDir = path.resolve(scriptDir, '..', 'data', 'processed');

function readCsv(fileName) {
  const content = fs.readFileSync(path.join(processedDir, fileName), 'utf8').trim();
  const [headerLine, ...lines] = content.split(/\r?\n/);
  const headers = headerLine.split(',');
  return lines.map((line) => {
    const values = line.split(',');
    return Object.fromEntries(headers.map((header, index) => [header, values[index] ?? '']));
  });
}

const users = readCsv('tableau_user_metrics.csv');
const funnel = readCsv('tableau_funnel_summary.csv');
const failures = [];

function assertEqual(label, actual, expected) {
  if (actual !== expected) failures.push(`${label}: expected ${expected}, received ${actual}`);
}

function assertRounded(label, actual, expected, digits) {
  const rounded = Number(actual.toFixed(digits));
  if (rounded !== expected) failures.push(`${label}: expected ${expected}, received ${rounded}`);
}

function number(row, field) {
  return Number(row[field] || 0);
}

const byGroup = Object.groupBy(users, (row) => row.experiment_group);
const expectedGroups = new Set(['control', 'treatment']);

assertEqual('User-level row count', users.length, 15467);
assertEqual('Unique user_id count', new Set(users.map((row) => row.user_id)).size, 15467);
assertEqual('Experiment-group domain', [...new Set(users.map((row) => row.experiment_group))].sort().join(','), [...expectedGroups].sort().join(','));
assertEqual('Control users', byGroup.control.length, 7754);
assertEqual('Treatment users', byGroup.treatment.length, 7713);

for (const [group, rows] of Object.entries(byGroup)) {
  const purchases = rows.reduce((sum, row) => sum + number(row, 'reached_purchase'), 0);
  const conversion = purchases / rows.length;
  const retainedRevenue = rows.reduce((sum, row) => sum + number(row, 'retained_revenue'), 0) / rows.length;
  const paymentFailures = rows.reduce((sum, row) => sum + number(row, 'had_payment_failure'), 0);
  const paymentAttempts = rows.reduce((sum, row) => sum + number(row, 'reached_payment_attempt'), 0);
  const checkoutErrors = rows.reduce((sum, row) => sum + number(row, 'had_checkout_error'), 0) / rows.length;
  const refundCancel = rows.reduce((sum, row) => sum + number(row, 'refunded_or_cancelled'), 0);
  const matureFollowup = rows.reduce((sum, row) => sum + number(row, 'mature_order_followup'), 0);

  assertEqual(`${group} purchases`, purchases, group === 'control' ? 2130 : 2285);
  assertRounded(`${group} purchase conversion (%)`, conversion * 100, group === 'control' ? 27.47 : 29.63, 2);
  assertRounded(`${group} retained revenue per exposed user`, retainedRevenue, group === 'control' ? 24.52 : 26.33, 2);
  assertRounded(`${group} payment failure rate (%)`, paymentFailures / paymentAttempts * 100, group === 'control' ? 5.36 : 5.13, 2);
  assertRounded(`${group} checkout error rate (%)`, checkoutErrors * 100, group === 'control' ? 3.07 : 3.49, 2);
  assertRounded(`${group} refund/cancellation rate (%)`, refundCancel / matureFollowup * 100, group === 'control' ? 5.68 : 6.48, 2);
}

const deviceExpected = {
  desktop: { control: 27.99, treatment: 29.66 },
  mobile: { control: 27.03, treatment: 29.49 },
  tablet: { control: 28.48, treatment: 30.72 },
};

for (const [device, groups] of Object.entries(deviceExpected)) {
  for (const [group, expected] of Object.entries(groups)) {
    const rows = byGroup[group].filter((row) => row.device_at_exposure === device);
    const conversion = rows.reduce((sum, row) => sum + number(row, 'reached_purchase'), 0) / rows.length;
    assertRounded(`${device} ${group} conversion (%)`, conversion * 100, expected, 2);
  }
}

const funnelExpected = {
  'control|checkout_view': 7754,
  'control|payment_attempt': 5844,
  'control|purchase': 2130,
  'treatment|checkout_view': 7713,
  'treatment|payment_attempt': 6004,
  'treatment|purchase': 2285,
};

assertEqual('Funnel summary row count', funnel.length, 6);
assertEqual('Unique funnel group-step keys', new Set(funnel.map((row) => `${row.experiment_group}|${row.funnel_step}`)).size, 6);
for (const row of funnel) {
  const key = `${row.experiment_group}|${row.funnel_step}`;
  assertEqual(`Funnel users ${key}`, number(row, 'step_users'), funnelExpected[key]);
}

const controlConversion = byGroup.control.reduce((sum, row) => sum + number(row, 'reached_purchase'), 0) / byGroup.control.length;
const treatmentConversion = byGroup.treatment.reduce((sum, row) => sum + number(row, 'reached_purchase'), 0) / byGroup.treatment.length;
assertRounded('Absolute lift (pp)', (treatmentConversion - controlConversion) * 100, 2.16, 2);
assertRounded('Relative lift (%)', (treatmentConversion / controlConversion - 1) * 100, 7.85, 2);

function erf(value) {
  const sign = value < 0 ? -1 : 1;
  const x = Math.abs(value);
  const t = 1 / (1 + 0.3275911 * x);
  const approximation = 1 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * Math.exp(-x * x);
  return sign * approximation;
}

const controlPurchases = byGroup.control.reduce((sum, row) => sum + number(row, 'reached_purchase'), 0);
const treatmentPurchases = byGroup.treatment.reduce((sum, row) => sum + number(row, 'reached_purchase'), 0);
const absoluteLift = treatmentConversion - controlConversion;
const pooledConversion = (controlPurchases + treatmentPurchases) / users.length;
const nullStandardError = Math.sqrt(pooledConversion * (1 - pooledConversion) * (1 / byGroup.control.length + 1 / byGroup.treatment.length));
const zStatistic = absoluteLift / nullStandardError;
const normalCdf = 0.5 * (1 + erf(Math.abs(zStatistic) / Math.sqrt(2)));
const twoSidedPValue = 2 * (1 - normalCdf);
const liftStandardError = Math.sqrt(
  controlConversion * (1 - controlConversion) / byGroup.control.length
    + treatmentConversion * (1 - treatmentConversion) / byGroup.treatment.length,
);
const criticalValue = 1.959963984540054;
assertRounded('Two-sided p-value', twoSidedPValue, 0.0030, 4);
assertRounded('Lift CI lower (pp)', (absoluteLift - criticalValue * liftStandardError) * 100, 0.73, 2);
assertRounded('Lift CI upper (pp)', (absoluteLift + criticalValue * liftStandardError) * 100, 3.58, 2);

if (failures.length) {
  console.error(`Power BI data validation failed (${failures.length} checks):`);
  failures.forEach((failure) => console.error(`- ${failure}`));
  process.exit(1);
}

console.log('Power BI data validation passed.');
console.log(`- User-level grain: ${users.length.toLocaleString('en-US')} unique mature exposed users`);
console.log('- Funnel grain: 6 unique experiment-group × step rows');
console.log('- Frozen conversion, inference, device, revenue, funnel, and guardrail outputs match');
