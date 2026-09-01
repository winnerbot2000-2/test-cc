<?php

declare(strict_types=1);

/*
 * Re-applies small, idempotent patches to third-party vendor code that the
 * NativePHP desktop conversion depends on. Registered as a Composer
 * `post-autoload-dump` hook so the patches survive `composer install --no-dev`
 * (which the NativePHP build runs inside the packaged app).
 */

$root = dirname(__DIR__);

// 1) Reverb: the bundled NativePHP PHP binary has no pcntl, so SIGINT/SIGTERM/
//    SIGTSTP are undefined. Skip signal subscription when pcntl is missing.
$reverb = $root.'/vendor/laravel/reverb/src/Servers/Reverb/Console/Commands/StartServer.php';

if (is_file($reverb)) {
    $contents = file_get_contents($reverb);

    if (str_contains($contents, 'if (! windows_os()) {') && ! str_contains($contents, "extension_loaded('pcntl')")) {
        $contents = str_replace(
            'if (! windows_os()) {',
            "if (! windows_os() && extension_loaded('pcntl')) {",
            $contents,
        );

        file_put_contents($reverb, $contents);

        fwrite(STDOUT, "[patch-vendor] patched Reverb StartServer for missing pcntl\n");
    }
}

// 2) NativePHP Desktop: FreshCommand declares its name both via the AsCommand
//    attribute and an inherited signature, which Laravel 13 rejects as
//    "registered under multiple names". Pin the signature explicitly.
$fresh = $root.'/vendor/nativephp/desktop/src/Commands/FreshCommand.php';

if (is_file($fresh)) {
    $contents = file_get_contents($fresh);

    if (str_contains($contents, 'class FreshCommand extends BaseFreshCommand') && ! str_contains($contents, "native:migrate:fresh\n")) {
        $contents = str_replace(
            "    protected \$name = 'native:migrate:fresh';\n",
            "    protected \$signature = 'native:migrate:fresh\n                    {--database= : The database connection to use}\n                    {--drop-views : Drop all tables and views}\n                    {--drop-types : Drop all tables and types (Postgres only)}\n                    {--force : Force the operation to run when in production}\n                    {--path=* : The path(s) to the migrations files to be executed}\n                    {--realpath : Indicate any provided migration file paths are pre-resolved absolute paths}\n                    {--schema-path= : The path to a schema dump file}\n                    {--seed : Indicates if the seed task should be re-run}\n                    {--seeder= : The class name of the root seeder}\n                    {--step : Force the migrations to be run so they can be rolled back individually}';\n",
            $contents,
        );

        file_put_contents($fresh, $contents);

        fwrite(STDOUT, "[patch-vendor] patched NativePHP FreshCommand signature\n");
    }
}
