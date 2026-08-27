List migrations:

```bash
php bin/console doctrine:migrations:list
```

Execute a single migration up:

```bash
php bin/console doctrine:migrations:execute --dry-run --up 'DoctrineMigrations\Version20260811231500_AddDebugModeField'
```
