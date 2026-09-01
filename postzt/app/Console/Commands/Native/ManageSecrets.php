<?php

declare(strict_types=1);

namespace App\Console\Commands\Native;

use App\Support\NativeSecrets;
use Illuminate\Console\Attributes\Description;
use Illuminate\Console\Attributes\Signature;
use Illuminate\Console\Command;

#[Signature('native:secrets
        {action=show : The action to perform: show, set, or unset}
        {key? : The secret key (env name), e.g. OPENAI_API_KEY}
        {value? : The secret value for "set" (omit to unset)}')]
#[Description('Manage secrets stored in the app data directory instead of the bundled .env')]
class ManageSecrets extends Command
{
    public function handle(): int
    {
        $action = (string) $this->argument('action');
        $key = $this->argument('key') ? strtoupper((string) $this->argument('key')) : null;
        $value = $this->argument('value');

        return match ($action) {
            'show', 'list' => $this->show(),
            'set' => $this->set($key, $value),
            'unset' => $this->unsetKey($key),
            default => $this->invalid($action),
        };
    }

    protected function show(): int
    {
        $secrets = NativeSecrets::all();

        if ($secrets === []) {
            $this->info('No secrets stored yet. Use `native:secrets set KEY VALUE`.');

            return self::SUCCESS;
        }

        $this->info('Stored secrets ('.NativeSecrets::path().'):');

        foreach ($secrets as $key => $value) {
            $this->line("  <comment>{$key}</comment>=".str_repeat('*', min(24, strlen((string) $value))));
        }

        return self::SUCCESS;
    }

    protected function set(?string $key, ?string $value): int
    {
        if ($key === null || $value === null || $value === '') {
            $this->error('Usage: native:secrets set KEY VALUE');

            return self::FAILURE;
        }

        NativeSecrets::set($key, $value);
        $this->info("Stored {$key}.");

        return self::SUCCESS;
    }

    protected function unsetKey(?string $key): int
    {
        if ($key === null) {
            $this->error('Usage: native:secrets unset KEY');

            return self::FAILURE;
        }

        NativeSecrets::set($key, null);
        $this->info("Removed {$key}.");

        return self::SUCCESS;
    }

    protected function invalid(string $action): int
    {
        $this->error("Unknown action [{$action}]. Use show, set, or unset.");

        return self::FAILURE;
    }
}
