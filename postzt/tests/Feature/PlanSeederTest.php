<?php

declare(strict_types=1);

use App\Enums\Plan\Slug;
use App\Models\Plan;
use Database\Seeders\PlanSeeder;

test('seeder creates only the per-workspace plan', function () {
    expect(Plan::count())->toBe(1);

    $workspace = Plan::where('slug', Slug::Workspace)->first();

    expect($workspace->name)->toBe('Workspace')
        ->and($workspace->monthly_credits_limit)->toBe(2500)
        ->and($workspace->is_archived)->toBeFalse();
});

test('seeder is idempotent', function () {
    $this->seed(PlanSeeder::class);

    expect(Plan::count())->toBe(1);
});

test('the per-workspace plan is active', function () {
    expect(Plan::active()->count())->toBe(1)
        ->and(Plan::active()->first()->slug)->toBe(Slug::Workspace);
});
