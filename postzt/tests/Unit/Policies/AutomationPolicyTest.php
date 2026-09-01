<?php

declare(strict_types=1);

use App\Models\Account;
use App\Models\Automation;
use App\Models\User;
use App\Models\Workspace;
use App\Policies\AutomationPolicy;

beforeEach(function () {
    $this->policy = new AutomationPolicy;
});

/**
 * Build an automation + an actor with the given workspace role, both in one account.
 *
 * @return array{0: User, 1: Automation}
 */
function automationPolicyActor(string $role): array
{
    $account = Account::factory()->create();
    $owner = User::factory()->create(['account_id' => $account->id]);
    $account->update(['owner_id' => $owner->id]);
    $workspace = Workspace::factory()->create(['account_id' => $account->id, 'user_id' => $owner->id]);
    $automation = Automation::factory()->create(['workspace_id' => $workspace->id]);

    if ($role === 'owner') {
        $actor = $owner;
    } else {
        $actor = User::factory()->create(['account_id' => $account->id]);
        $workspace->members()->attach($actor->id, ['role' => $role]);
    }

    $actor->update(['current_workspace_id' => $workspace->id]);

    return [$actor->refresh(), $automation];
}

test('any workspace member (including viewer) can view automations', function (string $role) {
    [$actor, $automation] = automationPolicyActor($role);

    expect($this->policy->viewAny($actor))->toBeTrue()
        ->and($this->policy->view($actor, $automation))->toBeTrue();
})->with(['owner', 'admin', 'member', 'viewer']);

test('automation create/update/delete/activate/pause is allowed for member+ and denied for viewer', function (string $role, bool $allowed) {
    [$actor, $automation] = automationPolicyActor($role);

    expect($this->policy->create($actor))->toBe($allowed)
        ->and($this->policy->update($actor, $automation))->toBe($allowed)
        ->and($this->policy->delete($actor, $automation))->toBe($allowed)
        ->and($this->policy->activate($actor, $automation))->toBe($allowed)
        ->and($this->policy->pause($actor, $automation))->toBe($allowed);
})->with([
    'owner' => ['owner', true],
    'admin' => ['admin', true],
    'member' => ['member', true],
    'viewer' => ['viewer', false],
]);
