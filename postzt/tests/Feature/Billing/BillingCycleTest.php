<?php

declare(strict_types=1);

use App\Models\Account;
use App\Models\AiUsageLog;
use App\Models\Plan;
use App\Models\Workspace;
use App\Support\BillingCycle;
use Illuminate\Support\Carbon;

test('monthly allotment is credits per workspace times workspace count', function () {
    $account = billingAccount('price_month', workspaces: 3);

    expect(BillingCycle::for($account)->creditAllotment())->toBe(7500);
});

test('yearly allotment grants twelve months upfront per workspace', function () {
    $account = billingAccount('price_year', workspaces: 2);

    expect(BillingCycle::for($account)->creditAllotment())->toBe(60000);
});

test('during trial the allotment is the monthly amount even on a yearly price', function () {
    Carbon::setTestNow('2026-06-20 12:00:00');

    $account = billingAccount('price_year', [
        'created_at' => Carbon::parse('2026-06-18'),
        'trial_ends_at' => Carbon::parse('2026-06-25'),
    ], workspaces: 1);

    expect(BillingCycle::for($account)->creditAllotment())->toBe(2500);
});

test('during trial the window spans the subscription creation to the trial end', function () {
    Carbon::setTestNow('2026-06-20 12:00:00');

    $account = billingAccount('price_year', [
        'created_at' => Carbon::parse('2026-06-18'),
        'trial_ends_at' => Carbon::parse('2026-06-25'),
    ], workspaces: 1);

    $cycle = BillingCycle::for($account);

    expect($cycle->periodStart()->toDateString())->toBe('2026-06-18')
        ->and($cycle->periodEnd()->toDateString())->toBe('2026-06-25');
});

test('monthly cycle window spans the anchor day to the next month', function () {
    Carbon::setTestNow('2026-06-20 12:00:00');
    $account = billingAccount('price_month', ['created_at' => Carbon::parse('2026-03-05')]);

    $cycle = BillingCycle::for($account);

    expect($cycle->periodStart()->toDateString())->toBe('2026-06-05')
        ->and($cycle->periodEnd()->toDateString())->toBe('2026-07-05');
});

test('yearly cycle window spans one year from the anchor', function () {
    Carbon::setTestNow('2026-06-20 12:00:00');
    $account = billingAccount('price_year', ['created_at' => Carbon::parse('2025-02-10')]);

    $cycle = BillingCycle::for($account);

    expect($cycle->periodStart()->toDateString())->toBe('2026-02-10')
        ->and($cycle->periodEnd()->toDateString())->toBe('2027-02-10');
});

test('used credits counts only usage within the current cycle window', function () {
    Carbon::setTestNow('2026-06-20 12:00:00');

    $account = billingAccount('price_month', ['created_at' => Carbon::parse('2026-03-05')]);
    $workspace = $account->workspaces()->first();

    AiUsageLog::factory()->text(credits: 10)->create([
        'account_id' => $account->id,
        'workspace_id' => $workspace->id,
        'created_at' => Carbon::parse('2026-06-10'),
    ]);

    AiUsageLog::factory()->text(credits: 99)->create([
        'account_id' => $account->id,
        'workspace_id' => $workspace->id,
        'created_at' => Carbon::parse('2026-06-01'),
    ]);

    expect(BillingCycle::for($account)->usedCredits())->toBe(10);
});

test('without a subscription the allotment falls back to a monthly amount', function () {
    $plan = Plan::query()->firstOrFail();
    $account = Account::factory()->create(['plan_id' => $plan->id, 'trial_ends_at' => null]);
    Workspace::factory()->count(2)->create(['account_id' => $account->id]);

    expect(BillingCycle::for($account)->creditAllotment())->toBe(5000);
});

test('monthly window clamps an end-of-month anchor without drift', function () {
    Carbon::setTestNow('2026-06-20 12:00:00');
    $account = billingAccount('price_month', ['created_at' => Carbon::parse('2026-01-31')]);

    $cycle = BillingCycle::for($account);

    expect($cycle->periodStart()->toDateString())->toBe('2026-05-31')
        ->and($cycle->periodEnd()->toDateString())->toBe('2026-06-30');
});

test('yearly window clamps a leap-day anchor without drift', function () {
    Carbon::setTestNow('2026-06-20 12:00:00');
    $account = billingAccount('price_year', ['created_at' => Carbon::parse('2024-02-29')]);

    $cycle = BillingCycle::for($account);

    expect($cycle->periodStart()->toDateString())->toBe('2026-02-28')
        ->and($cycle->periodEnd()->toDateString())->toBe('2027-02-28');
});

test('allotment is zero when the account has no plan', function () {
    $account = Account::factory()->create(['plan_id' => null, 'trial_ends_at' => null]);
    Workspace::factory()->count(2)->create(['account_id' => $account->id]);

    expect(BillingCycle::for($account)->creditAllotment())->toBe(0);
});
