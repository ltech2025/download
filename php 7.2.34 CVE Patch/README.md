# PHP për Xtream Codes

Script-e për ndërtimin dhe përditësimin e PHP-së në Ubuntu 18.04 x86_64.

## `build_php.sh`

Ndërton **PHP 7.2.34 me patch-et e përfshira**, ruan extensions origjinale dhe përdor profilin e bibliotekave të production: libcurl3, OpenSSL 1.0 dhe PNG12. Krijon dosjen PHP, arkivin dhe raportet; nuk e instalon në production.

Ekzekutoje në një VM build-i, si përdorues me të drejtë `sudo`:

```bash
bash build_php.sh
```

Për të kryer edhe testet:

```bash
bash build_php.sh --with-tests
```

Rezultati gjendet te `php-build-output/run.XXXXXXXX/php/`. Me `--with-tests`, `exit 2` tregon dështime testesh pas krijimit të paketës; kontrollo raportet para përdorimit.

## `update_php.sh`

Vendose brenda `iptv_xtream_codes`, pranë dosjes ekzistuese `php`. Ngarko përmbajtjen e build-it në `php_build`, që të përmbajë direkt `bin/`, `sbin/`, `lib/` dhe `etc/`.

Script-i:

- Krijon backup-in `php_old` dhe kopjen e build-it `php_patched`, pa mbishkruar kopje ekzistuese.
- Ruan konfigurimet origjinale, `GeoIP.dat`, pronësinë dhe lejet e skedarëve ekzistues.
- Vendos upload progress **Off** në `lib/php.ini` dhe pool-et FPM; heq `etc/php-fpm.d` vetëm kur është bosh.
- Kontrollon kopjen e përgatitur përpara zëvendësimit dhe raporton rezultatin.

```bash
sudo bash update_php.sh install php_build
```

Pas mesazhit të gjelbër **SUCCESS**, ekzekuto veçmas:

```bash
sudo bash ./start_services.sh
```

Rinisja është manuale; ndërmjet përditësimit dhe rinisjes pritet ndërprerje e PHP-së. Pastaj kontrollo panelin dhe streams.

Për rollback:

```bash
sudo bash update_php.sh rollback
```

Pas rollback-ut ekzekuto sërish `sudo bash ./start_services.sh`. Rollback-u rikthen edhe konfigurimet origjinale, pa riaplikuar ndryshimet `Off`.
