<?php

declare(strict_types=1);

namespace App\Providers;

use App\Actions\User\CreateUser;
use App\Models\User;
use App\Support\NativeSecrets;
use Illuminate\Support\Facades\File;
use Laravel\Passport\ClientRepository;
use Laravel\Passport\Passport;
use Native\Desktop\Contracts\ProvidesPhpIni;
use Native\Desktop\Facades\ChildProcess;
use Native\Desktop\Facades\Menu;
use Native\Desktop\Facades\Window;
use phpseclib3\Crypt\RSA;
use RuntimeException;

class NativeAppServiceProvider implements ProvidesPhpIni
{
    /**
     * Executed once the native application has been booted.
     * Use this method to open windows, register global shortcuts, etc.
     */
    public function boot(): void
    {
        if (app()->runningInConsole()) {
            return;
        }

        NativeSecrets::load();

        $this->firstRunSetup();

        $this->startReverb();

        Menu::default();

        Window::open()
            ->title(config('app.name', 'TryPost'))
            ->width(1280)
            ->height(820)
            ->minWidth(960)
            ->minHeight(640)
            ->rememberState();
    }

    /**
     * Idempotent setup that used to live in the Docker entrypoint. Runs on
     * every launch but only performs work when something is missing.
     *
     * Uses direct library calls instead of `Artisan::call()` because Passport's
     * console commands are only registered when running in console mode, which
     * is not the case here (this boot hook runs inside the native HTTP request).
     */
    protected function firstRunSetup(): void
    {
        $this->seedFirstUser();
        $this->generatePassportKeys();
        $this->ensurePersonalAccessClient();
    }

    /**
     * Seed the single local account on first run. Mirrors
     * Database\Seeders\UserSeeder (admin@trypost.it / password). There is no
     * login screen in the desktop build — AutoLoginLocalUser authenticates this
     * account automatically on every request, so the password is not a real
     * security boundary (physical access to the Mac is).
     */
    protected function seedFirstUser(): void
    {
        if (User::query()->exists()) {
            return;
        }

        CreateUser::execute([
            'name' => 'Admin',
            'email' => 'admin@trypost.it',
            'password' => 'password',
            'email_verified_at' => now(),
        ]);
    }

    /**
     * Generate Passport OAuth keys (API tokens / MCP) once, unless PEM keys are
     * provided via env. Mirrors `php artisan passport:keys`.
     */
    protected function generatePassportKeys(): void
    {
        if (config('passport.private_key') || config('passport.public_key')) {
            return;
        }

        $publicPath = Passport::keyPath('oauth-public.key');
        $privatePath = Passport::keyPath('oauth-private.key');

        if (File::exists($publicPath) && File::exists($privatePath)) {
            return;
        }

        $key = RSA::createKey(4096);

        File::put($publicPath, (string) $key->getPublicKey());
        File::put($privatePath, (string) $key);

        @chmod($publicPath, 0660);
        @chmod($privatePath, 0600);
    }

    /**
     * Ensure a Passport personal access client exists for REST API keys.
     * Mirrors Database\Seeders\PassportSeeder (idempotent).
     */
    protected function ensurePersonalAccessClient(): void
    {
        /** @var ClientRepository $clients */
        $clients = app(ClientRepository::class);

        try {
            $clients->personalAccessClient('users');

            return;
        } catch (RuntimeException) {
            // No client yet — fall through to create.
        }

        $clients->createPersonalAccessGrantClient('TryPost Personal Access Client');
    }

    /**
     * Reverb runs as a persistent child process so its WebSocket server lives
     * and dies with the app (replacing the separate `reverb` container).
     */
    protected function startReverb(): void
    {
        if (! config('reverb.apps.apps.0.key')) {
            return;
        }

        if (ChildProcess::get('reverb')) {
            return;
        }

        ChildProcess::artisan('reverb:start', alias: 'reverb', persistent: true);
    }

    /**
     * Return an array of php.ini directives to be set.
     */
    public function phpIni(): array
    {
        return [
            'memory_limit' => '512M',
            'max_execution_time' => '0',
            'max_input_time' => '0',
            'opcache.enable_cli' => '1',
        ];
    }
}
