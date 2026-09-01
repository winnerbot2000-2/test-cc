<?php

declare(strict_types=1);

namespace Database\Seeders;

use App\Enums\Plan\Slug;
use App\Models\Plan;
use Illuminate\Database\Seeder;

class PlanSeeder extends Seeder
{
    /**
     * Run the database seeds.
     */
    public function run(): void
    {
        Plan::updateOrCreate(
            ['slug' => Slug::Workspace],
            [
                'name' => 'Workspace',
                'stripe_monthly_price_id' => env('STRIPE_WORKSPACE_MONTHLY'),
                'stripe_yearly_price_id' => env('STRIPE_WORKSPACE_YEARLY'),
                'monthly_credits_limit' => 2500,
                'sort' => 1,
                'is_archived' => false,
            ],
        );
    }
}
